# GCP Kubeadm Terraform

This project automates the creation of a Kubernetes cluster on Google Compute Engine (GCE) using `kubeadm` and Cilium (eBPF).

### What it does:
- **Infrastructure:** Provisions a custom VPC, subnet, static public IP, and firewall rules.
- **Control Plane:** Deploys a GCE instance, reserves a static IP, and initializes a Kubernetes control plane.
- **Networking:** Deploys Cilium with GCP Native Routing for high performance.
- **Worker Node:** Deploys a GCE instance and automatically joins it to the cluster via SSH-captured tokens.
- **Bootstrap:** Uses an idiomatic `templatefile` approach for OS prep and Kubernetes installation.

### Getting Started

```bash
terraform init

# Extract the project ID from your variables
export GCP_PROJECT=$(echo var.gcp_project | terraform console | tr -d '"' )

# Set your billing and folder info
export GCP_BILLING_ACCOUNT=[billing account]
export GCP_FOLDER=[folder]

# Create and link the project
gcloud projects create ${GCP_PROJECT} --folder=${GCP_FOLDER}
gcloud billing projects link $GCP_PROJECT --billing-account ${GCP_BILLING_ACCOUNT} 

# Deploy the infrastructure
terraform plan
terraform apply

# Capture the Control Plane Static IP
export CP_IP=$(echo google_compute_address.cp_static_ip.address | terraform console | tr -d '"')

# Download the admin config
export KUBECONFIG=.tmp/kubeconfig.yaml
ssh -o StrictHostKeyChecking=no -i .tmp/vm_key admin@${CP_IP} "sudo cat /etc/kubernetes/admin.conf" > ${KUBECONFIG}

# Update the server URL safely to use the public IP
kubectl config set-cluster kubernetes --server=https://${CP_IP}:6443

# Verify access from your local machine
kubectl get nodes

# then for example, deploy NGINX
kubectl apply -f https://k8s.io/examples/controllers/nginx-deployment.yaml

# profit!
```
