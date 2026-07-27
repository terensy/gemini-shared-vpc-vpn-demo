resource "google_folder" "ai_demo" {
  display_name = "ai-demo-folder"
  parent       = "organizations/${var.org_id}"
}

resource "google_project" "host" {
  project_id      = "ai-demo-host-prj"
  name            = "ai-demo-host-prj"
  folder_id       = google_folder.ai_demo.folder_id
  billing_account = var.billing_account
}

resource "google_project" "onprem" {
  project_id      = "ai-demo-onprem-prj"
  name            = "ai-demo-onprem-prj"
  folder_id       = google_folder.ai_demo.folder_id
  billing_account = var.billing_account
}

resource "google_project" "service" {
  project_id      = "ai-demo-service-prj"
  name            = "ai-demo-service-prj"
  folder_id       = google_folder.ai_demo.folder_id
  billing_account = var.billing_account
}

# 只管我們這次建置實際去啟用的 API,不管專案建立時 GCP 自動附帶的那一大包預設 API。

resource "google_project_service" "host_compute" {
  project            = google_project.host.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "service_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "run.googleapis.com",
    "aiplatform.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
  ])
  project            = google_project.service.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service" "onprem_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "run.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "eventarc.googleapis.com",
  ])
  project            = google_project.onprem.project_id
  service            = each.value
  disable_on_destroy = false
}
