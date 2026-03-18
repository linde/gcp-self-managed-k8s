
resource "google_compute_instance" "worker_node" {
  count        = var.worker_node_count
  name         = "node-ipv6-${count.index + 1}-${local.rand_suffix}"
  project      = var.gcp_project
  machine_type = var.machine_type
  zone         = local.zone

  # IPv6-only stack
  can_ip_forward = true

  boot_disk {
    initialize_params {
      image = var.os_image
      size  = 40
    }
  }

  network_interface {
    network    = google_compute_network.k8s.id
    subnetwork = google_compute_subnetwork.k8s_subnet.id
    
    # IPv6 Stack configuration
    stack_type = "IPV6_ONLY"
    
    # Optional: Dynamic external IPv6 for management/debugging
    ipv6_access_config {
      network_tier = "PREMIUM"
    }
  }

  metadata = {
    "ssh-keys" = "admin:${tls_private_key.vm_ssh_key.public_key_openssh}"
  }

  service_account {
    email  = google_service_account.k8s_node.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/scripts/bootstrap-ipv6.sh.tftpl", {
    k8s_version           = var.k8s_version
    k8s_service_cidr_ipv6 = var.k8s_service_cidr_ipv6
    k8s_pod_cidr_ipv6      = var.k8s_pod_cidr_ipv6
    cp_public_ipv6        = google_compute_instance.cp_node.network_interface[0].ipv6_access_config[0].external_ipv6
    is_control_plane      = false
    node_index            = count.index
    kubeadm_token         = local.kubeadm_token
  })

  depends_on = [google_compute_instance.cp_node]
}
