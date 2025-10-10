resource "google_network_connectivity_policy_based_route" "pbr_allow_nva_to_internal" {

  name    = "netprobe-pbr-allow-nva-to-internal"
  network = google_compute_network.main.id

  # Highest priority (lowest number) to be evaluated first.
  priority = 650

  # This tells GCP to use the VPC's main route table, which knows how to
  # reach other subnets and the peered Cloud SQL network.
  next_hop_other_routes = "DEFAULT_ROUTING"

  filter {
    protocol_version = "IPV4"
    # The destination is any private IP address in your VPC's range.
    dest_range       = "10.0.0.0/8"
  }

  # This rule applies ONLY to traffic originating from the NVA instances.
  virtual_machine {
    tags = ["nva"]
  }
}


resource "google_network_connectivity_policy_based_route" "pbr_skip_nva" {
  name    = "netprobe-pbr-skip-nva-traffic"
  network = google_compute_network.main.id

  # Higher priority (lower number) than inspection route
  priority = 700

  # Tells GCP to ignore other PBRs and use the default VPC routing table
  next_hop_other_routes = "DEFAULT_ROUTING"

  filter {
    protocol_version = "IPV4"
    src_range        = "0.0.0.0/0"
    dest_range       = "0.0.0.0/0"
  }

  # Applies ONLY to NVA VMs
  virtual_machine {
    tags = ["nva"]
  }
}
# -----------------------------------------
# Main inspection route (lower priority)
# Sends traffic to Internal Load Balancer
# -----------------------------------------
resource "google_network_connectivity_policy_based_route" "pbr_to_nva" {
  name    = "netprobe-pbr-inspect-all"
  network = google_compute_network.main.id

  # Lower priority (higher number) so it is evaluated after the skip route
  priority = 800

  next_hop_ilb_ip = google_compute_forwarding_rule.nva.ip_address

  filter {
    protocol_version = "IPV4"
    src_range        = "0.0.0.0/0"
    dest_range       = "0.0.0.0/0"
  }

  # Currently applies to NVAs; will update for workload VMs later
  virtual_machine {
    tags = ["workload"]
  }

  depends_on = [
    google_network_connectivity_policy_based_route.pbr_skip_nva
  ]
}
