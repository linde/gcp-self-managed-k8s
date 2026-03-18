# Extract CCM YAML from Bootstrap Scripts

> *STATUS*: implemented!

This plan outlines extracting the inline Google Cloud Controller Manager (CCM) YAML from the bash bootstrap scripts into a shared Terraform template file. This allows maintaining Kubernetes manifest separately from the bash initialization scripts.

## 1. Extract to Shared Template
**Status:** pending

Extract the CCM daemonset and RBAC manifests into a new shared template `tf/ccm.yaml.tftpl`. It will take a parameterized `${cluster_cidr}` variable for interpolation.

## 2. Update IPv6 Configuration
**Status:** pending

- Update the `templatefile` method in `tf/ipv6-only/k8s_control_plane.tf` to pass a nested `ccm_yaml` variable by rendering `tf/ccm.yaml.tftpl`, injecting `cluster_cidr = var.k8s_pod_cidr_ipv6`.
- Replace the inline CCM YAML in `tf/ipv6-only/scripts/bootstrap-ipv6.sh.tftpl` with `${ccm_yaml}` parameter interpolation.

## 3. Update Vanilla Configuration
**Status:** pending

- Update the `templatefile` method in `tf/vanilla/k8s_control_plane.tf` to pass `ccm_yaml` by rendering `tf/ccm.yaml.tftpl`, injecting `cluster_cidr = "192.168.0.0/16"`.
- Replace the inline CCM YAML in `tf/vanilla/scripts/bootstrap.sh.tftpl` with `${ccm_yaml}` parameter interpolation.

---

## Verification Plan
Run Terraform checks for both vanilla and IPv6 configurations to ensure that syntax and variable interpolations are correct.
- `cd tf/vanilla && terraform validate && terraform plan`
- `cd tf/ipv6-only && terraform validate && terraform plan`
