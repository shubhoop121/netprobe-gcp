# Reserves a global IP range for the private service connection.
# Cloud SQL will use this range to peer with your VPC.
resource "google_compute_global_address" "private_service_access" {
  project       = var.project_id
  name          = "private-service-access-for-sql"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

# Creates the private service connection itself.
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access.name]
}

# --- Cloud SQL PostgreSQL Instance (Cost-Optimized) ---
resource "google_sql_database_instance" "netprobe_db" {
  project          = var.project_id
  name             = "netprobe-db"
  region           = var.region
  database_version = "POSTGRES_15"

  settings {
    tier = "db-g1-small"
    availability_type = "ZONAL"

    # Start the instance immediately upon creation.
    activation_policy = "ALWAYS"

    disk_type                 = "PD_SSD"
    disk_size                 = 10 # Minimal 10 GB SSD storage.
    disk_autoresize           = false
    deletion_protection_enabled = false # Allow easy teardown with `terraform destroy`.

    ip_configuration {
      ipv4_enabled    = true
      private_network = google_compute_network.main.id
    }

    backup_configuration {
      enabled = false # No backups to minimize cost during development.
    }
  }

  # Ensure the VPC peering is established before creating the SQL instance.
  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.sqladmin,
    google_project_service.service_networking
  ]
}

# Creates the specific database within the instance.
resource "google_sql_database" "netprobe_logs" {
  project  = var.project_id
  name     = "netprobe_logs"
  instance = google_sql_database_instance.netprobe_db.name
}

# Creates the user for the application to connect with.
resource "google_sql_user" "netprobe_user" {
  project  = var.project_id
  name     = "netprobe_user"
  instance = google_sql_database_instance.netprobe_db.name
  password = var.db_password
}
