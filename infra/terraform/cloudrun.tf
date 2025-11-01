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

# 4. Create the Cloud Run service for the API
resource "google_cloud_run_v2_service" "api" {
  name     = "netprobe-api"
  project  = var.project_id
  location = var.region
  
  # This controls who can access it.
  ingress = "INGRESS_TRAFFIC_ALL"
  
  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello" # Placeholder
    }
    
    # The 'vpc_access' block correctly defines egress for VPC traffic
    vpc_access {
      connector = google_vpc_access_connector.main.id
      # This setting routes all outbound traffic through the VPC
      egress    = "PRIVATE_RANGES_ONLY" 
    }
  }

  depends_on = [google_vpc_access_connector.main]
}

# 5. Create the Cloud Run service for the Dashboard
resource "google_cloud_run_v2_service" "dashboard" {
  name     = "netprobe-dashboard"
  project  = var.project_id
  location = var.region

  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello" # Placeholder
    }
    service_account = data.google_compute_default_service_account.default.email
  }

  depends_on = [google_cloud_run_v2_service.api]
}

# 6. Allow public (unauthenticated) users to view the dashboard
resource "google_cloud_run_v2_service_iam_member" "dashboard_public_access" {
  project  = google_cloud_run_v2_service.dashboard.project
  location = google_cloud_run_v2_service.dashboard.location
  name     = google_cloud_run_v2_service.dashboard.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "api_service_url" {
  description = "The public URL of the netprobe-api service"
  value       = google_cloud_run_v2_service.api.uri
}

output "dashboard_service_url" {
  description = "The public URL of the netprobe-dashboard service"
  value       = google_cloud_run_v2_service.dashboard.uri
}

