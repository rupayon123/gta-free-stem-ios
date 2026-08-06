#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

SCRIPT="docs/scripts/smoke-release-simulator.sh"

require_text() {
  local text="$1"
  if ! grep -Fq -- "$text" "$SCRIPT"; then
    echo "Release smoke integrity test failed: missing ${text}"
    exit 1
  fi
}

reject_text() {
  local text="$1"
  if grep -Fq -- "$text" "$SCRIPT"; then
    echo "Release smoke integrity test failed: stale global-build lookup remains: ${text}"
    exit 1
  fi
}

require_text 'DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/DerivedData-release-smoke}"'
require_text '-derivedDataPath "$DERIVED_DATA_PATH"'
require_text 'APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphonesimulator/${SCHEME}.app"'
require_text 'cmp -s "GTAFreeSTEM/Resources/opportunities.json" "$APP_OPPORTUNITIES"'
require_text 'SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_MODE=1'
require_text 'SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_READY_NONCE="$ready_nonce"'
require_text 'wait_for_app_ready "$device" "$ready_nonce"'
require_text 'xcrun simctl get_app_container "$device" "$BUNDLE_ID" data'
require_text '/Library/Caches/$SCREENSHOT_READY_MARKER'
reject_text '$HOME/Library/Developer/Xcode/DerivedData'
reject_text 'latest_app_path'
reject_text 'defaults read "$BUNDLE_ID" screenshotCaptureReady'
reject_text 'screenshotCaptureReady -bool false'

bash "$SCRIPT" --self-test

echo "Release simulator smoke integrity self-test passed."
