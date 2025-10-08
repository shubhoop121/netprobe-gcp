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