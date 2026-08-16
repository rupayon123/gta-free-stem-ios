#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

VERIFIER="docs/scripts/verify-screenshot-package.sh"
TEMPLATE="docs/FINAL_VISUAL_QA_TEMPLATE.md"
TMP_DIR="$(mktemp -d -t gtafreestem-screenshot-package.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SOURCE_COMMIT="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SOURCE_TREE_SHA256="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
VALID_ROOT="$TMP_DIR/valid"

/usr/bin/python3 - "$VALID_ROOT" "$TEMPLATE" "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
template = Path(sys.argv[2])
source_commit = sys.argv[3]
source_tree_sha256 = sys.argv[4]
paths = [
    "iphone-6.9/01-home.jpg",
    "iphone-6.9/02-opportunities.jpg",
    "iphone-6.9/03-high-school.jpg",
    "iphone-6.9/04-profile.jpg",
    "ipad-13/01-home.jpg",
    "ipad-13/02-opportunities.jpg",
    "ipad-13/03-high-school.jpg",
    "ipad-13/04-profile.jpg",
    "mac/01-home.jpg",
    "mac/02-opportunities.jpg",
    "mac/03-high-school.jpg",
    "mac/04-profile.jpg",
    "watch-series-11/01-home.jpg",
]
screenshots = []
for relative_path in paths:
    target = root / relative_path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(f"fixture screenshot bytes for {relative_path}\n".encode())
    screenshots.append({
        "path": relative_path,
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    })

