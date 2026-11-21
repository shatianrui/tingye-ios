#!/usr/bin/env python3
"""Read-only checks for the 页签 worktree against build 148. No Swift compilation."""
from collections import Counter
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
BASE = "56c3b79d71378c5d792f0db56097968bbf3fba48"
HISTORICAL_OUTPUTS = {
    *("Design/v21-swiss/icon/out/" + name + ".png" for name in (
        "current-folio-512", "v21-ticks-blue-512", "v21-ticks-blue",
        "v21-ticks-light-512", "v21-ticks-light", "v21-turning-blue-512",
        "v21-turning-blue", "v21-turning-dark-512", "v21-turning-dark",
        "v21-turning-light-512", "v21-turning-light", "v21-type-light-512", "v21-type-light",
    )),
    *("Design/v23-time/icon/out/" + name + ".png" for name in (
        "AppIcon-dark", "AppIcon-tinted", "AppIcon", "preview",
    )),
    *("Design/v31-anthropic/app-icon/out/" + name + ".png" for name in (
        "AppIcon-dark", "AppIcon-tinted", "AppIcon",
    )),
}
LOCALES = {"zh-Hans", "zh-Hant", "en", "ja"}
FORMAT = re.compile(r"%%|%(?:\d+\$)?[-+#0 '.\d]*(?:hh|ll|[hlLzjt])?[@difuxXosgGeEcC]")


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def previous(path):
    return git("show", f"{BASE}:{path}")


def current(path):
    return (ROOT / path).read_bytes()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        assert key not in result, f"Duplicate JSON key: {key}"
        result[key] = value
    return result


def load_json(data):
    return json.loads(data, object_pairs_hook=unique_object)


def preserve(path):
    assert previous(path) == current(path), path


def preserve_region(path, start, end=None):
    def region(data):
        source = data.decode()
        offset = source.index(start) if start else 0
        return source[offset:source.index(end, offset) if end else len(source)]
    assert region(previous(path)) == region(current(path)), (path, start, end)


def verify_resources():
    project_path = "Tingye.xcodeproj/project.pbxproj"
    preserve(project_path)
    parser = runpy.run_path(str(ROOT / "scripts/verify-swift-sources.py"))["parse_project"]
    project = parser(current(project_path).decode())
    objects = project["objects"]
    paths = {}

    def visit(ref, parent):
        obj = objects[ref]
        source_tree = obj.get("sourceTree", "<group>")
        if source_tree not in ("<group>", "SOURCE_ROOT"):
            return
        path = (ROOT if source_tree == "SOURCE_ROOT" else parent) / obj.get("path", "")
        if obj["isa"] in ("PBXGroup", "PBXVariantGroup"):
            for child in obj["children"]:
                visit(child, path)
        elif obj["isa"] == "PBXFileReference":
            paths[ref] = path.resolve()

    visit(objects[project["rootObject"]]["mainGroup"], ROOT)
    resource_paths = []
    for target in [obj for obj in objects.values() if obj["isa"] == "PBXNativeTarget"]:
        for phase_id in target["buildPhases"]:
            phase = objects[phase_id]
            if phase["isa"] == "PBXResourcesBuildPhase":
                for build_id in phase["files"]:
                    obj = objects[build_id]
                    assert obj["isa"] == "PBXBuildFile"
                    resource = paths[obj["fileRef"]]
                    assert resource.exists(), f"Missing production/test resource: {resource}"
                    resource_paths.append(resource)
    for resource in paths.values():
        assert "Design" not in resource.relative_to(ROOT).parts, resource
    missing = set(git("ls-files", "--deleted", "--").decode().splitlines())
    assert missing <= HISTORICAL_OUTPUTS, missing - HISTORICAL_OUTPUTS
    for path in missing:
        assert previous(path).startswith(b"\x89PNG\r\n\x1a\n"), path
    production = git("ls-files", "-z", "--", "Tingye", "Tingye.xcodeproj", ".github", "scripts",
                     "create-project.rb").decode().split("\0")
    historic_dirs = {str(Path(path).parent) for path in HISTORICAL_OUTPUTS}
    for rel in filter(None, production):
        if Path(rel).suffix in (".swift", ".pbxproj", ".rb", ".py", ".sh", ".yml", ".yaml", ".plist"):
            source = (ROOT / rel).read_text()
            assert not any(directory in source for directory in historic_dirs), rel
    assets = next(path for path in resource_paths if path.suffix == ".xcassets")
    manifests = list(assets.rglob("Contents.json"))
    assert manifests, "Asset catalog has no Contents.json files"
    for manifest in manifests:
        for item in load_json(manifest.read_bytes()).get("images", []):
            if filename := item.get("filename"):
                assert (manifest.parent / filename).is_file(), (manifest, filename)
    for path in git("ls-tree", "-r", "--name-only", BASE, "--", str(assets.relative_to(ROOT))).decode().splitlines():
        preserve(path)
    info = plistlib.loads(current("Tingye/Info.plist"))
    for font in info["UIAppFonts"]:
        assert font in {resource.name for resource in resource_paths}, font
    assert "IPHONEOS_DEPLOYMENT_TARGET = 17.0;" in current(project_path).decode()
    print(f"Resources: {len(resource_paths)} build members, {len(manifests)} asset manifests, "
          f"{len(info['UIAppFonts'])} registered fonts, {len(missing)} inventoried historical outputs excluded")


