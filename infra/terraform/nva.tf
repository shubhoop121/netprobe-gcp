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

  can_ip_forward = true

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e
    set -x  # Print each command to the log for easier debugging.

    # 1. System Preparation
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update
    sudo apt-get install -y curl gnupg2

    # 2. Install Zeek from official repository
    echo 'deb http://download.opensuse.org/repositories/security:/zeek/Debian_11/ /' | sudo tee /etc/apt/sources.list.d/zeek.list
    curl -fsSL https://download.opensuse.org/repositories/security:zeek/Debian_11/Release.key | sudo gpg --dearmor > /etc/apt/trusted.gpg.d/security_zeek.gpg
    sudo apt-get update
    sudo apt-get install -y zeek-lts

    # Add Zeek to the system path for all users
    echo "export PATH=$PATH:/opt/zeek/bin" | sudo tee /etc/profile.d/zeek.sh
    source /etc/profile.d/zeek.sh

    # 3. Install Suricata from Debian repository
    sudo apt-get install -y suricata

    # 4. Robust Configuration
    INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')
    SURICATA_CONF="/etc/suricata/suricata.yaml"

    # Fix Zeek interface
    sudo sed -i "s/^interface=.*/interface=$INTERFACE/" /opt/zeek/etc/node.cfg

    # Fix Suricata interface (first match only)
    sudo sed -i "0,/interface:.*/s//interface: $INTERFACE/" $SURICATA_CONF

    # ✅ Option A: Explicitly override HOME_NET
    sudo sed -i 's|HOME_NET: ""|HOME_NET: "[10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16]"|' $SURICATA_CONF

    # Enable the Unix command socket
    sudo sed -i '/unix-command:/,/enabled: no/ s/enabled: no/enabled: yes/' $SURICATA_CONF
    sudo mkdir -p /var/run/suricata
    sudo chown suricata:suricata /var/run/suricata

    # 5. Enable and Start Services
    sudo /opt/zeek/bin/zeekctl deploy
    sudo systemctl enable suricata
    sudo systemctl daemon-reload
    sudo systemctl restart suricata

    # 6. Enable IP forwarding
    echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ip-forward.conf
    sudo sysctl --system
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
  target_size        = var.nva_instance_count

  auto_healing_policies {
    health_check      = google_compute_region_health_check.nva.id
    initial_delay_sec = 300
  }
}
