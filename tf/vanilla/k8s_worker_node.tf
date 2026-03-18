
resource "google_compute_instance" "worker_node" {
  count          = var.worker_node_count
  name           = "node-${count.index + 1}-${local.rand_suffix}"
  project        = var.gcp_project
  machine_type   = var.machine_type
  zone           = local.zone
  can_ip_forward = true
  tags           = ["k8s-node"]

  service_account {
    email  = google_service_account.k8s_node.email
    scopes = ["cloud-platform"]
  }

  boot_disk {
    initialize_params {
      image = var.os_image
      size  = 40
    }
  }

  network_interface {
    network    = google_compute_network.k8s.id
    subnetwork = google_compute_subnetwork.k8s_subnet.id
    access_config {} // Ephemeral public IP
  }

  # Injects the public key we generated into the VM
  metadata = {
    "ssh-keys" = "admin:${tls_private_key.vm_ssh_key.public_key_openssh}"
  }

  # Use templatefile with the join command captured via SSH
  metadata_startup_script = templatefile("${path.module}/scripts/bootstrap.sh.tftpl", {
    k8s_version      = var.k8s_version
    k8s_subnet_cidr  = var.k8s_subnet_cidr
    cp_public_ip     = google_compute_address.cp_static_ip.address
    is_control_plane = false
    kubeadm_token    = local.kubeadm_token
    cp_internal_ip   = google_compute_instance.cp_node.network_interface[0].network_ip
  })

  # Explicitly depend on services being ready and the join command being available
  depends_on = [time_sleep.wait_for_services, google_compute_instance.cp_node]
}

