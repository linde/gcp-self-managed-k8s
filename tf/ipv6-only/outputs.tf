output "control_plane_public_ip" {
  value = google_compute_instance.cp_node.network_interface[0].ipv6_access_config[0].external_ipv6
}
