# Google Cloud Controller Manager (CCM) Implementation Plan

> *STATUS*: completed

This document outlines the steps to resolve the static routing / race-condition issues in the IPv6 implementation by deploying the external Google Cloud Controller Manager (CCM). By delegating route management to the CCM, we can completely remove the fragile 90-second stagger hack and static Terraform routes.

## 1. Required GCP Permissions
The Cloud Controller Manager runs within the Kubernetes cluster and communicates directly with the Google Cloud API to manage native routes for the instances. 

The GCP Service Account attached to your **Control Plane nodes** (where the CCM will run) must be granted the `roles/compute.networkAdmin` and `roles/compute.viewer` IAM roles.

## 2. Removing Terraform Static Routes & Hacks
You must clean up the current static routing logic.
- **In `network.tf`:** Delete the `google_compute_route` resources (`cp_pod_route` and `worker_pod_route`).
- **In `bootstrap-ipv6.sh.tftpl`:** Remove the 90-second sleep (`sleep $STAGGER_TIME`) logic from the worker node bootstrap section.

## 3. Kubernetes Node Configuration Flags
For the CCM to take over, Kubernetes components must be configured to expect an external cloud provider.

- **Kubelet:** On both Control Plane and Worker nodes, the Kubelet must be started with the `--cloud-provider=external` flag. (This can be injected via the `kubeadm` configuration's `nodeRegistration.kubeletExtraArgs`).
- **Kube-apiserver & Kube-controller-manager:** Must also be initialized with the `--cloud-provider=external` flag.
- **Node Names:** Ensure that your Kubelet registers the Kubernetes node name so that it exactly matches the GCP compute instance name. (This is usually the default, but if not, use `--hostname-override=$(hostname)`).

## 4. CCM Image and Deployment Configuration
After the Control Plane initializes, you must apply the GCP CCM manifests.

**Image to Use:**
You should use the official external GCP cloud provider image that corresponds to your Kubernetes version (v1.32).
- **Image:** `registry.k8s.io/cloud-provider-gcp/cloud-controller-manager:v32.2.5` *(or the latest patch version for v32)*

**Deployment Configuration:**
Deploy the CCM as a `DaemonSet` targeting only the Control Plane nodes (using node selectors/tolerations for `node-role.kubernetes.io/control-plane`).
The container must run with the following crucial arguments:
- `--cloud-provider=gce`
- `--configure-cloud-routes=true` (Tells CCM to manage GCP routes for the Pods)
- `--allocate-node-cidrs=true` (Tells CCM to manage PodCIDR allocations)
- `--cluster-cidr=fd00:10::/56` (Must match your `k8s_pod_cidr_ipv6` variable)
- `--use-service-account-credentials=true`

## 5. Verification (How to tell it was installed correctly)
Once you deploy the cluster with these changes, you can verify the CCM is working properly through the following checks:

1. **Node Initialization Taints:** 
   When Kubelet starts with `--cloud-provider=external`, the node will initially be `NotReady` and have the taint `node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule`. Once the CCM successfully connects to GCP and maps the instance, it will automatically remove this taint from the node.
2. **Node Status:**
   Run `kubectl get nodes`. All nodes should transition to the `Ready` state.
3. **GCP Route Creation:**
   Run `gcloud compute routes list --filter="network=k8s-network-ipv6-*"` (or check the GCP Console under VPC Network -> Routes). You should see dynamic routes automatically created by the CCM, pointing the allocated `/64` PodCIDRs to the exact internal instance IDs of your worker and control plane nodes.
4. **CCM Logs:**
   Run `kubectl logs -n kube-system -l component=cloud-controller-manager`. You should see successful logs verifying that routes were successfully reconciled and no permission denied (`403`) errors from the GCP API.
