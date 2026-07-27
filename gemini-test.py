"""
Gemini API 負載測試腳本
以固定 QPS(每秒請求數)持續發送請求,並統計結果。

用法:
    python3 gemini_load_test.py
    python3 gemini_load_test.py --qps 2 --duration 120
    python3 gemini_load_test.py --qps 5 --duration 60 --prompt "測試訊息"
"""

import argparse
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Optional

from google import genai
from google.genai import types
from google.oauth2 import service_account


@dataclass
class RequestResult:
    index: int
    success: bool
    latency_seconds: float
    output_chars: int = 0
    error: Optional[str] = None


def build_client(project: str, location: str, key_file: Optional[str] = None) -> genai.Client:
    credentials = None
    if key_file:
        credentials = service_account.Credentials.from_service_account_file(
            key_file,
            scopes=["https://www.googleapis.com/auth/cloud-platform"],
        )
    return genai.Client(
        vertexai=True,
        project=project,
        location=location,
        credentials=credentials,
    )


def send_one_request(
    client: genai.Client,
    model: str,
    prompt: str,
    index: int,
) -> RequestResult:
    contents = [
        types.Content(
            role="user",
            parts=[types.Part.from_text(text=prompt)],
        )
    ]

    generate_content_config = types.GenerateContentConfig(
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
    )

    start = time.monotonic()
    output_chars = 0
    try:
        for chunk in client.models.generate_content_stream(
            model=model,
            contents=contents,
            config=generate_content_config,
        ):
            if chunk.text:
                output_chars += len(chunk.text)
        latency = time.monotonic() - start
        return RequestResult(index=index, success=True, latency_seconds=latency, output_chars=output_chars)
    except Exception as exc:  # noqa: BLE001 - 負載測試需要捕捉所有例外並記錄
        latency = time.monotonic() - start
        return RequestResult(index=index, success=False, latency_seconds=latency, error=f"{type(exc).__name__}: {exc}")


def run_load_test(
    project: str,
    location: str,
    model: str,
    prompt: str,
    qps: float,
    duration: float,
    max_workers: int,
    key_file: Optional[str] = None,
) -> list:
    client = build_client(project, location, key_file)
    interval = 1.0 / qps
    total_requests = int(qps * duration)

    results: list = []
    results_lock = threading.Lock()
    completed_count = 0

    def on_done(future, idx):
        nonlocal completed_count
        result = future.result()
        with results_lock:
            results.append(result)
            completed_count_local = len(results)
        status = "OK" if result.success else f"FAIL ({result.error})"
        print(f"[{idx + 1:>4}/{total_requests}] {status} - {result.latency_seconds:.2f}s", flush=True)

    print(f"開始負載測試: {qps} QPS, 持續 {duration} 秒, 預計送出 {total_requests} 次請求")
    print(f"Project: {project} | Location: {location} | Model: {model}")
    print("-" * 60)

    overall_start = time.monotonic()
    futures = []

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        for i in range(total_requests):
            target_time = overall_start + i * interval
            sleep_time = target_time - time.monotonic()
            if sleep_time > 0:
                time.sleep(sleep_time)

            future = executor.submit(send_one_request, client, model, prompt, i)
            future.add_done_callback(lambda f, idx=i: on_done(f, idx))
            futures.append(future)

        # 等待所有仍在執行中的請求完成(因為 streaming 回應可能比發送間隔久)
        for future in as_completed(futures):
            pass

    overall_elapsed = time.monotonic() - overall_start
    return results, overall_elapsed


def print_summary(results: list, overall_elapsed: float, qps: float, duration: float):
    total = len(results)
    success = [r for r in results if r.success]
    failed = [r for r in results if not r.success]

    print("-" * 60)
    print("測試結果總結")
    print("-" * 60)
    print(f"實際耗時: {overall_elapsed:.1f} 秒 (預計 {duration} 秒)")
    print(f"實際平均 QPS: {total / overall_elapsed:.2f} (目標 {qps})")
    print(f"總請求數: {total}")
    print(f"成功: {len(success)}  失敗: {len(failed)}")

    if success:
        latencies = sorted(r.latency_seconds for r in success)
        avg = sum(latencies) / len(latencies)
        p50 = latencies[len(latencies) // 2]
        p95 = latencies[int(len(latencies) * 0.95)] if len(latencies) > 1 else latencies[0]
        print(f"延遲(成功請求) - 平均: {avg:.2f}s | p50: {p50:.2f}s | p95: {p95:.2f}s | 最大: {latencies[-1]:.2f}s")
        total_chars = sum(r.output_chars for r in success)
        print(f"總輸出字元數: {total_chars}")

    if failed:
        print("\n失敗原因統計:")
        error_counts = {}
        for r in failed:
            key = r.error or "unknown"
            error_counts[key] = error_counts.get(key, 0) + 1
        for err, count in sorted(error_counts.items(), key=lambda x: -x[1]):
            print(f"  [{count}x] {err}")


def main():
    parser = argparse.ArgumentParser(description="Gemini API 固定 QPS 負載測試")
    parser.add_argument("--project", default="tw-rd-sa-terence", help="GCP project ID")
    parser.add_argument("--location", default="global", help="Vertex AI location")
    parser.add_argument("--model", default="gemini-3.5-flash", help="Model ID")
    parser.add_argument("--prompt", default="今天天氣如何？", help="測試用的 prompt")
    parser.add_argument("--qps", type=float, default=2.0, help="每秒請求數")
    parser.add_argument("--duration", type=float, default=120.0, help="測試持續秒數")
    parser.add_argument("--max-workers", type=int, default=50, help="執行緒池大小上限")
    parser.add_argument("--key-file", default=None, help="Service account key JSON 檔案路徑(不指定則用 ADC)")
    args = parser.parse_args()

    results, overall_elapsed = run_load_test(
        project=args.project,
        location=args.location,
        model=args.model,
        prompt=args.prompt,
        qps=args.qps,
        duration=args.duration,
        max_workers=args.max_workers,
        key_file=args.key_file,
    )
    print_summary(results, overall_elapsed, args.qps, args.duration)


if __name__ == "__main__":
    main()