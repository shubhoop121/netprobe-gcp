# This data block finds the email of the default Compute Engine service account
data "google_compute_default_service_account" "default" {
  project = var.project_id
}

# This resource grants the Secret Manager Accessor role to that service account
resource "google_project_iam_member" "compute_sa_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}