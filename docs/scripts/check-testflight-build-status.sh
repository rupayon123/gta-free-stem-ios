#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

APP_APPLE_ID="${APP_APPLE_ID:-6779714459}"
BUNDLE_VERSION="${BUNDLE_VERSION:-}"
BUNDLE_SHORT_VERSION="${BUNDLE_SHORT_VERSION:-1.0}"
PLATFORM="${PLATFORM:-ios}"
PROVIDER_PUBLIC_ID="${APP_STORE_CONNECT_PROVIDER_PUBLIC_ID:-4bfabe71-697b-4d97-bc76-4c8d5be25591}"
DELIVERY_ID="${DELIVERY_ID:-}"
WAIT_FOR_PROCESSING="${WAIT_FOR_PROCESSING:-0}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-json}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required to check App Store Connect build status."
  exit 1
fi

if [ -z "$BUNDLE_VERSION" ]; then
  BUNDLE_VERSION="$(
    xcodebuild -project GTAFreeSTEM.xcodeproj \
      -scheme GTAFreeSTEM \
      -configuration Release \
      -showBuildSettings 2>/dev/null |
      awk -F'= ' '/CURRENT_PROJECT_VERSION/ {print $2; exit}'
  )"
fi

if [ -z "$BUNDLE_VERSION" ]; then
  echo "Could not determine CURRENT_PROJECT_VERSION. Set BUNDLE_VERSION explicitly."
  exit 1
fi

auth_args=()
if [ -n "${APP_STORE_CONNECT_API_KEY:-}" ] && [ -n "${APP_STORE_CONNECT_API_ISSUER:-}" ]; then
  auth_args+=(--api-key "$APP_STORE_CONNECT_API_KEY" --api-issuer "$APP_STORE_CONNECT_API_ISSUER")
elif [ -n "${APP_STORE_CONNECT_USERNAME:-}" ] && [ -n "${APP_STORE_CONNECT_KEYCHAIN_ITEM:-}" ]; then
  auth_args+=(
    --username "$APP_STORE_CONNECT_USERNAME"
    --password "@keychain:${APP_STORE_CONNECT_KEYCHAIN_ITEM}"
    --provider-public-id "$PROVIDER_PUBLIC_ID"
  )
elif [ -n "${APP_STORE_CONNECT_USERNAME:-}" ] && [ -n "${APP_STORE_CONNECT_APP_PASSWORD:-}" ]; then
  auth_args+=(
    --username "$APP_STORE_CONNECT_USERNAME"
    --password "$APP_STORE_CONNECT_APP_PASSWORD"
    --provider-public-id "$PROVIDER_PUBLIC_ID"
  )
else
  cat <<EOF
Missing App Store Connect authentication.

Use one of these secure options:

1. API key:
   APP_STORE_CONNECT_API_KEY=... APP_STORE_CONNECT_API_ISSUER=... $0

2. App-specific password stored in Keychain:
   xcrun altool --store-password-in-keychain-item GTA_FREE_STEM_ASC \\
     -u rupayon244@gmail.com -p '<app-specific-password>'
   APP_STORE_CONNECT_USERNAME=rupayon244@gmail.com \\
     APP_STORE_CONNECT_KEYCHAIN_ITEM=GTA_FREE_STEM_ASC $0

This script never requires or stores your normal Apple ID password.
EOF
  exit 2
fi

status_args=(--build-status --output-format "$OUTPUT_FORMAT")
if [ "$WAIT_FOR_PROCESSING" != "0" ]; then
  status_args+=(--wait)
fi

if [ -n "$DELIVERY_ID" ]; then
  status_args+=(--delivery-id "$DELIVERY_ID")
else
  status_args+=(
    --apple-id "$APP_APPLE_ID"
    --bundle-version "$BUNDLE_VERSION"
    --bundle-short-version-string "$BUNDLE_SHORT_VERSION"
    --platform "$PLATFORM"
  )
fi

echo "Checking App Store Connect build status for GTA FREE STEM ${BUNDLE_SHORT_VERSION} (${BUNDLE_VERSION})..."
xcrun altool "${status_args[@]}" "${auth_args[@]}"
