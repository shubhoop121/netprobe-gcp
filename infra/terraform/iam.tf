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
# (Cloud SQL Client & Secret Accessor)
resource "google_project_iam_member" "api_sa_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = google_service_account.api_sa.member
}

resource "google_project_iam_member" "api_sa_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = google_service_account.api_sa.member
}

# -----------------------------------------------------------------
# 3. GRANT PERMISSIONS BETWEEN SERVICES (THE 403 FIX)
# -----------------------------------------------------------------
# (Allow Dashboard to invoke API)
resource "google_cloud_run_service_iam_member" "dashboard_to_api_invoker" {
  project  = google_cloud_run_service.api.project
  location = google_cloud_run_service.api.location
  service  = google_cloud_run_service.api.name
  role     = "roles/run.invoker"
  member   = google_service_account.dashboard_sa.member
}

# -----------------------------------------------------------------
# 4. GRANT "actAs" & "TokenCreator" PERMISSIONS TO THE CI/CD PIPELINE
# -----------------------------------------------------------------
# This allows 'github-actions-sa' to deploy "as" the new SAs
# AND to generate tokens (which fixes our test step).

# --- 'actAs' (Service Account User) bindings ---

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

# --- 'TokenCreator' bindings ---

resource "google_service_account_iam_member" "github_token_creator_api" {
  service_account_id = google_service_account.api_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:github-actions-sa@netprobe-473119.iam.gserviceaccount.com"
}

resource "google_service_account_iam_member" "github_token_creator_dashboard" {
  service_account_id = google_service_account.dashboard_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:github-actions-sa@netprobe-473119.iam.gserviceaccount.com"
}

resource "google_service_account_iam_member" "dashboard_sa_token_creator" {
  service_account_id = google_service_account.api_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  
  member             = google_service_account.dashboard_sa.member
}

# -----------------------------------------------------------------
#  GRANT PERMISSIONS FOR CLOUD ARMOR (Active Response)
# -----------------------------------------------------------------
# "Security Admin" allows the API to update Security Policy Rules directly.
resource "google_project_iam_member" "api_sa_security_admin" {
  project = var.project_id
  role    = "roles/compute.securityAdmin"
  member  = google_service_account.api_sa.member
}