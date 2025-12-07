variable "project_id" {
  description = "The GCP project ID."
  type        = string
  default     = "netprobe-473119"
}

variable "region" {
  description = "The GCP region for resources."
  type        = string
  default     = "asia-south1"
}

variable "nva_instance_count" {
  description = "The number of NVA instances to run in the MIG."
  type        = number
  default     = 0
}

variable "db_password" {
  description = "The password for the 'netprobe_user' PostgreSQL user."
  type        = string
  sensitive   = true
}

variable "branch_name" {
  description = "The GitHub branch to clone on the NVA."
  type        = string
  default     = "main"
}

variable "app_version" {
  description = "The git commit SHA of the application code to trigger NVA updates."
  type        = string
}

variable "allowed_source_ranges" {
  description = "List of admin IPs allowed to bypass the blocklist (e.g., your home IP/Cloud Shell)"
  type        = list(string)
  default     = ["0.0.0.0/0", "35.247.137.215/32"] # Default to allow all for the demo to prevent errors
}