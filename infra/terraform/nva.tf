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

  # This robust startup script incorporates all debugging findings and best practices
  # for service management.
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e
    set -x # Print each command to the log for easier debugging

    # 1. System Preparation
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update
    sudo apt-get install -y curl gnupg2

    # 2. Install Zeek
    echo 'deb http://download.opensuse.org/repositories/security:/zeek/Debian_11/ /' | sudo tee /etc/apt/sources.list.d/zeek.list
    curl -fsSL https://download.opensuse.org/repositories/security:zeek/Debian_11/Release.key | sudo gpg --dearmor > /etc/apt/trusted.gpg.d/security_zeek.gpg
    sudo apt-get update
    sudo apt-get install -y zeek-lts

    # 3. Install Suricata
    sudo apt-get install -y suricata

    # 4. Robust Configuration
    INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')
    SURICATA_CONF="/etc/suricata/suricata.yaml"

    # Configure Zeek to monitor the primary interface
    sudo sed -i "s/^interface=.*/interface=$INTERFACE/" /opt/zeek/etc/node.cfg

    # Configure Suricata
    # Replace only the first occurrence of the interface line
    sudo sed -i "0,/interface:.*/s//interface: $INTERFACE/" $SURICATA_CONF
    # Set a valid HOME_NET to prevent startup failure
    sudo sed -i 's|HOME_NET: ""|HOME_NET: "\[10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16\]"|' $SURICATA_CONF
    # Enable the command socket for `suricatasc`
    sudo sed -i '/unix-command:/,/enabled: no/ s/enabled: no/enabled: yes/' $SURICATA_CONF
    # Create the run directory for the socket
    sudo mkdir -p /var/run/suricata
    sudo chown suricata:suricata /var/run/suricata

    # 5. Create a systemd service for Zeek (BETTER SOLUTION)
    # This ensures Zeek is managed properly by the OS, just like Suricata.
    sudo tee /etc/systemd/system/zeek.service > /dev/null <<'EOF'
[Unit]
Description=Zeek Network Security Monitor
After=network.target


Type=forking
ExecStart=/opt/zeek/bin/zeekctl start
ExecStop=/opt/zeek/bin/zeekctl stop
ExecReload=/opt/zeek/bin/zeekctl restart
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # 6. Enable and Start Services
    # Deploy Zeek once to generate initial configs, then manage with systemd
    sudo /opt/zeek/bin/zeekctl deploy

    # Enable and start both services using the OS service manager
    sudo systemctl enable --now zeek.service
    sudo systemctl enable --now suricata.service

    # 7. Enable IP forwarding at the kernel level
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
