# Bootstrap Script Merge Implementation Plan

> *STATUS*: implemented!

This plan outlines the refactoring strategy to merge `tf/ipv6-only/scripts/bootstrap-ipv6.sh.tftpl` and `tf/vanilla/scripts/bootstrap.sh.tftpl` into a single, unified `tf/scripts/bootstrap.sh.tftpl` template.

## Strategy
The two scripts are functionally similar but diverge in network-specific configuration (IPv4 vs. IPv6). We will unify the scripts using Terraform's native template directives (`%{ if ... }`) driven by a new boolean variable `ipv6_enabled`.

## Refactoring Steps

### 1. Create Unified Template (`tf/scripts/bootstrap.sh.tftpl`)
Create a new central file. The shared sections (kernel prep, containerd installation, k8s component repo setup, and CCM yaml injection) will be identical.

The divergent logic will be refactored using `ipv6_enabled = true/false`:

* **Sysctl Network Forwarding**: 
  Always inject `net.ipv6.conf.all.forwarding = 1` (it is safe to enable unconditionally for both platforms).
* **Control Plane API IP Discovery**:
  Conditionally curl for `$IPV6_ADDR` or `$INTERNAL_IP` from the GCP metadata server.
* **Kubeadm Init Args**:
  Use `%{ if ipv6_enabled }` to inject `--skip-phases=addon/kube-proxy` and `--service-cidr=${k8s_service_cidr}`, and set the appropriate `cp_public_ip` SAN logic. Vanilla requires an admin.conf `sed` replacement for external standard kubectl access, which will be preserved in the `else` block.
* **Cilium Installation**:
  Unify the installation to use the Cilium CLI (downloaded dynamically) for both configurations. The specific CLI `--set` flags will be dynamically toggled using `ipv6_enabled` to configure the appropriate IPAM and routing.
* **CoreDNS Fix**:
  Preserve the IPv6 Google Public DNS injection solely within the `ipv6_enabled` block.
* **Worker Join Loop**:
  Unify the join command using a generic `${cp_join_ip}` variable, and apply brackets for IPv6 dynamically: `kubeadm join %{ if ipv6_enabled }[${cp_join_ip}]%{ else }${cp_join_ip}%{ endif }:6443 ...`

### 2. Update Terraform Files
Modify the `templatefile` calls across both `tf/ipv6-only` and `tf/vanilla` modules (`k8s_control_plane.tf` and `k8s_worker_node.tf`) to point to the new unified path (`../scripts/bootstrap.sh.tftpl` or similar).

We will add the following parameters to the `templatefile` calls:
* `ipv6_enabled` (boolean)
* `k8s_pod_cidr` (unified name)
* `k8s_service_cidr` (empty for vanilla)
* `cp_join_ip` (internal IPv4 or public IPv6)
* `cp_public_ip` (used for Vanilla's external kubectl proxy)

### 3. Verification
* Run `terraform validate && terraform plan` on both `vanilla` and `ipv6-only` configurations.
* Visually inspect the terraform plan diffs for the `metadata_startup_script` to ensure the generated bash scripts match their legacy behavior exactly.
