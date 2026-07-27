resource "google_compute_region_network_endpoint_group" "api_server_neg" {
  name                  = "gemini-api-neg"
  project               = google_project.service.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.api_server.name
  }
}

resource "google_compute_region_backend_service" "api_server_backend" {
  name                  = "gemini-api-backend"
  project               = google_project.service.project_id
  region                = var.region
  load_balancing_scheme = "INTERNAL_MANAGED"
  protocol              = "HTTP"

  backend {
    group           = google_compute_region_network_endpoint_group.api_server_neg.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1
  }
}

resource "google_compute_region_url_map" "api_server_urlmap" {
  name            = "gemini-api-urlmap"
  project         = google_project.service.project_id
  region          = var.region
  default_service = google_compute_region_backend_service.api_server_backend.id
}

resource "google_compute_region_target_http_proxy" "api_server_proxy" {
  name    = "gemini-api-proxy"
  project = google_project.service.project_id
  region  = var.region
  url_map = google_compute_region_url_map.api_server_urlmap.id
}

resource "google_compute_forwarding_rule" "api_server_ilb" {
  name                  = "gemini-api-ilb"
  project               = google_project.service.project_id
  region                = var.region
  load_balancing_scheme = "INTERNAL_MANAGED"
  network               = "projects/${google_project.host.project_id}/global/networks/${google_compute_network.shared_vpc.name}"
  subnetwork            = "projects/${google_project.host.project_id}/regions/${var.region}/subnetworks/${google_compute_subnetwork.vm_subnet_1.name}"
  target                = google_compute_region_target_http_proxy.api_server_proxy.id
  port_range            = "80-80"
}
