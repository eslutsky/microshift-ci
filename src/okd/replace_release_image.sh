#!/bin/bash
set -euo pipefail

# Replace a single image in an OKD release:
# 1. Pull the release image locally
# 2. Extract release payload, replace the component image in image-references, rebuild
#    (avoids SCOS "allowed list" validation that fails when using --from-release override)
#
# Arguments: release release_tag target_image_name new_image_ref new_release
#
# Example:
#   replace_release_image.sh quay.io/okd/scos-release 4.22.0-okd-scos.ec.4 \
#     ovn-kubernetes-microshift \
#     quay.io/pmatusza/ovn-daemonset-fedora@sha256:3cfcbafd351630864a7b1ff24d3a8df559e454eab6ae19b13c9a74e27ec2c05f \
#     quay.io/eslutsky/scos-release:ovn-patched

usage() {
    echo "Usage: $(basename "$0") RELEASE RELEASE_TAG TARGET_IMAGE_NAME NEW_IMAGE_REF NEW_RELEASE"
    echo ""
    echo "  RELEASE            Release image (e.g. quay.io/okd/scos-release)"
    echo "  RELEASE_TAG        Release tag (e.g. 4.22.0-okd-scos.ec.4)"
    echo "  TARGET_IMAGE_NAME  Component to replace (e.g. ovn-kubernetes-microshift)"
    echo "  NEW_IMAGE_REF      New image reference (tag or digest)"
    echo "  NEW_RELEASE        Output release image (e.g. quay.io/user/scos-release:ovn-patched)"
    echo ""
    echo "Example:"
    echo "  $(basename "$0") quay.io/okd/scos-release 4.22.0-okd-scos.ec.4 \\"
    echo "    ovn-kubernetes-microshift quay.io/pmatusza/ovn-daemonset-fedora@sha256:... \\"
    echo "    quay.io/eslutsky/scos-release:ovn-patched"
    exit 1
}

check_prereqs() {
    for tool in oc podman jq; do
        if ! command -v "${tool}" &>/dev/null; then
            echo "ERROR: Required command '${tool}' not found in PATH"
            exit 1
        fi
    done
}

if [[ $# -ne 5 ]]; then
    usage
fi

RELEASE="$1"
RELEASE_TAG="$2"
TARGET_IMAGE_NAME="$3"
NEW_IMAGE_REF="$4"
NEW_RELEASE="$5"

SOURCE_RELEASE="${RELEASE}:${RELEASE_TAG}"

check_prereqs

WORKDIR=$(mktemp -d)
trap 'rm -rf "${WORKDIR}"' EXIT

echo "Source release: ${SOURCE_RELEASE}"
echo "Target image name: ${TARGET_IMAGE_NAME}"
CURRENT_IMAGE=$(oc adm release info "${SOURCE_RELEASE}" --image-for="${TARGET_IMAGE_NAME}" 2>/dev/null || true)
if [[ -n "${CURRENT_IMAGE}" ]]; then
    echo "Current image: ${CURRENT_IMAGE}"
fi

echo "Pulling release image: ${SOURCE_RELEASE}"
podman pull "${SOURCE_RELEASE}"

echo "Extracting release payload to ${WORKDIR}"
oc adm release extract --from "${SOURCE_RELEASE}" --to "${WORKDIR}"

# oc adm release extract writes image-references at root or under release-manifests/
IMAGE_REFERENCES=""
for candidate in "${WORKDIR}/image-references" "${WORKDIR}/release-manifests/image-references"; do
    if [[ -f "${candidate}" ]]; then
        IMAGE_REFERENCES="${candidate}"
        break
    fi
done
if [[ -z "${IMAGE_REFERENCES}" || ! -f "${IMAGE_REFERENCES}" ]]; then
    echo "ERROR: image-references not found under ${WORKDIR}"
    echo "Extracted contents:"
    find "${WORKDIR}" -maxdepth 3 -type f 2>/dev/null | head -30
    exit 1
fi
# Ensure image-references is at root (oc adm release new --from-dir expects it there)
if [[ "${IMAGE_REFERENCES}" != "${WORKDIR}/image-references" ]]; then
    cp "${IMAGE_REFERENCES}" "${WORKDIR}/image-references"
    IMAGE_REFERENCES="${WORKDIR}/image-references"
fi
# Copy release-metadata to root before we might remove release-manifests/
if [[ -f "${WORKDIR}/release-manifests/release-metadata" ]] && [[ ! -f "${WORKDIR}/release-metadata" ]]; then
    cp "${WORKDIR}/release-manifests/release-metadata" "${WORKDIR}/release-metadata"
fi

# oc adm release new --from-dir expects one subdirectory per image tag, each with that
# operator's manifest files. Extract may write manifests under release-manifests/ or at root.
# Manifest filenames are 0000_NN_<component>_<rest>.yaml — group by component (3rd field).
reorganize_manifests() {
    local search_dir="$1"
    while IFS= read -r -d '' f; do
        base=$(basename "$f")
        # Pattern: 0000_NN_<component>_<rest>; component may contain hyphens (e.g. cluster-version-operator)
        # OpenShift manifest names: 0000_NN_<component>_<rest> (component may contain hyphens)
        component=$(echo "$base" | awk -F'_' 'NF>=4 {print $3; exit}')
        if [[ -z "${component}" ]]; then
            continue
        fi
        mkdir -p "${WORKDIR}/${component}"
        mv "$f" "${WORKDIR}/${component}/"
    done < <(find "${search_dir}" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) ! -name 'image-references' ! -name 'release-metadata' -print0 2>/dev/null)
}

MANIFESTS_DIR="${WORKDIR}/release-manifests"
if [[ -d "${MANIFESTS_DIR}" ]]; then
    echo "Reorganizing manifests from release-manifests/ into per-operator directories"
    reorganize_manifests "${MANIFESTS_DIR}"
    rm -rf "${MANIFESTS_DIR}"
else
    # Some oc versions write manifest files at the root of --to directory
    manifest_count=$(find "${WORKDIR}" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) ! -name 'image-references' ! -name 'release-metadata' 2>/dev/null | wc -l)
    if [[ "${manifest_count}" -gt 0 ]]; then
        echo "Reorganizing ${manifest_count} root-level manifests into per-operator directories"
        reorganize_manifests "${WORKDIR}"
    fi
