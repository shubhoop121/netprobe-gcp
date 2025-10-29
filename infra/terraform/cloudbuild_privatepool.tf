# infra/terraform/cloudbuild-privatepool.tf

# Enable required Service Networking API if not already done (it is likely already enabled)
resource "google_project_service" "servicenetworking_for_cb" {
  project            = var.project_id
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

# Reserve an IP range specifically for the Cloud Build Private Pool peering
resource "google_compute_global_address" "cb_private_pool_range" {
  project       = var.project_id
  name          = "cb-private-pool-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16 # Adjust if needed, but /16 is common
  network       = google_compute_network.main.id
}

resource "google_cloudbuild_worker_pool" "private_pool" {
  project  = var.project_id
  name     = "netprobe-private-pool" # Choose a name for your pool
  location = var.region             # Pool must be in the same region as peered network resources

  # Configure network settings to use the peering connection
    network_config {
        peered_network = google_compute_network.main.id
    }

    # Worker config is also directly under the resource
    worker_config {
        machine_type = "e2-medium"
        disk_size_gb = 100
    }

    depends_on = [google_service_networking_connection.private_vpc_connection]
}