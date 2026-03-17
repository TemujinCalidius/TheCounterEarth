"""Roblox Open Cloud API wrapper for uploading assets."""

import os
import json
import mimetypes
import requests

ASSETS_API = "https://apis.roblox.com/assets/v1/assets"
OPERATIONS_API = "https://apis.roblox.com/assets/v1/operations"

# Roblox asset type IDs — use "Image" not "Decal" so ImageLabel can use the ID directly
ASSET_TYPES = {
    "image": "Image",
    "decal": "Decal",
    "audio": "Audio",
    "mesh": "Model",
    "model": "Model",
}

# MIME type mapping
MIME_TYPES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".bmp": "image/bmp",
    ".tga": "image/tga",
    ".mp3": "audio/mpeg",
    ".ogg": "audio/ogg",
    ".wav": "audio/wav",
    ".flac": "audio/flac",
    ".fbx": "model/fbx",
    ".obj": "model/obj",
    ".glb": "model/gltf-binary",
    ".stl": "model/stl",
}


def _get_config():
    api_key = os.environ.get("ROBLOX_OPEN_CLOUD_KEY")
    creator_id = os.environ.get("ROBLOX_CREATOR_ID")
    creator_type = os.environ.get("ROBLOX_CREATOR_TYPE", "User")
    if not api_key:
        raise RuntimeError(
            "ROBLOX_OPEN_CLOUD_KEY not set. Create one at https://create.roblox.com/credentials"
        )
    if not creator_id:
        raise RuntimeError("ROBLOX_CREATOR_ID not set in environment")
    return api_key, creator_id, creator_type


def _headers():
    api_key, _, _ = _get_config()
    return {"x-api-key": api_key}


def upload_asset(file_path, asset_type, name, description=""):
    """
    Upload a file to Roblox via Open Cloud Assets API.

    Args:
        file_path: Path to the file to upload
        asset_type: One of 'image', 'audio', 'mesh', 'model'
        name: Display name for the asset
        description: Optional description

    Returns:
        dict with 'assetId' and 'rbxassetid' keys
    """
    api_key, creator_id, creator_type = _get_config()

    roblox_type = ASSET_TYPES.get(asset_type.lower())
    if not roblox_type:
        raise ValueError(f"Unknown asset type: {asset_type}. Options: {list(ASSET_TYPES.keys())}")

    ext = os.path.splitext(file_path)[1].lower()
    content_type = MIME_TYPES.get(ext) or mimetypes.guess_type(file_path)[0] or "application/octet-stream"

    # Build the request metadata
    creation_context = {
        "creator": {
            "userId" if creator_type == "User" else "groupId": creator_id
        },
        "expectedPrice": 0,
    }

    request_json = {
        "assetType": roblox_type,
        "displayName": name,
        "description": description,
        "creationContext": creation_context,
    }

    headers = {"x-api-key": api_key}

    with open(file_path, "rb") as f:
        files = {
            "request": (None, json.dumps(request_json), "application/json"),
            "fileContent": (os.path.basename(file_path), f, content_type),
        }
        resp = requests.post(ASSETS_API, headers=headers, files=files)

    if resp.status_code == 400:
        raise RuntimeError(f"Upload failed (400): {resp.text}")
    resp.raise_for_status()

    data = resp.json()

    # The response may be an operation that needs polling
    if "path" in data and "done" in data:
        if data["done"]:
            result = data.get("response", {})
            asset_id = result.get("assetId")
        else:
            # Poll the operation
            asset_id = _poll_operation(data["path"], headers)
    elif "assetId" in data:
        asset_id = data["assetId"]
    else:
        raise RuntimeError(f"Unexpected response format: {data}")

    return {
        "assetId": asset_id,
        "rbxassetid": f"rbxassetid://{asset_id}",
    }


def _poll_operation(operation_path, headers, max_wait=60):
    """Poll an async operation until complete."""
    import time
    # operation_path may be "v1/operations/xxx" or "operations/xxx"
    # Normalize to use the assets operations endpoint
    op_id = operation_path.rsplit("/", 1)[-1]
    url = f"{OPERATIONS_API}/{op_id}"
    start = time.time()
    while time.time() - start < max_wait:
        resp = requests.get(url, headers=headers)
        resp.raise_for_status()
        data = resp.json()
        if data.get("done"):
            result = data.get("response", {})
            return result.get("assetId")
        time.sleep(2)
    raise TimeoutError(f"Upload operation timed out after {max_wait}s")


def check_config():
    """Verify Roblox Open Cloud configuration is set up."""
    try:
        api_key, creator_id, creator_type = _get_config()
        return {
            "configured": True,
            "creator_id": creator_id,
            "creator_type": creator_type,
            "api_key_set": bool(api_key),
        }
    except RuntimeError as e:
        return {"configured": False, "error": str(e)}
