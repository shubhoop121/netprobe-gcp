# Note: For simplicity in this step, we are creating a rule that would apply to the NVA instances themselves. 
# In a real-world scenario, you would create additional subnets for your actual workloads (e.g., web servers) 
# and apply a route that targets traffic from those subnets.


resource "google_compute_route" "pbr_to_nva" {
  name              = "netprobe-pbr-inspect-all"
  network           = google_compute_network.main.name
  dest_range        = "0.0.0.0/0"
  priority          = 800 # Higher priority than default (1000)

  # The IP address of the Internal Load Balancer's forwarding rule
  next_hop_ilb = google_compute_forwarding_rule.nva.id

  # Apply this route only to traffic originating from instances with the 'nva' tag.
  # In a real-world scenario, you would tag your workload VMs to be inspected.
  # For now, this sets up the pattern.
  tags = ["nva"]
}