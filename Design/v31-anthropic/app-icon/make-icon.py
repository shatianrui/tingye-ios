#!/usr/bin/env python3
"""v31 §8: offline, deterministic Pillow rendering; no fonts or downloaded assets.

Run from any directory. Writes 1024px RGB PNGs in out/ and synchronizes the
three iOS universal AppIcon slots. iOS applies the outer icon mask itself.
"""
from pathlib import Path
import json
import shutil
from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4
HERE = Path(__file__).resolve().parent
ASSETS = HERE.parents[2] / "Tingye/Resources/Assets.xcassets/AppIcon.appiconset"
PALETTES = {
    "AppIcon.png": ("#FAF9F5", "#191817", "#D97757"),
    "AppIcon-dark.png": ("#131211", "#F5F3EC", "#D97757"),
    # The system applies the user's tint. Preserve the same single accent point
    # as a middle luminance; all input channels are equal in this variant.
    "AppIcon-tinted.png": ("#F5F5F5", "#191919", "#929292"),
}


def cubic(start, control1, control2, end):
    """Sample a cubic at supersampled resolution without external path tools."""
    points = []
    for step in range(1, 97):
        t = step / 96
        u = 1 - t
        points.append(tuple(u**3 * start[i] + 3*u*u*t * control1[i]
                            + 3*u*t*t * control2[i] + t**3 * end[i]
                            for i in range(2)))
    return points


def page_points():
    # Retain the installed icon's open book / wave silhouette, redrawn from
    # simple geometry. A quiet 200px margin keeps it legible at small sizes.
    points = [(200, 326)]
    points += cubic(points[-1], (200, 294), (211, 283), (245, 281))
    points += cubic(points[-1], (325, 270), (408, 296), (480, 348))
    points += [(480, 742)]
    points += cubic(points[-1], (398, 687), (320, 666), (238, 680))
    points += cubic(points[-1], (212, 684), (200, 670), (200, 644))
    return points


def render(palette):
    paper, ink, clay = palette
    image = Image.new("RGB", (SIZE*SCALE, SIZE*SCALE), paper)
    draw = ImageDraw.Draw(image)
    left = page_points()
    right = [(SIZE-x, y) for x, y in left]
    for points in [left, right]:
        draw.polygon([(round(x*SCALE), round(y*SCALE)) for x, y in points], fill=ink)
    # Three negative-space sound bars cut into the right page.
    for box in [(584, 428, 616, 572), (656, 380, 688, 620), (728, 416, 760, 584)]:
        draw.rounded_rectangle(tuple(v*SCALE for v in box), radius=16*SCALE, fill=paper)
    # Exactly one clay point at the upper outside page corner.
    draw.ellipse(tuple(v*SCALE for v in (245, 315, 277, 347)), fill=clay)
    return image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main():
    out = HERE / "out"
    out.mkdir(exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    slots = []
    for filename, palette in PALETTES.items():
        path = out / filename
        render(palette).save(path, format="PNG", optimize=True)
        shutil.copyfile(path, ASSETS / filename)
        slot = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if "-dark" in filename or "-tinted" in filename:
            slot["appearances"] = [{"appearance": "luminosity", "value": "dark" if "-dark" in filename else "tinted"}]
        slots.append(slot)
    (ASSETS / "Contents.json").write_text(json.dumps({"images": slots, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    print("Generated and installed three 1024×1024 RGB app icons.")


if __name__ == "__main__":
    main()
