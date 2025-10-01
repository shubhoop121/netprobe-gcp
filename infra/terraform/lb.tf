# This defines the components for the Internal Load Balancer that will sit in front of our NVA cluster. 
# The forwarding rule's IP address will become the next hop for all traffic we want to inspect.

# A regional health check is required for a regional backend service.
resource "google_compute_region_health_check" "nva" {
  name                = "netprobe-nva-health-check"
  region              = var.region
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  # A simple TCP check on the SSH port is a reliable way to see if the VM is alive.
  tcp_health_check {
    port = "22"
  }
}

# An Internal Passthrough Network Load Balancer is a regional service,
# so it requires a regional backend service.
resource "google_compute_region_backend_service" "nva" {
  name                  = "netprobe-nva-backend"
  region                = var.region
  health_checks         = [google_compute_region_health_check.nva.id]
  load_balancing_scheme = "INTERNAL"
  protocol              = "TCP"

  backend {
    group = google_compute_region_instance_group_manager.nva.instance_group
  }
}

resource "google_compute_forwarding_rule" "nva" {
  name                  = "netprobe-nva-forwarding-rule"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.nva.id
  all_ports             = true
  network               = google_compute_network.main.name
  subnetwork            = google_compute_subnetwork.analysis.id
}