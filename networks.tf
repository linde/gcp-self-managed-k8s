
resource "google_compute_network" "k8s" {
  name                    = "k8s-network-${local.rand_suffix}"
  project                 = var.gcp_project
  auto_create_subnetworks = false

  depends_on = [time_sleep.wait_for_services]
}

resource "google_compute_subnetwork" "k8s_subnet" {
  name          = "k8s-subnet-${local.rand_suffix}"
  project       = var.gcp_project
  network       = google_compute_network.k8s.id
  region        = var.region
  ip_cidr_range = "10.0.0.0/24"
}


## Firewall Rules

# Allow internal traffic between all nodes in the subnet
resource "google_compute_firewall" "allow_internal" {
  name      = "allow-internal-k8s-${local.rand_suffix}"
  project   = var.gcp_project
  network   = google_compute_network.k8s.id
  direction = "INGRESS"

  allow {
    protocol = "all"
  }

  # Allow all internal traffic within the subnet
  source_ranges = [google_compute_subnetwork.k8s_subnet.ip_cidr_range]
}

# Allow SSH access (Required for the ssh_resource provider)
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh-k8s-${local.rand_suffix}"
  project = var.gcp_project
  network = google_compute_network.k8s.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"] # Change this to your IP for better security
}

# Allow Kubernetes API access (Required for kubeadm join)
resource "google_compute_firewall" "allow_k8s_api" {
  name    = "allow-k8s-api-${local.rand_suffix}"
  project = var.gcp_project
  network = google_compute_network.k8s.id

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = ["0.0.0.0/0"]
}
