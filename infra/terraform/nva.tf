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

  # 4. Robust Configuration (Based on your excellent debugging)
  INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')
  SURICATA_CONF="/etc/suricata/suricata.yaml"

  # FIX #2: Configure Zeek with a safer sed command
  sudo sed -i "s/^interface=.*/interface=$INTERFACE/" /opt/zeek/etc/node.cfg

  # Configure Suricata with all discovered fixes
  # FIX #3: Use a safer sed to replace only the first interface line
  sudo sed -i "0,/interface:.*/s//interface: $INTERFACE/" $SURICATA_CONF
  # FIX #1: Replace the correct default empty string for HOME_NET
  sudo sed -i 's|HOME_NET: ""|HOME_NET: "\[10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16\]"|' $SURICATA_CONF
  # FIX #4: Enable the command socket and create its run directory
  sudo sed -i '/unix-command:/,/enabled: no/ s/enabled: no/enabled: yes/' $SURICATA_CONF
  sudo mkdir -p /var/run/suricata
  sudo chown suricata:suricata /var/run/suricata

  # 5. Create a Professional systemd Service for Zeek
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

  # 6. Professional Service Initialization and Startup
  # Reload systemd to recognize the new zeek.service file
  sudo systemctl daemon-reload

  # FIX #5: Run zeekctl deploy ONCE to generate initial configurations
  sudo /opt/zeek/bin/zeekctl deploy
  # BEST PRACTICE: Immediately stop it so systemd can take over management
  sudo /opt/zeek/bin/zeekctl stop

  # FIX #6: Enable and start both services using the robust, canonical systemd sequence.
  # This ensures services start on boot and can be managed consistently.
  sudo systemctl enable zeek.service
  sudo systemctl start zeek.service

  sudo systemctl enable suricata.service
  sudo systemctl restart suricata.service # Use restart to ensure it picks up all config changes

  # 7. Enable IP forwarding
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
