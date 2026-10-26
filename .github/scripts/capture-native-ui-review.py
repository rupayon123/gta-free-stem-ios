"""Bounded simulator layout evidence; no persistent artifact storage or external services."""
from pathlib import Path
import base64
import hashlib
import json
import os
import re
import subprocess
import time
import uuid

prefix = "platform=iOS Simulator,id="
destination = os.environ["TEST_DESTINATION"]
if not destination.startswith(prefix):
    raise SystemExit("Expected the reviewed iPhone simulator destination")
device = destination[len(prefix):]
if not re.fullmatch(r"[A-Fa-f0-9-]{36}", device):
    raise SystemExit("Invalid simulator UUID")
root = Path(os.environ["RUNNER_TEMP"])
app = root / "GTAFreeSTEM-derived-data/Build/Products/Debug-iphonesimulator/GTAFreeSTEM.app"
if not app.is_dir():
    raise SystemExit("No compiled current-candidate app is available for UI review")
output = root / "GTAFreeSTEM-ui-review"
output.mkdir(exist_ok=True)
bundle = "com.rupayonhaldar.gtafreestem"
frameVerifier = root / "verify-native-frame"
activePid = None

def run(*args, timeout=30, check=True):
    try:
        return subprocess.run(args, check=check, timeout=timeout, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.strip()
    except subprocess.TimeoutExpired as error:
        raise SystemExit("Native capture command timed out after " + str(timeout) + "s: " + repr(args)) from error
    except subprocess.CalledProcessError as error:
        raise SystemExit("Native capture command failed: " + repr(args) + "\n" + (error.stdout or "")[-4000:]) from error

def require_alive():
    if activePid is not None:
        try:
            os.kill(activePid, 0)
        except ProcessLookupError as error:
            raise SystemExit("The app exited before native screen capture; PID " + str(activePid)) from error

def export(name, mode, **details):
    png = output / (name + ".png")
    jpg = output / (name + ".jpg")
    require_alive()
    # Retry a transient blank framebuffer only while the actual app process survives.
    for attempt in range(3):
        run("xcrun", "simctl", "io", device, "screenshot", "--type=png", str(png), timeout=90)
        result = subprocess.run([str(frameVerifier), str(png)], text=True, capture_output=True, timeout=10)
        require_alive()
        if result.returncode == 0:
            break
        if attempt == 2:
            raise SystemExit(result.stderr)
        time.sleep(1)
    # A bounded downsample of the native screenshot for log transport, never a re-created image.
    run("/usr/bin/sips", "-s", "format", "jpeg", "-s", "formatOptions", "76", "-Z", "1100", str(png), "--out", str(jpg))
    data = jpg.read_bytes()
    if len(data) > 180_000:
        raise SystemExit("Native frame exceeds the bounded log export size")
    metadata = dict(name=name, mode=mode, commit=os.environ["CANDIDATE_SOURCE_SHA"],
                    exportMaximumDimension=1100, format="jpeg", quality=76,
                    bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                    nativePngSha256=hashlib.sha256(png.read_bytes()).hexdigest(), **details)
    print("NATIVE_UI_CAPTURE_META " + json.dumps(metadata, sort_keys=True), flush=True)
    print("NATIVE_UI_CAPTURE_BEGIN " + name, flush=True)
    encoded = base64.b64encode(data).decode("ascii")
    for start in range(0, len(encoded), 100):
        print("NATIVE_UI_CAPTURE_DATA " + encoded[start:start + 100])
    print("NATIVE_UI_CAPTURE_END " + name, flush=True)

run("xcrun", "swiftc", ".github/scripts/verify-native-frame.swift", "-o", str(frameVerifier), timeout=60)

# xcodebuild may run tests on its own clone, leaving the reviewed destination shut down.
# Boot this exact preflight-selected device instead of selecting an unrelated booted simulator.
inventory = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
matched = [entry for entries in inventory.values() for entry in entries if entry.get("udid") == device]
if len(matched) != 1 or matched[0].get("state") not in ("Booted", "Shutdown"):
    raise SystemExit("Reviewed simulator missing or in an unsupported transition state")
if matched[0]["state"] == "Shutdown":
    run("xcrun", "simctl", "boot", device, timeout=30)
run("xcrun", "simctl", "bootstatus", device, "-b", timeout=120)
simulatorApp = Path(os.environ["DEVELOPER_DIR"]) / "Applications/Simulator.app"
if not simulatorApp.is_dir():
    raise SystemExit("The reviewed Xcode Simulator app is unavailable")
run("open", "-a", str(simulatorApp), "--args", "-CurrentDeviceUDID", device, timeout=30)
time.sleep(2)
run("xcrun", "simctl", "install", device, str(app), timeout=60)
# Each fixture sets its own native preferredColorScheme. A redundant simulator
# appearance RPC can hang after xcodebuild finishes; normal mode retains real defaults.
cases = [(screen, False, False, "en") for screen in ("home", "browse", "saved", "settings")]
cases += [(screen, True, False, "en") for screen in ("home", "browse")]
cases += [(screen, False, True, "en") for screen in ("home", "browse", "saved", "settings")]
cases += [("browse", False, False, "ar")]
cases += [("calendar", False, False, "en")]
for screen, dark, large, language in cases:
    nonce = uuid.uuid4().hex
    args = ["-frontend-layout-review", "-screenshot-mode", "-review-screen", screen,
            "-review-language", language, "-screenshot-ready-nonce", nonce]
    if screen == "browse":
        args += ["-start-opportunities"]
    elif screen in ("saved", "settings"):
        args += ["-start-account"]
    if screen == "calendar":
        args += ["-review-present-calendar"]
    if dark:
        args += ["-review-dark"]
    if large:
        args += ["-review-large-text"]
    stdoutLog = output / (nonce + ".stdout")
    stderrLog = output / (nonce + ".stderr")
    redirects = ["--stdout=" + str(stdoutLog), "--stderr=" + str(stderrLog)]
    if screen == "home" and not dark and not large and language == "en":
        launched = run("xcrun", "simctl", "launch", *redirects, device, bundle, *args, timeout=90)
    else:
        launched = run("xcrun", "simctl", "launch", "--terminate-running-process", *redirects, device, bundle, *args, timeout=45)
    match = re.search(r": (\d+)$", launched)
    if not match:
        raise SystemExit("Launch did not return an app PID: " + launched)
    activePid = int(match.group(1))
    readyTag = "GTA_CALENDAR_REVIEW_READY" if screen == "calendar" else "GTA_SAVED_REVIEW_READY" if screen == "saved" else "GTA_LAYOUT_REVIEW_READY"
    deadline = time.monotonic() + (30 if screen == "calendar" else 15)
    while time.monotonic() < deadline:
        if stdoutLog.is_file() and readyTag + " " + nonce in stdoutLog.read_text(errors="replace").splitlines():
            break
        time.sleep(0.25)
    else:
        diagnostics = stderrLog.read_text(errors="replace")[-4000:] if stderrLog.is_file() else "No app stderr output"
        print("NATIVE_UI_LAUNCH_DIAGNOSTICS " + screen + "\n" + diagnostics, flush=True)
        crashes = sorted((Path.home() / "Library/Logs/DiagnosticReports").glob("GTAFreeSTEM*.ips"), key=lambda p: p.stat().st_mtime, reverse=True)
        for crash in crashes[:1]:
            print("NATIVE_UI_CRASH_DIAGNOSTICS " + crash.name + "\n" + crash.read_text(errors="replace")[:20000], flush=True)
        raise SystemExit("Layout fixture did not signal readiness: " + screen)
    time.sleep(2 if screen == "calendar" else 0.75)
    name = "fixture-" + screen + ("-dark" if dark else "-light") + ("-large" if large else "") + ("-" + language if language != "en" else "")
    export(name, "app-owned-layout-fixture", screen=screen, language=language,
           dark=dark, dynamicType="accessibility3" if large else "large",
           productionData=False, isolatedMemoryStore=True, visibleFixtureBanner=screen != "calendar",
           systemCalendarPresentationOnly=screen == "calendar", calendarSaved=False,
           sampleTitleVisible=screen == "calendar")
# Normal runtime after simulator/framework warmup: actual source/rights/error state.
# This is a new process, but is not a first-install cold-start performance claim.
launched = run("xcrun", "simctl", "launch", "--terminate-running-process", device, bundle, timeout=90)
activePid = int(launched.rsplit(": ", 1)[1])
time.sleep(20)
export("normal-home", "normal-runtime", waitSeconds=20, dataAcceptance=False)
launched = run("xcrun", "simctl", "launch", "--terminate-running-process", device, bundle, "-start-opportunities")
activePid = int(launched.rsplit(": ", 1)[1])
time.sleep(8)
export("normal-browse", "normal-runtime", waitSeconds=8, dataAcceptance=False)


run("xcrun", "simctl", "terminate", device, bundle, check=False)
print("NATIVE_UI_CAPTURE_COMPLETE " + json.dumps(dict(normalFrames=2, fixtureFrames=len(cases),
      releaseAcceptance=False, physicalDeviceAcceptance=False)), flush=True)
