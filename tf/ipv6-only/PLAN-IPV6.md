# Plan: IPv6-Only Kubernetes Cluster on GCE (kubeadm + Cilium)

This plan outlines the architecture for a pure IPv6-only Kubernetes cluster. GCE recently added support for IPv6-only subnets and instances, which we will leverage.

## 1. Directory Structure
We will create a new project in a parallel directory:
`../gce-kubeadm-tf-ipv6/` (or similar) copying the logic from the current project but refactoring for IPv6.

## 2. Infrastructure Changes (Terraform)

### VPC and Subnet
- **Stack Type:** Set `stack_type = "IPV6_ONLY"` on the subnetwork.
- **IPv6 Range:** Use Google-assigned `/64` ranges.
- **VPC:** Ensure the VPC has IPv6 enabled.

```hcl
resource "google_compute_subnetwork" "k8s_subnet_ipv6" {
  name             = "k8s-subnet-ipv6"
  ip_cidr_range    = "10.0.0.0/24" # GCE currently requires an internal IPv4 range even for IPv6-only stacks for metadata access, but we set stack_type to limit usage.
  stack_type       = "IPV6_ONLY"
  ipv6_access_type = "EXTERNAL" 
}
```

### Instances
- **IPv6-Only Interface:** Configure the `network_interface` to use the `IPV6_ONLY` stack.
- **Static IPv6:** Reserve a static IPv6 address for the control plane.

```hcl
network_interface {
  subnetwork = google_compute_subnetwork.k8s_subnet_ipv6.id
  stack_type = "IPV6_ONLY"
  # No access_config needed for IPv4 nat_ip
  external_ipv6_address = google_compute_address.cp_static_ipv6.address
}
```

## 3. Kubernetes Configuration (kubeadm)

### Bootstrap Script Refactor
`kubeadm` requires specific flags and configuration to operate in IPv6-only mode.

1. **Advertise Address:** Use the node's IPv6 address.
2. **Service Subnet:** Define an IPv6 range (e.g., `fd00:1::/112`).
3. **Pod Subnet:** Define an IPv6 range (e.g., `fd00:10::/64`).

```bash
# Fetch IPv6 via Metadata
INTERNAL_IPV6=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ipv6s/0)

kubeadm init \
  --pod-network-cidr=fd00:10::/64 \
  --service-cidr=fd00:1::/112 \
  --apiserver-advertise-address=$INTERNAL_IPV6 \
  --apiserver-cert-extra-sans=${cp_public_ipv6}
```

## 4. CNI Configuration (Cilium)

Cilium must be explicitly told to operate in IPv6 mode and disable IPv4.

```bash
cilium install \
  --set ipv4.enabled=false \
  --set ipv6.enabled=true \
  --set routingMode=native \
  --set ipv6NativeRoutingCIDR=fd00:10::/64 \
  --set gcp.enabled=true
```

## 5. Security and Connectivity
- **Firewall:** Update rules to support IPv6 (ICMPv6, etc.).
- **NAT64/DNS64:** Note that without IPv4, the cluster will need a way to reach IPv4-only mirrors (like `pkgs.k8s.io` if they haven't migrated) unless GCE's NAT64 is enabled.

## Next Steps for Discussion:
1. **GCP Regions:** Only specific regions support IPv6-only stacks currently.
2. **External Access:** Your local machine must have IPv6 connectivity to talk to the API server via its public IPv6 address.
3. **CRI Support:** Ensure `containerd` is configured to pull images over IPv6.
