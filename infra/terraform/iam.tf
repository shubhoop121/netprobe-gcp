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

# --- 1. Define Dedicated Service Accounts ---
resource "google_service_account" "api_sa" {
  account_id   = "netprobe-api"
  display_name = "NetProbe API Runtime SA"
  project      = var.project_id
}

resource "google_service_account" "dashboard_sa" {
  account_id   = "netprobe-dashboard"
  display_name = "NetProbe Dashboard Runtime SA"
  project      = var.project_id
}

# --- 2. Grant API SA Required Permissions ---
# The API service needs to access Secret Manager for the DB password
resource "google_project_iam_member" "api_sa_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = google_service_account.api_sa.member
}

# The API service needs to connect to the Cloud SQL database
resource "google_project_iam_member" "api_sa_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = google_service_account.api_sa.member
}

# --- 3. Grant Dashboard SA Permission to Invoke API ---
# This is the explicit fix for the 403 error.
# It clearly states: "Dashboard" can invoke "API".
resource "google_cloud_run_service_iam_member" "dashboard_to_api_invoker" {
  project  = google_cloud_run_service.api.project
  location = google_cloud_run_service.api.location
  service  = google_cloud_run_service.api.name
  role     = "roles/run.invoker"

  # The member is the identity of the DASHBOARD service
  member   = google_service_account.dashboard_sa.member
}