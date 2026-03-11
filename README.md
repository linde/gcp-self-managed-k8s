# GCP Kubeadm Terraform

This project automates the creation of a minimal test Kubernetes cluster on Google Compute Engine (GCE) using `kubeadm`. 

### What it does:
- **Infrastructure:** Provisions a custom VPC, subnet, and firewall rules (SSH, K8s API, Internal).
- **Control Plane:** Deploys a GCE instance and initializes a Kubernetes control plane with Calico pod networking.
- **Worker Node:** Deploys a GCE instance and automatically joins it to the cluster using a join command captured via SSH from the control plane.
- **Bootstrap:** Uses an idiomatic `templatefile` approach for OS prep and Kubernetes installation.

### Getting Started

```bash
terraform init

# Extract the project ID from your variables
export GCP_PROJECT=$(echo var.gcp_project | terraform console | sed s/\"//g )

# Set your billing and folder info
export GCP_BILLING_ACCOUNT=[billing account]
export GCP_FOLDER=[folder]

# Create and link the project
gcloud projects create ${GCP_PROJECT} --folder=${GCP_FOLDER}
gcloud billing projects link $GCP_PROJECT --billing-account ${GCP_BILLING_ACCOUNT} 

# Deploy the infrastructure
terraform plan
terraform apply

# Capture the Control Plane IP
export CP_IP=$(echo google_compute_instance.cp_node.network_interface[0].access_config[0].nat_ip | terraform console | tr -d '"')
export NODE_IP=$(echo google_compute_instance.worker_node.network_interface[0].access_config[0].nat_ip | terraform console | tr -d '"')

# SSH in and configure kubectl locally
ssh -o StrictHostKeyChecking=no -i .tmp/vm_key admin@${CP_IP}
mkdir -p .kube ; sudo cat /etc/kubernetes/admin.conf | cat > .kube/config
kubectl get nodes

# Then for example, deploy NGINX
kubectl apply -f https://k8s.io/examples/controllers/nginx-deployment.yaml

# profit!

```
