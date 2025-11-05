# 1. Enable necessary APIs
resource "google_project_service" "run" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "vpcaccess" {
  project            = var.project_id
  service            = "vpcaccess.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# 2. Create the Artifact Registry to store our Docker images
resource "google_artifact_registry_repository" "docker_repo" {
  project       = var.project_id
  location      = var.region
  repository_id = "netprobe-docker-repo"
  description   = "Docker repository for NetProbe app images"
  format        = "DOCKER"
  depends_on    = [google_project_service.artifactregistry]
}

# 3. Create the Serverless VPC Connector
resource "google_vpc_access_connector" "main" {
  name          = "netprobe-vpc-connector"
  project       = var.project_id
  region        = var.region
  ip_cidr_range = "10.0.3.0/28" 
  network       = google_compute_network.main.name
  depends_on    = [google_project_service.vpcaccess]
}

# 4. Create the Cloud Run service for the API (v1 resource)
resource "google_cloud_run_service" "api" {
  name     = "netprobe-api"
  project  = var.project_id
  location = var.region

  # --- FIX 1 ---
  # 'ingress' annotation goes here, at the Service level
  metadata {
    annotations = {
      "run.googleapis.com/ingress" = "internal"
    }
  }

  template {
    # --- FIX 2 ---
    # VPC annotations go here, on the Revision template
    metadata {
      annotations = {
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.main.id
        "run.googleapis.com/vpc-access-egress"    = "private-ranges-only"
      }
    }
    spec {
      containers {
        image = "us-docker.pkg.dev/cloudrun/container/hello" # Placeholder
      }
      service_account_name = data.google_compute_default_service_account.default.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  autogenerate_revision_name = true
  depends_on                 = [google_vpc_access_connector.main]
}

# 5. Create the Cloud Run service for the Dashboard (v1 resource)
resource "google_cloud_run_service" "dashboard" {
  name     = "netprobe-dashboard"
  project  = var.project_id
  location = var.region

  # --- FIX 1 ---
  # 'ingress' annotation goes here, at the Service level
  metadata {
    annotations = {
      "run.googleapis.com/ingress" = "all"
    }
  }

  template {
    # --- FIX 2 ---
    # VPC annotations go here, on the Revision template
    metadata {
      annotations = {
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.main.id
        "run.googleapis.com/vpc-access-egress"    = "all-traffic"
      }
    }
    spec {
      containers {
        image = "us-docker.pkg.dev/cloudrun/container/hello" # Placeholder
      }
      service_account_name = data.google_compute_default_service_account.default.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  autogenerate_revision_name = true
  depends_on                 = [google_cloud_run_service.api]
}

# 6. Allow public (unauthenticated) users to view the dashboard (v1 resource)
resource "google_cloud_run_service_iam_member" "dashboard_public_access" {
  project  = google_cloud_run_service.dashboard.project
  location = google_cloud_run_service.dashboard.location
  service  = google_cloud_run_service.dashboard.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
