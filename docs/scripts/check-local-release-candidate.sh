#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

PROJECT="${PROJECT:-GTAFreeSTEM.xcodeproj}"
SCHEME="${SCHEME:-GTAFreeSTEM}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
RUN_SCREENSHOTS="${RUN_SCREENSHOTS:-1}"
RUN_SMOKE="${RUN_SMOKE:-1}"
SCREENSHOT_CAPTURE_ROOT="build/app-store-screenshots"
SCREENSHOT_PACKAGE_ROOT="$SCREENSHOT_CAPTURE_ROOT/final"
VISUAL_QA_MARKER="$SCREENSHOT_PACKAGE_ROOT/FINAL_VISUAL_QA.md"
CAPTURE_RECEIPT="$SCREENSHOT_PACKAGE_ROOT/CAPTURE_RECEIPT.json"
MAC_CAPTURE_SESSION="$SCREENSHOT_PACKAGE_ROOT/MAC_CAPTURE_SESSION.json"
VERIFY_SCREENSHOT_PACKAGE_SCRIPT="docs/scripts/verify-screenshot-package.sh"

step() {
  echo
  echo "=== $* ==="
}

step "Preflight"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required for local release-candidate checks."
  exit 1
fi
if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required for simulator release-candidate checks."
  exit 1
fi

step "Bundled-feed integrity self-test"
bash docs/scripts/test-feed-sync-integrity.sh

step "Release simulator smoke integrity self-test"
bash docs/scripts/test-release-smoke-integrity.sh

step "Archive-verifier self-tests"
bash docs/scripts/test-app-store-archive-verifier.sh

step "Screenshot provenance verifier self-test"
bash docs/scripts/test-screenshot-package-verifier.sh

if [ "$RUN_SCREENSHOTS" != "0" ]; then
  step "Capture App Store screenshots"
  SCREENSHOT_ROOT="$SCREENSHOT_CAPTURE_ROOT" OUTPUT_DIR="$SCREENSHOT_PACKAGE_ROOT" \
    bash docs/scripts/capture-app-store-screenshots.sh
  SCREENSHOT_ROOT="$SCREENSHOT_CAPTURE_ROOT" OUTPUT_DIR="$SCREENSHOT_PACKAGE_ROOT" \
    bash docs/scripts/capture-watch-app-store-screenshot.sh
  echo "Automated iPhone/iPad/Watch capture invalidated the prior receipt and visual approval, so existing Mac files cannot be treated as current." >&2
  echo "Run docs/scripts/prepare-mac-screenshot-capture.sh for the same clean source commit, capture all four Mac images from that prepared app, run docs/scripts/finalize-screenshot-capture-receipt.sh, visually audit the complete 13-file set, regenerate $VISUAL_QA_MARKER, then rerun with RUN_SCREENSHOTS=0." >&2
  exit 2
else
  echo "Skipping App Store screenshot capture because RUN_SCREENSHOTS=0."
  if [ ! -f "$CAPTURE_RECEIPT" ] || [ ! -f "$VISUAL_QA_MARKER" ]; then
    echo "RUN_SCREENSHOTS=0 requires both $CAPTURE_RECEIPT and $VISUAL_QA_MARKER from the exact current source build." >&2
    exit 1
  fi
  SCREENSHOT_PACKAGE_TEST_FIXTURE_ONLY=0 \
    SCREENSHOT_ROOT="$SCREENSHOT_PACKAGE_ROOT" \
    CAPTURE_RECEIPT_PATH="$CAPTURE_RECEIPT" \
    VISUAL_QA_MANIFEST_PATH="$VISUAL_QA_MARKER" \
    MAC_CAPTURE_SESSION_PATH="$MAC_CAPTURE_SESSION" \
    bash "$VERIFY_SCREENSHOT_PACKAGE_SCRIPT"
fi

step "Strict release-readiness audit"
STRICT_TRANSLATION_CHECK=1 CHECK_APP_STORE_SCREENSHOTS=1 bash docs/scripts/check-release-readiness.sh

step "Public release gate self-test"
bash docs/scripts/test-public-release-gates.sh

step "Release simulator build"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  build

step "XCTest suite"
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION"

if [ "$RUN_SMOKE" != "0" ]; then
  step "Clean-install simulator smoke"
  bash docs/scripts/smoke-release-simulator.sh
else
  echo "Skipping simulator smoke because RUN_SMOKE=0."
fi

step "Local candidate result"
cat <<'EOF'
Automated local release-candidate checks passed.

This does not replace the final public-release gate. Before App Review submission,
complete docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md from a real TestFlight install and
then run:

  IOS_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-1.0-12.xcarchive \
    IOS_IPA_PATH=/absolute/path/to/GTAFreeSTEM-1.0-12.ipa \
    MAC_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-Mac-1.0-12.xcarchive \
    MAC_PKG_PATH=/absolute/path/to/GTAFreeSTEM.pkg \
    PUBLIC_RELEASE_PLATFORMS=iphone,ipad,watch,mac \
    bash docs/scripts/check-public-release-gates.sh
EOF
