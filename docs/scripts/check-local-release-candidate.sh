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

if [ "$RUN_SCREENSHOTS" != "0" ]; then
  step "Capture App Store screenshots"
  bash docs/scripts/capture-app-store-screenshots.sh
else
  echo "Skipping App Store screenshot capture because RUN_SCREENSHOTS=0."
fi

step "Strict release-readiness audit"
STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh

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

  bash docs/scripts/check-public-release-gates.sh
EOF
