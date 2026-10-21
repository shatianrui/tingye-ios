#!/usr/bin/env python3
"""Render the v16 Ink icon (线装书题签); install only when explicitly passed --install.

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
# 墨夜：宣纸翻面为墨黑，书册为深色纸，朱砂印随夜间令牌转浅。
DARK = {
    "#FCF9F3": "#17171B", "#F0EBDE": "#101012",
    "#F3ECDA": "#2B2721", "#E9DFC9": "#211E18",
    "#8A7B5E": "#000000",
    "#E2D7BD": "#1C1A15", "#C4B494": "#463F32", "#CDBFA0": "#3A352A",
    "#D9CFB6": "#3A352A",
    "#FBF7EC": "#353026", "#DCD2B8": "#4C4638",
    "#1C1B18": "#EDE9DC",
    "#A63A2E": "#D97B6C",
}
# 着色图标：只保留明度层次，实际着色由 iOS 施加。
TINTED = {
    "#FCF9F3": "#2B2B2B", "#F0EBDE": "#1B1B1B",
    "#F3ECDA": "#D9D9D9", "#E9DFC9": "#C6C6C6",
    "#8A7B5E": "#080808",
    "#E2D7BD": "#ABABAB", "#C4B494": "#8F8F8F", "#CDBFA0": "#9A9A9A",
    "#D9CFB6": "#969696",
    "#FBF7EC": "#F2F2F2", "#DCD2B8": "#A2A2A2",
    "#1C1B18": "#333333",
    "#A63A2E": "#7A7A7A",
}


def gray(hex_color):
    rgb = [int(hex_color[i:i + 2], 16) for i in (1, 3, 5)]
    level = round(sum(c * w for c, w in zip(rgb, (0.2126, 0.7152, 0.0722))))
    return "#" + f"{level:02X}" * 3


def svg_for(source, mode):
    if mode == "light":
        return source
    palette = DARK if mode == "dark" else TINTED
    return re.sub(r"#[0-9A-Fa-f]{6}\b", lambda m: palette.get(m[0].upper(), gray(m[0]) if mode == "tinted" else m[0]), source)


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
    source = (HERE / "ink-book.svg").read_text()
    assert ET.fromstring(source).attrib["viewBox"] == "0 0 1024 1024"
    FINAL.mkdir(exist_ok=True)
    logs = ROOT / "build/ink-icon"
    logs.mkdir(parents=True, exist_ok=True)
    hashes = {}
    with tempfile.TemporaryDirectory(prefix="tingye-ink-icon-") as profile:
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
    report = {"selection": "ink-book", "sourceSHA256": hashlib.sha256(source.encode()).hexdigest(),
              "pngSHA256": hashes,
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
