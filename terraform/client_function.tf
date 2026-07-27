resource "google_service_account" "client_fn" {
  project      = google_project.onprem.project_id
  account_id   = "gemini-client-fn-sa"
  display_name = "Gemini Client Function (Cloud Run)"
}

data "archive_file" "client_fn_src" {
  type        = "zip"
  source_dir  = "${path.module}/../client-function"
  output_path = "${path.module}/.build/client-function.zip"
}

locals {
  # build_rev:原始碼沒變、但 build 指令本身要修正時,手動把這個數字往上加一次,
  # 強制 image tag 換新,讓 null_resource 跟 Cloud Run service 都重新 apply。
  client_fn_build_rev = "2"
  client_fn_image     = "asia-east1-docker.pkg.dev/${google_project.onprem.project_id}/cloud-run-source-deploy/gemini-client-fn:${data.archive_file.client_fn_src.output_sha}-${local.client_fn_build_rev}"
}

# functions-framework 的 HTTP function 用 buildpacks build,對應
# `gcloud run deploy --source=. --function=handle_request` 底層行為。
resource "null_resource" "build_client_fn" {
  triggers = {
    source_hash = data.archive_file.client_fn_src.output_sha
    build_rev   = local.client_fn_build_rev
  }

  provisioner "local-exec" {
    # 注意:--pack 的 env 參數一次只能帶一組 KEY=VALUE,帶多組(即使用 gcloud list
    # escaping)會導致 GOOGLE_FUNCTION_TARGET 沒有正確傳進 buildpack detect 階段,
    # 建置會靜默 fallback 成預設的 `gunicorn main:app`(找不到 app 物件會啟動失敗)。
    # GOOGLE_FUNCTION_SIGNATURE_TYPE 不設定時,functions-framework buildpack 預設就是 http。
    command = <<-EOT
      gcloud builds submit ${path.module}/../client-function \
        --pack image=${local.client_fn_image},builder=gcr.io/buildpacks/builder,env=GOOGLE_FUNCTION_TARGET=handle_request \
        --project=${google_project.onprem.project_id}
    EOT
  }

  depends_on = [google_project_service.onprem_apis]
}

resource "google_cloud_run_v2_service" "client_fn" {
  name     = "gemini-client-fn"
  project  = google_project.onprem.project_id
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.client_fn.email

    vpc_access {
      network_interfaces {
        network    = "projects/${google_project.onprem.project_id}/global/networks/${google_compute_network.onprem_vpc.name}"
        subnetwork = "projects/${google_project.onprem.project_id}/regions/${var.region}/subnetworks/${google_compute_subnetwork.subnet_1.name}"
      }
      egress = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = local.client_fn_image

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
        name  = "API_SERVER_AUDIENCE"
        value = google_cloud_run_v2_service.api_server.uri
      }

      env {
        name  = "LB_ENDPOINT"
        value = "http://${google_compute_forwarding_rule.api_server_ilb.ip_address}/"
      }
    }
  }

  depends_on = [null_resource.build_client_fn]
}
