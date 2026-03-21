# GCP Kubeadm Terraform

This project automates the creation of a Kubernetes cluster on Google Compute Engine (GCE) using `kubeadm` and Cilium (eBPF). It was intended just to explore problem space -- anyone interested in Kubernetes on GCP is _HIGHLY_ recommended to use the Google Kubernetes Engine ([GKE](https://cloud.google.com/kubernetes-engine)) instead of rolling their own.

With that caveat, this project provides two implementation examples:

* **Vanilla:** A standard vanilla cluster with external IPv4 access.
* **IPv6-Only:** A pure IPv6 cluster leveraging GCE's native IPv6-only subnets.

---

## 1. Getting Started

### Configuration
Really the only required configuration is to set the `gcp_project` variable. Additionally, you can scale the size of the cluster by overriding `worker_node_count` in your `terraform.tfvars`. We default to 2 worker nodes. The maximum supported number of worker nodes is 253, as kubeadm allocates a `/24` (254 addresses) per node from the cluster CIDR.

### Deployment

First, navigate to the directory of the implementation you want to deploy. 
*(Note: For IPv6-Only, your local machine must have IPv6 connectivity to access the API server.)*

```bash
# For Vanilla (IPv4)
cd tf/vanilla 

# OR For IPv6-Only
cd tf/ipv6-only
```

Initialize and deploy the infrastructure:

```bash
terraform init
terraform plan
terraform apply
```

Capture the Control Plane IP and setup Kubeconfig:

```bash
export CP_IP=$(terraform output -raw control_plane_public_ip)
export KUBECONFIG=$(pwd)/.tmp/kubeconfig.yaml

# Download config (this might take a minute, tf comes back when the machine is up, but the scripts might take longer ...)
# repeat if you get: `cat: /etc/kubernetes/admin.conf: No such file or directory`
ssh -o StrictHostKeyChecking=no -i .tmp/vm_key admin@${CP_IP} "sudo cat /etc/kubernetes/admin.conf" > ${KUBECONFIG}

# watch as the pods, then nodes come up
 kubectl get nodes,pods -A
 
```

### See it in action

Deploy a sample NGINX application exposed via a LoadBalancer service to verify pod networking and external access:

```bash
# For Vanilla (IPv4)
kubectl apply -f ../../docs/examples/nginx-loadbalancer-ipv4.yaml

# For IPv6-Only
kubectl apply -f ../../docs/examples/nginx-loadbalancer-ipv6.yaml

# then either way
kubectl get pods 
```

Once the pods are running, find the External IP of the LoadBalancer:

```bash
kubectl get service nginx-loadbalancer
```

> [!IMPORTANT]
> **IPv6 LoadBalancer Limitation:** In this custom `kubeadm` setup, the `nginx-loadbalancer-ipv6.yaml` Service is expected to remain in the `<pending>` state indefinitely due to limitations with the open-source GCP Cloud Provider natively provisioning external IPv6 LoadBalancers. See the [IPv6 LoadBalancer Limitation Plan](docs/ipv6-loadbalancer-limitation.md) for root causes, technical details, and workarounds.

Wait for the `EXTERNAL-IP` to transition from `<pending>` to an actual IP address. Then, test the connection using `curl`:

```bash
# For Vanilla (IPv4)
curl -4 http://<EXTERNAL-IP>

# For IPv6-Only
curl -6 http://<EXTERNAL-IP>
```

### Cleanup
When you are done experimenting, tear down the infrastructure:
```bash
terraform destroy
```

### Next Steps
We encourage you to experiment! If you started with the `vanilla` implementation, try tearing it down and provisioning the `ipv6-only` side to see GCE's native IPv6 networking in action. (And vice-versa!)

---

## 2. Infrastructure Details / Quirks

This repository demonstrates how to solve several quirks when running **eBPF (Cilium)** in an **IPv6-Only** Google Cloud environment.

- **Deterministic Node Joining:** Instead of relying on fragile SSH provisioners executing during `terraform apply` to fetch the `kubeadm join` command, a secure token is generated natively in Terraform. This token is injected directly into the GCP instance startup scripts to seamlessly bootstrap the control plane and instantly join worker nodes without requiring external Terraform SSH access.
- **GCP Native Routing:** Cilium requires knowing how to route Pod traffic across nodes. Instead of relying on VXLAN tunneling and its overhead, this project leverages **Native Routing**. Native Routing is achieved seamlessly by deploying the **Google Cloud Controller Manager (CCM)**, which automatically maps and provisions GCP Routes in the VPC for the assigned Kubernetes Pod CIDRs (`fd00:10:0:X::/64`) as nodes join the cluster.
- **NAT64:** Configured via Cloud NAT to allow the cluster to reach IPv4-only services (like GitHub or Docker Hub).
- **Cilium:** Installed via Helm during bootstrap with `ipv6.enabled=true`, `ipv4.enabled=false`, and `routingMode=native`.
- **CoreDNS Upstream**: A configmap patch forces CoreDNS to utilize Google's Public DNS64 endpoints (`2001:4860:4860::6464`) to restore external resolution to pods since the host `systemd-resolved` doesn't pass native IPv6 DNS effectively.
- **CCM Leaked Routes on Teardown:** When using GCP Native Routing, the Cloud Controller Manager dynamically creates VPC network routes outside of Terraform's state. Left completely alone, `terraform destroy` will fail and hang because GCP blocks VPC deletion while these orphaned routes still depend on it. To mitigate this without relying on external CLI tools, the Terraform worker nodes use a `local-exec` provisioner during destruction to SSH into the Control Plane and gracefully execute `kubectl delete node`. This allows the CCM to automatically clean up its own VPC routes before the underlying VM is destroyed. See the [CCM Leaked Routes Plan](docs/plans/ccm_leaked_routes_plan.md) for details.

### IPv6 Debugging utilities

```bash

# to watch the control plan script run
ssh -F /dev/null -o StrictHostKeyChecking=no -i .tmp/vm_key admin@${CP_IP}  \
  "sudo journalctl  -u google-startup-scripts.service -f " | sed 's-^.*/bin/bash.*: --g'

# use the following to try out networking tools within a pod on the cluster
kubectl run -i --tty --rm debug-session --image=jonasal/network-tools --restart=Never -- /bin/bash

# then within that pod
dig google.com AAAA
ping -6 google.com
curl -6 http://google.com

# one curveball, github who doesn't support ipv6 but we can resolve with 6to4
dig github.com AAAA

# these dont work
ping -6 github.com
curl -6 http://github.com
```

---

## 3. Automated Reachability Testing

This project includes a built-in reachability testing suite to experiment with pod-to-pod networking (both vanilla and IPv6-only) within a cluster. 

Please see the [Reachability Testing Documentation](docs/examples/reachability-testing.md) for full instructions on how to use `kind` to mock this locally, deploy the workloads, read the test results, and understand the dual-stack logic.
