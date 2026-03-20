#!/usr/bin/env python3
"""Batch generate and upload all missing item icons."""

import os
import sys
import time
import json

# Load .env
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
with open(os.path.join(PROJECT_ROOT, ".env")) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

import ai_studio
import roblox_upload
import img_utils

IMAGES_DIR = os.path.join(PROJECT_ROOT, "assets", "raw", "generated", "images")
RESULTS_FILE = os.path.join(PROJECT_ROOT, "assets", "raw", "generated", "icon_results.json")

PROMPT_TEMPLATE = """Create 1 matching inventory icon for a game UI: {subject}.

Context/theme: cozy survival RPG.
Composition: centered front view.
Shape language: chunky, rounded, cute, simple.
Material finish: smooth matte stylised surfaces.
Colour direction: muted earthy palette with cool accents.
Lighting: soft cinematic rim lighting.
Background: plain solid white background.
Mood: cozy and atmospheric.
Detail level: minimal but readable.

Use simple chunky forms, strong silhouette, clear negative space, and clean readability at small sizes.
Keep the presentation centered, cohesive, and game-ready.
The background MUST be pure white (#FFFFFF) with no gradients, shadows, or floor plane."""

ICONS = [
    ("stone_pickaxe", "A crude stone pickaxe, rough grey stone head lashed to a wooden twig handle"),
    ("wood", "A rough-hewn timber log, split firewood"),
    ("stone", "A solid grey stone chunk, chipped edges"),
    ("iron_ore", "Raw iron ore nugget, dark metallic rock with reddish-brown veins"),
    ("cooked_mushroom", "A roasted brown mushroom, golden-brown and slightly charred"),
    ("spoiled_food", "Rotten food remains, greenish-grey, flies buzzing"),
    ("water_skin", "A leather waterskin pouch tied with cord"),
    ("bandage", "A rolled white cloth bandage strip"),
    ("antidote", "A small corked glass vial with green liquid"),
    ("coin_credits", "A shiny gold coin with a star or credit symbol"),
    ("coin_copper", "A dull copper coin, simple design"),
    ("coin_silver", "A polished silver coin"),
    ("coin_gold", "An ornate gold coin with detailed edge"),
    ("pouch_credits", "A small drawstring coin pouch, simple fabric"),
    ("pouch_standard", "A leather coin pouch, slightly larger and heavier"),
    ("satchel_reed", "A woven reed satchel bag with shoulder strap"),
    ("pack_leather", "A sturdy leather backpack with buckle straps"),
]


def load_results():
    if os.path.exists(RESULTS_FILE):
        with open(RESULTS_FILE) as f:
            return json.load(f)
    return {}


def save_results(results):
    os.makedirs(os.path.dirname(RESULTS_FILE), exist_ok=True)
    with open(RESULTS_FILE, "w") as f:
        json.dump(results, f, indent=2)


def generate_one(name, subject, results):
    """Generate, process, and upload one icon. Returns rbxassetid string."""
    prompt = PROMPT_TEMPLATE.format(subject=subject)
    filename = f"{name}_icon.png"
    output_path = os.path.join(IMAGES_DIR, filename)
    os.makedirs(IMAGES_DIR, exist_ok=True)

    # Step 1: Generate
    print(f"  Generating...")
    task_id = ai_studio.generate_image(prompt, model="gemini-2.5-flash")
    print(f"  Task ID: {task_id}")

    result = ai_studio.poll_status(task_id)

    # Extract URL
    download_url = None
    if isinstance(result, dict):
        for container_key in ("results", "result", "outputs", "output"):
            container = result.get(container_key)
            if isinstance(container, list):
                for item in container:
                    if isinstance(item, dict) and "asset" in item:
                        download_url = item["asset"]
                        break
            if download_url:
                break
        if not download_url:
            for key in ("url", "download_url", "asset"):
                if key in result and result[key]:
                    download_url = result[key]
                    break

    if not download_url:
        print(f"  ERROR: No download URL found in: {result}")
        return None

    # Step 2: Download
    ai_studio.download_result(download_url, output_path)

    # Step 3: Background removal + resize
    img_utils.remove_background(output_path)
    img_utils.resize_icon(output_path, 512)
    print(f"  Saved: {output_path}")

    # Step 4: Upload to Roblox
    print(f"  Uploading to Roblox...")
    upload_result = roblox_upload.upload_asset(
        file_path=output_path,
        asset_type="image",
        name=f"{name}_icon",
        description=f"Inventory icon for {name.replace('_', ' ')}",
    )
    rbx_id = upload_result["rbxassetid"]
    print(f"  {rbx_id}")

    results[name] = rbx_id
    save_results(results)
    return rbx_id


def main():
    results = load_results()
    start_at = 0

    # Allow resuming from a specific index
    if len(sys.argv) > 1:
        start_at = int(sys.argv[1])

    print(f"=== Batch Icon Generation ({len(ICONS)} icons) ===")
    print(f"Already done: {list(results.keys())}")
    print()

    for i, (name, subject) in enumerate(ICONS):
        if i < start_at:
            continue
        if name in results:
            print(f"[{i+1}/{len(ICONS)}] {name}: SKIP (already done: {results[name]})")
            continue

        print(f"[{i+1}/{len(ICONS)}] {name}: {subject}")
        try:
            rbx_id = generate_one(name, subject, results)
            if rbx_id:
                print(f"  DONE: {rbx_id}")
            else:
                print(f"  FAILED: no asset ID")
        except Exception as e:
            print(f"  ERROR: {e}")

        # Rate limit: 3 req/min = 20s between requests
        if i < len(ICONS) - 1 and name not in results:
            print("  Waiting 22s (rate limit)...")
            time.sleep(22)

        print()

    print("=== Summary ===")
    for name, rbx_id in results.items():
        print(f"  {name}: {rbx_id}")
    print(f"\nResults saved to: {RESULTS_FILE}")


if __name__ == "__main__":
    main()
