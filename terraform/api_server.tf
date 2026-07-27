resource "google_service_account" "api_server" {
  project      = google_project.service.project_id
  account_id   = "gemini-api-server-sa"
  display_name = "Gemini API Server (Cloud Run)"
}

resource "google_project_iam_member" "api_server_aiplatform_user" {
  project = google_project.service.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.api_server.email}"
}

# --- 從原始碼 build image(空環境重建用)---
# Terraform 的 google provider 沒有「從原始碼 build」這種資源,這裡用
# null_resource + local-exec 呼叫 Cloud Build 的 buildpacks 建置,行為等同
# `gcloud run deploy --source`底層做的事。archive_file 算原始碼 hash 當 image tag,
# 原始碼沒變就不會觸發重建。

data "archive_file" "api_server_src" {
  type        = "zip"
  source_dir  = "${path.module}/../api-server"
  output_path = "${path.module}/.build/api-server.zip"
}

locals {
  api_server_image = "asia-east1-docker.pkg.dev/${google_project.service.project_id}/cloud-run-source-deploy/gemini-api-server:${data.archive_file.api_server_src.output_sha}"
}

resource "null_resource" "build_api_server" {
  triggers = {
    source_hash = data.archive_file.api_server_src.output_sha
  }

  provisioner "local-exec" {
    command = <<-EOT
      gcloud builds submit ${path.module}/../api-server \
        --pack image=${local.api_server_image},builder=gcr.io/buildpacks/builder \
        --project=${google_project.service.project_id}
    EOT
  }

  depends_on = [google_project_service.service_apis]
}

resource "google_cloud_run_v2_service" "api_server" {
  name     = "gemini-api-server"
  project  = google_project.service.project_id
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.api_server.email

    vpc_access {
      network_interfaces {
        network    = "projects/${google_project.host.project_id}/global/networks/${google_compute_network.shared_vpc.name}"
        subnetwork = "projects/${google_project.host.project_id}/regions/${var.region}/subnetworks/${google_compute_subnetwork.serverless_subnet.name}"
      }
      egress = "ALL_TRAFFIC"
    }

    containers {
      image = local.api_server_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = google_project.service.project_id
      }
    }
  }

  depends_on = [null_resource.build_api_server]
}

# onprem 端的 gemini-client-fn-sa 需要能呼叫這支服務(跨專案 IAM)。
resource "google_cloud_run_v2_service_iam_member" "api_server_invoker_from_client_fn" {
  project  = google_cloud_run_v2_service.api_server.project
  location = google_cloud_run_v2_service.api_server.location
  name     = google_cloud_run_v2_service.api_server.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.client_fn.email}"
}
