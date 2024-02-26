
# 1
resource "google_compute_project_metadata" "this" {    
    metadata = {
        enable-oslogin = "TRUE"
    }
}


# 2
resource "google_compute_region_instance_template" "instance_template" {
    name = "app-servers"
    #project =   The ID of the project in which the resource belongs. If it is not provided, the provider project is used.
    region = "us-central1"       // The region in which the resource belongs. If region is not provided, the provider region is used.
    machine_type = "e2-medium"

    tags = ["http-server", "https-server", "lb-health-check"]       # firewall rules - allowing these connections using firewall tags

    disk {
        boot = true
        disk_type = "pd-balanced"
        source_image = "debian-cloud/debian-12"
        # disk_size_gb = //  If not specified, it will inherit the size of its base image.
    }

    network_interface {
        network = "default"
        access_config {
            // this block is necessary even if left empty
        }
    }

    labels = {
        env = "test"
    }

    # metadata_startup_script = "${file("apache.sh")}"

    service_account {
        email = "ansible-sa@terraform-on-gcp-414809.iam.gserviceaccount.com"
        scopes = ["cloud-platform"]                     //
    }
}



# 3
resource "google_compute_region_autoscaler" "this" {
    name = "autoscaler"
    region = "us-central1"

    autoscaling_policy {
        min_replicas = 2
        max_replicas = 4
        cooldown_period = 60
        
        cpu_utilization {
            target = 0.6
        }
    }
    
    target = google_compute_region_instance_group_manager.mig.id
}


# 4
resource "google_compute_region_health_check" "this" {          // app hc
    name = "apache-servers-hc"
    region = "us-central1"

    check_interval_sec = 20
    timeout_sec = 10
    unhealthy_threshold = 3

    http_health_check {
        port = 80
        request_path = "/"         // default
    }
}


# 5 - firewall rules for the default network to allow:-
#     1.   hc probes to be able to connect from hc sources to the vm's/app.
#     2.   allow http traffic from lb to vm's
#     3.   allow https traffic from lb to vm's

resource "google_compute_firewall" "hc-probes" {
    name = "allow-hc-probes-to-vms"
    network = "default"
    # target_tags   // If no targetTags are specified, the firewall rule applies to all instances on the specified network.
    # direction = INGRESS  // default
    source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

    allow {
        protocol = "tcp"
        ports = ["80"]
    }
}

resource "google_compute_firewall" "allow-http" {
    name = "allow-http-traffic"
    network = "default"
    source_ranges = ["0.0.0.0/0"]   // ideally, the static ip of lb should be given here.
    target_tags = ["http-server", "https-server", "lb-health-check"]

    allow {
        protocol = "tcp"
        ports = ["80"]
    }
}

resource "google_compute_firewall" "allow-https" {
    name = "allow-https-traffic"
    network = "default"
    source_ranges = ["0.0.0.0/0"]   // ideally, the static ip of lb should be given here.
    target_tags = ["http-server", "https-server", "lb-health-check"]

    allow {
        protocol = "tcp"
        ports = ["443"]
    }
}


# 6
resource "google_compute_region_instance_group_manager" "mig" {
    name = "apache-server-mig"              // name of mig
    base_instance_name = "apache-server"    // instances' name

    version {
        name = "apache-v1"
        instance_template = google_compute_region_instance_template.instance_template.id
    }
    
    named_port {
        name = "http"
        port = "80"
    }

    region = "us-central1"
    distribution_policy_zones = ["us-central1-a", "us-central1-b", "us-central1-c"]
    distribution_policy_target_shape = "Even"

    auto_healing_policies {
        health_check = google_compute_region_health_check.this.id
        initial_delay_sec = 3000     //
    }
}


# ----------------
// regional external Application Load Balancer:-

// 7 - Proxy-only subnet: reserve a subnet to allocate an ip ( to the lb ?? ) from this subnet.

resource "google_compute_subnetwork" "this" {
    name = "subnet-for-ip-allocation"
    ip_cidr_range = "192.168.0.0/24"
    network = "default"
    region = "us-central1"
    purpose = "REGIONAL_MANAGED_PROXY"             // ********
    role = "ACTIVE"                                // required when purpose is set to "REGIONAL_MANAGED_PROXY"
}


// 8 - frontend config for Regional External Load Balancing:-

resource "google_compute_forwarding_rule" "this" {
    name = "frontend-config"

    depends_on = [google_compute_subnetwork.this]              //
    region = "us-central1"

    ip_protocol           = "TCP"
    load_balancing_scheme = "EXTERNAL_MANAGED"
    port_range            = "80"
    target                = google_compute_region_target_http_proxy.this.id    // URL of the target resource to receive the matched traffic
    network               = "default"
    # ip_address            = google_compute_address.default.id   // When omitted, Google Cloud assigns an ephemeral IP address.
    network_tier          = "STANDARD"
}


// 9 - backend config:-

resource "google_compute_region_backend_service" "this" {
    name = "apache-web-backend"
    load_balancing_scheme = "EXTERNAL_MANAGED"                    // *********
    protocol = "HTTP"
    port_name = "http"     // default    // named port
    # timeout_sec // defaults to 30 seconds

    region = "us-central1"

    backend {
        balancing_mode = "UTILIZATION"
        group = google_compute_region_instance_group_manager.mig.instance_group        //  ***************
        capacity_scaler = 1.0                           // A multiplier applied to the group's maximum servicing capacity
    }

    health_checks = [google_compute_region_health_check.this.id]   // HealthCheck resources for health checking this RegionBackendService.
}


// 10 - routing rules:-

resource "google_compute_region_url_map" "this" {
    name = "lb-routing-rules"
    region = "us-central1"
    default_service = google_compute_region_backend_service.this.id
}


// 11 - regional external lb:-

resource "google_compute_region_target_http_proxy" "this" {
    name = "lb-for-apache-backend"
    url_map = google_compute_region_url_map.this.id
    region = "us-central1"
}