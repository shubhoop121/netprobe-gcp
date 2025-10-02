#This will define the Cloud Router and the Cloud NAT gateway that attaches to it.

# A Cloud Router is required to manage the Cloud NAT gateway.
resource "google_compute_router" "main" {
  name    = "netprobe-router"
  network = google_compute_network.main.name
  region  = var.region
}

# The Cloud NAT gateway itself.
resource "google_compute_router_nat" "main" {
  name                               = "netprobe-nat-gateway"
  router                             = google_compute_router.main.name
  region                             = var.region
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  nat_ip_allocate_option = "AUTO_ONLY"
  # If you ever want to use reserved static IPs instead, replace with:
  # nat_ip_allocate_option = "MANUAL_ONLY"
  # nat_ips = [google_compute_address.nat_ip.self_link]

  subnetwork {
    name                    = google_compute_subnetwork.analysis.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
