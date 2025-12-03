# 1. Enable Network Security API
resource "google_project_service" "network_security" {
  project            = var.project_id
  service            = "networksecurity.googleapis.com"
  disable_on_destroy = false
}

# 2. The Address Group (Created now for future use)
resource "google_network_security_address_group" "global_blocklist" {
  name        = "netprobe-global-blocklist"
  parent      = "projects/${var.project_id}"
  location    = "global"
  type        = "IPV4"
  capacity    = 1000
  description = "Dynamic blocklist managed by NetProbe API"
  depends_on  = [google_project_service.network_security]
}

# 3. Cloud Armor Policy
resource "google_compute_security_policy" "main" {
  name        = "netprobe-security-policy"
  project     = var.project_id
  description = "Main WAF policy with Developer Access Only"

  # --- RULE 1: DEVELOPER ACCESS (Your IP) ---
  rule {
    action   = "allow"
    priority = 100
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        # KEEP YOUR ACTUAL IP HERE!
        src_ip_ranges = ["35.240.187.227/32"]
        
      }
    }
    description = "Allow Developer Access (Cloud Shell)"
  }

  # --- RULE 2: PLACEHOLDER BLOCKLIST (Unblocks Deployment) ---
  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        # Placeholder IP range (TEST-NET-1) to make Terraform happy
        # We will connect this to the Address Group later
        src_ip_ranges = ["192.0.2.0/24"]
      }
    }
    description = "Placeholder for dynamic blocklist"
  }

  # --- DEFAULT RULE: DENY ALL ---
  rule {
    action   = "deny(403)"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default deny all"
  }
}