#!/usr/bin/env python3
"""Run one original EPUB test on a fresh, matched macOS simulator and preserve evidence."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import subprocess as sp
import sys


EXPECTED_SHA = "cbbe25c8060635199995dae7cbdea461806578da"
TEST = "TingyeUITests/DesignFlowTests/testEPUBDerivedFixtureSmokeAndSearch"
DEVICE = "iPhone 17 Pro"
OS_VERSION = "26.4.1"
OS_BUILD = "23E254a"
XCODE = "Xcode 26.6\nBuild version 17F113"
XCODE_DIR = "/Applications/Xcode_26.6.app/Contents/Developer"
SIM = ["xcrun", "simctl"]
PREDICATE = (
    'process IN {"Tingye", "akd", "appSSOAgent", "AppSSOAgent", "appSSODaemon", "AppSSODaemon"} '
    'OR processImagePath CONTAINS[c] "/Tingye.app/" '
    'OR process BEGINSWITH[c] "com.apple.WebKit" OR subsystem BEGINSWITH[c] "com.apple.WebKit" '
    'OR subsystem BEGINSWITH[c] "com.apple.AppSSO" OR subsystem BEGINSWITH[c] "com.apple.AppSSOAgent" '
    'OR (process IN {"runningboardd", "SpringBoard", "testmanagerd"} '
    'AND (eventMessage CONTAINS[c] "com.shatianrui.wereader" OR eventMessage CONTAINS[c] "WebKit"))'
)
MILESTONE = re.compile(r"loadRequest|tryAuthorize|AppSSO|ExtensibleSSO|WebURLSchemeTask|provisionalLoad|"
                       r"didFinishNavigation|reader\.contents|Waiting 15\.0s for WebView|accessibility hierarchy|Test Case",
                       re.I)


def utc_now():
    return dt.datetime.now(dt.timezone.utc)


def output(argv, cwd=None, timeout=60):
    return sp.check_output(argv, cwd=cwd, timeout=timeout, text=True).strip()


def git(repo, *args):
    return output(["git", "-C", str(repo), *args])


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def choose_runtime(runtimes, types):
    available = [r for r in runtimes if r.get("isAvailable") and
                 r.get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
    matching = []
    for runtime in available:
        if runtime.get("buildversion") != OS_BUILD:
            continue
        installed_version = runtime.get("version")
        evidence = "simctl runtime JSON"
        if installed_version != OS_VERSION:
            # A runtime name/identifier can use the major.minor display version.
            # Confirm the patch on disk before accepting the shared build number.
            paths = []
            if runtime.get("runtimeRoot"):
                paths.append(Path(runtime["runtimeRoot"]))
            if runtime.get("bundlePath"):
                paths.append(Path(runtime["bundlePath"]) / "Contents/Resources/RuntimeRoot")
            for path in paths:
                system_version = path / "System/Library/CoreServices/SystemVersion.plist"
                if not system_version.is_file():
                    continue
                with system_version.open("rb") as file:
                    data = plistlib.load(file)
                if (data.get("ProductVersion"), data.get("ProductBuildVersion")) == (OS_VERSION, OS_BUILD):
                    installed_version, evidence = OS_VERSION, str(system_version)
                    break
        if installed_version == OS_VERSION:
            matching.append((runtime, evidence))
    devices = [d for d in types if d.get("name") == DEVICE]
    if len(matching) != 1 or len(devices) != 1:
        observed = [(r.get("version"), r.get("buildversion"), r.get("identifier")) for r in available]
        raise RuntimeError(f"Need one installed iOS {OS_VERSION} ({OS_BUILD}) runtime and one {DEVICE} type. "
                           f"Confirmed runtimes: {len(matching)}, device types: {len(devices)}, available iOS: {observed}")
    runtime, evidence = matching[0]
    return runtime, devices[0], evidence


def collect(argv, path, timeout=60):
    """Best-effort evidence has its own status and cannot replace the test result."""
    with path.open("w") as file:
        try:
            return sp.run(argv, stdout=file, stderr=sp.STDOUT, timeout=timeout).returncode
        except (OSError, sp.TimeoutExpired) as error:
            file.write(f"Evidence command failed: {error}\n")
            return None


def services(udid, path):
    try:
        result = output([*SIM, "spawn", udid, "launchctl", "list"], timeout=15)
        allowed = re.compile(r"Tingye|wereader|WebKit|AppSSO|^\S+\s+\S+\s+\S*\bakd\b|testmanagerd", re.I)
        path.write_text("\n".join(line for line in result.splitlines() if allowed.search(line)) + "\n")
        return 0
    except (OSError, sp.SubprocessError) as error:
        path.write_text(f"Simulator service state unavailable: {error}\n")
        return None


def stop_stream(stream):
    if stream is not None and stream.poll() is None:
        stream.terminate()
        try:
            stream.wait(timeout=5)
        except sp.TimeoutExpired:
            stream.kill()
            stream.wait()


def main(source, out):
    config = Path(__file__).resolve().parents[2]
    if out.is_relative_to(source) or out.is_relative_to(config):
        raise RuntimeError("Evidence directory must be outside both source trees.")
    out.mkdir(parents=True, exist_ok=False)
    os.environ.setdefault("DEVELOPER_DIR", XCODE_DIR)
    os.environ["TZ"] = "UTC"
    config_sha = git(config, "rev-parse", "HEAD")
    actual_sha = git(source, "rev-parse", "HEAD")
    print(f"Diagnostic only. Workflow configuration SHA: {config_sha}. "
          f"Checked-out app/test SHA: {actual_sha}. Expected app/test SHA: {EXPECTED_SHA}.", flush=True)
    write_json(out / "provenance.json", {
        "workflow_config_sha": config_sha,
        "github_sha": os.environ.get("GITHUB_SHA"),
        "github_workflow_sha": os.environ.get("GITHUB_WORKFLOW_SHA"),
        "github_ref": os.environ.get("GITHUB_REF"),
        "github_run_id": os.environ.get("GITHUB_RUN_ID"),
        "github_run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
        "expected_sha": EXPECTED_SHA,
        "actual_source_sha": actual_sha,
        "sha_matches": actual_sha == EXPECTED_SHA,
        "application_tree": git(source, "rev-parse", "HEAD^{tree}"),
        "diagnostic_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "test": TEST,
    })
    if os.environ.get("GITHUB_SHA", config_sha) != config_sha:
        raise RuntimeError("Diagnostic configuration checkout is not the dispatch SHA.")
    if os.environ.get("GITHUB_RUN_ATTEMPT", "1") != "1":
        raise RuntimeError("This experiment accepts run attempt 1 only.")
    if actual_sha != EXPECTED_SHA or git(source, "status", "--porcelain", "--untracked-files=all"):
        raise RuntimeError("Expected the exact source SHA with a clean application checkout.")
    if git(config, "status", "--porcelain", "--", str(Path(__file__).relative_to(config))):
        raise RuntimeError("Use the committed diagnostic script so its config SHA is attributable.")
    paths = (
        "TingyeUITests/DesignFlowTests.swift", "Tingye/TingyeApp.swift", "Tingye/ReaderView.swift",
        "Tingye/Readium/ReaderRouter.swift", "Tingye/Readium/ReadiumReaderView.swift",
        "Tingye/Readium/EPUBNavigatorHost.swift", "Tingye/Readium/PublicationStore.swift",
        "Tingye.xcodeproj/project.pbxproj",
        "Tingye.xcodeproj/xcshareddata/xcschemes/Tingye.xcscheme",
        "Tingye.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
    )
    write_json(out / "source-sha256.json", {name: hashlib.sha256((source / name).read_bytes()).hexdigest()
                                          for name in paths})

    metadata = {key: os.environ.get(key) for key in ("ImageOS", "ImageVersion", "RUNNER_OS", "RUNNER_ARCH")}
    metadata.update({"machine": platform.machine(), "macOS": platform.mac_ver()[0],
                     "developer_dir": os.environ["DEVELOPER_DIR"]})
    write_json(out / "runner.json", metadata)
    xcode = output(["xcodebuild", "-version"])
    (out / "xcode-version.txt").write_text(xcode + "\n")
    if platform.machine() != "arm64" or xcode != XCODE:
        raise RuntimeError(f"Need arm64 and {XCODE!r}. Found {platform.machine()} and {xcode!r}.")
    for name in ("runtimes", "devicetypes"):
        (out / f"simctl-{name}.json").write_text(output([*SIM, "list", name, "-j"]) + "\n")
    runtime, device_type, version_evidence = choose_runtime(
        json.loads((out / "simctl-runtimes.json").read_text())["runtimes"],
        json.loads((out / "simctl-devicetypes.json").read_text())["devicetypes"],
    )
    udid = output([*SIM, "create", "Tingye EPUB diagnostic", device_type["identifier"], runtime["identifier"]])
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", udid):
        raise RuntimeError(f"simctl create did not return a simulator UDID: {udid!r}")

    stream = None
    try:
        write_json(out / "selected-simulator.json", {
            "device_type": device_type, "runtime": runtime, "udid": udid,
            "confirmed_os_version": OS_VERSION, "confirmed_os_build": OS_BUILD,
            "version_evidence": version_evidence,
        })
        if collect([*SIM, "boot", udid], out / "simulator-boot.log") != 0 or collect(
            [*SIM, "bootstatus", udid, "-b"], out / "simulator-bootstatus.log", timeout=120
        ) != 0:
            raise RuntimeError("The fresh simulator failed to boot. See the boot logs.")
        evidence = {"services_before": services(udid, out / "services-before.txt")}
        bundle = out / "TingyeUITests.xcresult"
        command = [
            "xcodebuild", "test", "-project", "Tingye.xcodeproj", "-scheme", "Tingye",
            "-destination", f"platform=iOS Simulator,id={udid}",
            "-parallel-testing-enabled", "NO", "-test-iterations", "1",
            f"-only-testing:{TEST}", "-derivedDataPath", str(out.parent / f"tingye-derived-{udid}"),
            "-resultBundlePath", str(bundle),
        ]
        write_json(out / "test-command.json", command)
        (out / "log-predicate.txt").write_text(PREDICATE + "\n")
        started = utc_now()
        with (out / "simulator-log-stream.ndjson").open("w") as live, \
             (out / "simulator-log-stream.stderr").open("w") as stream_error, \
             (out / "xcodebuild.log").open("w") as build_log:
            stream = sp.Popen([*SIM, "spawn", udid, "log", "stream", "--style", "ndjson",
                               "--level", "debug", "--predicate", PREDICATE],
                              stdout=live, stderr=stream_error)
            print(f"{started.isoformat()} running {' '.join(command)}", flush=True)
            try:
                exit_code = sp.run(command, cwd=source, stdout=build_log, stderr=sp.STDOUT,
                                   timeout=30 * 60).returncode
                timed_out = False
            except sp.TimeoutExpired:
                exit_code, timed_out = None, True
            finished = utc_now()
        write_json(out / "test-exit.json", {"xcodebuild_exit_code": exit_code, "xcodebuild_timed_out": timed_out,
                                          "started_utc": started.isoformat(), "finished_utc": finished.isoformat()})
        print(f"Test ended at {finished.isoformat()} with xcodebuild exit {exit_code}", flush=True)
        evidence["screenshot"] = collect([*SIM, "io", udid, "screenshot", str(out / "after-test.png")],
                                         out / "screenshot.log", timeout=15)
        evidence["services_after"] = services(udid, out / "services-after.txt")
        evidence["booted_device"] = collect([*SIM, "list", "devices", runtime["identifier"], "-j"],
                                           out / "simctl-devices-after.json", timeout=15)
        evidence["unified_log_show"] = collect([
            *SIM, "spawn", udid, "log", "show", "--style", "ndjson", "--info", "--debug",
            "--start", started.strftime("%Y-%m-%d %H:%M:%S%z"),
            "--end", finished.strftime("%Y-%m-%d %H:%M:%S%z"), "--predicate", PREDICATE,
        ], out / "simulator-log-show.ndjson")
        evidence["unified_log_stream_exit_before_cleanup"] = stream.poll()
        stop_stream(stream)
        if bundle.is_dir():
            evidence["test_summary"] = collect(["xcrun", "xcresulttool", "get", "test-results", "summary",
                                                "--path", str(bundle)], out / "xcresult-summary.json")
            evidence["attachments"] = collect(["xcrun", "xcresulttool", "export", "attachments",
                                               "--path", str(bundle), "--output-path", str(out / "attachments")],
                                              out / "xcresult-attachments.log")
        write_json(out / "evidence-status.json", evidence)
        test_starts = 0
        start_marker = "testEPUBDerivedFixtureSmokeAndSearch]' started."
        with (out / "milestones.txt").open("w") as milestones:
            for name in ("xcodebuild.log", "simulator-log-stream.ndjson", "simulator-log-show.ndjson"):
                with (out / name).open(errors="replace") as log:
                    for line in log:
                        if name == "xcodebuild.log" and start_marker in line:
                            test_starts += 1
                        if MILESTONE.search(line):
                            milestones.write(f"{name}: {line}")
        write_json(out / "observed-test-starts.json", {"test": TEST, "starts_in_xcodebuild_log": test_starts})
        if exit_code == 0 and test_starts != 1:
            raise RuntimeError(f"xcodebuild returned 0 but the original test started {test_starts} times.")
        if timed_out:
            return 124
        return exit_code if exit_code >= 0 else 128 - exit_code
    finally:
        stop_stream(stream)
        # Only the simulator created above is owned by the diagnostic.
        collect([*SIM, "shutdown", udid], out / "simulator-shutdown.log", timeout=20)
        collect([*SIM, "delete", udid], out / "simulator-delete.log", timeout=20)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: diagnose-epub-smoke.py CLEAN_SOURCE_CHECKOUT NEW_EVIDENCE_DIRECTORY")
    try:
        sys.exit(main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()))
    except (RuntimeError, OSError, sp.SubprocessError) as error:
        sys.exit(str(error))
