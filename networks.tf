
resource "google_compute_network" "k8s" {
  name                    = "k8s-network-${local.rand_suffix}"
  project                 = var.gcp_project
  auto_create_subnetworks = false 
  routing_mode            = "REGIONAL"

  depends_on = [ time_sleep.wait_for_services ]
}

resource "google_compute_subnetwork" "k8s_subnet" {
  name          = "k8s-subnet-${local.rand_suffix}"
  project       = var.gcp_project
  network       = google_compute_network.k8s.id
  region        = var.region
  ip_cidr_range = "10.0.0.0/24"
}

# 1. Allow ALL internal traffic within the subnet (all ports/protocols)
resource "google_compute_firewall" "allow_internal_all" {
  name      = "allow-internal-all-${local.rand_suffix}"
  project   = var.gcp_project
  network   = google_compute_network.k8s.id
  direction = "INGRESS"
  priority  = 100

  allow {
    protocol = "all"
  }
  
  source_ranges = [google_compute_subnetwork.k8s_subnet.ip_cidr_range]
}

# 2. Allow SSH and K8s API access from anywhere (for management)
resource "google_compute_firewall" "allow_management" {
  name    = "allow-management-${local.rand_suffix}"
  project = var.gcp_project
  network = google_compute_network.k8s.id

  allow {
    protocol = "tcp"
    ports    = ["22", "6443"]
  }

  source_ranges = ["0.0.0.0/0"]
}
