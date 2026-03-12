# GCP Kubeadm Terraform

This project automates the creation of a Kubernetes cluster on Google Compute Engine (GCE) using `kubeadm` and Cilium (eBPF). 

It provides two implementation examples:
1. **Vanilla:** A standard dual-stack (IPv4/IPv6) cluster.
2. **IPv6-Only:** A pure IPv6 cluster leveraging GCE's native IPv6-only subnets.

---

## 1. Getting Started (Vanilla)

The vanilla implementation creates a standard Kubernetes cluster with external IPv4 access and internal networking managed by Cilium.

### Deployment

```bash
cd tf/vanilla 
terraform init

# Deploy the infrastructure
terraform plan
terraform apply

# Capture the Control Plane IP and setup Kubeconfig
export CP_IP=$(terraform output -raw control_plane_public_ip)
export KUBECONFIG=.tmp/kubeconfig.yaml
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
export KUBECONFIG=.tmp/kubeconfig.yaml
scp -i .tmp/vm_key admin@[${CP_IPV6}]:/etc/kubernetes/admin.conf ${KUBECONFIG}

# Verify access
kubectl get nodes -o wide
```

### Infrastructure Details
- **Networking:** Uses `stack_type = "IPV6_ONLY"` and GCE Native Routing.
- **NAT64:** Configured via Cloud NAT to allow the cluster to reach IPv4-only services (like GitHub or Docker Hub).
- **Cilium:** Installed via Helm during bootstrap with `ipv6.enabled=true` and `ipv4.enabled=false`.

### Cleanup (IPv6-Only)
```bash
terraform destroy
```
