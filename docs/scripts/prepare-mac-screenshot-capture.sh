#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

PROJECT="GTAFreeSTEM.xcodeproj"
SCHEME="GTAFreeSTEM"
CONFIGURATION="Release"
DESTINATION="platform=macOS,variant=Mac Catalyst,name=My Mac"
SCREENSHOT_ROOT="${SCREENSHOT_ROOT:-build/app-store-screenshots/final}"
MAC_OUTPUT_DIR="$SCREENSHOT_ROOT/mac"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData-app-store-mac-screenshots}"
MAC_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release-maccatalyst/GTAFreeSTEM.app"
CAPTURE_SESSION="$SCREENSHOT_ROOT/MAC_CAPTURE_SESSION.json"
CAPTURE_RECEIPT="$SCREENSHOT_ROOT/CAPTURE_RECEIPT.json"
VISUAL_QA_MANIFEST="$SCREENSHOT_ROOT/FINAL_VISUAL_QA.md"
CONTACT_SHEET="$SCREENSHOT_ROOT/contact-sheet.jpg"
SOURCE_PATHS=(GTAFreeSTEM GTAFreeSTEMWatch GTAFreeSTEM.xcodeproj project.yml)

screenshot_source_tree_sha256() {
  local commit="$1"
  git ls-tree -r -z --full-tree "$commit" -- "${SOURCE_PATHS[@]}" \
    | shasum -a 256 \
    | awk '{print $1}'
}

require_clean_source_match() {
  local source_commit="$1"
  local expected_tree="$2"
  local status
  local current_tree

  status="$(git status --porcelain=v1 --untracked-files=all -- "${SOURCE_PATHS[@]}")"
  if [ -n "$status" ]; then
    echo "Source tree is not clean for the Mac screenshot build inputs:" >&2
    printf '%s\n' "$status" >&2
    exit 1
  fi
  current_tree="$(screenshot_source_tree_sha256 HEAD)"
  if [ "$current_tree" != "$expected_tree" ] \
    || ! git diff --quiet "$source_commit" -- "${SOURCE_PATHS[@]}"; then
    echo "Current Mac screenshot source inputs do not match $source_commit." >&2
    exit 1
  fi
}

require_unchanged_source() {
  local source_commit="$1"
  local expected_tree="$2"
  if [ "$(git rev-parse --verify HEAD)" != "$PREPARE_HEAD_COMMIT" ]; then
    echo "Source tree changed while the Mac screenshot app was being prepared." >&2
    exit 1
  fi
  require_clean_source_match "$source_commit" "$expected_tree"
}

PREPARE_HEAD_COMMIT="$(git rev-parse --verify HEAD)"
SOURCE_COMMIT="$(git rev-parse --verify "${SCREENSHOT_SOURCE_COMMIT:-HEAD}^{commit}")"
if ! [[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Mac screenshot source must resolve to a full lowercase 40-character commit." >&2
  exit 1
fi
SOURCE_TREE_SHA256="$(screenshot_source_tree_sha256 "$SOURCE_COMMIT")"
require_clean_source_match "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"

mkdir -p "$MAC_OUTPUT_DIR"
rm -f -- \
  "$CAPTURE_SESSION" \
  "$CAPTURE_RECEIPT" \
  "$VISUAL_QA_MANIFEST" \
  "$CONTACT_SHEET" \
  "$MAC_OUTPUT_DIR/01-home.jpg" \
  "$MAC_OUTPUT_DIR/02-opportunities.jpg" \
  "$MAC_OUTPUT_DIR/03-high-school.jpg" \
  "$MAC_OUTPUT_DIR/04-profile.jpg"

echo "Building the source-bound Release Mac Catalyst screenshot app..."
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "GTA_RELEASE_SOURCE_COMMIT=$SOURCE_COMMIT" >/dev/null

SESSION_TMP="$(mktemp "$SCREENSHOT_ROOT/.MAC_CAPTURE_SESSION.XXXXXX")"
trap 'rm -f "$SESSION_TMP"' EXIT

/usr/bin/python3 - \
  "$MAC_APP_PATH" \
  "$SESSION_TMP" \
  "$SOURCE_COMMIT" \
  "$SOURCE_TREE_SHA256" <<'PY'
import hashlib
import json
import plistlib
import sys
import time
from pathlib import Path

raw_app_path = Path(sys.argv[1])
app_path = raw_app_path.resolve()
session_path = Path(sys.argv[2])
source_commit = sys.argv[3]
source_tree_sha256 = sys.argv[4]
info_path = app_path / "Contents/Info.plist"


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


if raw_app_path.is_symlink() or not raw_app_path.is_dir():
    raise SystemExit(f"Missing regular Mac screenshot app bundle: {raw_app_path}")
try:
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
except (OSError, plistlib.InvalidFileException) as error:
    raise SystemExit(f"Unable to read Mac screenshot app metadata: {error}")
expected = {
    "CFBundleIdentifier": "com.rupayonhaldar.gtafreestem.maccatalyst",
    "CFBundleShortVersionString": "1.0",
    "CFBundleVersion": "12",
    "GTAReleaseSourceCommit": source_commit,
}
for key, value in expected.items():
    observed = str(info.get(key, ""))
    if observed != value:
        raise SystemExit(f"Mac screenshot app {key} is {observed or 'blank'}; expected {value}")
executable = app_path / "Contents/MacOS" / str(info.get("CFBundleExecutable", ""))
if executable.is_symlink() or not executable.is_file():
    raise SystemExit(f"Missing regular Mac screenshot executable: {executable}")

session = {
    "schema": "GTA-FREE-STEM-MAC-CAPTURE-SESSION-v1",
    "sourceCommit": source_commit,
    "sourceTreeSHA256": source_tree_sha256,
    "appPath": str(app_path),
    "bundleIdentifier": expected["CFBundleIdentifier"],
    "versionBuild": "1.0 (12)",
    "executableSHA256": file_sha256(executable),
    "infoPlistSHA256": file_sha256(info_path),
    "preparedAtEpochNanoseconds": time.time_ns(),
}
session_path.write_text(json.dumps(session, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

require_unchanged_source "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"
mv -f -- "$SESSION_TMP" "$CAPTURE_SESSION"
trap - EXIT

open -na "$MAC_APP_PATH"

echo "Mac screenshot session prepared: $CAPTURE_SESSION"
echo "The four previous Mac JPEGs were removed. Capture all four 1440 x 900 images from this exact app, then run the receipt finalizer."
