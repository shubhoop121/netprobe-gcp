# Ensures that the required Network Connectivity API is enabled for the project.
# This makes our Terraform configuration self-contained and repeatable.
resource "google_project_service" "network_connectivity" {
  project = var.project_id
  service = "networkconnectivity.googleapis.com"

  # Do not disable the API when destroying the infrastructure,
  # as other resources might depend on it.
  disable_on_destroy = false
}