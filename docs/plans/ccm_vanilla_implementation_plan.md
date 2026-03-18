# Vanilla Cluster: Google Cloud Controller Manager (CCM) Implementation Plan

> *STATUS*: Implemented

This document outlines the exact steps to migrate the Vanilla (IPv4) cluster implementation to use the external Google Cloud Controller Manager (CCM) and deterministic token joining, mimicking the successful IPv6-only transition. This will completely remove the fragile SSH commands and hardcoded Terraform static routes.

## 1. Required GCP Permissions & IAM
The CCM needs access to the GCP API to route traffic.
- Create a new file `tf/vanilla/iam.tf` to define a dedicated Service Account (e.g., `k8s-node-vanilla`).
- Grant this Service Account the `roles/compute.networkAdmin` and `roles/compute.viewer` IAM roles.
- Attach this Service Account to both the `cp_node` (`tf/vanilla/k8s_control_plane.tf`) and the `worker_node` (`tf/vanilla/k8s_worker_node.tf`) instances.

## 2. Removing Terraform Static Routes
The static routes are the root of scaling and lifecycle issues. They must be removed so the CCM can handle Native Routing autonomously.
- **In `tf/vanilla/network.tf`:** Delete the `google_compute_route` resources (`cp_pod_route` and `worker_pod_route`).

## 3. Removing the Brittle SSH Join Command Hack
We must replace the error-prone SSH-based `join_command` retrieval with dynamic Terraform tokens.
- **In `tf/vanilla/k8s_control_plane.tf`:** Remove the `ssh_resource` and `null_resource.get_join_command` blocks.
- **In `tf/vanilla/k8s_control_plane.tf`:** Add `random_string.token_id` and `random_string.token_secret` resources. Create a local variable `kubeadm_token = "${random_string.token_id.result}.${random_string.token_secret.result}"`.
- **In `tf/vanilla/ssh.tf`**: You can optionally delete this entirely if we no longer need Terraform to SSH into the nodes (we don't!).

## 4. Kubelet & Kubeadm Configuration (Bootstrap Script)
Update the provisioning scripts to use the external CCM.
- **In `tf/vanilla/scripts/bootstrap.sh.tftpl` (Before kubeadm init):** Add configuration for the `external` cloud provider for Kubelet:
  ```bash
  echo 'KUBELET_EXTRA_ARGS="--cloud-provider=external"' > /etc/default/kubelet
  ```
- **In `tf/vanilla/scripts/bootstrap.sh.tftpl` (Control Plane `kubeadm init`):**
  Pass the new generated token and specific cloud flags:
  ```bash
  kubeadm init \
    --pod-network-cidr=192.168.0.0/16 \
    --apiserver-advertise-address=$INTERNAL_IP \
    --apiserver-cert-extra-sans=${cp_public_ip} \
    --node-name=$(hostname) \
    --token="${kubeadm_token}"
  ```
- **In `tf/vanilla/scripts/bootstrap.sh.tftpl` (Worker `kubeadm join`):**
  Replace the dynamic shell loop parameter `${join_command}` with:
  ```bash
  kubeadm join ${cp_internal_ip}:6443 --token ${kubeadm_token} --discovery-token-unsafe-skip-ca-verification --node-name=$(hostname)
  ```
  *(Note: You'll need to pass `cp_internal_ip` from `k8s_worker_node.tf` into the templatefile).*

## 5. Deploying the CCM Manifest
At the end of the `is_control_plane` logic block in `bootstrap.sh.tftpl`, deploy the CCM `DaemonSet`.
- Use the stable `registry.k8s.io/cloud-provider-gcp/cloud-controller-manager:v32.2.5` image.
- Start the server using the standard GCP required arguments:
  ```yaml
  args:
    - --cloud-provider=gce
    - --leader-elect=true
    - --use-service-account-credentials=true
    - --configure-cloud-routes=true
    - --allocate-node-cidrs=true
    - --cluster-cidr=192.168.0.0/16
  ```

## 6. Apply Changes
Run `terraform apply` in `tf/vanilla` to reconcile the environment.
