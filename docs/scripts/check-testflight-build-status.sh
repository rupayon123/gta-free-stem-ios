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
KEYCHAIN_SECRET_TIMEOUT="${APP_STORE_CONNECT_KEYCHAIN_SECRET_TIMEOUT:-8}"

case "$KEYCHAIN_SECRET_TIMEOUT" in
  ''|*[!0-9]*) KEYCHAIN_SECRET_TIMEOUT=8 ;;
esac

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
elif [ -n "${APP_STORE_CONNECT_USERNAME:-}" ] && [ -n "${APP_STORE_CONNECT_APP_PASSWORD:-}" ]; then
  auth_args+=(
    --username "$APP_STORE_CONNECT_USERNAME"
    --password "$APP_STORE_CONNECT_APP_PASSWORD"
    --provider-public-id "$PROVIDER_PUBLIC_ID"
  )
elif [ -n "${APP_STORE_CONNECT_USERNAME:-}" ] && [ -n "${APP_STORE_CONNECT_KEYCHAIN_ITEM:-}" ]; then
  keychain_password=""
  keychain_status=1
  keychain_password_file="$(mktemp -t gtafreestem-keychain-password.XXXXXX)"
  keychain_status_file="$(mktemp -t gtafreestem-keychain-status.XXXXXX)"
  keychain_pid=""
  cleanup_keychain_read() {
    if [ -n "${keychain_pid:-}" ] && kill -0 "$keychain_pid" 2>/dev/null; then
      kill "$keychain_pid" 2>/dev/null || true
      wait "$keychain_pid" 2>/dev/null || true
    fi
    rm -f "$keychain_password_file" "$keychain_status_file"
  }
  trap cleanup_keychain_read INT TERM EXIT
  (
    set +e
    security find-generic-password \
      -a "$APP_STORE_CONNECT_USERNAME" \
      -l "$APP_STORE_CONNECT_KEYCHAIN_ITEM" \
      -w >"$keychain_password_file" 2>/dev/null
    echo $? >"$keychain_status_file"
  ) &
  keychain_pid=$!
  keychain_waited=0
  while kill -0 "$keychain_pid" 2>/dev/null; do
    if [ "$KEYCHAIN_SECRET_TIMEOUT" -gt 0 ] && [ "$keychain_waited" -ge "$KEYCHAIN_SECRET_TIMEOUT" ]; then
      kill "$keychain_pid" 2>/dev/null || true
      wait "$keychain_pid" 2>/dev/null || true
      echo "Timed out reading Keychain secret after ${KEYCHAIN_SECRET_TIMEOUT}s; trying altool's @keychain lookup." >&2
      break
    fi
    sleep 1
    keychain_waited=$((keychain_waited + 1))
  done
  if ! kill -0 "$keychain_pid" 2>/dev/null; then
    wait "$keychain_pid" 2>/dev/null || true
  fi
  if [ -s "$keychain_status_file" ]; then
    keychain_status="$(cat "$keychain_status_file")"
  fi
  if [ "$keychain_status" = "0" ]; then
    keychain_password="$(cat "$keychain_password_file")"
  fi
  cleanup_keychain_read
  trap - INT TERM EXIT

  if [ -n "$keychain_password" ]; then
    export APP_STORE_CONNECT_RESOLVED_PASSWORD="$keychain_password"
    trap 'unset APP_STORE_CONNECT_RESOLVED_PASSWORD' EXIT
    auth_args+=(
      --username "$APP_STORE_CONNECT_USERNAME"
      --password "@env:APP_STORE_CONNECT_RESOLVED_PASSWORD"
      --provider-public-id "$PROVIDER_PUBLIC_ID"
    )
  else
    auth_args+=(
      --username "$APP_STORE_CONNECT_USERNAME"
      --password "@keychain:${APP_STORE_CONNECT_KEYCHAIN_ITEM}"
      --provider-public-id "$PROVIDER_PUBLIC_ID"
    )
  fi
  unset -f cleanup_keychain_read
  unset keychain_password keychain_status keychain_pid keychain_waited keychain_password_file keychain_status_file
else
  cat <<EOF
Missing App Store Connect authentication.

Use one of these secure options:

1. API key:
   APP_STORE_CONNECT_API_KEY=... APP_STORE_CONNECT_API_ISSUER=... $0

2. App-specific password stored in Keychain:
   xcrun altool --store-password-in-keychain-item --item GTA_FREE_STEM_ASC \\
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
