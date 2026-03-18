resource "google_service_account" "k8s_node" {
  account_id   = "k8s-node-ipv6-${local.rand_suffix}"
  display_name = "Kubernetes Node Service Account"
  project      = var.gcp_project
}

resource "google_project_iam_member" "network_admin" {
  project = var.gcp_project
  role    = "roles/compute.networkAdmin"
  member  = "serviceAccount:${google_service_account.k8s_node.email}"
}

resource "google_project_iam_member" "compute_viewer" {
  project = var.gcp_project
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.k8s_node.email}"
}
