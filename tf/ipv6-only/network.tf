
resource "google_compute_network" "k8s" {
  name                    = "k8s-network-ipv6-${local.rand_suffix}"
  project                 = var.gcp_project
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  # Required for IPv6 stack in GCE
  enable_ula_internal_ipv6 = true

  depends_on = [time_sleep.wait_for_services]
}

resource "google_compute_subnetwork" "k8s_subnet" {
  name          = "k8s-subnet-ipv6-${local.rand_suffix}"
  project       = var.gcp_project
  network       = google_compute_network.k8s.id
  region        = var.region
  
  # For IPV6_ONLY stack, NO ip_cidr_range (IPv4) should be provided.
  stack_type       = "IPV6_ONLY"
  ipv6_access_type = "EXTERNAL"
}

# Allow ALL internal IPv6 traffic within the subnet
resource "google_compute_firewall" "allow_internal_ipv6_all" {
  name      = "allow-internal-ipv6-all-${local.rand_suffix}"
  project   = var.gcp_project
  network   = google_compute_network.k8s.id
  direction = "INGRESS"
  priority  = 100

  allow {
    protocol = "all"
  }

  source_ranges = ["::/0"] 
}

# Allow SSH and K8s API access from anywhere (IPv6)
resource "google_compute_firewall" "allow_management_ipv6" {
  name    = "allow-management-ipv6-${local.rand_suffix}"
  project = var.gcp_project
  network = google_compute_network.k8s.id

  allow {
    protocol = "tcp"
    ports    = ["22", "6443"]
  }

  source_ranges = ["::/0"]
}

# Cloud Router and NAT (NAT64)
# Required for IPv6-only instances to reach IPv4-only sites (GitHub, pkgs.k8s.io)
resource "google_compute_router" "router" {
  name    = "k8s-router-ipv6-${local.rand_suffix}"
  project = var.gcp_project
  network = google_compute_network.k8s.id
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name    = "k8s-nat-ipv6-${local.rand_suffix}"
  project = var.gcp_project
  router  = google_compute_router.router.name
  region  = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # NAT64 is enabled automatically by GCP when the subnet is IPv6-only
  # and the NAT is configured.
}

# Route for Control Plane Pod IPs (For Native Routing)
resource "google_compute_route" "cp_pod_route" {
  name              = "k8s-pod-route-cp-${local.rand_suffix}"
  dest_range        = "fd00:10::/64" # kubeadm's 1st allocated subnet
  network           = google_compute_network.k8s.name
  next_hop_instance = google_compute_instance.cp_node.id
  priority          = 1000
}

# Route for Worker Node Pod IPs (For Native Routing)
resource "google_compute_route" "worker_pod_route" {
  count             = var.worker_node_count
  name              = "k8s-pod-route-worker-${count.index + 1}-${local.rand_suffix}"
  dest_range        = "fd00:10:0:${count.index + 1}::/64" # kubeadm's 2nd+ allocated subnet
  network           = google_compute_network.k8s.name
  next_hop_instance = google_compute_instance.worker_node[count.index].id
  priority          = 1000
}
