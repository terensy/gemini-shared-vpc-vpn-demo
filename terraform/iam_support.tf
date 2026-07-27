# 這個 org 沒有幫 default compute service account 自動加 Editor,
# gcloud run deploy --source 用到的 Cloud Build 步驟需要下面這些角色才跑得動。

resource "google_project_iam_member" "service_default_sa_storage_viewer" {
  project = google_project.service.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_project.service.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "service_default_sa_cloudbuild_builder" {
  project = google_project.service.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_project.service.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "onprem_default_sa_storage_viewer" {
  project = google_project.onprem.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_project.onprem.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "onprem_default_sa_cloudbuild_builder" {
  project = google_project.onprem.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_project.onprem.number}-compute@developer.gserviceaccount.com"
}

# Cloud Run 的 service agent 要有 compute.networkUser,才能用 Direct VPC Egress
# 打進對應的 VPC 子網路(host 是 Shared VPC,onprem 是自己的 VPC)。

resource "google_project_iam_member" "host_networkuser_for_service_run_agent" {
  project = google_project.host.project_id
  role    = "roles/compute.networkUser"
  member  = "serviceAccount:service-${google_project.service.number}@serverless-robot-prod.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "onprem_networkuser_for_onprem_run_agent" {
  project = google_project.onprem.project_id
  role    = "roles/compute.networkUser"
  member  = "serviceAccount:service-${google_project.onprem.number}@serverless-robot-prod.iam.gserviceaccount.com"
}
