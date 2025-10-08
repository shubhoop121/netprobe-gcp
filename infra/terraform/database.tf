# infra/terraform/database.tf

# 1. Enable the Service Networking API to allow VPC peering for managed services.
resource "google_project_service" "service_networking" {
  project = var.project_id
  service = "servicenetworking.googleapis.com"

  # Do not disable this API when destroying resources
  disable_on_destroy = false
}

# 2. Reserve a global IP range for the private service connection.
#    Cloud SQL will use this range to peer with your VPC.
resource "google_compute_global_address" "private_service_access" {
  project       = var.project_id
  name          = "private-service-access-for-sql"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16 # A /16 range is standard and recommended.
  network       = google_compute_network.main.id
}

# 3. Create the private service connection itself.
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access.name]

  # Explicitly depend on the API being enabled.
  depends_on = [google_project_service.service_networking]
}

# 4. Define the cost-optimized Cloud SQL for PostgreSQL instance.
resource "google_sql_database_instance" "netprobe_db" {
  project = var.project_id
  name    = "netprobe-db"
  region  = var.region

  database_version = "POSTGRES_15"

  settings {
    # This is the smallest shared-core tier for cost optimization.
    tier = "db-g1-small"

    # ZONAL means no high-availability, avoiding standby costs.
    availability_type = "ZONAL"

    # Start the instance immediately upon creation.
    activation_policy = "ALWAYS"

    disk_type               = "PD_SSD"
    disk_size               = 10 # Minimal 10 GB SSD storage.
    disk_autoresize         = false
    deletion_protection_enabled = false # Allow easy teardown with `terraform destroy`.

    ip_configuration {
      ipv4_enabled    = false # No public IP for security.
      private_network = google_compute_network.main.id
    }

    backup_configuration {
      enabled = false # No backups to minimize cost during development.
    }
  }

  # Ensure the VPC peering is established before creating the SQL instance.
  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# 5. Create the specific database within the instance.
resource "google_sql_database" "netprobe_logs" {
  project  = var.project_id
  name     = "netprobe_logs"
  instance = google_sql_database_instance.netprobe_db.name
}

# 6. Create the user for the application to connect with.
resource "google_sql_user" "netprobe_user" {
  project  = var.project_id
  name     = "netprobe_user"
  instance = google_sql_database_instance.netprobe_db.name
  password = var.db_password
}