fi

# Verify we have operator dirs (oc adm release new --from-dir requires them for a full payload)
operator_dirs=$(find "${WORKDIR}" -maxdepth 1 -type d ! -path "${WORKDIR}" 2>/dev/null | wc -l)
if [[ "${operator_dirs}" -eq 0 ]]; then
    echo "WARNING: No per-operator directories found. Extracted contents:"
    ls -la "${WORKDIR}"
    echo "The release image may not contain extractable manifests in the expected layout."
fi

echo "Replacing '${TARGET_IMAGE_NAME}' with '${NEW_IMAGE_REF}' in image-references"
jq --arg name "${TARGET_IMAGE_NAME}" --arg ref "${NEW_IMAGE_REF}" \
    '.spec.tags |= map(if .name == $name then (.from |= (. + {name: $ref})) else . end)' \
    "${IMAGE_REFERENCES}" > "${WORKDIR}/image-references.new"
mv "${WORKDIR}/image-references.new" "${IMAGE_REFERENCES}"

# Preserve release metadata (version, upgrades) from the source release
RELEASE_METADATA_FILE="${WORKDIR}/release-metadata"
if [[ ! -f "${RELEASE_METADATA_FILE}" ]]; then
    RELEASE_METADATA_FILE="${WORKDIR}/release-manifests/release-metadata"
fi
RELEASE_NAME_ARG=()
RELEASE_PREVIOUS_ARGS=()
if [[ -f "${RELEASE_METADATA_FILE}" ]]; then
    release_version=$(jq -r '.version // empty' "${RELEASE_METADATA_FILE}")
    if [[ -n "${release_version}" ]]; then
        RELEASE_NAME_ARG=(--name "${release_version}")
    fi
    release_previous=$(jq -r '.previous[]? // empty' "${RELEASE_METADATA_FILE}" | paste -sd, -)
    if [[ -n "${release_previous}" ]]; then
        # oc accepts --previous multiple times or comma-separated
        RELEASE_PREVIOUS_ARGS=(--previous "${release_previous}")
    fi
fi

# Include all images from image-references so none are pruned (we have 65 operator dirs but ~193 images)
INCLUDE_ARGS=()
while IFS= read -r tag; do
    [[ -z "${tag}" ]] && continue
    INCLUDE_ARGS+=(--include "${tag}")
done < <(jq -r '.spec.tags[].name' "${IMAGE_REFERENCES}")

echo "Building new release image: ${NEW_RELEASE}"
oc adm release new \
    --from-dir "${WORKDIR}" \
    --to-image-base "${SOURCE_RELEASE}" \
    --keep-manifest-list \
    "${RELEASE_NAME_ARG[@]}" \
    "${RELEASE_PREVIOUS_ARGS[@]}" \
    "${INCLUDE_ARGS[@]}" \
    --to-image "${NEW_RELEASE}"

echo "New release image: ${NEW_RELEASE}"
