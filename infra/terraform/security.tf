# ==============================================================================
# 1. NETWORK SECURITY ADDRESS GROUP (The "Database" of Blocked IPs)
# ==============================================================================
# This is the resource our Python API will populate.
# It allows up to 100,000 IPs, unlike standard Security Policy rules.
resource "google_network_security_address_group" "global_blocklist" {
  name        = "netprobe-global-blocklist"
  parent      = "projects/${var.project_id}"
  location    = "global"
  type        = "IPV4"
  capacity    = 100
  description = "Dynamic Blocklist populated by NetProbe Active Defense"
}

# ==============================================================================
# 2. CLOUD ARMOR SECURITY POLICY (The "Bouncer")
# ==============================================================================
resource "google_compute_security_policy" "api_security_policy" {
  name        = "netprobe-api-security-policy"
  description = "Public API policy with Active Defense (Cloud Armor)"

  # --- RULE 1: DYNAMIC BLOCKLIST (Highest Priority) ---
  # FIX: Use 'config' block. Cloud Armor accepts Address Group IDs 
  # directly in the src_ip_ranges list.
  rule {
    action   = "deny(403)"
    priority = 500
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = [google_network_security_address_group.global_blocklist.id]
      }
    }
    description = "Active Defense: Block specific attackers"
  }

  # --- RULE 2: ALLOW ADMINS (Safety Net) ---
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

  # --- RULE 3: DEFAULT ALLOW (Public Access) ---
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