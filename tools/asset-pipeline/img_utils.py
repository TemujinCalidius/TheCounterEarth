"""Image post-processing utilities for the asset pipeline."""

from PIL import Image


def remove_background(path, threshold_high=240, threshold_low=220):
    """
    Remove near-white backgrounds from generated images by converting to RGBA
    with true transparency.

    AI image generators often render "transparent" as a white or checkerboard
    background baked into RGB pixels. This detects and removes it.

    Args:
        path: Path to a PNG image (modified in-place)
        threshold_high: RGB min channel value above which pixels are fully transparent
        threshold_low: RGB min channel value above which pixels are feathered
    """
    img = Image.open(path).convert("RGBA")
    pixels = img.load()
    w, h = img.size

    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            min_rgb = min(r, g, b)
            if min_rgb > threshold_high:
                pixels[x, y] = (r, g, b, 0)
            elif min_rgb > threshold_low:
                new_a = int((threshold_high - min_rgb) / (threshold_high - threshold_low) * 255)
                pixels[x, y] = (r, g, b, new_a)

    img.save(path)


def resize_icon(path, max_size=512):
    """Resize an image to max_size x max_size if larger. Preserves aspect ratio and transparency."""
    img = Image.open(path)
    if img.width <= max_size and img.height <= max_size:
        return
    img.thumbnail((max_size, max_size), Image.LANCZOS)
    img.save(path)
