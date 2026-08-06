#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

/usr/bin/python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
workflow = (root / ".github/workflows/ios-release-readiness.yml").read_text()
status_script = (root / "docs/scripts/check-testflight-build-status.sh").read_text()

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

print("Release security controls passed.")
PY
