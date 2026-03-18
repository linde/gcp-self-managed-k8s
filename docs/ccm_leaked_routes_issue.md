# Issue: Leaked GCP Routes from Cloud Controller Manager (CCM)

## Problem Description
By enabling the Google Cloud Controller Manager (CCM) to handle native routing (`--configure-cloud-routes=true` and `--allocate-node-cidrs=true`), the CCM dynamically creates `google_compute_route` objects in GCP for every Kubernetes node to route traffic to its assigned Pod CIDR.

Because these routes are created dynamically by a Kubernetes component and **not** by Terraform, they are completely untracked in the Terraform state file. 

When you run `terraform destroy`, Terraform attempts to delete the VPC network. However, Google Cloud prevents the deletion of a VPC network if there are still active routes referencing it. This causes `terraform destroy` to fail and hang, citing that the network is still in use by the left-over "leaked" routes.

## Potential Mitigations

Here are a few ways we can address this issue in the future:

### 1. Terraform `null_resource` with a Destroy Provisioner (Recommended)
We can add a `null_resource` bound to the lifecycle of the VPC network that runs a local script explicitly when the network is destroyed. This script would use the `gcloud` CLI to find and forcefully delete any dynamically generated routes before Terraform attempts to delete the network.

```hcl
resource "null_resource" "cleanup_ccm_routes" {
  triggers = {
    network_name = google_compute_network.k8s.name
    project      = var.gcp_project
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      ROUTES=$(gcloud compute routes list --project=${self.triggers.project} --filter="network:${self.triggers.network_name} AND name~^kubernetes-" --format="value(name)")
      if [ -n "$ROUTES" ]; then
        for route in $ROUTES; do
          gcloud compute routes delete $route --project=${self.triggers.project} --quiet
        done
      fi
    EOT
  }
}
```
**Pros:** Embedded directly in Terraform, natively fires on `terraform destroy`.
**Cons:** Requires `gcloud` CLI to be authenticated and available on the machine running Terraform.

### 2. Manual Bash Teardown Script
Instead of relying purely on `terraform destroy`, we create a `destroy.sh` wrapper script. The script would first manually clean up dependencies (like dangling routes and load balancers created by CCM) and then execute `terraform destroy`.

**Pros:** Easy to write and doesn't clutter Terraform state.
**Cons:** Users must remember to run `destroy.sh` instead of standard `terraform destroy`.

### 3. Graceful Node Deletion (Drain & Delete)
If a Kubernetes Node object is gracefully deleted from the cluster while the CCM is still running, the CCM will automatically clean up the corresponding GCP route for that node. If we can trigger a script to `kubectl delete node --all` and wait for CCM to remove the routes before Terraform forcefully deletes the VM instances, the routes would not leak.

**Pros:** The "cleanest" Kubernetes-native approach, letting the CCM clean up its own messes.
**Cons:** Very difficult to coordinate timing with Terraform. If Terraform deletes the Control Plane VM first, the CCM goes offline, and the worker node routes will be permanently orphaned anyway.
