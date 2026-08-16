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
SCREENSHOT_ROOT="${SCREENSHOT_ROOT:-build/app-store-screenshots}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCREENSHOT_ROOT/final}"
RAW_OUTPUT_DIR="${RAW_OUTPUT_DIR:-$SCREENSHOT_ROOT/raw}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData-app-store-screenshots}"
# The bootstrap and visible browse surface can complete separate deduplicated
# refresh passes. Keep the UI settled long enough to avoid capturing the brief
# saved-cache/loading state after the production request succeeds.
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-12}"
SCREENSHOT_READY_TIMEOUT="${SCREENSHOT_READY_TIMEOUT:-45}"
SIMCTL_TIMEOUT="${SIMCTL_TIMEOUT:-90}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-120}"
USE_DEDICATED_SIMULATORS="${USE_DEDICATED_SIMULATORS:-1}"
VISUAL_QA_MARKER="$OUTPUT_DIR/FINAL_VISUAL_QA.md"
CAPTURE_RECEIPT="$OUTPUT_DIR/CAPTURE_RECEIPT.json"
MAC_CAPTURE_SESSION="$OUTPUT_DIR/MAC_CAPTURE_SESSION.json"
CONTACT_SHEET="$OUTPUT_DIR/contact-sheet.jpg"
SOURCE_PATHS=(GTAFreeSTEM GTAFreeSTEMWatch GTAFreeSTEM.xcodeproj project.yml)

IPHONE_ID=""
IPAD_ID=""
CREATED_IPHONE_ID=""
CREATED_IPAD_ID=""

invalidate_visual_qa() {
  rm -f -- "$VISUAL_QA_MARKER" "$CAPTURE_RECEIPT" "$MAC_CAPTURE_SESSION" "$CONTACT_SHEET"
}

mkdir -p "$OUTPUT_DIR/iphone-6.9" "$OUTPUT_DIR/ipad-13" "$RAW_OUTPUT_DIR/iphone-6.9" "$RAW_OUTPUT_DIR/ipad-13"
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
    echo "Source tree changed while iPhone/iPad screenshots were being captured." >&2
    exit 1
  fi
}

