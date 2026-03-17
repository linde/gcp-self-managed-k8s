# GCP Kubeadm Terraform

This project automates the creation of a Kubernetes cluster on Google
Compute Engine (GCE) using `kubeadm` and Cilium (eBPF). It was
intended just to explore problem space -- anyone iterested in
Kubernetes on GCP is _HIGHLY_ recommended to use the Google Kubernetes
Engine ([GKE](https://cloud.google.com/kubernetes-engine)) instead of
rolling their own.

With that caveat, this project provides two implementation examples:

* **Vanilla:** A standard vanilla cluster.
* **IPv6-Only:** A pure IPv6 cluster leveraging GCE's native IPv6-only subnets.

---

## 1. Getting Started (Vanilla)

The vanilla implementation creates a standard Kubernetes cluster with external IPv4 access and internal networking managed by Cilium.

### Configuration
You can easily scale the vanilla cluster by overriding `worker_node_count` in your `terraform.tfvars`. We default to 2 worker nodes. The maximum supported number of worker nodes is 253, as kubeadm allocates a `/24` (254 addresses) per node from the `192.168.0.0/16` cluster CIDR.

### Deployment

```bash
cd tf/vanilla 
terraform init

# Deploy the infrastructure
terraform plan
terraform apply

# Capture the Control Plane IP and setup Kubeconfig
export CP_IP=$(terraform output -raw control_plane_public_ip)
export KUBECONFIG=$(pwd)/.tmp/kubeconfig.yaml
ssh -o StrictHostKeyChecking=no -i .tmp/vm_key admin@${CP_IP} "sudo cat /etc/kubernetes/admin.conf" > ${KUBECONFIG}

# Verify the cluster
kubectl get nodes -o wide
```

### See it in action
Deploy a sample NGINX deployment to verify pod networking:
```bash
kubectl apply -f https://k8s.io/examples/controllers/nginx-deployment.yaml
kubectl get pods -w
```

### Cleanup (Vanilla)
```bash
terraform destroy
```

---

## 2. Moving to IPv6-Only

The `ipv6-only` implementation uses GCE's `IPV6_ONLY` stack type. This requires a machine with IPv6 connectivity to access the API server externally.

### Deployment

```bash
cd tf/ipv6-only
terraform init
terraform apply

# Capture the IPv6 address
export CP_IPV6=$(terraform output -raw control_plane_public_ipv6)

# Download config (Note: your local machine must have IPv6 access)
export KUBECONFIG=$(pwd)/.tmp/kubeconfig.yaml
ssh -o StrictHostKeyChecking=no -i .tmp/vm_key admin@${CP_IPV6} "sudo cat /etc/kubernetes/admin.conf" > ${KUBECONFIG}

# Verify access (after the nodes have had a chance to join)
kubectl get nodes -o wide
```

### Infrastructure Details

This repository demonstrates how to solve several quirks when running **eBPF (Cilium)** in an **IPv6-Only** Google Cloud environment.

- **Scaling (`worker_node_count`):** You can easily scale the cluster by overriding `worker_node_count` in your `terraform.tfvars`. We default to 2.
- **GCP Native Routing:** Cilium requires knowing how to route Pod traffic across nodes. Instead of relying on VXLAN tunneling and its overhead, this project leverages **Native Routing**. Native Routing works by using Terraform `google_compute_route` resources to explicitly map Kubernetes PodCIDRs (`fd00:10:0:X::/64`) directly to the VM instances within the GCP VPC.
- **Race Condition Staggering**: Kubernetes `kube-controller-manager` assigns PodCIDRs sequentially to nodes strictly based on the millisecond they join the cluster. Because package installation times (`apt-get`) vary, a naive `kubeadm join` will result in Terraform's static route map getting misaligned with the actual acquired PodCIDR. The `bootstrap-ipv6.sh.tftpl` resolves this naturally by calculating an absolute **90-second stagger** per node based on its index (`T+0` for CP, `T+90` for worker 1, `T+180` for worker 2), guaranteeing deterministic CIDR acquisition and seamless Native Routing. Improvements for this approach are welcome!
- **NAT64:** Configured via Cloud NAT to allow the cluster to reach IPv4-only services (like GitHub or Docker Hub).
- **Cilium:** Installed via Helm during bootstrap with `ipv6.enabled=true`, `ipv4.enabled=false`, and `routingMode=native`.
- **CoreDNS Upstream**: A configmap patch forces CoreDNS to utilize Google's Public DNS64 endpoints (`2001:4860:4860::6464`) to restore external resolution to pods since the host `systemd-resolved` doesn't pass native IPv6 DNS effectively.

### Cleanup (IPv6-Only)
```bash
terraform destroy
```


### IPv6 Debugging utilities

```
# use the following to try out networking tools within a pod on the cluster
kubectl run -i --tty --rm debug-session --image=jonasal/network-tools --restart=Never -- /bin/bash

# the within that pod
dig google.com AAAA
ping -6 google.com

curl -6 http://google.com

# one curveball, github who doesn't support ipv6 but we can resolve with 6to4
dig github.com AAAA

# these dont work
ping -6 github.com
curl -6 http://github.com

```

## Automated Reachability Testing

This project includes a built-in reachability testing suite to experiment with pod-to-pod networking (both vanilla and IPv6-only) within a cluster. 

Please see the [Reachability Testing Documentation](docs/examples/reachability-testing.md) for full instructions on how to use `kind` to mock this locally, deploy the workloads, read the test results, and understand the dual-stack logic.
