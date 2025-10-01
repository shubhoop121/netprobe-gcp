# This is the heart of our system. We'll define an instance template that specifies what our analysis VMs 
# will look like, and then a Managed Instance Group (MIG) to create and manage them.
# Crucially, we enable can_ip_forward = true, which allows the VMs to act as routers—the key requirement 
# for our inline inspection model.

resource "google_compute_instance_template" "nva" {
  name_prefix  = "netprobe-nva-template-"
  machine_type = "e2-medium"
  region       = var.region
  tags         = ["nva"]

  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.analysis.id
  }

  // This is the critical setting that allows the instance to act as a router.
  can_ip_forward = true

  // This script runs when the VM first boots.
  // We will add Zeek/Suricata installation here later.
  metadata_startup_script = <<-EOT
    #!/bin/bash
    # Enable IP forwarding at the kernel level
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ip-forward.conf
    sysctl --system
  EOT

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "nva" {
  name   = "netprobe-nva-mig"
  region = var.region

  version {
    instance_template = google_compute_instance_template.nva.id
  }

  base_instance_name = "netprobe-nva"
  target_size        = 2

  auto_healing_policies {
    health_check      = google_compute_health_check.nva.id
    initial_delay_sec = 300
  }
}