def verify_localization():
    path = "Tingye/Resources/Localizable.xcstrings"
    before = load_json(previous(path))["strings"]
    after = load_json(current(path))["strings"]
    assert all(after.get(key) == entry for key, entry in before.items())
    added = after.keys() - before.keys()
    for key in added:
        translations = after[key]["localizations"]
        assert set(translations) == LOCALES, key
        expected = Counter(re.sub(r"^%\d+\$", "%", part) for part in FORMAT.findall(key))
        for locale, entry in translations.items():
            unit = entry["stringUnit"]
            assert unit["state"] == "translated" and unit["value"].strip(), (key, locale)
            actual = Counter(re.sub(r"^%\d+\$", "%", part) for part in FORMAT.findall(unit["value"]))
            assert expected == actual, (key, locale, expected, actual)
    print(f"Localization: {len(before)} preserved entries, {len(added)} added entries × 4 locales")


def verify_boundaries():
    protected = [
        ".github", "Tingye.xcodeproj", "Tingye/Info.plist", "Tingye/AppModel.swift",
        "Tingye/Models.swift", "Tingye/Services.swift", "Tingye/BookImporter.swift",
        "Tingye/MobiReader.swift", "Tingye/OriginalBookView.swift", "Tingye/SpeechPlayer.swift",
        "Tingye/DialogueRoles.swift", "scripts", "create-project.rb",
    ]
    protected += [
        str(path.relative_to(ROOT)) for path in (ROOT / "Tingye/Readium").glob("*.swift")
        if path.name != "ReadiumReaderView.swift"
    ]
    assert not git("diff", "--name-only", BASE, "--", *protected).strip()
    ranges = [
        ("Tingye/Theme.swift", "enum ReaderPaper", "extension String {"),
        ("Tingye/ReaderAnnotations.swift", None, "// MARK: - 选择面板"),
        ("Tingye/ReaderView.swift", "    private var textContent:", "    private var topBar:"),
        ("Tingye/ReaderView.swift", "struct NativeTextPage:", "struct PDFReader:"),
        ("Tingye/ReaderView.swift", "        view.displayMode = .singlePageContinuous", "// MARK: - 目录"),
        ("Tingye/Readium/ReadiumReaderView.swift", None, "struct ReadiumReaderView:"),
        ("Tingye/Readium/ReadiumReaderView.swift", "                    EPUBNavigatorHost(", "\n                }"),
        ("Tingye/Readium/ReadiumReaderView.swift", "    @MainActor private func open() async", "    @ViewBuilder private var annotationPanel"),
        ("Tingye/Readium/ReadiumReaderView.swift", "    private func saveAnnotation(", None),
        ("Tingye/ComicReaderView.swift", "        .task(id: index)", "\n    }\n"),
        ("Tingye/ComicReaderView.swift", "private struct ZoomableComicImage", None),
        ("Tingye/ICloudBackup.swift", None, "struct ICloudBackupView:"),
        ("Tingye/Library.swift", None, "struct AppLockGate:"),
        ("Tingye/GeneralSettingsView.swift", None, "struct GeneralSettingsView:"),
        ("Tingye/FocusSession.swift", None, "struct FocusStartView:"),
        ("Tingye/StorageView.swift", "enum StorageUsage", None),
        ("Tingye/Typography.swift", None, "struct MyFontsView:"),
        ("Tingye/PlayerView.swift", "    private var glmVoices:", None),
        ("Tingye/ShelfView.swift", "@MainActor\nstruct LocalBookPicker:", "\n/// 最近一批导入"),
        ("Tingye/ShelfView.swift", "struct ShareSheet:", None),
        ("Tingye/SMBBrowser.swift", None, "struct SMBBrowser:"),
        ("Tingye/Sources.swift", None, "struct SourcesView:"),
        ("Tingye/Sources.swift", "struct WebDAVItem:", "struct OPDSBrowser:"),
        ("Tingye/Sources.swift", "struct OPDSEntry:", "struct WiFiTransferView:"),
        ("Tingye/Sources.swift", "@MainActor\nfinal class WiFiTransferServer", None),
        ("Tingye/TingyeApp.swift", "    private var autoOpenAllowed:", "    var body:"),
        ("Tingye/TingyeApp.swift", "        .onChange(of: model.entries.count,", "        #if DEBUG"),
        ("Tingye/TingyeApp.swift", "        .onChange(of: model.selectedBook?.id)", "        .fullScreenCover"),
        ("Tingye/TingyeApp.swift", "                .onOpenURL", "#if DEBUG\n///"),
        ("Tingye/TingyeApp.swift", "struct WindowAppearance:", "// MARK: - 迷你播放器"),
        ("Tingye/TingyeApp.swift", "        .onChange(of: showingResults)", "            NavigationStack { ImportResultsView()"),
    ]
    for values in ranges:
        preserve_region(*values)
    app = current("Tingye/TingyeApp.swift").decode()
    assert app.count("LocalBookPicker(multiple: request.multiple)") == 1
    assert "resumeOnLaunch" not in app and "launch.resume" not in app
    changed_swift = git("diff", "--name-only", BASE, "--", "Tingye").decode().splitlines()
    tokens = [r'\.accessibilityIdentifier\(("[^"]*"|[^\n\)]*)', r"@AppStorage\([^\n]*"]
    for path in (p for p in changed_swift if p.endswith(".swift")):
        for pattern in tokens:
            removed = set(re.findall(pattern, previous(path).decode())) - set(re.findall(pattern, current(path).decode()))
            assert not removed, (path, removed)
    declarations = current("Tingye/Theme.swift").decode()
    for namespace in ("IndexTheme", "Icon"):
        body = declarations.split(f"enum {namespace} {{", 1)[1].split("\n}", 1)[0]
        known = set(re.findall(r"\bstatic (?:let|var|func) (\w+)", body))
        for path in (p for p in changed_swift if p.endswith(".swift")):
            source = current(path).decode()
            references = set(re.findall(rf"\b{namespace}\.(\w+)", source))
            assert references <= known, (path, namespace, references - known)
    kept = new = 0
    for path in git("ls-tree", "-r", "--name-only", BASE, "--", "TingyeTests", "TingyeUITests").decode().splitlines():
        original, actual = previous(path), current(path)
        if path.endswith(".swift"):
            assert actual.startswith(original), path
            kept += len(re.findall(rb"\bfunc test\w+\(", original))
            new += len(re.findall(rb"\bfunc test\w+\(", actual[len(original):]))
        else:
            assert original == actual, path
    scheme = ET.parse(ROOT / "Tingye.xcodeproj/xcshareddata/xcschemes/Tingye.xcscheme")
    testables = scheme.findall(".//TestableReference")
    assert len(testables) == 2 and all(t.get("skipped") == "NO" for t in testables)
    print(f"Source boundaries: {len(ranges)} byte-compared regions, original accessibility IDs and AppStorage, "
          f"{kept} test methods preserved and {new} appended")


