#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

WATCH_BUNDLE_ID="com.rupayonhaldar.gtafreestem.watchkitapp"
SCHEME="GTAFreeSTEM Watch"
PROJECT="GTAFreeSTEM.xcodeproj"
CONFIGURATION="Release"
WATCH_DEVICE="${WATCH_DEVICE:-Apple Watch Series 11 (46mm)}"
OUTPUT_DIR="${OUTPUT_DIR:-build/app-store-screenshots}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData-app-store-watch-screenshot}"
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-12}"
SIMCTL_TIMEOUT="${SIMCTL_TIMEOUT:-45}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-120}"
USE_DEDICATED_SIMULATOR="${USE_DEDICATED_SIMULATOR:-1}"

WATCH_ID=""
CREATED_WATCH_ID=""

mkdir -p "$OUTPUT_DIR/watch-series-11" "$OUTPUT_DIR/raw/watch-series-11"

existing_device_id() {
  /usr/bin/python3 - "$1" <<'PY'
import json
import subprocess
import sys

target = sys.argv[1]
payload = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
for devices in payload.get("devices", {}).values():
    for device in devices:
        if device.get("name") == target and device.get("udid"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit(f"Watch simulator not found: {target}")
PY
}

device_state() {
  /usr/bin/python3 - "$1" <<'PY'
import json
import subprocess
import sys

target = sys.argv[1]
payload = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
for devices in payload.get("devices", {}).values():
    for device in devices:
        if device.get("udid") == target:
            print(device.get("state", ""))
            raise SystemExit(0)
raise SystemExit(f"Watch simulator not found: {target}")
PY
}

cleanup() {
  if [ -n "$CREATED_WATCH_ID" ]; then
    xcrun simctl shutdown "$CREATED_WATCH_ID" >/dev/null 2>&1 || true
    xcrun simctl delete "$CREATED_WATCH_ID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_simctl() {
  local command_timeout="${SIMCTL_COMMAND_TIMEOUT:-$SIMCTL_TIMEOUT}"
  /usr/bin/python3 - "$command_timeout" "$@" <<'PY'
import subprocess
import sys

timeout = float(sys.argv[1])
command = ["xcrun", "simctl", *sys.argv[2:]]
try:
    result = subprocess.run(command, timeout=timeout)
except subprocess.TimeoutExpired:
    print(
        f"{' '.join(command[1:])} exceeded {timeout:g}s; stopping the stalled command.",
        file=sys.stderr,
    )
    raise SystemExit(124)
raise SystemExit(result.returncode)
PY
}

clone_dedicated_watch() {
  local source_id
  local source_state
  local restore_source_boot=0
  local identifier

  source_id="$(existing_device_id "$WATCH_DEVICE")"
  source_state="$(device_state "$source_id")"
  if [ "$source_state" = "Booted" ] || [ "$source_state" = "Booting" ]; then
    echo "Temporarily shutting down $WATCH_DEVICE so its isolated clone can be created." >&2
    restore_source_boot=1
    SIMCTL_COMMAND_TIMEOUT="$BOOT_TIMEOUT" run_simctl shutdown "$source_id" >/dev/null
  fi

  if ! identifier="$(xcrun simctl clone "$source_id" "GTA STEM Watch Screenshot $$")"; then
    if [ "$restore_source_boot" = "1" ]; then
      run_simctl boot "$source_id" >/dev/null 2>&1 || true
    fi
    return 1
  fi

  if [ "$restore_source_boot" = "1" ]; then
    if ! run_simctl boot "$source_id" >/dev/null; then
      xcrun simctl delete "$identifier" >/dev/null 2>&1 || true
      echo "Could not restore the source Watch simulator after cloning." >&2
      return 1
    fi
  fi

  echo "$identifier"
}

verify_jpeg() {
  local file="$1"
  local width
  local height
  local format
  local alpha

  width="$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "$file" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
  format="$(sips -g format "$file" 2>/dev/null | awk '/format/ {print $2}')"
  alpha="$(sips -g hasAlpha "$file" 2>/dev/null | awk '/hasAlpha/ {print $2}')"

  if [ "$width" != "416" ] || [ "$height" != "496" ]; then
    echo "$file is $width x $height; expected 416 x 496 for Apple Watch Series 11."
    exit 1
  fi
  if [ "$format" != "jpeg" ] || [ "$alpha" != "no" ]; then
    echo "$file must be an opaque JPEG; got format=$format hasAlpha=$alpha"
    exit 1
  fi
  echo "Verified $file: 416 x 496, opaque JPEG"
}

seed_watch_screenshot_data() {
  local device="$1"
  local payload_hex

  payload_hex="$(/usr/bin/python3 - <<'PY'
import json
from datetime import datetime, timedelta, timezone

reference = datetime(2001, 1, 1, tzinfo=timezone.utc)
now = datetime.now(timezone.utc)

def apple_seconds(value):
    return (value - reference).total_seconds()

def event(identifier, title, organization, city, category, days_from_now):
    start = (now + timedelta(days=days_from_now)).replace(hour=14, minute=0, second=0, microsecond=0)
    end = start + timedelta(hours=2)
    return {
        "id": identifier,
        "title": title,
        "organization": organization,
        "details": "Free hands-on STEM learning saved from the iPhone app.",
        "category": category,
        "city": city,
        "region": "Toronto",
        "address": f"{city}, ON",
        "latitude": None,
        "longitude": None,
        "startDate": start.isoformat().replace("+00:00", "Z"),
        "endDate": end.isoformat().replace("+00:00", "Z"),
        "deadline": None,
        "archiveBoundary": apple_seconds(end),
        "archived": False,
        "sourceURL": "https://gta-free-stem.vercel.app",
        "registrationURL": "https://gta-free-stem.vercel.app",
        "savedAt": apple_seconds(now),
    }

payload = {
    "schemaVersion": 1,
    "syncedAt": apple_seconds(now),
    "totalSavedCount": 2,
    "events": [
        event("screenshot-robotics", "Build a Robot Lab", "Toronto Public Library", "Toronto", "Coding & Robotics", 3),
        event("screenshot-space", "Family Space Science Night", "Community Science Centre", "Scarborough", "Science & Engineering", 7),
    ],
}
print(json.dumps(payload, separators=(",", ":")).encode("utf-8").hex())
PY
)"

  run_simctl spawn "$device" defaults write "$WATCH_BUNDLE_ID" watch-saved-events-v1 -data "$payload_hex" >/dev/null
}

