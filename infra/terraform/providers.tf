terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google"{
  project = "netprobe-473119"
  region  = "asia-south1"
}