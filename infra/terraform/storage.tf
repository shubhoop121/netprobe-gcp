
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Define the GCS bucket for our Terraform state
resource "google_storage_bucket" "terraform_state" {
  # Bucket names must be globally unique. Appending the project ID and a random suffix is a good practice.
  name          = "netprobe-tfstate-${var.project_id}-${random_id.bucket_suffix.hex}"
  location      = "ASIA-SOUTH1"
  force_destroy = false

  # Enable versioning to keep a history of state files, which is crucial for recovery.
  versioning {
    enabled = true
  }

  # Prevent accidental deletion of the state bucket.
  # To delete this bucket, this line must be commented out or set to false first.
  lifecycle {
    prevent_destroy = true
  }
}