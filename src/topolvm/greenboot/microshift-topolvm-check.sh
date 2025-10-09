#!/bin/bash
set -euo pipefail

# Source the MicroShift health check functions library
# shellcheck disable=SC1091
source /usr/share/microshift/functions/greenboot.sh

# Exit if the current user is not 'root'
if [ "$(id -u)" -ne 0 ] ; then
    echo "The '${SCRIPT_NAME}' script must be run with the 'root' user privileges"
    exit 1
fi

echo "STARTED"

# Set the wait timeout for the current check based on the boot counter
WAIT_TIMEOUT_SECS=$(get_wait_timeout)

if ! microshift healthcheck \
        -v=2 --timeout="${WAIT_TIMEOUT_SECS}s" \
        --custom '{"topolvm-system":{"deployments": ["topolvm-controller"], "daemonsets": ["topolvm-node"]}}'; then
    create_fail_marker_and_exit
fi
