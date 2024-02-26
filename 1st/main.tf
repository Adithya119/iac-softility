resource "google_compute_instance" "this" {
    name         = "test"
    zone         = "us-central1-a"
    machine_type = "e2-small"
    allow_stopping_for_update = true
    
    boot_disk {
        initialize_params {
            image = "debian-cloud/debian-12"
            // size
        }
    }

    network_interface {      // vpc??
        network = "default"
        access_config {
            // necessary even if left empty
        }
    }

// The below block is needed because the Applications running on the VM use the service account to call Google Cloud APIs. Use the service account which was provided with the desired permissions.

    service_account {
        email = "terraform-service-acc@terraform-on-gcp-414809.iam.gserviceaccount.com"
        scopes = ["cloud-platform"]      // To allow full access to all Cloud APIs, use the "cloud-platform" scope.
    }
}