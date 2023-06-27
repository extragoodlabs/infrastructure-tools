provider "google" {
  region = var.region
}

resource "google_compute_address" "jumpwire" {
  count   = var.instance_count
  project = var.project_id
  name    = "${var.prefix}-${format("%d", count.index + 1)}"
  region  = var.region
}

resource "google_compute_instance" "jumpwire" {
  count          = var.instance_count
  name           = "${var.prefix}-${count.index + 1}"
  description    = "Terraform-managed JumpWire GCE instance."
  tags           = var.vm_tags
  labels         = var.labels
  machine_type   = var.instance_type
  project        = var.project_id
  zone           = var.zone
  can_ip_forward = false

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  boot_disk {
    initialize_params {
      type  = "pd-standard"
      image = "projects/cos-cloud/global/images/family/cos-stable"
      size  = var.boot_disk_size
    }
  }

  network_interface {
    subnetwork = var.subnetwork
    access_config {
      nat_ip = google_compute_address.jumpwire.*.address[count.index]

    }
  }

  service_account {
    email  = var.service_account
    scopes = var.scopes
  }

  metadata = {
    google-logging-enabled    = var.stackdriver_logging
    google-monitoring-enabled = var.stackdriver_monitoring
    ssh-keys                  = join(",", [for k, v in var.ssh_keys : "${k}:${v}"])
    user-data = templatefile(
      "${path.module}/cloud-config.yaml",
      {
        token         = var.token
        domain        = var.domain
        tls_cert      = var.tls_cert
        tls_key       = var.tls_key
        instance_id   = count.index + 1
        instance_name = "${var.prefix}-${count.index + 1}"
        ip_address    = google_compute_address.jumpwire.*.address[count.index]
      }
    )
  }

  allow_stopping_for_update = false
}

resource "google_compute_firewall" "postgres" {
  name    = "${var.prefix}-postgres"
  project = var.project_id
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  target_tags   = var.vm_tags
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "ssh" {
  name    = "${var.prefix}-ssh"
  project = var.project_id
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags   = var.vm_tags
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "cluster" {
  name    = "${var.prefix}-cluster"
  project = var.project_id
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["4369"]
  }

  source_tags = var.vm_tags
  target_tags = var.vm_tags
}
