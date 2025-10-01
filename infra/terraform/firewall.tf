resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "netprobe-allow-iap-ssh"
  network = google_compute_network.main.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  # This CIDR block is used by Google's Identity-Aware Proxy for secure SSH.
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["nva"]
}

resource "google_compute_firewall" "allow_health_checks" {
  name    = "netprobe-allow-health-checks"
  network = google_compute_network.main.name
  allow {
    protocol = "tcp"
  }
  # These are the specific IP ranges used by GCP health checkers.
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["nva"]
}