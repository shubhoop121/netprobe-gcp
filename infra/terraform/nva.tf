# This is the heart of our system. We'll define an instance template that specifies what our analysis VMs 
# will look like, and then a Managed Instance Group (MIG) to create and manage them.
# Crucially, we enable can_ip_forward = true, which allows the VMs to act as routers—the key requirement 
# for our inline inspection model.

# infra/terraform/nva.tf

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
  // It now installs and configures Zeek and Suricata.
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e # Exit on any error

    # 1. System Preparation
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl gnupg2

    # 2. Install Zeek from official repository
    echo 'deb http://download.opensuse.org/repositories/security:/zeek/Debian_11/ /' > /etc/apt/sources.list.d/zeek.list
    curl -fsSL https://download.opensuse.org/repositories/security:zeek/Debian_11/Release.key | gpg --dearmor > /etc/apt/trusted.gpg.d/security_zeek.gpg
    apt-get update
    apt-get install -y zeek-lts

    # Add Zeek to the system path
    echo "export PATH=$PATH:/opt/zeek/bin" > /etc/profile.d/zeek.sh
    source /etc/profile.d/zeek.sh

    # 3. Install Suricata from Debian repository
    apt-get install -y suricata

    # 4. Basic Configuration
    # Get the primary network interface name (usually ens4 on GCP)
    INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')

    # Configure Zeek to monitor the primary interface
    sed -i "s/^interface=.*$/interface=$INTERFACE/" /opt/zeek/etc/node.cfg

    # Configure Suricata to monitor the primary interface
    sed -i "s/interface: eth0/interface: $INTERFACE/" /etc/suricata/suricata.yaml
    # Also update the HOME_NET variable in Suricata's config
    SUBNET_CIDR=$(ip -o -4 addr show dev $INTERFACE | awk '{print $4}')
    sed -i "s|HOME_NET: \"\\[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12\\]\"|HOME_NET: \"\"|" /etc/suricata/suricata.yaml

    # 5. Enable and Start Services
    # Deploy Zeek using its control tool
    /opt/zeek/bin/zeekctl deploy

    # Enable and start Suricata as a system service
    systemctl enable --now suricata

    # 6. Enable IP forwarding at the kernel level (retained from previous step)
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
    health_check      = google_compute_region_health_check.nva.id
    initial_delay_sec = 300
  }
}