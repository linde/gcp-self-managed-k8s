
resource "google_compute_instance" "cp_node" {
  name         = "cp-ipv6-${local.rand_suffix}"
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

    ipv6_access_config {
      network_tier = "PREMIUM"
    }
  }

  metadata = {
    "ssh-keys" = "admin:${tls_private_key.vm_ssh_key.public_key_openssh}"
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/scripts/bootstrap-ipv6.sh.tftpl", {
    k8s_version          = var.k8s_version
    k8s_service_cidr_ipv6 = var.k8s_service_cidr_ipv6
    k8s_pod_cidr_ipv6     = var.k8s_pod_cidr_ipv6
    is_control_plane     = true
    join_command         = ""
  })

  depends_on = [time_sleep.wait_for_services]
}

# Fetch the join command using the dynamic external IPv6
resource "ssh_resource" "get_join_command" {
  host        = google_compute_instance.cp_node.network_interface[0].ipv6_access_config[0].external_ipv6
  user        = "admin"
  private_key = tls_private_key.vm_ssh_key.private_key_openssh
  timeout     = "10m"

  commands = [
    "while [ ! -f /etc/kubernetes/admin.conf ]; do sleep 5; done",
    "sudo kubeadm token create --print-join-command"
  ]

  depends_on = [google_compute_instance.cp_node]
}
