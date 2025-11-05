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
# -----------------------------------------------------------------
# 1. CREATE DEDICATED SERVICE ACCOUNTS (SAs)
# -----------------------------------------------------------------
# We create one SA for the API and one for the Dashboard.
# This follows the principle of least privilege.

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

# -----------------------------------------------------------------
# 2. GRANT PERMISSIONS TO THE API'S SA
# -----------------------------------------------------------------
# The API service needs to connect to the database and read secrets.

# Allows the API to access the DB password from Secret Manager
resource "google_project_iam_member" "api_sa_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = google_service_account.api_sa.member
}

# Allows the API to connect to the Cloud SQL database
resource "google_project_iam_member" "api_sa_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = google_service_account.api_sa.member
}

# -----------------------------------------------------------------
# 3. GRANT PERMISSIONS BETWEEN SERVICES (THE 403 FIX)
# -----------------------------------------------------------------
# This explicitly allows the Dashboard to invoke the API.
# This is the fix for the 403 Forbidden error.

resource "google_cloud_run_service_iam_member" "dashboard_to_api_invoker" {
  project  = google_cloud_run_service.api.project
  location = google_cloud_run_service.api.location
  service  = google_cloud_run_service.api.name
  role     = "roles/run.invoker"

  # Member: The Dashboard SA
  # Resource: The API Service
  member   = google_service_account.dashboard_sa.member
}

# -----------------------------------------------------------------
# 4. GRANT PERMISSIONS TO THE CI/CD PIPELINE (THE 'actAs' FIX)
# -----------------------------------------------------------------
# This allows your GitHub Actions (github-actions-sa) to
# deploy services "as" the new SAs. This fixes the
# 'iam.serviceaccounts.actAs' PERMISSION_DENIED error.

resource "google_service_account_iam_member" "github_actas_api" {
  service_account_id = google_service_account.api_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:github-actions-sa@netprobe-473119.iam.gserviceaccount.com"
}

resource "google_service_account_iam_member" "github_actas_dashboard" {
  service_account_id = google_service_account.dashboard_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:github-actions-sa@netprobe-473119.iam.gserviceaccount.com"
}