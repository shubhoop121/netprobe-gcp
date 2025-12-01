# infra/terraform/identity_job.tf

# 1. The Cloud Run Job (The Worker)
resource "google_cloud_run_v2_job" "identity_engine" {
  name     = "netprobe-identity-engine"
  location = var.region
  project  = var.project_id

  template {
    template {
      containers {
        image = "us-docker.pkg.dev/cloudrun/container/hello" # Placeholder, updated by CI/CD
        
        env {
          name = "DB_NAME"
          value = "netprobe_logs"
        }
        env {
          name = "DB_USER"
          value = "netprobe_user"
        }
      }
      service_account = google_service_account.api_sa.email # Reuse the API SA (it has DB permissions)
      
      vpc_access {
        connector = google_vpc_access_connector.main.id
        egress    = "PRIVATE_RANGES_ONLY"
      }
    }
  }
  
  lifecycle {
    ignore_changes = [template[0].template[0].containers[0].image]
  }
}

# 2. The Scheduler (The Trigger)
# Run every 5 minutes
resource "google_cloud_scheduler_job" "identity_trigger" {
  name             = "netprobe-identity-trigger"
  region           = var.region
  schedule         = "*/5 * * * *"
  attempt_deadline = "320s"

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.identity_engine.name}:run"
    
    oauth_token {
      service_account_email = google_service_account.api_sa.email
    }
  }
}