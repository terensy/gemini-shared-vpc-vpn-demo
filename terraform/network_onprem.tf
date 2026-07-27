resource "google_compute_network" "onprem_vpc" {
  name                    = "onprem-vpc"
  project                 = google_project.onprem.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.onprem_apis]
}

resource "google_compute_subnetwork" "subnet_1" {
  name          = "subnet-1"
  project       = google_project.onprem.project_id
  region        = var.region
  network       = google_compute_network.onprem_vpc.id
  ip_cidr_range = "10.10.0.0/24"
  purpose       = "PRIVATE"

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
    filter_expr          = "true"
  }
}
