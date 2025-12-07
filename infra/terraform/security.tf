# ==============================================================================
# 1. NETWORK SECURITY ADDRESS GROUP (The "Database" of Blocked IPs)
# ==============================================================================
# This is the resource our Python API will populate.
# It allows up to 100,000 IPs, unlike standard Security Policy rules.

# 1. The Address Group (Database of Blocked IPs)
resource "google_network_security_address_group" "global_blocklist" {
  name        = "netprobe-global-blocklist"
  parent      = "projects/${var.project_id}"
  location    = "global"
  type        = "IPV4"
  capacity    = 100
  description = "Dynamic Blocklist populated by NetProbe Active Defense"
}

resource "google_compute_security_policy" "api_security_policy" {
  name        = "netprobe-api-security-policy"
  description = "Public API policy with Active Defense (Cloud Armor)"

  # --- RULE 1: DYNAMIC BLOCKLIST (Highest Priority) ---
  # The Python API will dynamically append IPs to 'src_ip_ranges' here.
  rule {
    action   = "deny(403)"
    priority = 500
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        # Placeholder IP (TEST-NET-1) to initialize the list.
        # Python will append real attacker IPs to this array.
        src_ip_ranges = ["192.0.2.1/32"]
      }
    }
    description = "Active Defense: Dynamic Blocklist"
  }

  # --- RULE 2: ALLOW ADMINS ---
  rule {
    action   = "allow"
    priority = 900
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = var.allowed_source_ranges
      }
    }
    description = "Allow specific admin IPs"
  }

  # --- RULE 3: DEFAULT ALLOW (Public Access for Demo) ---
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow (Public API)"
  }
}