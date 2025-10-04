resource "google_compute_instance" "test_workload" {
  # This clever trick links the test VM's lifecycle to the NVA cluster.
  # It will only be created when nva_instance_count is greater than 0.
  count = var.nva_instance_count > 0 ? 1 : 0

  name         = "test-workload-vm"
  machine_type = "e2-micro" # Using a small instance to minimize cost
  zone         = "${var.region}-a"
  tags         = ["workload"] # This tag is essential for our routing rule

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.workload.id
    # Note: No public IP. All internet-bound traffic must follow our PBR.
  }

  # We allow Terraform to gracefully delete this test instance
  allow_stopping_for_update = true
}