#!/usr/bin/env python3
"""Render the selected icon 02; install only when explicitly passed --install.

Requires local Google Chrome. All browsing uses a disposable profile and local SVGs.
"""
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
FINAL = HERE / "final"
ASSETS = ROOT / "Tingye/Resources/Assets.xcassets/AppIcon.appiconset"
CHROME = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
NAMES = {"light": "AppIcon.png", "dark": "AppIcon-dark.png", "tinted": "AppIcon-tinted.png"}
DARK = {
    "#F0F3E9": "#35423D", "#D7E1D9": "#1D2825", "#F7F7EC": "#526050",
    "#B69E6D": "#C7B282", "#5B6F60": "#101815",
    "#ECCE8C": "#E3C582", "#CCA257": "#C49C55",
    "#F9E7CC": "#EEDDC1", "#F0D2AC": "#DEC29D",
    "#7F9E84": "#8CA38C", "#52755F": "#607F69",
    "#FFFAEE": "#E8E0D0", "#EEE4D3": "#CBC0AD", "#F5EDDF": "#DAD0BD",
    "#C8BCA6": "#A39782", "#CEC0AA": "#A99A82", "#D2C3AC": "#AD9F87",
    "#82748D": "#A292AF", "#F1D3AE": "#E5CAA7",
}
# Purposeful luminance separation, rather than simply desaturating the light background.
TINTED = {
    "#F0F3E9": "#252525", "#D7E1D9": "#151515", "#F7F7EC": "#3D3D3D",
    "#B69E6D": "#9B9B9B", "#5B6F60": "#080808",
    "#ECCE8C": "#D4D4D4", "#CCA257": "#AAAAAA",
    "#F9E7CC": "#F0F0F0", "#F0D2AC": "#DADADA",
    "#7F9E84": "#929292", "#52755F": "#646464",
    "#FFFAEE": "#EEEEEE", "#EEE4D3": "#CCCCCC", "#F5EDDF": "#DDDDDD",
    "#82748D": "#A0A0A0", "#6C6353": "#494949", "#B38D72": "#797979",
}


def gray(hex_color):
    rgb = [int(hex_color[i:i + 2], 16) for i in (1, 3, 5)]
    level = round(sum(c * w for c, w in zip(rgb, (0.2126, 0.7152, 0.0722))))
    return "#" + f"{level:02X}" * 3


def svg_for(source, mode):
    if mode == "light":
        return source
    palette = DARK if mode == "dark" else TINTED
    svg = re.sub(r"#[0-9A-Fa-f]{6}\b", lambda m: palette.get(m[0].upper(), gray(m[0]) if mode == "tinted" else m[0]), source)
    # Preserve the chosen silhouette, pose and facial expression in every appearance.
    # Target the halo only; do not alter the opacity of any illustration strokes.
    old_halo = f'<circle cx="513" cy="448" r="281" fill="{palette["#F7F7EC"]}" opacity=".5"/>'
    assert svg.count(old_halo) == 1
    svg = svg.replace(old_halo, old_halo.replace('opacity=".5"', 'opacity=".32"'))
    return svg


def validate_png(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    assert data[12:16] == b"IHDR", path
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    assert (width, height, depth) == (1024, 1024, 8), (path, width, height, depth)
    assert color in (0, 2), f"PNG must have no alpha channel: {path}"
    offset = 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        assert data[offset + 4:offset + 8] != b"tRNS", f"Transparent PNG: {path}"
        offset += length + 12
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true", help="Copy the checked PNGs into the existing AppIcon asset set")
    args = parser.parse_args()
    assert CHROME.is_file(), "Local Google Chrome is required"
    source = (HERE / "02-reading.svg").read_text()
    assert ET.fromstring(source).attrib["viewBox"] == "0 0 1024 1024"
    FINAL.mkdir(exist_ok=True)
    logs = ROOT / "build/little-prince-icon"
    logs.mkdir(parents=True, exist_ok=True)
    hashes = {}
    with tempfile.TemporaryDirectory(prefix="tingye-prince-final-") as profile:
        for mode, filename in NAMES.items():
            svg = FINAL / f"{mode}.svg"
            svg.write_text(svg_for(source, mode))
            image = FINAL / filename
            with (logs / f"final-{mode}-render.log").open("w") as log:
                subprocess.run([
                    str(CHROME), "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--no-first-run", "--no-default-browser-check", "--disable-background-networking",
                    f"--user-data-dir={profile}", "--window-size=1024,1024", "--force-device-scale-factor=1",
                    f"--screenshot={image}", "--virtual-time-budget=1200", svg.as_uri(),
                ], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=45)
            hashes[filename] = validate_png(image)
            print(f"Validated {mode}: 1024 × 1024, opaque, SHA256 {hashes[filename]}", flush=True)
    selected_hash = hashlib.sha256((HERE / "previews/02-reading.png").read_bytes()).hexdigest()
    assert hashes["AppIcon.png"] == selected_hash, "Default icon must remain identical to the selected preview"
    report = {"selection": "02-reading", "sourceSHA256": hashlib.sha256(source.encode()).hexdigest(),
              "pngSHA256": hashes, "defaultMatchesSelectedPreview": True,
              "installed": args.install, "note": "Tinted is grayscale input; the actual tint is applied by iOS."}
    if args.install:
        metadata = json.loads((ASSETS / "Contents.json").read_text())
        assert {entry["filename"] for entry in metadata["images"]} == set(NAMES.values())
        for name in NAMES.values():
            shutil.copyfile(FINAL / name, ASSETS / name)
            assert validate_png(ASSETS / name) == hashes[name]
    (logs / "final-assets.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
