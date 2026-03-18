# Create the Compute Engine Instance
resource "google_compute_instance" "cp_node" {
  name           = "cp-${local.rand_suffix}"
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
    access_config {
      nat_ip = google_compute_address.cp_static_ip.address
    }
  }

  # Injects the public key we generated into the VM
  metadata = {
    "ssh-keys" = "admin:${tls_private_key.vm_ssh_key.public_key_openssh}"
  }

  # Use templatefile for cleaner, idiomatic bootstrap scripts
  metadata_startup_script = templatefile("${path.module}/scripts/bootstrap.sh.tftpl", {
    k8s_version      = var.k8s_version
    k8s_subnet_cidr  = var.k8s_subnet_cidr
    cp_public_ip     = google_compute_address.cp_static_ip.address
    is_control_plane = true
    kubeadm_token    = local.kubeadm_token
    cp_internal_ip   = ""
  })

  # Ensure services are ready and propagated
  depends_on = [time_sleep.wait_for_services]

}

# Kubeadm Token Generation
resource "random_string" "token_id" {
  length  = 6
  special = false
  upper   = false
}

resource "random_string" "token_secret" {
  length  = 16
  special = false
  upper   = false
}

locals {
  kubeadm_token = "${random_string.token_id.result}.${random_string.token_secret.result}"
}
