"""Asset manifest management — tracks generated and uploaded assets."""

import json
import os
from datetime import datetime, timezone

MANIFEST_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "assets",
    "asset-manifest.json",
)


def _load():
    if not os.path.exists(MANIFEST_PATH):
        return {"assets": []}
    with open(MANIFEST_PATH, "r") as f:
        return json.load(f)


def _save(data):
    os.makedirs(os.path.dirname(MANIFEST_PATH), exist_ok=True)
    with open(MANIFEST_PATH, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def add_entry(name, local_path=None, rbx_asset_id=None, prompt=None, model=None,
              credit_cost=None, asset_type=None, source="3daistudio"):
    """Add or update an asset entry in the manifest."""
    data = _load()
    # Check if entry with this name already exists
    existing = None
    for i, entry in enumerate(data["assets"]):
        if entry.get("name") == name:
            existing = i
            break

    entry = {
        "name": name,
        "localPath": local_path,
        "rbxAssetId": rbx_asset_id,
        "source": source,
        "prompt": prompt,
        "model": model,
        "creditCost": credit_cost,
        "type": asset_type,
        "updatedAt": datetime.now(timezone.utc).isoformat(),
    }

    if existing is not None:
        # Preserve fields not being updated
        old = data["assets"][existing]
        for key in old:
            if key not in entry or entry[key] is None:
                entry[key] = old[key]
        entry["updatedAt"] = datetime.now(timezone.utc).isoformat()
        data["assets"][existing] = entry
    else:
        entry["createdAt"] = entry["updatedAt"]
        data["assets"].append(entry)

    _save(data)
    return entry


def get_by_name(name):
    """Look up an asset by name."""
    data = _load()
    for entry in data["assets"]:
        if entry.get("name") == name:
            return entry
    return None


def list_all():
    """Return all asset entries."""
    return _load()["assets"]


def remove(name):
    """Remove an asset entry by name."""
    data = _load()
    data["assets"] = [e for e in data["assets"] if e.get("name") != name]
    _save(data)
