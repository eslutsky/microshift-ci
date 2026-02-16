#
# Beginning of the header copied from microshift/packaging/rpm/microshift.spec
#
%global shortcommit %(c=%{commit}; echo ${c:0:7})
# Debug info not supported with Go
%global debug_package %{nil}

Name: microshift
Version: %{version}
Release: %{release}%{dist}
Summary: MicroShift service
License: ASL 2.0
URL: https://github.com/openshift/microshift
Source0: https://github.com/openshift/microshift/archive/%{commit}/microshift-%{shortcommit}.tar.gz

ExclusiveArch: x86_64 aarch64

%description
The microshift package provides an OpenShift Kubernetes distribution optimized for small form factor and edge computing.

%prep
%setup -n microshift-%{commit}
#
# End of the header copied from microshift/packaging/rpm/microshift.spec
#

%package multus
Summary: Multus CNI for MicroShift
ExclusiveArch: x86_64 aarch64
Requires: microshift = %{version}

%description multus
The microshift-multus package provides the required manifests for the Multus CNI to be installed on MicroShift.

%package multus-release-info
Summary: Release information for Multus CNI for MicroShift
BuildArch: noarch
Requires: microshift-release-info = %{version}

%description multus-release-info
The microshift-multus-release-info package provides release information files for this
release. These files contain the list of container image references used by
the Multus CNI for MicroShift and can be used to embed those images into
osbuilder blueprints or bootc containerfiles.

%install
install -d -m755 %{buildroot}/%{_sysconfdir}/microshift/config.d
install -d -m755 %{buildroot}%{_sysconfdir}/crio/crio.conf.d

# multus manifests
install -d -m755 %{buildroot}/%{_prefix}/lib/microshift/manifests.d/003-microshift-multus
install -p -m644 assets/optional/multus/0* %{buildroot}/%{_prefix}/lib/microshift/manifests.d/003-microshift-multus
install -p -m644 assets/optional/multus/kustomization.yaml %{buildroot}/%{_prefix}/lib/microshift/manifests.d/003-microshift-multus

%ifarch x86_64
cat assets/optional/multus/kustomization.x86_64.yaml >> %{buildroot}/%{_prefix}/lib/microshift/manifests.d/003-microshift-multus/kustomization.yaml
%endif

%ifarch %{arm} aarch64
cat assets/optional/multus/kustomization.aarch64.yaml >> %{buildroot}/%{_prefix}/lib/microshift/manifests.d/003-microshift-multus/kustomization.yaml
%endif

# multus config and crio
install -p -m644 packaging/microshift/dropins/enable-multus.yaml %{buildroot}%{_sysconfdir}/microshift/config.d/00-enable-multus.yaml
install -p -m755 packaging/crio.conf.d/12-microshift-multus.conf %{buildroot}%{_sysconfdir}/crio/crio.conf.d/12-microshift-multus.conf

# multus-release-info
mkdir -p -m755 %{buildroot}%{_datadir}/microshift/release
install -p -m644 assets/optional/multus/release-multus-{x86_64,aarch64}.json %{buildroot}%{_datadir}/microshift/release/

%post multus
# only for install, not on upgrades
if [ $1 -eq 1 ]; then
	# if crio was already started, restart it so it will catch /etc/crio/crio.conf.d/12-microshift-multus.conf
	systemctl is-active --quiet crio && systemctl restart --quiet crio || true
fi

%files multus
%dir %{_prefix}/lib/microshift/manifests.d/003-microshift-multus
%{_prefix}/lib/microshift/manifests.d/003-microshift-multus/*
%config(noreplace) %{_sysconfdir}/microshift/config.d/00-enable-multus.yaml
%{_sysconfdir}/crio/crio.conf.d/12-microshift-multus.conf

%files multus-release-info
%{_datadir}/microshift/release/release-multus-{x86_64,aarch64}.json
