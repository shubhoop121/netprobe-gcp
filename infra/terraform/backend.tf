terraform {
  backend "gcs" {
    # This now refers to the bucket we are creating in storage.tf
    bucket = "netprobe-tfstate-netprobe-473119-${random_id.bucket_suffix.hex}"
    prefix = "terraform/state"
  }
}