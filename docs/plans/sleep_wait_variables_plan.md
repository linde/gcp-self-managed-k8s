# Extracting Sleep and Wait Variables

> *STATUS*: in pending

The goal of this refactoring is to extract all hardcoded `sleep` and `wait` durations into configurable Terraform variables. This will make it easier to adjust timeouts for different environments or to speed up testing.

## Proposed Changes

We will introduce two new variables to both the `vanilla` and `ipv6-only` Terraform projects:
- `wait_api_propagation_time` (default: `"45s"`): The duration to wait for GCP APIs to fully propagate after getting enabled.
- `wait_destroy_route_cleanup_sleep` (default: `20`): The number of seconds to sleep during the control plane destroy provisioner, giving the Cloud Controller Manager time to clean up the GCP route.

---

### tf/vanilla

#### [MODIFY] variables.tf
- Add `variable "wait_api_propagation_time"` with default `"45s"`.
- Add `variable "wait_destroy_route_cleanup_sleep"` with default `20`.

#### [MODIFY] gcp_services.tf
- Update `resource "time_sleep" "wait_for_services"` to use `create_duration = var.wait_api_propagation_time` instead of `"45s"`.

#### [MODIFY] k8s_control_plane.tf
- Update the `local-exec` bash command sleep to use `sleep $${var.wait_destroy_route_cleanup_sleep}` instead of `sleep 20`.

---

### tf/ipv6-only

#### [MODIFY] variables.tf
- Add `variable "wait_api_propagation_time"` with default `"45s"`.
- Add `variable "wait_destroy_route_cleanup_sleep"` with default `20`.

#### [MODIFY] gcp_services.tf
- Update `resource "time_sleep" "wait_for_services"` to use `create_duration = var.wait_api_propagation_time` instead of `"45s"`.

#### [MODIFY] k8s_control_plane.tf
- Update the `local-exec` bash command sleep to use `sleep $${var.wait_destroy_route_cleanup_sleep}` instead of `sleep 20`.

## Verification Plan

### Automated Tests
- Run `terraform plan` in both `tf/vanilla` and `tf/ipv6-only` directories. Ensure that the plan succeeds and does not show any destructive changes to existing infrastructure (since the default values exactly match the current hardcoded values).
