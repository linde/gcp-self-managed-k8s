
resource "google_compute_network" "k8s" {
  name                    = "k8s-network-${local.rand_suffix}"
  project                 = var.gcp_project
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [time_sleep.wait_for_services]
}

resource "google_compute_subnetwork" "k8s_subnet" {
  name          = "k8s-subnet-${local.rand_suffix}"
  project       = var.gcp_project
  network       = google_compute_network.k8s.id
  region        = var.region
  ip_cidr_range = var.k8s_subnet_cidr
}

resource "google_compute_address" "cp_static_ip" {
  name   = "cp-static-ip-${local.rand_suffix}"
  region = var.region
}

# Allow ALL internal traffic within the subnet CIDR (all ports/protocols)
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


# Allow SSH and K8s API access from anywhere (for management)
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

# Route for Control Plane Pod IPs (For Native Routing)
resource "google_compute_route" "cp_pod_route" {
  name              = "k8s-pod-route-cp-${local.rand_suffix}"
  dest_range        = "192.168.0.0/24" # kubeadm's 1st allocated subnet natively starting at .0.0
  network           = google_compute_network.k8s.name
  next_hop_instance = google_compute_instance.cp_node.id
  priority          = 1000
}

# Route for Worker Node Pod IPs (For Native Routing)
resource "google_compute_route" "worker_pod_route" {
  count             = var.worker_node_count
  name              = "k8s-pod-route-worker-${count.index + 1}-${local.rand_suffix}"
  dest_range        = "192.168.${count.index + 1}.0/24" # kubeadm's 2nd+ allocated subnet (192.168.1.x, 192.168.2.x)
  network           = google_compute_network.k8s.name
  next_hop_instance = google_compute_instance.worker_node[count.index].id
  priority          = 1000
}
