output "control_plane_public_ip" {
  value = google_compute_instance.cp_node.network_interface[0].access_config[0].nat_ip
}
