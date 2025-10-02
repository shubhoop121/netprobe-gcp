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