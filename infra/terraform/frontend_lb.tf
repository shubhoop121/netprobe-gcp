# infra/terraform/frontend_lb.tf

# 1. Static Global IP
resource "google_compute_global_address" "frontend_ip" {
  name        = "netprobe-frontend-ip"
  project     = var.project_id
  description = "Static Global IP for NetProbe"
}

# 2. Serverless NEGs
resource "google_compute_region_network_endpoint_group" "dashboard_neg" {
  name                  = "netprobe-dashboard-neg"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run { service = google_cloud_run_service.dashboard.name }
}

resource "google_compute_region_network_endpoint_group" "api_neg" {
  name                  = "netprobe-api-neg"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run { service = google_cloud_run_service.api.name }
}

# 3. Backend Services (Attached to Cloud Armor)
resource "google_compute_backend_service" "dashboard_backend" {
  name        = "netprobe-dashboard-backend"
  project     = var.project_id
  protocol    = "HTTPS" # Changed to HTTPS as it's standard for Serverless NEGs internally
  load_balancing_scheme = "EXTERNAL_MANAGED"
  backend { group = google_compute_region_network_endpoint_group.dashboard_neg.id }
  security_policy = google_compute_security_policy.api_security_policy.id
}

resource "google_compute_backend_service" "api_backend" {
  name        = "netprobe-api-backend"
  project     = var.project_id
  protocol    = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  backend { group = google_compute_region_network_endpoint_group.api_neg.id }
  security_policy = google_compute_security_policy.api_security_policy.id
}

# 4. URL Map
resource "google_compute_url_map" "default" {
  name            = "netprobe-global-url-map"
  project         = var.project_id
  default_service = google_compute_backend_service.dashboard_backend.id
  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }
  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.dashboard_backend.id
  }
}

# 5. HTTP Proxy & Forwarding Rule
resource "google_compute_target_http_proxy" "default" {
  name    = "netprobe-http-proxy"
  project = var.project_id
  url_map = google_compute_url_map.default.id
}

resource "google_compute_global_forwarding_rule" "http" {
  name       = "netprobe-http-forwarding-rule"
  project    = var.project_id
  target     = google_compute_target_http_proxy.default.id
  port_range = "80"
  ip_address = google_compute_global_address.frontend_ip.address
}