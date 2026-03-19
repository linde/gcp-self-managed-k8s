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
  metadata_startup_script = templatefile("${path.module}/../scripts/bootstrap.sh.tftpl", {
    k8s_version      = var.k8s_version
    k8s_service_cidr = ""
    k8s_pod_cidr     = "192.168.0.0/16"
    cp_public_ip     = google_compute_address.cp_static_ip.address
    cp_join_ip       = ""
    is_control_plane = true
    ipv6_enabled     = false
    kubeadm_token    = local.kubeadm_token
    ccm_yaml         = templatefile("${path.module}/../scripts/ccm.yaml.tftpl", {
      cluster_cidr = "192.168.0.0/16"
    })
  })

  # Remove node from cluster on destroy so we clean up cloud controller managed GCP resources
  provisioner "local-exec" {
    when    = destroy
    command = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${path.module}/.tmp/vm_key admin@${self.network_interface[0].access_config[0].nat_ip} 'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf delete node ${self.name} && sleep 20'"
  }

  # Ensure services are ready and propagated
  depends_on = [
    time_sleep.wait_for_services, 
    local_file.private_key,
    google_compute_firewall.allow_management,
    google_compute_firewall.allow_internal_all
  ]

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
