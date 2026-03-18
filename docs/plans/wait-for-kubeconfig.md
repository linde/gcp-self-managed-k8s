# Plan: Wait for Kubeconfig Readiness

> *STATUS*: pending


## Goal
To prevent users from fetching `/etc/kubernetes/admin.conf` before `kubeadm init` completes and the control plane public IP is fully plumbed through via the startup script, we will add a Terraform `null_resource` that waits for the Kubernetes API server to become ready on port `6443` over the public IP before `terraform apply` completes.

## Proposed Changes

### 1. `tf/vanilla/k8s_control_plane.tf`
Add a `null_resource` to poll the API server via the IPv4 control plane public IP.

```hcl
resource "null_resource" "wait_for_k8s_api" {
  depends_on = [google_compute_instance.cp_node]

  provisioner "local-exec" {
    command = "echo 'Waiting for Control Plane API...'; while ! curl -k -s -f https://${google_compute_address.cp_static_ip.address}:6443/version > /dev/null; do sleep 10; done; echo 'Control Plane API is ready!'"
  }
}
```

### 2. `tf/ipv6-only/k8s_control_plane.tf`
Add a `null_resource` to poll the API server via the IPv6 control plane public IP. Brackets `[]` are required in the URL for the IPv6 address.

```hcl
resource "null_resource" "wait_for_k8s_api" {
  depends_on = [google_compute_instance.cp_node]

  provisioner "local-exec" {
    command = "echo 'Waiting for Control Plane API...'; while ! curl -k -s -f https://[${google_compute_instance.cp_node.network_interface[0].ipv6_access_config[0].external_ipv6}]:6443/version > /dev/null; do sleep 10; done; echo 'Control Plane API is ready!'"
  }
}
```

## Verification Plan

### Automated Tests
*None. Handled by Terraform application logs.*

### Manual Verification
1. **Apply Vanilla Terraform**: Run `terraform apply` in `tf/vanilla`. Verify the execution pauses at the `null_resource` provisioner.
2. **Fetch Vanilla Kubeconfig**: Directly after Terraform completes safely, fetch `admin.conf` via the SSH command and run `kubectl get pods -A`. It should yield the correct connection using the `cp_public_ip` immediately without connection refusion.
3. **Apply IPv6 Terraform**: Run `terraform apply` in `tf/ipv6-only`. Verify it similarly pauses until port 6443 is ready.
4. **Fetch IPv6 Kubeconfig**: Fetch `admin.conf` immediately after apply and confirm `kubectl get pods -A` works.
