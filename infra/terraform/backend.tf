terraform {
  backend "gcs" {
    bucket = "netprobe-473119-tfstate"
    prefix = "terraform/state"
  }
}