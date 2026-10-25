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

def run(*args, timeout=30, check=True):
    try:
        return subprocess.run(args, check=check, timeout=timeout, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.strip()
    except subprocess.CalledProcessError as error:
        raise SystemExit("Native capture command failed: " + repr(args) + "\n" + (error.stdout or "")[-4000:]) from error

def export(name, mode, **details):
    png = output / (name + ".png")
    jpg = output / (name + ".jpg")
    run("xcrun", "simctl", "io", device, "screenshot", "--type=png", str(png))
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

# xcodebuild may run tests on its own clone, leaving the reviewed destination shut down.
# Boot this exact preflight-selected device instead of selecting an unrelated booted simulator.
inventory = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
matched = [entry for entries in inventory.values() for entry in entries if entry.get("udid") == device]
if len(matched) != 1 or matched[0].get("state") not in ("Booted", "Shutdown"):
    raise SystemExit("Reviewed simulator missing or in an unsupported transition state")
if matched[0]["state"] == "Shutdown":
    run("xcrun", "simctl", "boot", device, timeout=30)
run("xcrun", "simctl", "bootstatus", device, "-b", timeout=120)
run("xcrun", "simctl", "install", device, str(app), timeout=60)
run("xcrun", "simctl", "ui", device, "appearance", "light")
# Normal app launch: actual source/rights/error state, not a fixture or data acceptance claim.
run("xcrun", "simctl", "launch", "--terminate-running-process", device, bundle)
time.sleep(20)
export("normal-home", "normal-runtime", waitSeconds=20, dataAcceptance=False)
run("xcrun", "simctl", "launch", "--terminate-running-process", device, bundle, "-start-opportunities")
time.sleep(8)
export("normal-browse", "normal-runtime", waitSeconds=8, dataAcceptance=False)

cases = [(screen, False, False, "en") for screen in ("home", "browse", "saved", "settings")]
cases += [(screen, True, False, "en") for screen in ("home", "browse")]
cases += [(screen, False, True, "en") for screen in ("home", "browse", "saved", "settings")]
cases += [("browse", False, False, "ar")]
for screen, dark, large, language in cases:
    nonce = uuid.uuid4().hex
    args = ["-frontend-layout-review", "-screenshot-mode", "-review-screen", screen,
            "-review-language", language, "-screenshot-ready-nonce", nonce]
    if screen == "browse":
        args += ["-start-opportunities"]
    elif screen in ("saved", "settings"):
        args += ["-start-account"]
    if dark:
        args += ["-review-dark"]
    if large:
        args += ["-review-large-text"]
    run("xcrun", "simctl", "launch", "--terminate-running-process", device, bundle, *args)
    container = Path(run("xcrun", "simctl", "get_app_container", device, bundle, "data"))
    marker = container / "Library/Caches/gta-free-stem-screenshot-ready"
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if marker.is_file() and marker.read_text() == nonce:
            break
        time.sleep(0.25)
    else:
        raise SystemExit("Layout fixture did not signal readiness: " + screen)
    time.sleep(0.75)
    name = "fixture-" + screen + ("-dark" if dark else "-light") + ("-large" if large else "") + ("-" + language if language != "en" else "")
    export(name, "app-owned-layout-fixture", screen=screen, language=language,
           dark=dark, dynamicType="accessibility3" if large else "large",
           productionData=False, isolatedMemoryStore=True, visibleFixtureBanner=True)
run("xcrun", "simctl", "terminate", device, bundle, check=False)
print("NATIVE_UI_CAPTURE_COMPLETE " + json.dumps(dict(normalFrames=2, fixtureFrames=len(cases),
      releaseAcceptance=False, physicalDeviceAcceptance=False)), flush=True)
