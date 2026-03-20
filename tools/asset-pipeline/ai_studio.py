"""3D AI Studio API wrapper for generating images, 3D models, and textures."""

import os
import time
import requests

API_BASE = "https://api.3daistudio.com"
POLL_INTERVAL = 4  # seconds between status checks
MAX_POLL_TIME = 300  # 5 minutes max wait

# Model presets — endpoint paths from 3daistudio.com/Platform/API/Documentation
IMAGE_MODELS = {
    "gemini-2.5-flash": "/v1/images/gemini/2.5/flash/generate/",
    "gemini-3.1-flash": "/v1/images/gemini/3.1/flash/generate/",
    "gemini-3-pro": "/v1/images/gemini/3/pro/generate/",
    "seedream": "/v1/images/seedream/v5/lite/generate/",
}

MODEL_3D_MODELS = {
    "trellis2": "/v1/3d-models/trellis2/generate/",
    "hunyuan-pro": "/v1/3d-models/tencent/generate/pro/",
    "hunyuan-rapid": "/v1/3d-models/tencent/generate/rapid/",
}


def _get_api_key():
    key = os.environ.get("AI_STUDIO_API_KEY")
    if not key:
        raise RuntimeError("AI_STUDIO_API_KEY not set in environment")
    return key


def _headers():
    return {
        "Authorization": f"Bearer {_get_api_key()}",
    }


def _json_headers():
    h = _headers()
    h["Content-Type"] = "application/json"
    return h


def check_wallet():
    """Return wallet balance and rate limit."""
    resp = requests.get(f"{API_BASE}/account/user/wallet/", headers=_headers())
    resp.raise_for_status()
    return resp.json()


def poll_status(task_id):
    """Poll a generation task until complete. Returns result dict with download URLs."""
    url = f"{API_BASE}/v1/generation-request/{task_id}/status/"
    start = time.time()
    while True:
        resp = requests.get(url, headers=_headers())
        resp.raise_for_status()
        data = resp.json()
        status = data.get("status", "").lower()

        if status in ("completed", "complete", "done", "finished"):
            return data
        if status in ("failed", "error"):
            raise RuntimeError(f"Generation failed: {data}")
        if time.time() - start > MAX_POLL_TIME:
            raise TimeoutError(f"Generation timed out after {MAX_POLL_TIME}s. Task ID: {task_id}")

        elapsed = int(time.time() - start)
        print(f"  Status: {status} ({elapsed}s elapsed)...")
        time.sleep(POLL_INTERVAL)


def download_result(url, output_path):
    """Download a file from a URL to a local path."""
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    resp = requests.get(url, stream=True)
    resp.raise_for_status()
    with open(output_path, "wb") as f:
        for chunk in resp.iter_content(chunk_size=8192):
            f.write(chunk)
    return output_path


def generate_image(prompt, model="gemini-2.5-flash", num_images=1):
    """Submit an image generation request. Returns task_id."""
    endpoint = IMAGE_MODELS.get(model)
    if not endpoint:
        raise ValueError(f"Unknown image model: {model}. Options: {list(IMAGE_MODELS.keys())}")

    payload = {"prompt": prompt}

    # Model-specific parameters
    if model == "seedream":
        payload["num_images"] = min(num_images, 6)
    else:
        payload["num_images"] = min(num_images, 4)

    resp = requests.post(f"{API_BASE}{endpoint}", headers=_json_headers(), json=payload)
    resp.raise_for_status()
    data = resp.json()
    task_id = data.get("id") or data.get("task_id") or data.get("request_id")
    if not task_id:
        raise RuntimeError(f"No task ID in response: {data}")
    return task_id


def generate_3d(prompt=None, image_url=None, image_base64=None, model="trellis2"):
    """Submit a 3D model generation request. Returns task_id."""
    endpoint = MODEL_3D_MODELS.get(model)
    if not endpoint:
        raise ValueError(f"Unknown 3D model: {model}. Options: {list(MODEL_3D_MODELS.keys())}")

    payload = {}
    if prompt:
        payload["prompt"] = prompt
    if image_url:
        payload["image"] = image_url
    if image_base64:
        payload["image"] = image_base64

    if not payload:
        raise ValueError("Must provide either prompt, image_url, or image_base64")

    resp = requests.post(f"{API_BASE}{endpoint}", headers=_json_headers(), json=payload)
    resp.raise_for_status()
    data = resp.json()
    task_id = data.get("id") or data.get("task_id") or data.get("request_id")
    if not task_id:
        raise RuntimeError(f"No task ID in response: {data}")
    return task_id


def convert_format(file_url, output_format="fbx"):
    """Convert a 3D model between formats. Returns task_id."""
    payload = {
        "file": file_url,
        "output_format": output_format,
    }
    resp = requests.post(f"{API_BASE}/v1/tools/convert/", headers=_json_headers(), json=payload)
    resp.raise_for_status()
    data = resp.json()
    task_id = data.get("id") or data.get("task_id") or data.get("request_id")
    if not task_id:
        raise RuntimeError(f"No task ID in response: {data}")
    return task_id
