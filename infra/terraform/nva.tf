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
  # Remove 'set -e' temporarily to prevent early exit
  set -x

  # Log everything to a file for debugging
  exec 1> >(tee -a /var/log/nva-startup.log)
  exec 2>&1

  echo "=== Starting NVA Setup at $(date) ==="

  # 1. System Preparation
  export DEBIAN_FRONTEND=noninteractive
  echo "Step 1: Updating system packages..."
  apt-get update || { echo "Failed to update packages"; exit 1; }
  apt-get install -y curl gnupg2 || { echo "Failed to install curl/gnupg2"; exit 1; }

  # 2. Install Zeek
  echo "Step 2: Installing Zeek..."
  echo 'deb http://download.opensuse.org/repositories/security:/zeek/Debian_11/ /' | tee /etc/apt/sources.list.d/zeek.list
  curl -fsSL https://download.opensuse.org/repositories/security:zeek/Debian_11/Release.key | gpg --dearmor > /etc/apt/trusted.gpg.d/security_zeek.gpg
  apt-get update
  apt-get install -y zeek-lts || { echo "Failed to install Zeek"; exit 1; }
  echo "Zeek installed successfully"

  # 3. Install Suricata
  echo "Step 3: Installing Suricata..."
  apt-get install -y suricata || { echo "Failed to install Suricata"; exit 1; }
  echo "Suricata installed successfully"

  # 4. Get network interface
  echo "Step 4: Detecting network interface..."
  INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')
  echo "Detected interface: $INTERFACE"

  if [ -z "$INTERFACE" ]; then
    echo "ERROR: Could not detect network interface"
    exit 1
  fi

  # 5. Configure Zeek
  echo "Step 5: Configuring Zeek..."
  ZEEK_NODE_CFG="/opt/zeek/etc/node.cfg"
  
  if [ -f "$ZEEK_NODE_CFG" ]; then
    # Update the interface in node.cfg
    sed -i "s/^interface=.*/interface=$INTERFACE/" "$ZEEK_NODE_CFG"
    echo "Updated Zeek interface to $INTERFACE"
  else
    echo "ERROR: Zeek node.cfg not found at $ZEEK_NODE_CFG"
    exit 1
  fi

  # Add network configuration
  cat > /opt/zeek/etc/networks.cfg <<EOF
10.0.0.0/8          Private IP space
172.16.0.0/12       Private IP space
192.168.0.0/16      Private IP space
EOF
  echo "Created Zeek networks.cfg"

  # 6. Configure Suricata
  echo "Step 6: Configuring Suricata..."
  SURICATA_CONF="/etc/suricata/suricata.yaml"
  
  sed -i "0,/interface:.*/s//interface: $INTERFACE/" "$SURICATA_CONF"
  sed -i 's|HOME_NET: ""|HOME_NET: "\[10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16\]"|' "$SURICATA_CONF"
  sed -i '/unix-command:/,/enabled: no/ s/enabled: no/enabled: yes/' "$SURICATA_CONF"
  
  mkdir -p /var/run/suricata
  chown suricata:suricata /var/run/suricata
  echo "Suricata configured successfully"

  # 7. Initialize Zeek
  echo "Step 7: Initializing Zeek..."
  cd /opt/zeek
  /opt/zeek/bin/zeekctl install || { echo "Failed to install Zeek configuration"; exit 1; }
  echo "Zeek initialized successfully"

  # 8. Create systemd service for Zeek
  echo "Step 8: Creating Zeek systemd service..."
  cat > /etc/systemd/system/zeek.service <<'ZEEKSERVICE'
[Unit]
Description=Zeek Network Security Monitor
Documentation=https://docs.zeek.org
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/zeek
ExecStart=/opt/zeek/bin/zeekctl start
ExecStop=/opt/zeek/bin/zeekctl stop
ExecReload=/opt/zeek/bin/zeekctl restart
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
ZEEKSERVICE

  # Verify the service file was created
  if [ ! -f /etc/systemd/system/zeek.service ]; then
    echo "ERROR: Failed to create zeek.service file"
    exit 1
  fi
  echo "Zeek service file created successfully"

  # 9. Enable IP forwarding
  echo "Step 9: Enabling IP forwarding..."
  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ip-forward.conf
  sysctl --system >/dev/null 2>&1
  echo "IP forwarding enabled"

  # 10. Reload systemd daemon
  echo "Step 10: Reloading systemd daemon..."
  systemctl daemon-reload || { echo "Failed to reload systemd daemon"; exit 1; }
  echo "Systemd daemon reloaded"

  # 11. Enable and start Suricata
  echo "Step 11: Starting Suricata..."
  systemctl enable suricata.service
  systemctl restart suricata.service
  sleep 3
  
  if systemctl is-active --quiet suricata.service; then
    echo "Suricata started successfully"
  else
    echo "WARNING: Suricata failed to start"
    systemctl status suricata.service --no-pager
  fi

  # 12. Enable and start Zeek
  echo "Step 12: Starting Zeek..."
  systemctl enable zeek.service
  systemctl start zeek.service
  sleep 3

  if systemctl is-active --quiet zeek.service; then
    echo "Zeek started successfully"
  else
    echo "WARNING: Zeek service failed to start"
    systemctl status zeek.service --no-pager
  fi

  # 13. Verify Zeek is actually running
  echo "Step 13: Verifying Zeek processes..."
  /opt/zeek/bin/zeekctl status
  
  if pgrep -f "zeek.*worker" > /dev/null; then
    echo "Zeek worker process is running"
  else
    echo "WARNING: Zeek worker process not found"
  fi

  # 14. Final status report
  echo "=== Final Service Status ==="
  echo "--- Suricata ---"
  systemctl status suricata.service --no-pager || true
  
  echo "--- Zeek ---"
  systemctl status zeek.service --no-pager || true
  
  echo "--- Zeek Control ---"
  /opt/zeek/bin/zeekctl status || true

  echo "=== NVA Setup completed at $(date) ==="
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