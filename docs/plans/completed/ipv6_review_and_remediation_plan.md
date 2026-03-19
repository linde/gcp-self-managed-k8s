# IPv6 Implementation Review 

> *STATUS*: completed

Here is a list of issues and non-idiomatic practices found in the IPv6 implementation, with details on why they are problematic and how they should be properly handled for GCP and Kubernetes.

## 1. Static PodCIDR Routing & The "90-Second Stagger" Hack
**Issue:**
The implementation manually creates static GCP network routes in Terraform (`google_compute_route` for `cp_pod_route` and `worker_pod_route`) pointing to specific nodes. Because `kubeadm` assigns PodCIDRs sequentially as nodes join, a race condition occurs where Terraform's static routes might point to the wrong node if worker 2 joins before worker 1. To work around this, `bootstrap-ipv6.sh.tftpl` introduces an artificial 90-second sleep (`STAGGER_TIME=$(( ${node_index} * 90 ))`) per worker node index.

**Proper Handling:**
This is highly non-idiomatic and fragile. In a proper Kubernetes on GCP setup, Route management for Native Routing should be handled by the **Google Cloud Controller Manager (CCM)**. 
- You should deploy the external GCP `cloud-controller-manager`.
- Configure `kube-controller-manager` with `--allocate-node-cidrs=true`.
- Configure the GCP CCM with `--configure-cloud-routes=true`. 
This allows the CCM to dynamically read the PodCIDR assigned to each node and automatically create/update the necessary `google_compute_route` resources in GCP, completely eliminating the need for hardcoded Terraform routes and the artificial 90-second sleep stagger.

## 2. Using `ssh` in Terraform to Fetch Join Commands
**Issue:**
In `k8s_control_plane.tf`, the configuration uses the `ssh_resource` provider to SSH into the control plane and run `kubeadm token create --print-join-command`. This requires the machine running Terraform to have direct network access to the nodes (which forces the node to have a public IP and open SSH port). 
Furthermore, the bootstrap script contains dead code that writes the join command to GCP Guest Attributes (`curl -s -X PUT --data "$JOIN_CMD" ... guest-attributes/kubeadm/join-command`), which is not actually used by the worker nodes.

**Proper Handling:**
Terraform should be completely decoupled from the runtime state of the VM.
- **Idiomatic approach**: Pre-generate the `kubeadm` bootstrap token dynamically within Terraform (e.g., using the `random_string` resource to match the regex `[a-z0-9]{6}\.[a-z0-9]{16}`). Pass this token via `user-data` (startup scripts) to both the control plane (for `kubeadm init --token <TOKEN>`) and the worker nodes (for `kubeadm join --token <TOKEN>`). This completely removes the need to SSH into the control plane mid-deployment.

## 3. Brittle CoreDNS Configuration Replacement
**Issue:**
In `bootstrap-ipv6.sh.tftpl`, the script pipes a hardcoded YAML string replacing the entire `coredns` ConfigMap to force it to use Google Public DNS64 (`2001:4860:4860::6464`). If `kubeadm` changes the default CoreDNS template in future Kubernetes versions, this script will overwrite it with a potentially outdated or incompatible configuration, breaking DNS resolution.

**Proper Handling:**
Instead of replacing the entire ConfigMap blindly:
- Use `kubectl patch` or a structured update tool (like `yq`) to modify only the `forward` plugin block, preserving the rest of the configuration.
- Alternatively, utilize Kubelet's `--resolv-conf` argument to point to a custom `resolv.conf` file on the node that contains the DNS64 endpoints, which CoreDNS will naturally inherit.

## 4. Insecure Firewall Rules
**Issue:**
In `network.tf`, the firewall rule `allow_management_ipv6` opens SSH (port 22) and the Kubernetes API server (port 6443) to the entire IPv6 internet (`::/0`).

**Proper Handling:**
While this might just be intended as an exploratory example, it is a critical security vulnerability. 
- The Kubernetes API server and SSH should be restricted to trusted IP prefixes (e.g., your corporate office or specific VPN exit nodes).
- For SSH in GCP, the idiomatic approach is to use **Cloud Identity-Aware Proxy (IAP)**, which allows SSH access without needing external IPs. *(Note: IAP support for IPv6-only environments is still evolving, but at the very least, strict source IP filtering should be applied).*

## 5. Over-Permissive GCP Service Accounts
**Issue:**
The compute instances (`k8s_control_plane.tf` and `k8s_worker_node.tf`) use the default compute engine service account and assign it the broad `https://www.googleapis.com/auth/cloud-platform` API scope.

**Proper Handling:**
Nodes in a Kubernetes cluster should operate with the principle of least privilege. You should create a dedicated `google_service_account` for the nodes and assign it only the specific IAM roles required (e.g., `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/monitoring.viewer`). The `cloud-platform` scope should be avoided as it grants the VM broad administrative access to the GCP project (depending on the default service account's IAM bindings).

## 6. Manual Package Installation over OS Images
**Issue:**
The bootstrap script manually installs Containerd, Kubernetes tools (kubeadm, kubelet, kubectl), and Helm on every boot via `apt-get` during startup.

**Proper Handling:**
- **Idiomatic approach**: When working with immutable infrastructure (like Kubernetes nodes on cloud providers), you should ideally pre-bake these dependencies into a custom machine image using tools like HashiCorp Packer. This drastically reduces node startup time, prevents failures due to transient network issues while downloading packages, and ensures consistency across nodes.
