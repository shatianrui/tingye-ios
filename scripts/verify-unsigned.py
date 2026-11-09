"""Validate the unsigned app before packaging. Run on macOS or Linux."""
import plistlib
import sys
from pathlib import Path

app = Path(sys.argv[1])
if not app.is_dir():
    raise SystemExit("Missing .app bundle")
with (app / "Info.plist").open("rb") as f:
    info = plistlib.load(f)
if not info.get("CFBundleExecutable") or not (app / info["CFBundleExecutable"]).is_file():
    raise SystemExit("Missing app executable")
for pattern in ("**/_CodeSignature", "**/embedded.mobileprovision"):
    if next(app.glob(pattern), None):
        raise SystemExit("Unexpected signing artifact: " + pattern)
print("Unsigned bundle structure verified:", info.get("CFBundleIdentifier"))
