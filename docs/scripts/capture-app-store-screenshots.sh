#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

BUNDLE_ID="com.rupayonhaldar.gtafreestem"
SCHEME="GTAFreeSTEM"
PROJECT="GTAFreeSTEM.xcodeproj"
CONFIGURATION="Release"
IPHONE_DEVICE="${IPHONE_DEVICE:-iPhone 17 Pro Max}"
IPAD_DEVICE="${IPAD_DEVICE:-iPad Pro 13-inch (M5)}"
OUTPUT_DIR="${OUTPUT_DIR:-build/app-store-screenshots}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData-app-store-screenshots}"
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-2}"
SCREENSHOT_READY_TIMEOUT="${SCREENSHOT_READY_TIMEOUT:-45}"
SCREENSHOT_READY_MARKER="gta-free-stem-screenshot-ready"
SIMCTL_TIMEOUT="${SIMCTL_TIMEOUT:-90}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-120}"
USE_DEDICATED_SIMULATORS="${USE_DEDICATED_SIMULATORS:-1}"

IPHONE_ID=""
IPAD_ID=""
CREATED_IPHONE_ID=""
CREATED_IPAD_ID=""

mkdir -p "$OUTPUT_DIR/iphone-6.9" "$OUTPUT_DIR/ipad-13" "$OUTPUT_DIR/raw/iphone-6.9" "$OUTPUT_DIR/raw/ipad-13"

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
raise SystemExit(f"Simulator device not found: {target}")
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
raise SystemExit(f"Simulator device not found: {target}")
PY
}

clone_dedicated_device() {
  local display_name="$1"
  local source_id
  local source_state
  local restore_source_boot=0
  local identifier

  source_id="$(existing_device_id "$display_name")"
  source_state="$(device_state "$source_id")"
  if [ "$source_state" = "Booted" ] || [ "$source_state" = "Booting" ]; then
    echo "Temporarily shutting down $display_name so its isolated clone can be created." >&2
    restore_source_boot=1
    SIMCTL_COMMAND_TIMEOUT="$BOOT_TIMEOUT" run_simctl shutdown "$source_id" >/dev/null
  fi

  if ! identifier="$(xcrun simctl clone "$source_id" "GTA STEM Screenshots ${display_name} $$")"; then
    if [ "$restore_source_boot" = "1" ]; then
      run_simctl boot "$source_id" >/dev/null 2>&1 || true
    fi
    return 1
  fi

  if [ "$restore_source_boot" = "1" ]; then
    if ! run_simctl boot "$source_id" >/dev/null; then
      xcrun simctl delete "$identifier" >/dev/null 2>&1 || true
      echo "Could not restore the source simulator $display_name after cloning." >&2
      return 1
    fi
  fi
  echo "$identifier"
}

