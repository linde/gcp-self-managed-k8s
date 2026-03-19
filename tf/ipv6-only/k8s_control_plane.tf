
resource "google_compute_instance" "cp_node" {
  name         = "cp-ipv6-${local.rand_suffix}"
  project      = var.gcp_project
  machine_type = var.machine_type
  zone         = local.zone

  # IPv6-only stack
  can_ip_forward = true
  tags           = ["k8s-node"]

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
    email  = google_service_account.k8s_node.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/../scripts/bootstrap.sh.tftpl", {
    k8s_version       = var.k8s_version
    k8s_service_cidr  = var.k8s_service_cidr_ipv6
    k8s_pod_cidr      = var.k8s_pod_cidr_ipv6
    cp_public_ip      = ""
    cp_join_ip        = ""
    is_control_plane  = true
    ipv6_enabled      = true
    kubeadm_token     = local.kubeadm_token
    ccm_yaml          = templatefile("${path.module}/../scripts/ccm.yaml.tftpl", {
      cluster_cidr = var.k8s_pod_cidr_ipv6
    })
  })

  # Remove node from cluster on destroy so we clean up cloud controller managed GCP resources
  provisioner "local-exec" {
    when    = destroy
    command = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${path.module}/.tmp/vm_key admin@${self.network_interface[0].ipv6_access_config[0].external_ipv6} 'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf delete node ${self.name} && sleep 20'"
  }

  depends_on = [
    time_sleep.wait_for_services, 
    local_file.private_key,
    google_compute_firewall.allow_management_ipv6,
    google_compute_firewall.allow_internal_ipv6_all
  ]
}

resource "random_string" "token_id" {
  length  = 6
  lower   = true
  numeric = true
  upper   = false
  special = false
}

resource "random_string" "token_secret" {
  length  = 16
  lower   = true
  numeric = true
  upper   = false
  special = false
}

locals {
  kubeadm_token = "${random_string.token_id.result}.${random_string.token_secret.result}"
}
