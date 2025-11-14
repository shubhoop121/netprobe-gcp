# This is the heart of our system. We'll define an instance template that specifies what our analysis VMs 
# will look like, and then a Managed Instance Group (MIG) to create and manage them.
# Crucially, we enable can_ip_forward = true, which allows the VMs to act as routers—the key requirement 
# for our inline inspection model.

resource "google_compute_instance_template" "nva" {
  name_prefix  = "netprobe-nva-template-"
  machine_type = "e2-medium"
  region       = var.region
  tags         = ["nva"]

  # This label acts as a trigger. When the app_version changes,
  # a new instance template is created, forcing a rolling update.
  labels = {
    app-version = var.app_version
  }

  disk {
    source_image = "global/images/netprobe-nva-golden-image-v3"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.analysis.id
      access_config {
      // An empty block requests an ephemeral public IP address.
    }
  }

  can_ip_forward          = true

  service_account {
    # This is your project's Compute Engine default service account email
    email  = "412150966753-compute@developer.gserviceaccount.com"
    # This scope grants the VM full access to all cloud APIs.
    # IAM roles will still be the final gatekeeper for what it can actually do.
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/nva-startup.sh.tftpl", {
    project_id    = var.project_id
    branch_name   = var.branch_name
    terraform_db_pass = var.db_password
  })

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
