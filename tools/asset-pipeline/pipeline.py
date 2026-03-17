#!/usr/bin/env python3
"""
Asset Pipeline CLI — Generate assets via 3D AI Studio and upload to Roblox.

Usage:
    python3 pipeline.py wallet
    python3 pipeline.py generate-image --prompt "..." --name NAME [--model MODEL]
    python3 pipeline.py generate-3d --prompt "..." --name NAME [--model MODEL]
    python3 pipeline.py upload --file PATH --type TYPE --name NAME
    python3 pipeline.py generate-and-upload --prompt "..." --name NAME --type TYPE [--model MODEL]
    python3 pipeline.py status --task-id TASK_ID
    python3 pipeline.py manifest
    python3 pipeline.py roblox-check
"""

import argparse
import os
import sys

# Load .env from project root
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ENV_PATH = os.path.join(PROJECT_ROOT, ".env")

def load_dotenv():
    """Simple .env loader (no dependency needed)."""
    if not os.path.exists(ENV_PATH):
        return
    with open(ENV_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value

load_dotenv()

import ai_studio
import roblox_upload
import manifest
import img_utils


# Default output directories
IMAGES_DIR = os.path.join(PROJECT_ROOT, "assets", "raw", "generated", "images")
MODELS_DIR = os.path.join(PROJECT_ROOT, "assets", "raw", "generated", "models")


def cmd_wallet(args):
    """Check 3D AI Studio credit balance."""
    result = ai_studio.check_wallet()
    print(f"Balance: {result['balance']} credits")
    print(f"Rate limit: {result['rate_limit']} req/min")


def cmd_generate_image(args):
    """Generate an image via 3D AI Studio."""
    print(f"Generating image with {args.model}...")
    print(f"  Prompt: {args.prompt}")

    task_id = ai_studio.generate_image(args.prompt, model=args.model)
    print(f"  Task ID: {task_id}")
    print("  Polling for result...")

    result = ai_studio.poll_status(task_id)

    # Find the download URL(s) in the result
    download_urls = _extract_urls(result)
    if not download_urls:
        print(f"  Result: {result}")
        print("  WARNING: Could not find download URLs in response.")
        return

    os.makedirs(IMAGES_DIR, exist_ok=True)
    for i, url in enumerate(download_urls):
        suffix = f"_{i}" if len(download_urls) > 1 else ""
        ext = ".png"  # Default for images
        filename = f"{args.name}{suffix}{ext}"
        output_path = os.path.join(IMAGES_DIR, filename)
        ai_studio.download_result(url, output_path)
        img_utils.remove_background(output_path)
        img_utils.resize_icon(output_path)
        print(f"  Saved: {output_path}")

        # Log to manifest
        manifest.add_entry(
            name=f"{args.name}{suffix}" if suffix else args.name,
            local_path=os.path.relpath(output_path, PROJECT_ROOT),
            prompt=args.prompt,
            model=args.model,
            asset_type="image",
        )

    print("Done!")


def cmd_generate_3d(args):
    """Generate a 3D model via 3D AI Studio."""
    print(f"Generating 3D model with {args.model}...")
    print(f"  Prompt: {args.prompt}")

    task_id = ai_studio.generate_3d(prompt=args.prompt, model=args.model)
    print(f"  Task ID: {task_id}")
    print("  Polling for result (this may take a few minutes)...")

    result = ai_studio.poll_status(task_id)

    download_urls = _extract_urls(result)
    if not download_urls:
        print(f"  Result: {result}")
        print("  WARNING: Could not find download URLs in response.")
        return

    os.makedirs(MODELS_DIR, exist_ok=True)
    for i, url in enumerate(download_urls):
        suffix = f"_{i}" if len(download_urls) > 1 else ""
        ext = ".glb"  # Default for 3D models
        filename = f"{args.name}{suffix}{ext}"
        output_path = os.path.join(MODELS_DIR, filename)
        ai_studio.download_result(url, output_path)
        print(f"  Saved: {output_path}")

        manifest.add_entry(
            name=f"{args.name}{suffix}" if suffix else args.name,
            local_path=os.path.relpath(output_path, PROJECT_ROOT),
            prompt=args.prompt,
            model=args.model,
            asset_type="3d_model",
        )

    print("Done!")


def cmd_upload(args):
    """Upload an existing file to Roblox."""
    config = roblox_upload.check_config()
    if not config["configured"]:
        print(f"ERROR: {config['error']}")
        print("Set ROBLOX_OPEN_CLOUD_KEY and ROBLOX_CREATOR_ID in .env")
        sys.exit(1)

    print(f"Uploading {args.file} to Roblox as {args.type}...")
    result = roblox_upload.upload_asset(
        file_path=args.file,
        asset_type=args.type,
        name=args.name,
        description=args.description or "",
    )

    print(f"  Asset ID: {result['assetId']}")
    print(f"  rbxassetid: {result['rbxassetid']}")

    # Update manifest if this asset exists
    existing = manifest.get_by_name(args.name)
    manifest.add_entry(
        name=args.name,
        local_path=os.path.relpath(args.file, PROJECT_ROOT) if os.path.isabs(args.file) else args.file,
        rbx_asset_id=result["rbxassetid"],
        asset_type=args.type,
        source="upload",
    )

    print("Done!")


def cmd_generate_and_upload(args):
    """Generate an image then upload it to Roblox."""
    # Step 1: Generate
    print(f"Step 1/2: Generating image with {args.model}...")
    task_id = ai_studio.generate_image(args.prompt, model=args.model)
    print(f"  Task ID: {task_id}")
    result = ai_studio.poll_status(task_id)

    download_urls = _extract_urls(result)
    if not download_urls:
        print(f"  Result: {result}")
        print("  ERROR: Could not find download URLs.")
        sys.exit(1)

    os.makedirs(IMAGES_DIR, exist_ok=True)
    local_path = os.path.join(IMAGES_DIR, f"{args.name}.png")
    ai_studio.download_result(download_urls[0], local_path)
    img_utils.remove_background(local_path)
    img_utils.resize_icon(local_path)
    print(f"  Saved: {local_path}")

    # Step 2: Upload
    config = roblox_upload.check_config()
    if not config["configured"]:
        print(f"\nStep 2/2: SKIPPED — Roblox not configured: {config['error']}")
        manifest.add_entry(
            name=args.name,
            local_path=os.path.relpath(local_path, PROJECT_ROOT),
            prompt=args.prompt,
            model=args.model,
            asset_type=args.type,
        )
        print("  Asset saved locally. Run 'upload' separately after configuring Roblox.")
        return

    print(f"\nStep 2/2: Uploading to Roblox...")
    upload_result = roblox_upload.upload_asset(
        file_path=local_path,
        asset_type=args.type,
        name=args.name,
    )
    print(f"  {upload_result['rbxassetid']}")

    manifest.add_entry(
        name=args.name,
        local_path=os.path.relpath(local_path, PROJECT_ROOT),
        rbx_asset_id=upload_result["rbxassetid"],
        prompt=args.prompt,
        model=args.model,
        asset_type=args.type,
    )
    print("Done!")


def cmd_status(args):
    """Check status of a generation task."""
    result = ai_studio.poll_status(args.task_id)
    print(f"Status: {result}")


def cmd_manifest(args):
    """List all assets in the manifest."""
    assets = manifest.list_all()
    if not assets:
        print("No assets in manifest.")
        return
    print(f"{'Name':<25} {'Type':<10} {'Roblox ID':<30} {'Local Path'}")
    print("-" * 95)
    for a in assets:
        name = a.get("name", "?")[:24]
        atype = (a.get("type") or "?")[:9]
        rbx = (a.get("rbxAssetId") or "—")[:29]
        path = a.get("localPath") or "—"
        print(f"{name:<25} {atype:<10} {rbx:<30} {path}")


def cmd_roblox_check(args):
    """Check Roblox Open Cloud configuration."""
    config = roblox_upload.check_config()
    if config["configured"]:
        print("Roblox Open Cloud: CONFIGURED")
        print(f"  Creator ID: {config['creator_id']}")
        print(f"  Creator type: {config['creator_type']}")
    else:
        print("Roblox Open Cloud: NOT CONFIGURED")
        print(f"  {config['error']}")


def _extract_urls(result):
    """Extract download URLs from a poll result, handling various response formats."""
    urls = []

    # Check common response structures
    if isinstance(result, dict):
        # Direct URL field
        for key in ("url", "download_url", "result_url", "output_url", "asset"):
            if key in result and result[key]:
                urls.append(result[key])

        # Nested in 'result' or 'output'
        for container_key in ("result", "output", "results", "outputs"):
            container = result.get(container_key)
            if isinstance(container, str) and container.startswith("http"):
                urls.append(container)
            elif isinstance(container, list):
                for item in container:
                    if isinstance(item, str) and item.startswith("http"):
                        urls.append(item)
                    elif isinstance(item, dict):
                        for key in ("url", "download_url", "file_url", "asset"):
                            if key in item and item[key]:
                                urls.append(item[key])
            elif isinstance(container, dict):
                for key in ("url", "download_url", "file_url"):
                    if key in container and container[key]:
                        urls.append(container[key])

        # GLB-specific fields
        for key in ("glb_url", "model_url", "mesh_url"):
            if key in result and result[key]:
                urls.append(result[key])

    return list(dict.fromkeys(urls))  # deduplicate while preserving order


def main():
    parser = argparse.ArgumentParser(
        description="Asset Pipeline — Generate and upload game assets",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # wallet
    subparsers.add_parser("wallet", help="Check 3D AI Studio credit balance")

    # generate-image
    p = subparsers.add_parser("generate-image", help="Generate an image")
    p.add_argument("--prompt", required=True, help="Text prompt for generation")
    p.add_argument("--name", required=True, help="Asset name (used for filename and manifest)")
    p.add_argument("--model", default="gemini-2.5-flash",
                   choices=list(ai_studio.IMAGE_MODELS.keys()),
                   help="Image model to use (default: gemini-2.5-flash)")

    # generate-3d
    p = subparsers.add_parser("generate-3d", help="Generate a 3D model")
    p.add_argument("--prompt", required=True, help="Text prompt for generation")
    p.add_argument("--name", required=True, help="Asset name")
    p.add_argument("--model", default="trellis2",
                   choices=list(ai_studio.MODEL_3D_MODELS.keys()),
                   help="3D model to use (default: trellis)")

    # upload
    p = subparsers.add_parser("upload", help="Upload a file to Roblox")
    p.add_argument("--file", required=True, help="Path to the file to upload")
    p.add_argument("--type", required=True, choices=["image", "audio", "mesh", "model"],
                   help="Asset type")
    p.add_argument("--name", required=True, help="Display name for the asset")
    p.add_argument("--description", default="", help="Optional description")

    # generate-and-upload
    p = subparsers.add_parser("generate-and-upload", help="Generate an image and upload to Roblox")
    p.add_argument("--prompt", required=True, help="Text prompt")
    p.add_argument("--name", required=True, help="Asset name")
    p.add_argument("--type", default="image", choices=["image", "audio"],
                   help="Asset type (default: image)")
    p.add_argument("--model", default="gemini-2.5-flash",
                   choices=list(ai_studio.IMAGE_MODELS.keys()),
                   help="Image model (default: gemini-2.5-flash)")

    # status
    p = subparsers.add_parser("status", help="Check generation task status")
    p.add_argument("--task-id", required=True, help="Task ID to check")

    # manifest
    subparsers.add_parser("manifest", help="List all assets in manifest")

    # roblox-check
    subparsers.add_parser("roblox-check", help="Check Roblox Open Cloud configuration")

    args = parser.parse_args()
    cmd_map = {
        "wallet": cmd_wallet,
        "generate-image": cmd_generate_image,
        "generate-3d": cmd_generate_3d,
        "upload": cmd_upload,
        "generate-and-upload": cmd_generate_and_upload,
        "status": cmd_status,
        "manifest": cmd_manifest,
        "roblox-check": cmd_roblox_check,
    }
    cmd_map[args.command](args)


if __name__ == "__main__":
    main()
