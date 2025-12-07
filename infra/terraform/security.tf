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
  # This runs FIRST. If an IP is in the group, it is dropped immediately.
  # Action: 403 Forbidden
  rule {
    action   = "deny(403)"
    priority = 500
    match {
      expr {
        # This expression checks if the incoming IP exists inside our Address Group
        expression = "inIpRange(origin.ip, '${google_network_security_address_group.global_blocklist.id}')"
      }
    }
    description = "Active Defense: Block specific attackers"
  }

  # --- RULE 2: ALLOW ADMINS (Safety Net) ---
  # Ensures your Cloud Shell / Home IP is explicitly allowed.
  # (Less critical now that Default is Allow, but good practice)
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
  # We OPEN the gates so the Red Team attacker can connect initially.
  # They will only be blocked if Rule 1 catches them.
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