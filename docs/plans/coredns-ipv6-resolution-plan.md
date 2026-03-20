# CoreDNS IPv6 Resolver Alternatives

## Overview
Currently, the bootstrap script patches the `coredns` ConfigMap by replacing `forward . /etc/resolv.conf` with a hardcoded Google Public DNS IPv6 resolver (`2001:4860:4860::6464`, `2001:4860:4860::64`). While this works to allow Pods to resolve external domains in an IPv6-only cluster, hardcoding external DNS nameservers bypasses Google Cloud's internal DNS resolving capabilities (meaning internal VPC records and private zones might not resolve correctly) and makes the script fragile by relying on a `sed` replacement of a live ConfigMap.

## Root Cause
In an IPv6-only cluster, CoreDNS pods default to forwarding external DNS queries to the nameservers listed in the node's `/etc/resolv.conf`. In a typical GCP environment, this file points to the Google Cloud metadata server's IPv4 address (`169.254.169.254`). Because the pods operate purely over IPv6, they lack routes or capabilities to connect to the node's IPv4 nameserver, causing external DNS resolution to fail.

## Alternatives

### Kubelet `--resolv-conf` Customization (KubeletConfiguration)
**Approach**: Create a dedicated `resolv.conf` specifically for Kubernetes (e.g., `/etc/k8s-resolv.conf`) containing the necessary IPv6 resolvers. Configure Kubeadm to pass this to the kubelet using the `resolvConf` under `KubeletConfiguration`.
**Pros**: 
- Standard, officially supported Kubelet functionality. Kubernetes elegantly handles this natively.
- Leaves the host's primary `/etc/resolv.conf` untouched avoiding side-effects on the OS toolings.
**Cons**: 
- You still have to hardcode an IPv6 nameserver (unless you write the GCP metadata IPv6 server IP instead of Google Public DNS).

### Configure Node-Level `/etc/resolv.conf` System-Wide
**Approach**: Before running `kubeadm init` or `kubeadm join`, configure the host OS (e.g., via `systemd-resolved` or GCP's `google-guest-agent`) to natively append the IPv6 resolvers in the host's `/etc/resolv.conf`.
**Pros**: 
- CoreDNS naturally inherits the correct nameservers because it uses `forward . /etc/resolv.conf` by default.
- No `sed` manipulation of the `kube-system` ConfigMap.
**Cons**: 
- Modifying OS-level DNS behavior could lead to unexpected resolution issues on the node itself or conflict with standard GCP network management.

### Declarative CoreDNS ConfigMap
**Approach**: Rather than imperative `kubectl get | sed | kubectl apply`, apply a standard declarative Kubeadm addon ConfigMap adjustment.
**Pros**: 
- Avoids fragile script patterns like inline `sed`.
**Cons**: 
- Still manually bypassing the host `resolv.conf`, carrying the same functional disadvantages.

### Enable IPv6 Metadata / Internal DNS in GCP
**Approach**: Google Cloud's metadata server provides DNS resolution services, which are natively accessible via IPv6 at `fd20:ce::254`. By properly configuring the VPC and subnets for internal IPv6, GCP's DHCPv6 and `google-guest-agent` will automatically provision the host's `/etc/resolv.conf` with this local IPv6 nameserver. CoreDNS can then naturally forward to `/etc/resolv.conf` and resolve both Google-internal names (like `.internal` VM DNS) and external domains.

**What is specifically entailed:**
To implement this approach in the underlying infrastructure, the following Terraform modifications are typically required:
- **VPC Network**: Must have ULA internal IPv6 enabled (`enable_ula_internal_ipv6 = true` in `google_compute_network`).
- **Subnetwork**: Must be configured with an IPv6 access type (`ipv6_access_type = "INTERNAL"` or `"EXTERNAL"`) to assign IPv6 ranges.
- **VM Instances**: Must be configured as dual-stack instances (`stack_type = "IPV4_IPV6"`) to receive the IPv6 assignments.
- **Firewall Rules**: Must permit IPv6 internal traffic, particularly allowing UDP/TCP port 53 (DNS) to the nameserver ranges if heavily restricted.

**Pros**: 
- Preserves VPC-internal DNS resolution capabilities (e.g., `*.c.[PROJECT_ID].internal` resolutions will work correctly for pods).
- CoreDNS naturally inherits the correct nameservers because it uses `forward . /etc/resolv.conf` by default. No Kubelet or CoreDNS overrides are required.
- Follows native cloud mechanics, providing exactly the same developer experience as an IPv4 cluster.

**Cons**: 
- Requires configuring and ensuring the GCP VPC supports IPv6 interior DNS, which might require rebuilding networks/subnets if they were not created with dual-stack support initially.
- Hard dependence on `google-guest-agent` functioning properly to configure the host OS resolver.

## Recommendation

**Primary Recommendation: Enable IPv6 Metadata / Internal DNS in GCP**

Rather than relying on workaround configuration scripts or hardcoding external DNS servers, the cluster should natively consume Google Cloud's internal DNS over IPv6. This provides the most standards-compliant and reliable operational experience, mirroring IPv4 functionality natively where `.internal` GCP DNS names and external domains can be resolved correctly by the pods.

**Implementation Steps:**
- In the Terraform definitions for the GCP VPC and subnet, ensure IPv6 is supported internally:
```hcl
resource "google_compute_network" "vpc_network" {
  name                     = "k8s-vpc"
  auto_create_subnetworks  = false
  enable_ula_internal_ipv6 = true
}

resource "google_compute_subnetwork" "subnetwork" {
  name               = "k8s-subnet"
  ip_cidr_range      = "10.0.0.0/16"
  region             = "us-central1"
  network            = google_compute_network.vpc_network.id
  stack_type         = "IPV4_IPV6"
  ipv6_access_type   = "INTERNAL" # Or EXTERNAL
}
```
- Ensure the firewall permits UDP port 53 traffic, especially allowing the cluster nodes to query GCP's IPv6 metadata server at `fd20:ce::254`.
- With the VPC networking properly configured, the `google-guest-agent` operating on the VM automatically configures the host OS's `/etc/resolv.conf` with the `fd20:ce::254` nameserver. CoreDNS will natively inherit this standard resolver configuration.
- Remove the imperative `sed` injection command that modifies the CoreDNS ConfigMap from the node bootstrap scripts. No Kubeadm or CoreDNS customizations are required.

**Alternative Recommendation: Kubelet `--resolv-conf` configuration**

If re-architecting the VPC for dual-stack interior DNS is not immediately feasible, explicitly define the resolver file for the Kubelet during the `kubeadm init` / `join` phases instead of using imperative `sed` commands on live ConfigMaps post-deployment.

**Implementation Steps:**
- In your `bootstrap.sh.tftpl`, statically write out an alternative resolver file when preparing the node:
```bash
echo "nameserver 2001:4860:4860::6464" > /etc/k8s-resolv.conf
echo "nameserver 2001:4860:4860::64" >> /etc/k8s-resolv.conf
```
- Update the `kubeadm-config.yaml` template to specify `resolvConf` within the `KubeletConfiguration` section:
```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
resolvConf: /etc/k8s-resolv.conf
```
- CoreDNS naturally inherits its upstream configuration from Kubelet upon bootstrap. No custom post-install hacks required.
