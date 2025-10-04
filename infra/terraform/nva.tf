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

  can_ip_forward = true
metadata_startup_script = <<-EOT
#!/bin/bash
# Redirect all output to a dedicated log file for easy debugging
exec > >(sudo tee /var/log/startup-script.log) 2>&1

set -e
set -x # Print each command to the log for debugging

echo "--- STARTING NVA PROVISIONING SCRIPT ---"

# 1. System Preparation
echo "--- PHASE 1: System Preparation ---"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y curl gnupg2
echo "--- COMPLETED: System Preparation ---"

# 2. Install Zeek
echo "--- PHASE 2: Zeek Installation ---"
echo 'deb http://download.opensuse.org/repositories/security:/zeek/Debian_11/ /' | sudo tee /etc/apt/sources.list.d/zeek.list
curl -fsSL https://download.opensuse.org/repositories/security:zeek/Debian_11/Release.key | sudo gpg --dearmor > /etc/apt/trusted.gpg.d/security_zeek.gpg
sudo apt-get update
sudo apt-get install -y zeek-lts
echo "--- COMPLETED: Zeek Installation ---"

# 3. Install Suricata
echo "--- PHASE 3: Suricata Installation ---"
sudo apt-get install -y suricata
echo "--- COMPLETED: Suricata Installation ---"

# 4. Robust Configuration
echo "--- PHASE 4: Application Configuration ---"
INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')
SURICATA_CONF="/etc/suricata/suricata.yaml"

# Configure Zeek
sudo sed -i "s/^interface=.*/interface=$INTERFACE/" /opt/zeek/etc/node.cfg

# Configure Suricata
sudo sed -i "0,/interface:.*/s//interface: $INTERFACE/" $SURICATA_CONF
sudo sed -i 's|HOME_NET: ""|HOME_NET: "\[10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16\]"|' $SURICATA_CONF
sudo sed -i '/unix-command:/,/enabled: no/ s/enabled: no/enabled: yes/' $SURICATA_CONF

# Create the run directory only if Suricata user exists
if id "suricata" &>/dev/null; then
    sudo mkdir -p /var/run/suricata
    sudo chown suricata:suricata /var/run/suricata
fi
echo "--- COMPLETED: Application Configuration ---"

# 5. Create systemd Service for Zeek
echo "--- PHASE 5: Creating Zeek systemd Service ---"
sudo tee /etc/systemd/system/zeek.service > /dev/null <<'EOF'
[Unit]
Description=Zeek Network Security Monitor
After=network.target

[Service]
Type=forking
ExecStart=/opt/zeek/bin/zeekctl start
ExecStop=/opt/zeek/bin/zeekctl stop
ExecReload=/opt/zeek/bin/zeekctl restart
Restart=on-failure
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
echo "--- COMPLETED: Creating Zeek systemd Service ---"

# 6. Professional Service Initialization and Startup
echo "--- PHASE 6: Service Initialization and Startup ---"
sudo systemctl daemon-reload

# Deploy Zeek once to generate initial configs, then stop so systemd can manage it
sudo /opt/zeek/bin/zeekctl deploy
sudo /opt/zeek/bin/zeekctl stop

# Enable and start both services
sudo systemctl enable zeek.service
sudo systemctl start zeek.service

sudo systemctl enable suricata.service
sudo systemctl restart suricata.service
echo "--- COMPLETED: Service Initialization and Startup ---"

# 7. Enable IP forwarding
echo "--- PHASE 7: Enabling IP Forwarding ---"
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl --system
echo "--- COMPLETED: IP Forwarding ---"

echo "--- NVA PROVISIONING SCRIPT FINISHED SUCCESSFULLY ---"
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
