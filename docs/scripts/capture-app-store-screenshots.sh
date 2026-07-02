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
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-8}"

mkdir -p "$OUTPUT_DIR/iphone-6.9" "$OUTPUT_DIR/ipad-13"

device_id() {
  /usr/bin/python3 - "$1" <<'PY'
import json
import subprocess
import sys

target = sys.argv[1]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
for runtime_devices in data.get("devices", {}).values():
    for device in runtime_devices:
        if device.get("name") == target:
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit(f"Simulator device not found: {target}")
PY
}

latest_app_path() {
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/Build/Products/Release-iphonesimulator/GTAFreeSTEM.app" \
    -type d -print0 |
    xargs -0 ls -dt |
    head -n 1
}

capture() {
  local device="$1"
  local output="$2"
  shift 2

  xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$device" "$BUNDLE_ID" "$@" >/dev/null
  sleep "$SCREENSHOT_DELAY"
  xcrun simctl io "$device" screenshot "$output" >/dev/null
  xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
  echo "Captured $output"
}

prepare_device() {
  local device="$1"
  local app_path="$2"

  xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
  xcrun simctl boot "$device" >/dev/null
  xcrun simctl bootstatus "$device" >/dev/null
  xcrun simctl uninstall "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$device" "$app_path" >/dev/null
  xcrun simctl ui "$device" appearance light >/dev/null 2>&1 || true
  xcrun simctl status_bar "$device" override \
    --time "9:41" \
    --dataNetwork wifi \
    --wifiBars 3 \
    --batteryState charged \
    --batteryLevel 100 >/dev/null 2>&1 || true
}

warm_up_device() {
  local device="$1"

  xcrun simctl launch "$device" "$BUNDLE_ID" >/dev/null
  sleep 5
  xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 2
}

finish_device() {
  local device="$1"
  xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
}

echo "Building ${SCHEME} for ${IPHONE_DEVICE}..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -destination "platform=iOS Simulator,name=${IPHONE_DEVICE}" build >/dev/null

APP_PATH="$(latest_app_path)"
if [ -z "$APP_PATH" ]; then
  echo "Could not find built GTAFreeSTEM.app"
  exit 1
fi

IPHONE_ID="$(device_id "$IPHONE_DEVICE")"
IPAD_ID="$(device_id "$IPAD_DEVICE")"

prepare_device "$IPHONE_ID" "$APP_PATH"
warm_up_device "$IPHONE_ID"
capture "$IPHONE_ID" "$OUTPUT_DIR/iphone-6.9/01-home.png"
capture "$IPHONE_ID" "$OUTPUT_DIR/iphone-6.9/02-opportunities.png" -start-opportunities
capture "$IPHONE_ID" "$OUTPUT_DIR/iphone-6.9/03-high-school.png" -start-high-school
capture "$IPHONE_ID" "$OUTPUT_DIR/iphone-6.9/04-support-account.png" -start-support
finish_device "$IPHONE_ID"

prepare_device "$IPAD_ID" "$APP_PATH"
warm_up_device "$IPAD_ID"
capture "$IPAD_ID" "$OUTPUT_DIR/ipad-13/01-home.png"
capture "$IPAD_ID" "$OUTPUT_DIR/ipad-13/02-opportunities.png" -start-opportunities
capture "$IPAD_ID" "$OUTPUT_DIR/ipad-13/03-high-school.png" -start-high-school
capture "$IPAD_ID" "$OUTPUT_DIR/ipad-13/04-support-account.png" -start-support
finish_device "$IPAD_ID"

echo
echo "Screenshot dimensions:"
find "$OUTPUT_DIR" -type f -name "*.png" | sort |
  while IFS= read -r file; do
    width=$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    height=$(sips -g pixelHeight "$file" 2>/dev/null | awk '/pixelHeight/ {print $2}')
    echo "${file}: ${width} x ${height}"
  done