def luminance(rgb):
    channels = [(rgb >> shift & 0xFF) / 255 for shift in (16, 8, 0)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in channels]
    return sum(c * scale for c, scale in zip(linear, (0.2126, 0.7152, 0.0722)))


def contrast(a, b):
    low, high = sorted(map(luminance, (a, b)))
    return (high + 0.05) / (low + 0.05)


def verify_contrast():
    theme = current("Tingye/Theme.swift").decode().split("enum IndexTheme {", 1)[1].split("struct IndexRule", 1)[0]
    tokens = {key: [int(code, 16) for code in re.findall(r"0x([0-9A-Fa-f]{6})", args)]
              for key, args in re.findall(r"static let (\w+) = Theme\.dynamic\(([^)]*)\)", theme)}
    text_pairs = [(color, layer) for color in ("ink", "muted", "accent", "danger", "warning")
                  for layer in ("canvas", "surface", "wash")]
    text_pairs += [("onAccent", "accent"), ("danger", "dangerWash")]
    lines = [("edge", layer) for layer in ("canvas", "surface", "wash")]
    text_values, line_values = [], []
    for mode in (0, 1, 2, 3):
        def color(key):
            tones = tokens[key]
            return tones[mode] if mode < len(tones) else tones[mode % 2]
        text_values.extend(contrast(color(a), color(b)) for a, b in text_pairs)
        line_values.extend(contrast(color(a), color(b)) for a, b in lines)
    assert min(text_values) >= 4.5 and min(line_values) >= 3, (min(text_values), min(line_values))
    print(f"Nominal contrast: {len(text_values)} text pairs, min {min(text_values):.2f}:1; "
          f"{len(line_values)} control pairs, min {min(line_values):.2f}:1")


def verify_matrix():
    folder = ROOT / "docs/redesign-20261121"
    pattern = r"^\| ([GISRPMT]\d\d)\b"
    coverage = re.findall(pattern, (folder / "COVERAGE.md").read_text(), re.M)
    status = (folder / "STATUS.md").read_text().split("## 当前 59 项验收矩阵", 1)[1]
    current_ids = re.findall(pattern, status, re.M)
    assert len(coverage) == len(set(coverage)) == 59 and current_ids == coverage
    for reference in set(re.findall(r"`(Tingye/[^ `]+\.swift)`", status)):
        assert (ROOT / reference).is_file(), reference
    for path in folder.glob("*.md"):
        for index, line in enumerate(path.read_text().splitlines(), 1):
            assert line == line.rstrip(), (path, index)
    print("Coverage: 59 unique rows reconciled in current STATUS")


if __name__ == "__main__":
    verify_resources()
    verify_localization()
    verify_boundaries()
    verify_contrast()
    verify_matrix()