cleanup() {
  local identifier
  for identifier in "${CREATED_IPHONE_ID:-}" "${CREATED_IPAD_ID:-}"; do
    [ -n "$identifier" ] || continue
    xcrun simctl shutdown "$identifier" >/dev/null 2>&1 || true
    xcrun simctl delete "$identifier" >/dev/null 2>&1 || true
  done
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

verify_jpeg() {
  local file="$1"
  local expected_width="$2"
  local expected_height="$3"
  local width
  local height
  local format
  local alpha

  width="$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "$file" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
  format="$(sips -g format "$file" 2>/dev/null | awk '/format/ {print $2}')"
  alpha="$(sips -g hasAlpha "$file" 2>/dev/null | awk '/hasAlpha/ {print $2}')"

  if [ "$width" != "$expected_width" ] || [ "$height" != "$expected_height" ]; then
    echo "$file is $width x $height; expected $expected_width x $expected_height"
    exit 1
  fi
  if [ "$format" != "jpeg" ] || [ "$alpha" != "no" ]; then
    echo "$file must be an opaque JPEG; got format=$format hasAlpha=$alpha"
    exit 1
  fi
  if [ "$(stat -f '%z' "$file")" -lt 100000 ]; then
    echo "$file is unexpectedly small."
    exit 1
  fi
  echo "Verified $file: $width x $height, opaque JPEG"
}

read_ready_nonce() {
  local device="$1"
  local data_container

  if [ -n "${SCREENSHOT_READY_OVERRIDE+x}" ]; then
    echo "$SCREENSHOT_READY_OVERRIDE"
    return 0
  fi

  data_container="$(run_simctl get_app_container "$device" "$BUNDLE_ID" data 2>/dev/null || true)"
  [ -n "$data_container" ] || return 0
  /bin/cat "$data_container/Library/Caches/$SCREENSHOT_READY_MARKER" 2>/dev/null || true
}

wait_for_app_ready() {
  local device="$1"
  local expected_nonce="$2"
  local deadline=$((SECONDS + SCREENSHOT_READY_TIMEOUT))
  local ready=""

  while [ "$SECONDS" -lt "$deadline" ]; do
    ready="$(read_ready_nonce "$device")"
    if [ "$ready" = "$expected_nonce" ]; then
      return 0
    fi
    sleep 0.25
  done

  echo "GTAFreeSTEM did not expose its interactive screenshot state within ${SCREENSHOT_READY_TIMEOUT}s." >&2
  return 1
}

capture() {
  local device="$1"
  local raw_output="$2"
  local output="$3"
  local expected_width="$4"
  local expected_height="$5"
  shift 5
  local screenshot_query=""
  local ready_nonce

  if [ "${1:-}" = "--screenshot-query" ]; then
    screenshot_query="$2"
    shift 2
  fi

  run_simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
  ready_nonce="$(/usr/bin/uuidgen)"
  if [ -n "$screenshot_query" ]; then
    SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_MODE=1 \
      SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_QUERY="$screenshot_query" \
      SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_READY_NONCE="$ready_nonce" \
      run_simctl launch "$device" "$BUNDLE_ID" "$@" >/dev/null
  else
    SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_MODE=1 \
      SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_READY_NONCE="$ready_nonce" \
      run_simctl launch "$device" "$BUNDLE_ID" "$@" >/dev/null
  fi
  wait_for_app_ready "$device" "$ready_nonce"
  sleep "$SCREENSHOT_DELAY"
  run_simctl io "$device" screenshot "$raw_output" >/dev/null
  sips -s format jpeg -s formatOptions 90 "$raw_output" --out "$output" >/dev/null
  verify_jpeg "$output" "$expected_width" "$expected_height"
  run_simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

prepare_device() {
  local device="$1"
  local app_path="$2"

  run_simctl shutdown "$device" >/dev/null 2>&1 || true
  run_simctl boot "$device" >/dev/null
  SIMCTL_COMMAND_TIMEOUT="$BOOT_TIMEOUT" run_simctl bootstatus "$device" -b >/dev/null
  if run_simctl get_app_container "$device" "$BUNDLE_ID" app >/dev/null 2>&1; then
    run_simctl uninstall "$device" "$BUNDLE_ID" >/dev/null
  fi
  run_simctl install "$device" "$app_path" >/dev/null
  run_simctl ui "$device" appearance light >/dev/null 2>&1 || true
  run_simctl status_bar "$device" override \
    --time "9:41" \
    --dataNetwork wifi \
    --wifiBars 3 \
    --batteryState charged \
    --batteryLevel 100 >/dev/null 2>&1 || true
}

warm_up_device() {
  local device="$1"
  local ready_nonce
  ready_nonce="$(/usr/bin/uuidgen)"
  SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_MODE=1 \
    SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_READY_NONCE="$ready_nonce" \
    run_simctl launch "$device" "$BUNDLE_ID" >/dev/null
  wait_for_app_ready "$device" "$ready_nonce"
  sleep 5
  run_simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

if [ "$USE_DEDICATED_SIMULATORS" = "1" ]; then
  echo "Cloning isolated iPhone and iPad simulators for deterministic capture..."
  if ! IPHONE_ID="$(clone_dedicated_device "$IPHONE_DEVICE")" || [ -z "$IPHONE_ID" ]; then
    echo "Could not create an isolated clone of $IPHONE_DEVICE." >&2
    exit 1
  fi
  CREATED_IPHONE_ID="$IPHONE_ID"
  if ! IPAD_ID="$(clone_dedicated_device "$IPAD_DEVICE")" || [ -z "$IPAD_ID" ]; then
    echo "Could not create an isolated clone of $IPAD_DEVICE." >&2
    exit 1
  fi
  CREATED_IPAD_ID="$IPAD_ID"
else
  IPHONE_ID="$(existing_device_id "$IPHONE_DEVICE")"
  IPAD_ID="$(existing_device_id "$IPAD_DEVICE")"
fi

echo "Building $SCHEME for $IPHONE_DEVICE in isolated release DerivedData..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS Simulator,id=$IPHONE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build >/dev/null

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release-iphonesimulator/GTAFreeSTEM.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Could not find built GTAFreeSTEM.app at $APP_PATH"
  exit 1
fi

prepare_device "$IPHONE_ID" "$APP_PATH"
warm_up_device "$IPHONE_ID"
capture "$IPHONE_ID" "$OUTPUT_DIR/raw/iphone-6.9/01-home.png" "$OUTPUT_DIR/iphone-6.9/01-home.jpg" 1320 2868
capture "$IPHONE_ID" "$OUTPUT_DIR/raw/iphone-6.9/02-opportunities.png" "$OUTPUT_DIR/iphone-6.9/02-opportunities.jpg" 1320 2868 --screenshot-query robotics -start-opportunities
capture "$IPHONE_ID" "$OUTPUT_DIR/raw/iphone-6.9/03-high-school.png" "$OUTPUT_DIR/iphone-6.9/03-high-school.jpg" 1320 2868 -start-high-school
capture "$IPHONE_ID" "$OUTPUT_DIR/raw/iphone-6.9/04-profile.png" "$OUTPUT_DIR/iphone-6.9/04-profile.jpg" 1320 2868 -start-account -localProfileName "STEM Explorer" -localProfileEnabled YES
run_simctl shutdown "$IPHONE_ID" >/dev/null 2>&1 || true

prepare_device "$IPAD_ID" "$APP_PATH"
warm_up_device "$IPAD_ID"
capture "$IPAD_ID" "$OUTPUT_DIR/raw/ipad-13/01-home.png" "$OUTPUT_DIR/ipad-13/01-home.jpg" 2064 2752
capture "$IPAD_ID" "$OUTPUT_DIR/raw/ipad-13/02-opportunities.png" "$OUTPUT_DIR/ipad-13/02-opportunities.jpg" 2064 2752 --screenshot-query robotics -start-opportunities
capture "$IPAD_ID" "$OUTPUT_DIR/raw/ipad-13/03-high-school.png" "$OUTPUT_DIR/ipad-13/03-high-school.jpg" 2064 2752 -start-high-school
capture "$IPAD_ID" "$OUTPUT_DIR/raw/ipad-13/04-profile.png" "$OUTPUT_DIR/ipad-13/04-profile.jpg" 2064 2752 -start-account -localProfileName "STEM Explorer" -localProfileEnabled YES
run_simctl shutdown "$IPAD_ID" >/dev/null 2>&1 || true

echo
echo "Release screenshot capture complete: $OUTPUT_DIR"