mac_capture_session = {
    "schema": "GTA-FREE-STEM-MAC-CAPTURE-SESSION-v1",
    "sourceCommit": source_commit,
    "sourceTreeSHA256": source_tree_sha256,
    "appPath": "/tmp/GTAFreeSTEM.app",
    "bundleIdentifier": "com.rupayonhaldar.gtafreestem.maccatalyst",
    "versionBuild": "1.0 (12)",
    "executableSHA256": "3" * 64,
    "infoPlistSHA256": "6" * 64,
    "preparedAtEpochNanoseconds": 1,
}
mac_session_path = root / "MAC_CAPTURE_SESSION.json"
mac_session_path.write_text(
    json.dumps(mac_capture_session, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

receipt = {
    "schema": "GTA-FREE-STEM-SCREENSHOT-CAPTURE-v1",
    "sourceCommit": source_commit,
    "sourceTreeSHA256": source_tree_sha256,
    "sourceState": "CLEAN",
    "versionBuild": "1.0 (12)",
    "apps": {
        "ios": {
            "bundleIdentifier": "com.rupayonhaldar.gtafreestem",
            "sourceCommit": source_commit,
            "executableSHA256": "1" * 64,
            "infoPlistSHA256": "4" * 64,
        },
        "watch": {
            "bundleIdentifier": "com.rupayonhaldar.gtafreestem.watchkitapp",
            "sourceCommit": source_commit,
            "executableSHA256": "2" * 64,
            "infoPlistSHA256": "5" * 64,
        },
        "mac": {
            "bundleIdentifier": "com.rupayonhaldar.gtafreestem.maccatalyst",
            "sourceCommit": source_commit,
            "executableSHA256": "3" * 64,
            "infoPlistSHA256": "6" * 64,
        },
    },
    "macCaptureSessionSHA256": hashlib.sha256(mac_session_path.read_bytes()).hexdigest(),
    "screenshots": screenshots,
    "createdAt": "2026-08-06T20:00:00Z",
}
receipt_path = root / "CAPTURE_RECEIPT.json"
receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
receipt_sha = hashlib.sha256(receipt_path.read_bytes()).hexdigest()

manifest = template.read_text(encoding="utf-8")
replacements = {
    "- Approval status: `PENDING`": "- Approval status: `PASS`",
    "- Published commit: `REPLACE_WITH_40_CHARACTER_LOWERCASE_COMMIT`": f"- Published commit: `{source_commit}`",
    "- Capture receipt SHA-256: `REPLACE_WITH_64_CHARACTER_LOWERCASE_SHA256`": f"- Capture receipt SHA-256: `{receipt_sha}`",
    "- Reviewer:": "- Reviewer: `Release QA`",
    "- Reviewed on: `YYYY-MM-DD`": "- Reviewed on: `2026-08-06`",
}
for old, new in replacements.items():
    if manifest.count(old) != 1:
        raise SystemExit(f"Expected exactly one manifest placeholder: {old}")
    manifest = manifest.replace(old, new, 1)
for row in screenshots:
    old = f"| {row['path']} | REPLACE_WITH_64_CHARACTER_LOWERCASE_SHA256 |"
    if manifest.count(old) != 1:
        raise SystemExit(f"Expected exactly one screenshot row: {row['path']}")
    manifest = manifest.replace(old, f"| {row['path']} | {row['sha256']} |", 1)
(root / "FINAL_VISUAL_QA.md").write_text(manifest, encoding="utf-8")
PY

run_fixture() {
  local root="$1"
  SCREENSHOT_PACKAGE_TEST_FIXTURE_ONLY=1 \
    SCREENSHOT_PACKAGE_TEST_SOURCE_COMMIT="$SOURCE_COMMIT" \
    SCREENSHOT_PACKAGE_TEST_SOURCE_TREE_SHA256="$SOURCE_TREE_SHA256" \
    SCREENSHOT_ROOT="$root" \
    CAPTURE_RECEIPT_PATH="$root/CAPTURE_RECEIPT.json" \
    VISUAL_QA_MANIFEST_PATH="$root/FINAL_VISUAL_QA.md" \
    bash "$VERIFIER"
}

PASS_OUTPUT="$TMP_DIR/pass-output.txt"
run_fixture "$VALID_ROOT" >"$PASS_OUTPUT"
rg -Fq "SCREENSHOT_PACKAGE_FIXTURE_PASS_NOT_RELEASE_SIGNOFF" "$PASS_OUTPUT" || {
  echo "Screenshot verifier fixture success did not use the non-release sentinel."
  exit 1
}

expect_fail() {
  local root="$1"
  local expected="$2"
  local output="$TMP_DIR/fail-output.txt"
  if run_fixture "$root" >"$output" 2>&1; then
    echo "Expected screenshot package verifier to fail."
    exit 1
  fi
  rg -Fq "$expected" "$output" || {
    echo "Expected screenshot package error missing: $expected"
    sed -n '1,160p' "$output"
    exit 1
  }
}

MISSING_ROOT="$TMP_DIR/missing"
cp -R "$VALID_ROOT" "$MISSING_ROOT"
rm -f "$MISSING_ROOT/watch-series-11/01-home.jpg"
expect_fail "$MISSING_ROOT" "Screenshot package paths mismatch; missing=watch-series-11/01-home.jpg"

MUTATED_ROOT="$TMP_DIR/mutated"
cp -R "$VALID_ROOT" "$MUTATED_ROOT"
printf '%s\n' "post-receipt mutation" >> "$MUTATED_ROOT/iphone-6.9/01-home.jpg"
expect_fail "$MUTATED_ROOT" "Screenshot hash mismatch for iphone-6.9/01-home.jpg"

RECEIPT_ROOT="$TMP_DIR/receipt-mutated"
cp -R "$VALID_ROOT" "$RECEIPT_ROOT"
printf '%s\n' " " >> "$RECEIPT_ROOT/CAPTURE_RECEIPT.json"
expect_fail "$RECEIPT_ROOT" "Capture receipt hash mismatch"

MISSING_RECEIPT_ROOT="$TMP_DIR/missing-receipt"
cp -R "$VALID_ROOT" "$MISSING_RECEIPT_ROOT"
rm -f "$MISSING_RECEIPT_ROOT/CAPTURE_RECEIPT.json"
expect_fail "$MISSING_RECEIPT_ROOT" "Capture receipt: missing regular non-symlink file"

MISSING_SESSION_ROOT="$TMP_DIR/missing-session"
cp -R "$VALID_ROOT" "$MISSING_SESSION_ROOT"
rm -f "$MISSING_SESSION_ROOT/MAC_CAPTURE_SESSION.json"
expect_fail "$MISSING_SESSION_ROOT" "Mac capture session: missing regular non-symlink file"

MUTATED_SESSION_ROOT="$TMP_DIR/mutated-session"
cp -R "$VALID_ROOT" "$MUTATED_SESSION_ROOT"
printf '%s\n' " " >> "$MUTATED_SESSION_ROOT/MAC_CAPTURE_SESSION.json"
expect_fail "$MUTATED_SESSION_ROOT" "Mac capture session hash mismatch"

ROGUE_IMAGE_ROOT="$TMP_DIR/rogue-image"
cp -R "$VALID_ROOT" "$ROGUE_IMAGE_ROOT"
printf '%s\n' "unexpected image" > "$ROGUE_IMAGE_ROOT/mac/extra.png"
expect_fail "$ROGUE_IMAGE_ROOT" "unexpected=mac/extra.png"

echo "Screenshot package verifier self-test passed."
