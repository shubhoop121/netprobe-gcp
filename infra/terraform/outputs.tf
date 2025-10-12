output "netprobe_db_private_ip" {
  description = "The private IP address of the Cloud SQL instance (for the Log Shipper)."
  value       = google_sql_database_instance.netprobe_db.private_ip_address
}

output "db_connection_name" {
  description = "The connection name of the Cloud SQL instance (for the CI/CD Proxy)."
  value       = google_sql_database_instance.netprobe_db.connection_name
}

output "test_workload_vm_name" {
  description = "The name of the test workload VM (only created when nva_instance_count > 0)."
  # This condition prevents the error when no VM is created.
  value       = var.nva_instance_count > 0 ? google_compute_instance.test_workload[0].name : "not_created"
}

output "test_workload_vm_zone" {
  description = "The zone of the test workload VM (only created when nva_instance_count > 0)."
  # This condition prevents the error when no VM is created.
  value       = var.nva_instance_count > 0 ? google_compute_instance.test_workload[0].zone : "not_created"
}
