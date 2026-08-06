#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

BUNDLE_ID="${BUNDLE_ID:-com.rupayonhaldar.gtafreestem}"
SCHEME="${SCHEME:-GTAFreeSTEM}"
PROJECT="${PROJECT:-GTAFreeSTEM.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Release}"
DEVICE="${DEVICE:-iPhone 17}"
OUTPUT_DIR="${OUTPUT_DIR:-build/release-smoke}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/DerivedData-release-smoke}"
# BrowseView renders a live, filterable result surface on the screenshot-only
# deep-link routes. Give a clean simulator enough time to leave the branded
# loader and render that surface before asserting the capture is useful.
# The bundled offline snapshot is intentionally decoded before the home screen
# becomes interactive. A fresh simulator can take longer than seven seconds to
# perform its first decode; wait long enough to verify the actual destination
# screen instead of capturing the deliberate, brief 100% handoff frame.
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-1}"
SCREENSHOT_READY_TIMEOUT="${SCREENSHOT_READY_TIMEOUT:-30}"
SCREENSHOT_READY_MARKER="gta-free-stem-screenshot-ready"
EXPECTED_OPPORTUNITY_COUNT="${EXPECTED_OPPORTUNITY_COUNT:-}"

mkdir -p "$OUTPUT_DIR"

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

opportunity_count() {
  local file="$1"

  if command -v jq >/dev/null 2>&1; then
    jq '(.opportunities // .data) | length' "$file"
  else
    /usr/bin/python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)
print(len(payload.get("opportunities") or payload.get("data") or []))
PY
  fi
}

