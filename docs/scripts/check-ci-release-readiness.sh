#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

PROJECT="${PROJECT:-GTAFreeSTEM.xcodeproj}"
SCHEME="${SCHEME:-GTAFreeSTEM}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for CI release-readiness checks."
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required for CI release-readiness checks."
  exit 1
fi
if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required for CI release-readiness checks."
  exit 1
fi

if [ -z "$DESTINATION" ]; then
  DESTINATION="$(/usr/bin/python3 - <<'PY'
import json
import subprocess

preferred_names = [
    "iPhone 17",
    "iPhone 17 Pro",
    "iPhone 16",
    "iPhone 16 Pro",
    "iPhone 15",
    "iPhone 15 Pro",
    "iPhone 14",
    "iPhone SE (3rd generation)",
]
payload = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
devices = [device for runtime in payload.get("devices", {}).values() for device in runtime]
for name in preferred_names:
    for device in devices:
        if device.get("name") == name and device.get("udid"):
            print(f"platform=iOS Simulator,id={device['udid']}")
            raise SystemExit(0)
for device in devices:
    name = str(device.get("name", ""))
    if name.startswith("iPhone ") and device.get("udid"):
        print(f"platform=iOS Simulator,id={device['udid']}")
        raise SystemExit(0)
raise SystemExit("No available iPhone simulator found for CI")
PY
)"
fi

echo "Using CI test destination: ${DESTINATION}"

echo
echo "=== CI strict release-readiness audit ==="
CHECK_APP_STORE_SCREENSHOTS=0 STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh

echo
echo "=== CI Release build ==="
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  build

echo
echo "=== CI XCTest suite ==="
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION"
