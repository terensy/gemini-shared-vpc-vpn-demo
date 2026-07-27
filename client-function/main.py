"""
onprem 端的 Cloud Run function 入口:接收 name / model 顯示名稱 / prompt,
透過 Direct VPC Egress -> onprem-vpc/subnet-1 -> VPN -> Internal LB,呼叫
ai-demo-service-prj 的 gemini-api-server。

不對外公開,僅供 Console / gcloud 以有權限的身份直接呼叫測試。
"""

import os

import functions_framework
import google.auth.transport.requests
import google.oauth2.id_token
import requests

# gemini-api-server 的原生 Cloud Run URL(不是 LB 的網址)——
# Cloud Run IAM 驗證的 ID token audience 必須對到這個值,否則會 401。
API_SERVER_AUDIENCE = os.environ["API_SERVER_AUDIENCE"]
# Internal Load Balancer 的內部 IP,經 VPN 可達。
LB_ENDPOINT = os.environ["LB_ENDPOINT"]

MODEL_NAME_TO_ID = {
    "Gemini 3.6 Flash": "gemini-3.6-flash",
    "Gemini 3.5 Flash": "gemini-3.5-flash",
    "Gemini 3.1 Pro": "gemini-3.1-pro-preview",
}


@functions_framework.http
def handle_request(request):
    body = request.get_json(silent=True) or {}
    name = body.get("name")
    model_display_name = body.get("model")
    prompt = body.get("prompt")

    if not name or not model_display_name or not prompt:
        return {"error": "name, model, prompt 皆為必填"}, 400

    model_id = MODEL_NAME_TO_ID.get(model_display_name)
    if not model_id:
        return {
            "error": f"未知的 model: {model_display_name}",
            "valid_models": list(MODEL_NAME_TO_ID.keys()),
        }, 400

    auth_req = google.auth.transport.requests.Request()
    id_token = google.oauth2.id_token.fetch_id_token(auth_req, API_SERVER_AUDIENCE)

    resp = requests.post(
        LB_ENDPOINT,
        json={"name": name, "model": model_id, "prompt": prompt},
        headers={"Authorization": f"Bearer {id_token}"},
        timeout=120,
    )

    return resp.content, resp.status_code, {"Content-Type": "application/json"}
