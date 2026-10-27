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
run("open", "-a", str(simulatorApp), "--args", "-CurrentDeviceUDID", device, timeout=90)
time.sleep(2)
run("xcrun", "simctl", "install", device, str(app), timeout=60)
# Each fixture sets its own native preferredColorScheme. A redundant simulator
# appearance RPC can hang after xcodebuild finishes; normal mode retains real defaults.
# Actual normal launch: no screenshot/fixture flags, no seeded records.
launch = run("xcrun", "simctl", "launch", "--terminate-running-process", device, bundle,
             "-start-opportunities", timeout=90)
match = re.search(r":\s*(\d+)\s*$", launch)
if not match:
    raise SystemExit("Could not establish actual app process identity: " + launch)
activePid = int(match.group(1))
started = time.monotonic()
for minimumWait in (20, 40, 60):
    time.sleep(max(0, minimumWait - (time.monotonic() - started)))
    require_alive()
    export("normal-browse-" + str(minimumWait), "normal-runtime",
           minimumWaitSeconds=minimumWait, observedElapsedBeforeCapture=round(time.monotonic() - started, 2),
           actualNormalLaunch=True, fixtureFlags=False, dataAcceptance=False,
           qaCommit=os.environ["QA_COMMIT"])
print("NATIVE_UI_CAPTURE_COMPLETE " + json.dumps(dict(normalFrames=3, fixtureFrames=0,
      appSource=os.environ["CANDIDATE_SOURCE_SHA"], releaseAcceptance=False,
      physicalDeviceAcceptance=False, visualInspection="required; captured frames are not automatic data acceptance")), flush=True)
