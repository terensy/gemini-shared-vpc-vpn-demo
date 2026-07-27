"""
Cloud Run API server: 接收內部請求,呼叫 Vertex AI Gemini。

呼叫路徑: onprem Cloud Run function -> Internal LB -> 這支服務 -> Vertex AI。
"""

import json
import os
import re
import sys
from datetime import datetime, timezone

from flask import Flask, request, jsonify
from google import genai
from google.genai import types

PROJECT = os.environ.get("GOOGLE_CLOUD_PROJECT", "ai-demo-service-prj")
LOCATION = "global"
DEPT_LABEL = "infra_sa"

app = Flask(__name__)
client = genai.Client(vertexai=True, project=PROJECT, location=LOCATION)


def sanitize_label_value(value: str) -> str:
    """GCP label value 只能是小寫英數字、底線、連字號,最長 63 字元。"""
    value = str(value).strip().lower()
    value = re.sub(r"[^a-z0-9_-]", "-", value)
    return value[:63] or "unknown"


@app.route("/", methods=["POST"])
def generate():
    body = request.get_json(force=True, silent=True) or {}
    name = body.get("name")
    model = body.get("model")
    prompt = body.get("prompt")

    if not name or not model or not prompt:
        return jsonify({"error": "name, model, prompt 皆為必填"}), 400

    label_name = sanitize_label_value(name)
    label_model = sanitize_label_value(model)
    label_time = datetime.now(timezone.utc).strftime("%Y-%m-%d-%H-%M")

    contents = [
        types.Content(role="user", parts=[types.Part.from_text(text=prompt)]),
    ]
    config = types.GenerateContentConfig(
        temperature=1,
        top_p=0.95,
        max_output_tokens=65535,
        safety_settings=[
            types.SafetySetting(category="HARM_CATEGORY_HATE_SPEECH", threshold="OFF"),
            types.SafetySetting(category="HARM_CATEGORY_DANGEROUS_CONTENT", threshold="OFF"),
            types.SafetySetting(category="HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold="OFF"),
            types.SafetySetting(category="HARM_CATEGORY_HARASSMENT", threshold="OFF"),
        ],
        thinking_config=types.ThinkingConfig(thinking_level="low"),
        labels={
            "name": label_name,
            "model": label_model,
            "dept": DEPT_LABEL,
            "time": label_time,
        },
    )

    try:
        response = client.models.generate_content(model=model, contents=contents, config=config)
    except Exception as exc:  # noqa: BLE001
        print(json.dumps({"severity": "ERROR", "message": f"gemini call failed: {exc}"}), file=sys.stderr)
        return jsonify({"error": str(exc)}), 502

    usage = response.usage_metadata
    input_token = usage.prompt_token_count if usage else None
    output_token = usage.candidates_token_count if usage else None

    # Cloud Run 會把符合 JSON 格式的 stdout 行,自動轉成 Cloud Logging 的 jsonPayload。
    print(
        json.dumps(
            {
                "name": label_name,
                "model": label_model,
                "dept": DEPT_LABEL,
                "time": label_time,
                "input_token": input_token,
                "output_token": output_token,
            }
        ),
        flush=True,
    )

    return jsonify(
        {
            "text": response.text,
            "input_token": input_token,
            "output_token": output_token,
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
