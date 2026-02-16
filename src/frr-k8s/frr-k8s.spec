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

%package multus-frr-k8s
Summary: FRR-K8s for MicroShift (Multus)
ExclusiveArch: x86_64 aarch64
Requires: microshift-multus = %{version}

%description multus-frr-k8s
The microshift-multus-frr-k8s package provides the FRR-K8s manifests for use with
Multus CNI on MicroShift (e.g. BGP / MetalLB-style networking).

%install
install -d -m755 %{buildroot}/%{_prefix}/lib/microshift/manifests.d/004-microshift-multus-frr-k8s
install -p -m644 assets/optional/udn/frr-k8s/kustomization.yaml %{buildroot}/%{_prefix}/lib/microshift/manifests.d/004-microshift-multus-frr-k8s/
install -p -m644 assets/optional/udn/frr-k8s/frr-k8s.yaml %{buildroot}/%{_prefix}/lib/microshift/manifests.d/004-microshift-multus-frr-k8s/

%files multus-frr-k8s
%dir %{_prefix}/lib/microshift/manifests.d/004-microshift-multus-frr-k8s
%{_prefix}/lib/microshift/manifests.d/004-microshift-multus-frr-k8s/*
