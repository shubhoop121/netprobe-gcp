# infra/terraform/outputs.tf

output "netprobe_db_private_ip" {
  description = "The private IP address of the Cloud SQL instance."
  value       = google_sql_database_instance.netprobe_db.private_ip_address
}