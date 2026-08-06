#!/usr/bin/env bash
set -euo pipefail

# Builds and installs a development-signed copy on one explicitly selected,
# already-trusted physical iPhone or iPad. It never uploads or submits a build.

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

BUNDLE_ID="${BUNDLE_ID:-com.rupayonhaldar.gtafreestem}"
SCHEME="${SCHEME:-GTAFreeSTEM}"
PROJECT="${PROJECT:-GTAFreeSTEM.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DEVICE_ID="${DEVICE_ID:-}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData-connected-device}"

if [ -z "$DEVICE_ID" ]; then
  echo "No DEVICE_ID was supplied. Connect, unlock, and trust your iPhone or iPad, then run:"
  echo "  xcrun devicectl list devices"
  echo "  DEVICE_ID=<the device UUID> $0"
  exit 2
fi

devices="$(xcrun devicectl list devices)"
device_state="$(printf '%s\n' "$devices" | awk -v device_id="$DEVICE_ID" '
  {
    for (column = 1; column <= NF; column += 1) {
      if ($column == device_id) {
        print $(column + 1)
        exit
      }
    }
  }
')"

if [ -z "$device_state" ]; then
  echo "Device '$DEVICE_ID' was not found. Connect, unlock, and trust the exact device first."
  printf '%s\n' "$devices"
  exit 2
fi

case "$device_state" in
  available|connected)
    ;;
  *)
    echo "Device '$DEVICE_ID' is currently '$device_state', not connected and available."
    echo "Connect it by cable or Wi-Fi, unlock it, accept any Trust prompt, and keep Developer Mode enabled."
    printf '%s\n' "$devices"
    exit 2
    ;;
esac

build_for_device() {
  xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=iOS,id=${DEVICE_ID}" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "$@"
}

echo "Building ${SCHEME} for the explicitly selected device ${DEVICE_ID}..."
if [ "${ALLOW_PROVISIONING_UPDATES:-0}" = "1" ]; then
  # This opt-in may register the selected device and create or refresh
  # development provisioning under the Apple team already configured in Xcode.
  build_for_device -allowProvisioningUpdates -allowProvisioningDeviceRegistration
else
  # Calling the helper without arguments is safe under the macOS Bash 3.2
  # shipped with Xcode hosts, even when `set -u` is enabled.
  build_for_device
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphoneos/${SCHEME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Expected built app was not found at: $APP_PATH"
  exit 1
fi

echo "Installing the development build on ${DEVICE_ID}..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "Launching ${BUNDLE_ID}..."
xcrun devicectl device process launch --terminate-existing --device "$DEVICE_ID" "$BUNDLE_ID"

echo "Installed and launched. This is a local development install only; it was not uploaded to TestFlight or App Store Connect."
