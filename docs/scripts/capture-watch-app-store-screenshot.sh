#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

WATCH_BUNDLE_ID="com.rupayonhaldar.gtafreestem.watchkitapp"
SCHEME="GTAFreeSTEM Watch"
PROJECT="GTAFreeSTEM.xcodeproj"
CONFIGURATION="Release"
WATCH_DEVICE="${WATCH_DEVICE:-Apple Watch Series 11 (46mm)}"
SCREENSHOT_ROOT="${SCREENSHOT_ROOT:-build/app-store-screenshots}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCREENSHOT_ROOT/final}"
RAW_OUTPUT_DIR="${RAW_OUTPUT_DIR:-$SCREENSHOT_ROOT/raw}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData-app-store-watch-screenshot}"
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-12}"
SIMCTL_TIMEOUT="${SIMCTL_TIMEOUT:-45}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-120}"
USE_DEDICATED_SIMULATOR="${USE_DEDICATED_SIMULATOR:-1}"
VISUAL_QA_MARKER="$OUTPUT_DIR/FINAL_VISUAL_QA.md"
CAPTURE_RECEIPT="$OUTPUT_DIR/CAPTURE_RECEIPT.json"
MAC_CAPTURE_SESSION="$OUTPUT_DIR/MAC_CAPTURE_SESSION.json"
CONTACT_SHEET="$OUTPUT_DIR/contact-sheet.jpg"
SOURCE_PATHS=(GTAFreeSTEM GTAFreeSTEMWatch GTAFreeSTEM.xcodeproj project.yml)

WATCH_ID=""
CREATED_WATCH_ID=""

invalidate_visual_qa() {
  rm -f -- "$VISUAL_QA_MARKER" "$CAPTURE_RECEIPT" "$MAC_CAPTURE_SESSION" "$CONTACT_SHEET"
}

mkdir -p "$OUTPUT_DIR/watch-series-11" "$RAW_OUTPUT_DIR/watch-series-11"
invalidate_visual_qa

screenshot_source_commit() {
  git rev-parse --verify "${SCREENSHOT_SOURCE_COMMIT:-HEAD}^{commit}"
}

screenshot_source_tree_sha256() {
  local commit="$1"
  git ls-tree -r -z --full-tree "$commit" -- "${SOURCE_PATHS[@]}" \
    | shasum -a 256 \
    | awk '{print $1}'
}

require_clean_screenshot_source() {
  local expected_commit="$1"
  local expected_tree="$2"
  local current_head
  local current_tree
  local status

  if ! [[ "$expected_commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Screenshot source must resolve to a full lowercase 40-character commit." >&2
    exit 1
  fi
  status="$(git status --porcelain=v1 --untracked-files=all -- "${SOURCE_PATHS[@]}")"
  if [ -n "$status" ]; then
    echo "Source tree is not clean for the screenshot build inputs:" >&2
    printf '%s\n' "$status" >&2
    exit 1
  fi
  current_head="$(git rev-parse --verify HEAD)"
  current_tree="$(screenshot_source_tree_sha256 "$current_head")"
  if [ "$current_tree" != "$expected_tree" ] \
    || ! git diff --quiet "$expected_commit" -- "${SOURCE_PATHS[@]}"; then
    echo "Current screenshot source inputs do not match $expected_commit." >&2
    exit 1
  fi
  if [ "$(screenshot_source_tree_sha256 "$expected_commit")" != "$expected_tree" ]; then
    echo "Could not reproduce the screenshot source tree hash." >&2
    exit 1
  fi
}

require_unchanged_screenshot_source() {
  local expected_commit="$1"
  local expected_tree="$2"
  local status

  status="$(git status --porcelain=v1 --untracked-files=all -- "${SOURCE_PATHS[@]}")"
  if [ "$(git rev-parse --verify HEAD)" != "$CAPTURE_HEAD_COMMIT" ] \
    || [ -n "$status" ] \
    || [ "$(screenshot_source_tree_sha256 HEAD)" != "$expected_tree" ] \
    || ! git diff --quiet "$expected_commit" -- "${SOURCE_PATHS[@]}"; then
    echo "Source tree changed while the Watch screenshot was being captured." >&2
    exit 1
  fi
}

verify_built_source_commit() {
  local info_plist="$1"
  local expected_commit="$2"
  local observed_commit

  if [ ! -f "$info_plist" ]; then
    echo "Missing built Watch app metadata at $info_plist" >&2
    exit 1
  fi
  observed_commit="$(plutil -extract GTAReleaseSourceCommit raw -o - "$info_plist" 2>/dev/null || true)"
  if [ "$observed_commit" != "$expected_commit" ]; then
    echo "Built Watch screenshot app embeds ${observed_commit:-no source commit}; expected $expected_commit." >&2
    exit 1
  fi
}

CAPTURE_HEAD_COMMIT="$(git rev-parse --verify HEAD)"
SOURCE_COMMIT="$(screenshot_source_commit)"
SOURCE_TREE_SHA256="$(screenshot_source_tree_sha256 "$SOURCE_COMMIT")"
require_clean_screenshot_source "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"

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

wait_for_device_state() {
  local device="$1"
  local expected_state="$2"
  local timeout_seconds="$3"
  local deadline=$((SECONDS + timeout_seconds))
  local state=""

  while [ "$SECONDS" -lt "$deadline" ]; do
    state="$(device_state "$device" 2>/dev/null || true)"
    if [ "$state" = "$expected_state" ]; then
      return 0
    fi
    sleep 0.25
  done

  echo "Watch simulator $device did not reach $expected_state within ${timeout_seconds}s (last state: ${state:-unknown})." >&2
  return 1
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
    wait_for_device_state "$source_id" "Shutdown" "$BOOT_TIMEOUT"
  fi

  if ! identifier="$(xcrun simctl clone "$source_id" "GTA STEM Watch Screenshot $$")"; then
    if [ "$restore_source_boot" = "1" ]; then
      run_simctl boot "$source_id" >/dev/null 2>&1 || true
    fi
    return 1
  fi

  if ! wait_for_device_state "$identifier" "Shutdown" "$BOOT_TIMEOUT"; then
    xcrun simctl delete "$identifier" >/dev/null 2>&1 || true
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
GTA_RELEASE_SOURCE_COMMIT="$SOURCE_COMMIT"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=watchOS Simulator,id=$WATCH_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "GTA_RELEASE_SOURCE_COMMIT=$GTA_RELEASE_SOURCE_COMMIT" \
  build >/dev/null

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release-watchsimulator/GTAFreeSTEMWatch.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Could not find built Watch app at $APP_PATH"
  exit 1
fi
verify_built_source_commit "$APP_PATH/Info.plist" "$SOURCE_COMMIT"

run_simctl shutdown "$WATCH_ID" >/dev/null 2>&1 || true
wait_for_device_state "$WATCH_ID" "Shutdown" "$BOOT_TIMEOUT"
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

RAW_OUTPUT="$RAW_OUTPUT_DIR/watch-series-11/01-home.png"
OUTPUT="$OUTPUT_DIR/watch-series-11/01-home.jpg"
run_simctl io "$WATCH_ID" screenshot "$RAW_OUTPUT" >/dev/null
sips -s format jpeg -s formatOptions 90 "$RAW_OUTPUT" --out "$OUTPUT" >/dev/null
verify_jpeg "$OUTPUT"
run_simctl terminate "$WATCH_ID" "$WATCH_BUNDLE_ID" >/dev/null 2>&1 || true

require_unchanged_screenshot_source "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"

echo "Watch screenshot capture complete: $OUTPUT"
