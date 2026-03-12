
resource "google_project_service" "services" {
  project = var.gcp_project
  for_each = toset([
    "compute.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# Wait for the Compute API to fully propagate
resource "time_sleep" "wait_for_services" {
  depends_on      = [google_project_service.services]
  create_duration = "45s"
}
