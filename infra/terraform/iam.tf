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

# Grant the Compute Engine default SA (used by our API) the Cloud SQL Client role
resource "google_project_iam_member" "api_runtime_sa_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

# Grant the Compute Engine default SA (used by our API) the Secret Accessor role
# (This might be redundant if compute_sa_secret_accessor is already present,
# but it is good practice to be explicit for the API's runtime SA)
resource "google_project_iam_member" "api_runtime_sa_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}