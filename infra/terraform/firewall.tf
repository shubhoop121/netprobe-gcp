resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "netprobe-allow-iap-ssh"
  network = google_compute_network.main.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  # This CIDR block is used by Google's Identity-Aware Proxy for secure SSH.
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["nva","workload"]
}

resource "google_compute_firewall" "allow_health_checks" {
  name    = "netprobe-allow-health-checks"
  network = google_compute_network.main.name
  allow {
    protocol = "tcp"
  }
  # Specific IP ranges used by GCP health checkers.
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["nva"]
}

# This rule allows traffic from our workload VMs to reach our NVA instances.
# This is the missing link that allows the ILB to forward packets to the backends.
resource "google_compute_firewall" "allow_workload_to_nva" {
  name    = "netprobe-allow-workload-to-nva"
  network = google_compute_network.main.name
  
  allow {
    protocol = "all"
  }

  source_tags = ["workload"]
  target_tags = ["nva"]
}


resource "google_compute_firewall" "allow_sql_proxy_ingress" {
  name    = "netprobe-allow-sql-proxy"
  network = google_compute_network.main.name
  
  source_ranges = ["${google_compute_global_address.private_service_access.address}/${google_compute_global_address.private_service_access.prefix_length}"]

  allow {
    protocol = "tcp"
    ports    = ["3307"] 
  }
}