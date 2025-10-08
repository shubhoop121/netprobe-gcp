output "netprobe_db_private_ip" {
  description = "The private IP address of the Cloud SQL instance (for the Log Shipper)."
  value       = google_sql_database_instance.netprobe_db.private_ip_address
}

output "db_connection_name" {
  description = "The connection name of the Cloud SQL instance (for the CI/CD Proxy)."
  value       = google_sql_database_instance.netprobe_db.connection_name
}

output "test_workload_vm_name" {
  description = "The name of the test workload VM (for CI/CD Tests)."
  # The [0] is needed because the resource uses the 'count' meta-argument.
  value       = google_compute_instance.test_workload[0].name
}

output "test_workload_vm_zone" {
  description = "The zone of the test workload VM (for CI/CD Tests)."
  value       = google_compute_instance.test_workload[0].zone
}