verify_png() {
  /usr/bin/python3 - "$1" <<'PY'
import struct
import sys
import zlib
from pathlib import Path

path = Path(sys.argv[1])
blob = path.read_bytes()
if len(blob) < 100_000:
    raise SystemExit(f"{path} is unexpectedly small: {len(blob)} bytes")

if not blob.startswith(b"\x89PNG\r\n\x1a\n"):
    raise SystemExit(f"{path} is not a PNG")

offset = 8
width = height = bit_depth = color_type = None
idat = bytearray()
while offset < len(blob):
    length = struct.unpack(">I", blob[offset:offset + 4])[0]
    kind = blob[offset + 4:offset + 8]
    data = blob[offset + 8:offset + 8 + length]
    offset += length + 12
    if kind == b"IHDR":
        width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", data)
    elif kind == b"IDAT":
        idat.extend(data)
    elif kind == b"IEND":
        break

if width is None or height is None:
    raise SystemExit(f"{path} is missing IHDR")
if width < 300 or height < 600:
    raise SystemExit(f"{path} dimensions are too small: {width} x {height}")
if bit_depth != 8 or color_type not in (0, 2, 6):
    print(f"{path}: {width} x {height}; skipped color variance for PNG type {color_type}")
    raise SystemExit(0)

channels = {0: 1, 2: 3, 6: 4}[color_type]
stride = width * channels
raw = zlib.decompress(bytes(idat))
rows = []
cursor = 0

def paeth(a, b, c):
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c

previous = bytearray(stride)
for _ in range(height):
    filter_type = raw[cursor]
    cursor += 1
    current = bytearray(raw[cursor:cursor + stride])
    cursor += stride

    for index, value in enumerate(current):
        left = current[index - channels] if index >= channels else 0
        up = previous[index]
        upper_left = previous[index - channels] if index >= channels else 0
        if filter_type == 1:
            current[index] = (value + left) & 0xFF
        elif filter_type == 2:
            current[index] = (value + up) & 0xFF
        elif filter_type == 3:
            current[index] = (value + ((left + up) // 2)) & 0xFF
        elif filter_type == 4:
            current[index] = (value + paeth(left, up, upper_left)) & 0xFF
        elif filter_type != 0:
            raise SystemExit(f"{path} has unsupported PNG filter {filter_type}")
    rows.append(current)
    previous = current

sampled = set()
y_step = max(1, height // 80)
x_step = max(1, width // 80)
for y in range(0, height, y_step):
    row = rows[y]
    for x in range(0, width, x_step):
        start = x * channels
        sampled.add(tuple(row[start:start + min(channels, 3)]))

if len(sampled) < 24:
    raise SystemExit(f"{path} appears blank or nearly blank: {len(sampled)} sampled colors")

print(f"{path}: {width} x {height}, {len(sampled)} sampled colors")
PY
}

read_ready_nonce() {
  local device="$1"
  local data_container
  if [ -n "${SCREENSHOT_READY_OVERRIDE+x}" ]; then
    echo "$SCREENSHOT_READY_OVERRIDE"
    return 0
  fi
  data_container="$(xcrun simctl get_app_container "$device" "$BUNDLE_ID" data 2>/dev/null || true)"
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
  local output="$2"
  local ready_nonce
  shift 2

  xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
  ready_nonce="$(/usr/bin/uuidgen)"
  SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_MODE=1 \
    SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_READY_NONCE="$ready_nonce" \
    xcrun simctl launch "$device" "$BUNDLE_ID" "$@" >/dev/null
  wait_for_app_ready "$device" "$ready_nonce"
  sleep "$SCREENSHOT_DELAY"
  xcrun simctl io "$device" screenshot "$output" >/dev/null
  verify_png "$output"
  xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

if [ "${1:-}" = "--self-test" ]; then
  SCREENSHOT_READY_TIMEOUT=1
  SCREENSHOT_READY_OVERRIDE="current-nonce"
  wait_for_app_ready "self-test" "current-nonce"
  SCREENSHOT_READY_OVERRIDE="stale-nonce"
  if wait_for_app_ready "self-test" "current-nonce"; then
    echo "Release smoke readiness self-test failed: a never-ready app was accepted." >&2
    exit 1
  fi
  echo "Release smoke readiness self-test passed."
  exit 0
fi

echo "Building ${SCHEME} ${CONFIGURATION} for ${DEVICE}..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS Simulator,name=${DEVICE}" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build >/dev/null

APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphonesimulator/${SCHEME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Could not find the app built by this run at ${APP_PATH}"
  exit 1
fi

APP_OPPORTUNITIES="$APP_PATH/opportunities.json"
if [ ! -f "$APP_OPPORTUNITIES" ]; then
  echo "Built app is missing bundled opportunities.json"
  exit 1
fi

SOURCE_COUNT="$(opportunity_count "GTAFreeSTEM/Resources/opportunities.json")"
APP_COUNT="$(opportunity_count "$APP_OPPORTUNITIES")"
if [ -z "$EXPECTED_OPPORTUNITY_COUNT" ]; then
  EXPECTED_OPPORTUNITY_COUNT="$SOURCE_COUNT"
fi

if [ "$SOURCE_COUNT" != "$EXPECTED_OPPORTUNITY_COUNT" ]; then
  echo "Source opportunity count ${SOURCE_COUNT} does not match expected ${EXPECTED_OPPORTUNITY_COUNT}"
  exit 1
fi

if [ "$APP_COUNT" != "$EXPECTED_OPPORTUNITY_COUNT" ]; then
  echo "Built app opportunity count ${APP_COUNT} does not match expected ${EXPECTED_OPPORTUNITY_COUNT}"
  exit 1
fi

if ! cmp -s "GTAFreeSTEM/Resources/opportunities.json" "$APP_OPPORTUNITIES"; then
  echo "Built app opportunities.json is not byte-for-byte identical to the release source feed"
  exit 1
fi

DEVICE_ID="$(device_id "$DEVICE")"

xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl boot "$DEVICE_ID" >/dev/null
xcrun simctl bootstatus "$DEVICE_ID" >/dev/null
xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH" >/dev/null
xcrun simctl ui "$DEVICE_ID" appearance light >/dev/null 2>&1 || true
xcrun simctl status_bar "$DEVICE_ID" override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiBars 3 \
  --batteryState charged \
  --batteryLevel 100 >/dev/null 2>&1 || true

capture "$DEVICE_ID" "$OUTPUT_DIR/01-clean-home.png"
capture "$DEVICE_ID" "$OUTPUT_DIR/02-opportunities.png" -start-opportunities
capture "$DEVICE_ID" "$OUTPUT_DIR/03-high-school.png" -start-high-school
capture "$DEVICE_ID" "$OUTPUT_DIR/04-support.png" -start-support

echo
echo "Release simulator smoke passed for ${DEVICE}."
echo "App path: ${APP_PATH}"
echo "Opportunity count: ${APP_COUNT}"
echo "Screenshots: ${OUTPUT_DIR}"
