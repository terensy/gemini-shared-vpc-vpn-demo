resource "google_compute_network" "shared_vpc" {
  name                    = "ai-demo-shared-vpc"
  project                 = google_project.host.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.host_compute]
}

resource "google_compute_subnetwork" "serverless_subnet" {
  name                     = "serverless-subnet"
  project                  = google_project.host.project_id
  region                   = var.region
  network                  = google_compute_network.shared_vpc.id
  ip_cidr_range            = "10.22.0.0/20"
  purpose                  = "PRIVATE"
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
    filter_expr          = "true"
  }
}

resource "google_compute_subnetwork" "vm_subnet_1" {
  name          = "vm-subnet-1"
  project       = google_project.host.project_id
  region        = var.region
  network       = google_compute_network.shared_vpc.id
  ip_cidr_range = "10.33.0.0/29"
  purpose       = "PRIVATE"
}

resource "google_compute_subnetwork" "ilb_proxy_subnet" {
  name          = "ilb-proxy-subnet"
  project       = google_project.host.project_id
  region        = var.region
  network       = google_compute_network.shared_vpc.id
  ip_cidr_range = "10.33.1.0/26"
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

resource "google_compute_firewall" "allow_proxy_subnet" {
  name    = "allow-proxy-subnet"
  project = google_project.host.project_id
  network = google_compute_network.shared_vpc.name

  direction     = "INGRESS"
  source_ranges = ["10.33.1.0/26"]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

resource "google_compute_firewall" "allow_onprem_to_ilb" {
  name    = "allow-onprem-to-ilb"
  project = google_project.host.project_id
  network = google_compute_network.shared_vpc.name

  direction     = "INGRESS"
  source_ranges = ["10.10.0.0/24"]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

resource "google_compute_shared_vpc_host_project" "host" {
  project = google_project.host.project_id
}

resource "google_compute_shared_vpc_service_project" "service_attach" {
  host_project    = google_compute_shared_vpc_host_project.host.project
  service_project = google_project.service.project_id
}
