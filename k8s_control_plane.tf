# 3. Create the Compute Engine Instance
resource "google_compute_instance" "cp_node" {
  name           = "cp-${local.rand_suffix}"
  project        = var.gcp_project
  machine_type   = var.machine_type
  zone           = local.zone
  can_ip_forward = true
  tags           = ["k8s-node"]

  service_account {
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

  # Use templatefile for cleaner, idiomatic bootstrap scripts
  metadata_startup_script = templatefile("${path.module}/scripts/bootstrap.sh.tftpl", {
    k8s_version      = var.k8s_version
    k8s_subnet_cidr  = var.k8s_subnet_cidr
    is_control_plane = true
    join_command     = "" # Not needed for control plane
  })

  # Ensure services are ready and propagated
  depends_on = [time_sleep.wait_for_services]

}

# 4. Use the SSH provider to fetch the join command from the VM
resource "ssh_resource" "get_join_command" {
  host        = google_compute_instance.cp_node.network_interface[0].access_config[0].nat_ip
  user        = "admin"
  private_key = tls_private_key.vm_ssh_key.private_key_openssh

  # Set a connection and command execution timeout (10 minutes)
  timeout = "10m"

  commands = [
    # Poll until the admin.conf exists, ensuring kubeadm init is done
    "while [ ! -f /etc/kubernetes/admin.conf ]; do sleep 3; done",
    "sudo kubeadm token create --print-join-command"
  ]

  depends_on = [google_compute_instance.cp_node]
}
