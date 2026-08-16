#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

/usr/bin/python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import plistlib
import re
import sys

root = Path(sys.argv[1])
workflow = (root / ".github/workflows/ios-release-readiness.yml").read_text()
status_script = (root / "docs/scripts/check-testflight-build-status.sh").read_text()
readiness_script = (root / "docs/scripts/check-release-readiness.sh").read_text()
ci_readiness_script = (root / "docs/scripts/check-ci-release-readiness.sh").read_text()
device_install_script = (root / "docs/scripts/install-connected-device.sh").read_text()
safe_export_options = plistlib.loads(
    (root / "docs/AppStoreExportOptions.plist").read_bytes()
)
upload_export_options = plistlib.loads(
    (root / "docs/AppStoreConnectExportOptions.plist").read_bytes()
)

if not re.search(r"(?m)^permissions:\n  contents: read$", workflow):
    raise SystemExit("Release workflow must declare top-level contents: read permission.")

checkout = re.search(r"uses: actions/checkout@([^\s#]+)", workflow)
if not checkout or not re.fullmatch(r"[0-9a-f]{40}", checkout.group(1)):
    raise SystemExit("actions/checkout must be pinned to a full 40-character commit SHA.")

required_auth = (
    '--password "@env:APP_STORE_CONNECT_APP_PASSWORD"',
    '--password "@keychain:${APP_STORE_CONNECT_KEYCHAIN_ITEM}"',
)
for fragment in required_auth:
    if fragment not in status_script:
        raise SystemExit(f"Missing secure altool credential indirection: {fragment}")

for forbidden in (
    '--password "$APP_STORE_CONNECT_APP_PASSWORD"',
    "find-generic-password",
    "keychain_password_file",
):
    if forbidden in status_script:
        raise SystemExit(f"Release script still exposes credential material: {forbidden}")

project_guard = readiness_script.find('[ -f project.yml ] || { echo "Missing project.yml"; exit 1; }')
pbx_guard = readiness_script.find('[ -f "$PBXPROJ" ] || { echo "Missing $PBXPROJ"; exit 1; }')
identity_scan = readiness_script.find("if rg -n 'CODE_SIGN_IDENTITY' project.yml \"$PBXPROJ\"; then")
if min(project_guard, pbx_guard, identity_scan) < 0 or not (
    project_guard < identity_scan and pbx_guard < identity_scan
):
    raise SystemExit(
        "Release readiness must require both signing source files before scanning for fixed identities."
    )

for fragment in (
    'GTA_RELEASE_SOURCE_COMMIT: UNSET',
    'GTAReleaseSourceCommit',
    '"GTA_RELEASE_SOURCE_COMMIT=$SOURCE_COMMIT"',
):
    if fragment not in readiness_script and fragment not in device_install_script:
        raise SystemExit(f"Release source-commit provenance guard is missing: {fragment}")
if 'git diff --quiet "$SOURCE_COMMIT"' not in device_install_script:
    raise SystemExit("Connected-device installs must reject source bytes that do not match the embedded commit.")

if 'CHECK_PUBLIC_SUPPORT_CONTACT="${CHECK_PUBLIC_SUPPORT_CONTACT:-1}"' not in readiness_script:
    raise SystemExit("Public support-contact verification must remain enabled by default.")
if 'CHECK_PUBLIC_SUPPORT_CONTACT=0' not in ci_readiness_script:
    raise SystemExit("CI must explicitly defer the release-owner support-contact check.")

if safe_export_options.get("destination") != "export":
    raise SystemExit("The local App Store export options must never upload during verification.")
if upload_export_options.get("destination") != "upload":
    raise SystemExit("The App Store Connect export options must remain explicitly upload-only.")
for name, options in (
    ("safe export", safe_export_options),
    ("upload export", upload_export_options),
):
    if options.get("method") != "app-store-connect":
        raise SystemExit(f"{name} must use the app-store-connect export method.")
    if options.get("signingStyle") != "automatic":
        raise SystemExit(f"{name} must use automatic signing.")
    if options.get("teamID") != "FE33NM88XX":
        raise SystemExit(f"{name} must use Apple team FE33NM88XX.")
    if options.get("manageAppVersionAndBuildNumber") is not False:
        raise SystemExit(f"{name} must preserve the verified source build number.")

print("Release security controls passed.")
PY