verify_built_source_commit() {
  local info_plist="$1"
  local expected_commit="$2"
  local observed_commit

  if [ ! -f "$info_plist" ]; then
    echo "Missing built app metadata at $info_plist" >&2
    exit 1
  fi
  observed_commit="$(plutil -extract GTAReleaseSourceCommit raw -o - "$info_plist" 2>/dev/null || true)"
  if [ "$observed_commit" != "$expected_commit" ]; then
    echo "Built screenshot app embeds ${observed_commit:-no source commit}; expected $expected_commit." >&2
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

  echo "Simulator $device did not reach $expected_state within ${timeout_seconds}s (last state: ${state:-unknown})." >&2
  return 1
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
    wait_for_device_state "$source_id" "Shutdown" "$BOOT_TIMEOUT"
  fi

  if ! identifier="$(xcrun simctl clone "$source_id" "GTA STEM Screenshots ${display_name} $$")"; then
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

live_feed_store_path() {
  local device="$1"
  local data_container

  if ! data_container="$(run_simctl get_app_container "$device" "$BUNDLE_ID" data 2>/dev/null)"; then
    echo "Could not resolve the installed app data container on simulator $device." >&2
    return 1
  fi
  if [ -z "$data_container" ]; then
    echo "Simulator $device returned an empty app data-container path." >&2
    return 1
  fi
  printf '%s\n' "$data_container/Library/Application Support/default.store"
}

read_live_feed_updated_at() {
  local device="$1"
  local store
  local value

  store="$(live_feed_store_path "$device")" || return 1
  if [ ! -e "$store" ]; then
    printf '%s\n' "-1"
    return 0
  fi
  if [ ! -f "$store" ]; then
    echo "SwiftData live-feed store is not a regular file: $store" >&2
    return 1
  fi

  if ! value="$(/usr/bin/sqlite3 -readonly "$store" \
    "SELECT COALESCE((SELECT printf('%.9f', ZUPDATEDAT) FROM ZOPPORTUNITYCACHERECORD WHERE ZCACHEKEY = 'latest-opportunities' ORDER BY ZUPDATEDAT DESC LIMIT 1), '-1');")"; then
    echo "Could not read the live-feed timestamp baseline from $store." >&2
    return 1
  fi
  if ! [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    echo "Invalid live-feed timestamp baseline from $store: ${value:-empty}" >&2
    return 1
  fi
  printf '%s\n' "$value"
}

read_live_refresh_completed_at() {
  local device="$1"
  local store
  local value

  store="$(live_feed_store_path "$device")" || return 1
  if [ ! -e "$store" ]; then
    printf '%s\n' "-1"
    return 0
  fi
  if [ ! -f "$store" ]; then
    echo "SwiftData live-feed store is not a regular file: $store" >&2
    return 1
  fi

  if ! value="$(/usr/bin/sqlite3 -readonly "$store" \
    "SELECT CASE WHEN MAX(ZLASTSEENAT) IS NULL THEN '-1' ELSE printf('%.9f', MAX(ZLASTSEENAT)) END FROM ZSEENOPPORTUNITYRECORD WHERE ZLASTSEENAT IS NOT NULL;")"; then
    echo "Could not read the live-refresh timestamp baseline from $store." >&2
    return 1
  fi
  if ! [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    echo "Invalid live-refresh timestamp baseline from $store: ${value:-empty}" >&2
    return 1
  fi
  printf '%s\n' "$value"
}

read_validated_live_feed_state() {
  local device="$1"
  local previous_feed_updated_at="$2"
  local previous_refresh_completed_at="$3"
  local store
  local state

  if ! [[ "$previous_feed_updated_at" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    echo "Invalid pre-launch live-feed baseline: ${previous_feed_updated_at:-empty}" >&2
    return 1
  fi
  if ! [[ "$previous_refresh_completed_at" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    echo "Invalid pre-launch live-refresh baseline: ${previous_refresh_completed_at:-empty}" >&2
    return 1
  fi

  store="$(live_feed_store_path "$device")" || return 1
  [ ! -e "$store" ] && return 0
  if [ ! -f "$store" ]; then
    echo "SwiftData live-feed store is not a regular file: $store" >&2
    return 1
  fi

  # A successful production refresh normally updates the retained feed record.
  # SwiftData may reuse an unchanged payload without advancing that timestamp,
  # so the seen-opportunity write is a second success witness: it happens only
  # after the public request succeeds and the public-feed state has been applied.
  # Either witness must be newer than its pre-launch baseline; the feed itself
  # must still carry nonempty metadata and data. Bundled/offline reuse advances
  # neither witness and therefore cannot satisfy this readiness check.
  if ! state="$(/usr/bin/sqlite3 -readonly "$store" \
    "SELECT printf('%.9f', feed.ZUPDATEDAT) || '|' || json_extract(CAST(feed.ZPAYLOAD AS TEXT), '$.meta.lastUpdated') || '|' || json_array_length(json_extract(CAST(feed.ZPAYLOAD AS TEXT), '$.data')) || '|' || printf('%.9f', COALESCE((SELECT MAX(seen.ZLASTSEENAT) FROM ZSEENOPPORTUNITYRECORD AS seen), -1)) FROM ZOPPORTUNITYCACHERECORD AS feed WHERE feed.ZCACHEKEY = 'latest-opportunities' AND (feed.ZUPDATEDAT > $previous_feed_updated_at OR COALESCE((SELECT MAX(seen.ZLASTSEENAT) FROM ZSEENOPPORTUNITYRECORD AS seen), -1) > $previous_refresh_completed_at) AND COALESCE(json_extract(CAST(feed.ZPAYLOAD AS TEXT), '$.meta.lastUpdated'), '') != '' AND COALESCE(json_array_length(json_extract(CAST(feed.ZPAYLOAD AS TEXT), '$.data')), 0) > 0 ORDER BY feed.ZUPDATEDAT DESC LIMIT 1;")"; then
    echo "Could not validate the refreshed public feed in $store." >&2
    return 1
  fi
  printf '%s\n' "$state"
}

wait_for_live_feed_refresh() {
  local device="$1"
  local previous_feed_updated_at="$2"
  local previous_refresh_completed_at="$3"
  local deadline=$((SECONDS + SCREENSHOT_READY_TIMEOUT))
  local state=""

  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! state="$(read_validated_live_feed_state "$device" "$previous_feed_updated_at" "$previous_refresh_completed_at")"; then
      echo "Aborting screenshot capture because live-feed readiness could not be verified." >&2
      return 1
    fi
    if [ -n "$state" ]; then
      echo "Validated public feed for capture: $state"
      return 0
    fi
    sleep 0.25
  done

  echo "GTAFreeSTEM did not complete a newly validated public-feed refresh within ${SCREENSHOT_READY_TIMEOUT}s." >&2
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
  local previous_feed_updated_at
  local previous_refresh_completed_at

  if [ "${1:-}" = "--screenshot-query" ]; then
    screenshot_query="$2"
    shift 2
  fi

  run_simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
  previous_feed_updated_at="$(read_live_feed_updated_at "$device")"
  previous_refresh_completed_at="$(read_live_refresh_completed_at "$device")"
  if [ -n "$screenshot_query" ]; then
    SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_QUERY="$screenshot_query" \
      run_simctl launch "$device" "$BUNDLE_ID" "$@" >/dev/null
  else
    run_simctl launch "$device" "$BUNDLE_ID" "$@" >/dev/null
  fi
  wait_for_live_feed_refresh "$device" "$previous_feed_updated_at" "$previous_refresh_completed_at"
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
  wait_for_device_state "$device" "Shutdown" "$BOOT_TIMEOUT"
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
  local previous_feed_updated_at
  local previous_refresh_completed_at
  previous_feed_updated_at="$(read_live_feed_updated_at "$device")"
  previous_refresh_completed_at="$(read_live_refresh_completed_at "$device")"
  run_simctl launch "$device" "$BUNDLE_ID" >/dev/null
  wait_for_live_feed_refresh "$device" "$previous_feed_updated_at" "$previous_refresh_completed_at"
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
GTA_RELEASE_SOURCE_COMMIT="$SOURCE_COMMIT"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS Simulator,id=$IPHONE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "GTA_RELEASE_SOURCE_COMMIT=$GTA_RELEASE_SOURCE_COMMIT" \
  build >/dev/null

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release-iphonesimulator/GTAFreeSTEM.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Could not find built GTAFreeSTEM.app at $APP_PATH"
  exit 1
fi
verify_built_source_commit "$APP_PATH/Info.plist" "$SOURCE_COMMIT"

prepare_device "$IPHONE_ID" "$APP_PATH"
warm_up_device "$IPHONE_ID"
capture "$IPHONE_ID" "$RAW_OUTPUT_DIR/iphone-6.9/01-home.png" "$OUTPUT_DIR/iphone-6.9/01-home.jpg" 1320 2868
capture "$IPHONE_ID" "$RAW_OUTPUT_DIR/iphone-6.9/03-high-school.png" "$OUTPUT_DIR/iphone-6.9/03-high-school.jpg" 1320 2868 -start-high-school
capture "$IPHONE_ID" "$RAW_OUTPUT_DIR/iphone-6.9/02-opportunities.png" "$OUTPUT_DIR/iphone-6.9/02-opportunities.jpg" 1320 2868 -start-opportunities
capture "$IPHONE_ID" "$RAW_OUTPUT_DIR/iphone-6.9/04-profile.png" "$OUTPUT_DIR/iphone-6.9/04-profile.jpg" 1320 2868 -start-account -localProfileName "STEM Explorer" -localProfileEnabled YES
run_simctl shutdown "$IPHONE_ID" >/dev/null 2>&1 || true

prepare_device "$IPAD_ID" "$APP_PATH"
warm_up_device "$IPAD_ID"
capture "$IPAD_ID" "$RAW_OUTPUT_DIR/ipad-13/01-home.png" "$OUTPUT_DIR/ipad-13/01-home.jpg" 2064 2752
capture "$IPAD_ID" "$RAW_OUTPUT_DIR/ipad-13/03-high-school.png" "$OUTPUT_DIR/ipad-13/03-high-school.jpg" 2064 2752 -start-high-school
capture "$IPAD_ID" "$RAW_OUTPUT_DIR/ipad-13/02-opportunities.png" "$OUTPUT_DIR/ipad-13/02-opportunities.jpg" 2064 2752 -start-opportunities
capture "$IPAD_ID" "$RAW_OUTPUT_DIR/ipad-13/04-profile.png" "$OUTPUT_DIR/ipad-13/04-profile.jpg" 2064 2752 -start-account -localProfileName "STEM Explorer" -localProfileEnabled YES
run_simctl shutdown "$IPAD_ID" >/dev/null 2>&1 || true

require_unchanged_screenshot_source "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"

echo
echo "Release screenshot capture complete: $OUTPUT_DIR"
