resource "google_compute_network" "main" {
  name                    = "netprobe-vpc"
  auto_create_subnetworks = false
  mtu                     = 1460
}

resource "google_compute_subnetwork" "analysis" {
  name          = "netprobe-analysis-subnet"
  ip_cidr_range = "10.0.1.0/24"
  network       = google_compute_network.main.id
  region        = var.region
}