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

if [ "$RUN_SCREENSHOTS" != "0" ]; then
  step "Capture App Store screenshots"
  bash docs/scripts/capture-app-store-screenshots.sh
  bash docs/scripts/capture-watch-app-store-screenshot.sh
  for screenshot in \
    build/app-store-screenshots/mac/01-home.jpg \
    build/app-store-screenshots/mac/02-opportunities.jpg; do
    if [ ! -f "$screenshot" ]; then
      echo "Missing $screenshot. Capture the Release Mac Catalyst window as documented in docs/APP_STORE_SCREENSHOTS.md, then rerun this check."
      exit 1
    fi
  done
else
  echo "Skipping App Store screenshot capture because RUN_SCREENSHOTS=0."
fi

step "Strict release-readiness audit"
STRICT_TRANSLATION_CHECK=1 CHECK_APP_STORE_SCREENSHOTS="$RUN_SCREENSHOTS" bash docs/scripts/check-release-readiness.sh

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
    PUBLIC_RELEASE_PLATFORMS=iphone,ipad,watch \
    bash docs/scripts/check-public-release-gates.sh
EOF
