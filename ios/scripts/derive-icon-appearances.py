#!/usr/bin/env python3
"""Derive appearance assets without redrawing the owner's artwork.

Requires Pillow 13.0.0 (a tooling dependency, never an app dependency).
Run from any directory. The source hash is a deliberate brand-artwork guard.
"""
from collections import Counter
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "ios/Departs/Departs/Assets.xcassets/AppIcon.appiconset"
CAPTURES = ROOT / "docs/screenshots/ios-design-phase-4"
SOURCE = ASSETS / "AppIcon.png"
EXPECTED = "d434b6d1494b397ad0427b3b5c6cd75028a579d1f95da01dfd3eb2d78039d0a3"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == EXPECTED, "Source artwork changed"
original = Image.open(SOURCE)
assert original.size == (1024, 1024) and original.mode == "RGB"
pixels = list(original.get_flattened_data())
ground = (35, 35, 40)
assert Counter(pixels)[ground] == 981928, "Unexpected artwork ground"

# Remove only exact ground pixels. Do not threshold, trace, move, or repaint
# any foreground or antialiased pixel. RGB channels remain byte-for-byte equal.
dark = original.convert("RGBA")
dark.putdata([(*pixel, 0 if pixel == ground else 255) for pixel in pixels])
assert dark.convert("RGB").tobytes() == original.tobytes()
dark.save(ASSETS / "AppIcon-Dark.png")

# Standard deterministic luminance conversion; keep the full original geometry.
tinted = original.convert("L")
profile = Path("/System/Library/ColorSync/Profiles/Generic Gray Gamma 2.2 Profile.icc")
assert profile.exists(), "Install the system Gray Gamma 2.2 profile before deriving"
tinted.save(ASSETS / "AppIcon-Tinted.png", icc_profile=profile.read_bytes())
assert tinted.size == original.size
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == EXPECTED

# Captures of unchanged artwork at actual @2x and @3x point sizes.
# Only resampling for these review sheets; no changes to the wordmark.
CAPTURES.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 26)
metrics = {"source_sha256": EXPECTED, "transparent_ground_pixels": 981928, "sizes": []}
foreground = Image.new("L", original.size)
foreground.putdata([0 if pixel == ground else 255 for pixel in pixels])
wordmark_box = foreground.crop((0, 0, 1024, 500)).getbbox()
line_box = foreground.crop((120, 600, 250, 670)).getbbox()
stop_mask = Image.new("L", original.size)
stop_mask.putdata([255 if pixel == (180, 210, 240) else 0 for pixel in pixels])
stop_box = stop_mask.getbbox()
assert wordmark_box and line_box and stop_box
wordmark_height = wordmark_box[3] - wordmark_box[1]
line_height = line_box[3] - line_box[1]
stop_diameter = stop_box[2] - stop_box[0]
metrics["source_geometry_px"] = {
    "wordmark_bbox": wordmark_box,
    "line_thickness": line_height,
    "stop_diameter": stop_diameter,
}
for scale in (2, 3):
    sheet = Image.new("RGB", (1020, 420), "#f2f2f7")
    draw = ImageDraw.Draw(sheet)
    draw.text((20, 15), f"Unchanged artwork • @{scale}x • 60 / 40 / 29 pt", font=font, fill="#232328")
    for column, points in enumerate((60, 40, 29)):
        size = points * scale
        thumb = original.resize((size, size), Image.Resampling.LANCZOS)
        thumb.save(CAPTURES / f"icon-default-{points}pt-{scale}x.png")
        x = 25 + column * 330
        sheet.paste(thumb, (x, 85))
        draw.text((x, 295), f"{points} pt ({size} px)", font=font, fill="#232328")
        metrics["sizes"].append({
            "points": points, "scale": scale,
            "wordmark_height_pt": round(wordmark_height * points / 1024, 2),
            "line_thickness_pt": round(line_height * points / 1024, 2),
            "stop_diameter_pt": round(stop_diameter * points / 1024, 2),
        })
    sheet.save(CAPTURES / f"icon-small-sizes-{scale}x.png")

# Appearance review on a checkerboard makes transparent pixels explicit.
sheet = Image.new("RGB", (1020, 400), "#f2f2f7")
draw = ImageDraw.Draw(sheet)
for column, (label, icon) in enumerate((("Default (unchanged)", original), ("Dark (ground removed)", dark), ("Tinted (grayscale)", tinted))):
    x = column * 340 + 20
    for y in range(55, 355, 20):
        for xx in range(x, x + 300, 20):
            draw.rectangle((xx, y, xx + 19, y + 19), fill="#3a3a3c" if ((xx-x)//20 + (y-55)//20) % 2 else "#28282a")
    thumb = icon.resize((300, 300), Image.Resampling.LANCZOS)
    sheet.paste(thumb, (x, 55), thumb if thumb.mode == "RGBA" else None)
    draw.text((x, 14), label, font=ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 22), fill="#232328")
sheet.save(CAPTURES / "icon-appearance-review.png")
(CAPTURES / "icon-measurements.json").write_text(json.dumps(metrics, indent=2) + "\n")
print(json.dumps(metrics, indent=2))
