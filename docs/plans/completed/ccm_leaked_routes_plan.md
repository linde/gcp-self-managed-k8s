# Plan: Prevent Leaked GCP Routes During Teardown

> *STATUS*: completed

## Problem Description
By enabling the Google Cloud Controller Manager (CCM) to handle native routing (`--configure-cloud-routes=true` and `--allocate-node-cidrs=true`), the CCM dynamically creates `google_compute_route` objects in GCP for every Kubernetes node to route traffic to its assigned Pod CIDR.

Because these routes are created dynamically by a Kubernetes component and **not** by Terraform, they are completely untracked in the Terraform state file. 

When you run `terraform destroy`, Terraform attempts to delete the VPC network. However, Google Cloud prevents the deletion of a VPC network if there are still active routes referencing it. This causes `terraform destroy` to fail and hang, citing that the network is still in use by the left-over "leaked" routes.

## Immediate Manual Workaround

If your `terraform destroy` command is currently hung or blocked by these orphaned routes, you can manually sweep and delete them using the following `gcloud` one-liner:

```bash
gcloud compute routes list --project=$GCP_PROJECT --filter="name~^kubernetes-" --format="value(name)" | xargs -I {} gcloud compute routes delete {} --project=$GCP_PROJECT --quiet
```

## Proposed Solution: Node-Level Destroy Provisioners (Graceful Kubernetes Deletion)

We will address this problem by intercepting the destruction of the VM instances themselves and commanding the Kubernetes API to delete the node *before* the underlying VM is completely destroyed. 

Because Terraform automatically destroys resources in the reverse order of creation, it guarantees that all worker nodes will ideally be destroyed *before* the control plane VM goes down. We can securely hook into this pipeline via a `local-exec` destroy provisioner attached to the `worker_node` itself.

### `tf/vanilla/k8s_worker_node.tf` & `tf/ipv6-only/k8s_worker_node.tf`
We will add the following provisioner to the `google_compute_instance` block for `worker_node`. This SSHes into the still-living Control Plane and safely deletes the underlying node object from the cluster.

```hcl
  provisioner "local-exec" {
    when    = destroy
    command = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${path.module}/.tmp/vm_key admin@${lookup(self.metadata, "cp-ip", "127.0.0.1")} 'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf delete node ${self.name}'"
  }
```

The CCM, upon witnessing the Kubernetes node gracefully disappear from the cluster, will automatically make an API call to GCP to cleanly obliterate its associated VPC route.

## Alternatives Considered

### Terraform `null_resource` Network Teardown 
Create a global `null_resource` strictly bound strictly to the `google_compute_network` teardown which forcefully sweeps and deletes all `kubernetes-*` routes in the VPC utilizing the `gcloud` CLI.
*Reason for rejecting:* Tying destruction entirely to external dependencies like `gcloud` on the executor's machine introduces friction. Utilizing Kubernetes-native functionality (the CCM tearing down its own routes via API node-deletion) is considerably more robust and platform agnostic.

## Verification Plan
1. Apply the changes to the clusters: `terraform apply`
2. Test a generic teardown: `terraform destroy`
3. Verify that the provisioners correctly SSH into the control plane and that `kubectl delete node node-1-xxx` successfully triggers the CCM's graceful teardown, permitting the VPC network to cleanly unbind.