if [ "$USE_DEDICATED_SIMULATOR" = "1" ]; then
  echo "Cloning an isolated Watch simulator for deterministic capture..."
  if ! CREATED_WATCH_ID="$(clone_dedicated_watch)" || [ -z "$CREATED_WATCH_ID" ]; then
    echo "Could not create an isolated clone of $WATCH_DEVICE." >&2
    exit 1
  fi
  WATCH_ID="$CREATED_WATCH_ID"
else
  WATCH_ID="$(existing_device_id "$WATCH_DEVICE")"
fi

echo "Building $SCHEME for $WATCH_DEVICE in isolated release DerivedData..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=watchOS Simulator,id=$WATCH_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build >/dev/null

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release-watchsimulator/GTAFreeSTEMWatch.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Could not find built Watch app at $APP_PATH"
  exit 1
fi

run_simctl shutdown "$WATCH_ID" >/dev/null 2>&1 || true
run_simctl boot "$WATCH_ID" >/dev/null
SIMCTL_COMMAND_TIMEOUT="$BOOT_TIMEOUT" run_simctl bootstatus "$WATCH_ID" -b >/dev/null
if run_simctl get_app_container "$WATCH_ID" "$WATCH_BUNDLE_ID" app >/dev/null 2>&1; then
  run_simctl uninstall "$WATCH_ID" "$WATCH_BUNDLE_ID" >/dev/null
fi
run_simctl install "$WATCH_ID" "$APP_PATH" >/dev/null
seed_watch_screenshot_data "$WATCH_ID"
run_simctl status_bar "$WATCH_ID" override --time "10:09" --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true
run_simctl launch "$WATCH_ID" "$WATCH_BUNDLE_ID" >/dev/null
sleep "$SCREENSHOT_DELAY"

RAW_OUTPUT="$OUTPUT_DIR/raw/watch-series-11/01-home.png"
OUTPUT="$OUTPUT_DIR/watch-series-11/01-home.jpg"
run_simctl io "$WATCH_ID" screenshot "$RAW_OUTPUT" >/dev/null
sips -s format jpeg -s formatOptions 90 "$RAW_OUTPUT" --out "$OUTPUT" >/dev/null
verify_jpeg "$OUTPUT"
run_simctl terminate "$WATCH_ID" "$WATCH_BUNDLE_ID" >/dev/null 2>&1 || true

echo "Watch screenshot capture complete: $OUTPUT"
