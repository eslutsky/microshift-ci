**Purpose:** Produce **UDN (User-Defined Networking) solution upstream** and test it with a 

---

## Overall Summary

This branch extends the MicroShift upstream (OKD) CI and build system to support **UDN** and enable **cluster-to-cluster communication** between upstream nodes with multi-node cluster support. It adds **Multus** and **FRR-K8s** as buildable components, enhances the quick-RPM workflow for custom network drivers, and introduces tooling to build and test with patched or custom images in multi-node environments. The changes are incremental and focused on enabling the UDN stack—including inter-node connectivity—within the upstream repository.

---

## Details
### -. add frr-k8s rpm upstream  
*Enables building the FRR-K8s RPM (BGP/EVPN component of UDN) in the same pipeline as MicroShift.*

### -. add multus upstream  
*Provides the multi-network attachment layer required for UDN and multi-node.*

### -. add network_driver option to quickrpm.sh for easier deployment  
*Adds a `network_driver` argument/option to `quickrpm.sh`, making it easier to specify and deploy with different networking components (e.g., Kindnet, OVN, or custom drivers) during installation.*

### -. script to replace single image in OKD release and publish as new test release  
*Adds **`src/okd/replace_release_image.sh`**: allows replacing a single container image in an OKD release payload and publishing the modified release as a new test version. This enables the new release to be automatically picked up by the GitHub Action pipeline, which then produces MicroShift RPMs with the substituted image for integration and validation testing.*



