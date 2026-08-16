#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

SCREENSHOT_ROOT="${SCREENSHOT_ROOT:-build/app-store-screenshots/final}"
CAPTURE_RECEIPT="${CAPTURE_RECEIPT_PATH:-$SCREENSHOT_ROOT/CAPTURE_RECEIPT.json}"
VISUAL_QA_MANIFEST="${VISUAL_QA_MANIFEST_PATH:-$SCREENSHOT_ROOT/FINAL_VISUAL_QA.md}"
IOS_SCREENSHOT_APP_PATH="${IOS_SCREENSHOT_APP_PATH:-build/DerivedData-app-store-screenshots/Build/Products/Release-iphonesimulator/GTAFreeSTEM.app}"
WATCH_SCREENSHOT_APP_PATH="${WATCH_SCREENSHOT_APP_PATH:-build/DerivedData-app-store-watch-screenshot/Build/Products/Release-watchsimulator/GTAFreeSTEMWatch.app}"
MAC_SCREENSHOT_APP_PATH="${MAC_SCREENSHOT_APP_PATH:-}"
MAC_CAPTURE_SESSION="${MAC_CAPTURE_SESSION_PATH:-$SCREENSHOT_ROOT/MAC_CAPTURE_SESSION.json}"
EXPECTED_VERSION="${EXPECTED_VERSION:-1.0}"
EXPECTED_BUILD="${EXPECTED_BUILD:-12}"
SOURCE_PATHS=(GTAFreeSTEM GTAFreeSTEMWatch GTAFreeSTEM.xcodeproj project.yml)

screenshot_source_tree_sha256() {
  local commit="$1"
  git ls-tree -r -z --full-tree "$commit" -- "${SOURCE_PATHS[@]}" \
    | shasum -a 256 \
    | awk '{print $1}'
}

require_clean_screenshot_source() {
  local commit="$1"
  local expected_tree="$2"
  local current_head
  local current_tree
  local status
  local observed_tree

  if ! [[ "$commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Screenshot source must resolve to a full lowercase 40-character commit." >&2
    exit 1
  fi
  status="$(git status --porcelain=v1 --untracked-files=all -- "${SOURCE_PATHS[@]}")"
  if [ -n "$status" ]; then
    echo "Source tree is not clean for the screenshot build inputs:" >&2
    printf '%s\n' "$status" >&2
    exit 1
  fi
  current_head="$(git rev-parse --verify HEAD)"
  current_tree="$(screenshot_source_tree_sha256 "$current_head")"
  if [ "$current_tree" != "$expected_tree" ] \
    || ! git diff --quiet "$commit" -- "${SOURCE_PATHS[@]}"; then
    echo "Current screenshot source inputs do not match $commit." >&2
    exit 1
  fi
  observed_tree="$(screenshot_source_tree_sha256 "$commit")"
  if [ "$observed_tree" != "$expected_tree" ]; then
    echo "Screenshot source tree hash could not be reproduced from $commit." >&2
    exit 1
  fi
}

require_unchanged_screenshot_source() {
  local expected_commit="$1"
  local expected_tree="$2"
  local current_commit
  local current_tree
  local status

  current_commit="$(git rev-parse --verify HEAD)"
  status="$(git status --porcelain=v1 --untracked-files=all -- "${SOURCE_PATHS[@]}")"
  current_tree="$(screenshot_source_tree_sha256 "$current_commit")"
  if [ "$current_commit" != "$FINALIZER_HEAD_COMMIT" ] \
    || [ -n "$status" ] \
    || [ "$current_tree" != "$expected_tree" ] \
    || ! git diff --quiet "$expected_commit" -- "${SOURCE_PATHS[@]}"; then
    echo "Source tree changed while screenshots were being finalized." >&2
    exit 1
  fi
}

if [ -z "$MAC_SCREENSHOT_APP_PATH" ]; then
  echo "MAC_SCREENSHOT_APP_PATH is required and must point to the exact Release Mac Catalyst app used for the four Mac screenshots." >&2
  exit 1
fi

FINALIZER_HEAD_COMMIT="$(git rev-parse --verify HEAD)"
SOURCE_COMMIT="$(git rev-parse --verify "${SCREENSHOT_SOURCE_COMMIT:-HEAD}^{commit}")"
SOURCE_TREE_SHA256="$(screenshot_source_tree_sha256 "$SOURCE_COMMIT")"
require_clean_screenshot_source "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"

mkdir -p "$SCREENSHOT_ROOT"
RECEIPT_TMP="$(mktemp "$SCREENSHOT_ROOT/.CAPTURE_RECEIPT.XXXXXX")"
trap 'rm -f "$RECEIPT_TMP"' EXIT

/usr/bin/python3 - \
  "$SCREENSHOT_ROOT" \
  "$RECEIPT_TMP" \
  "$SOURCE_COMMIT" \
  "$SOURCE_TREE_SHA256" \
  "$EXPECTED_VERSION" \
  "$EXPECTED_BUILD" \
  "$IOS_SCREENSHOT_APP_PATH" \
  "$WATCH_SCREENSHOT_APP_PATH" \
  "$MAC_SCREENSHOT_APP_PATH" \
  "$MAC_CAPTURE_SESSION" <<'PY'
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
receipt_path = Path(sys.argv[2])
source_commit = sys.argv[3]
source_tree_sha256 = sys.argv[4]
expected_version = sys.argv[5]
expected_build = sys.argv[6]

expected_screenshots = {
    "iphone-6.9/01-home.jpg": (1320, 2868, "ios"),
    "iphone-6.9/02-opportunities.jpg": (1320, 2868, "ios"),
    "iphone-6.9/03-high-school.jpg": (1320, 2868, "ios"),
    "iphone-6.9/04-profile.jpg": (1320, 2868, "ios"),
    "ipad-13/01-home.jpg": (2064, 2752, "ios"),
    "ipad-13/02-opportunities.jpg": (2064, 2752, "ios"),
    "ipad-13/03-high-school.jpg": (2064, 2752, "ios"),
    "ipad-13/04-profile.jpg": (2064, 2752, "ios"),
    "mac/01-home.jpg": (1440, 900, "mac"),
    "mac/02-opportunities.jpg": (1440, 900, "mac"),
    "mac/03-high-school.jpg": (1440, 900, "mac"),
    "mac/04-profile.jpg": (1440, 900, "mac"),
    "watch-series-11/01-home.jpg": (416, 496, "watch"),
}
app_specs = {
    "ios": {
        "path": Path(sys.argv[7]),
        "bundleIdentifier": "com.rupayonhaldar.gtafreestem",
        "infoRelativePath": "Info.plist",
        "executableDirectory": "",
    },
    "watch": {
        "path": Path(sys.argv[8]),
        "bundleIdentifier": "com.rupayonhaldar.gtafreestem.watchkitapp",
        "infoRelativePath": "Info.plist",
        "executableDirectory": "",
    },
    "mac": {
        "path": Path(sys.argv[9]),
        "bundleIdentifier": "com.rupayonhaldar.gtafreestem.maccatalyst",
        "infoRelativePath": "Contents/Info.plist",
        "executableDirectory": "Contents/MacOS",
    },
}
mac_capture_session_path = Path(sys.argv[10])


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sips_property(path, name):
    result = subprocess.run(
        ["sips", "-g", name, str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"Unable to inspect {path} with sips: {result.stderr.strip()}")
    match = re.search(rf"{re.escape(name)}:\s*(.+)", result.stdout)
    return match.group(1).strip() if match else ""


apps = {}
build_mtimes = {}
for label, spec in app_specs.items():
    app_path = spec["path"]
    if app_path.is_symlink() or not app_path.is_dir():
        raise SystemExit(f"Missing regular {label} screenshot app bundle: {app_path}")
    info_path = app_path / spec["infoRelativePath"]
    try:
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        raise SystemExit(f"Unable to read {label} screenshot app metadata: {error}")
    expected_values = {
        "CFBundleIdentifier": spec["bundleIdentifier"],
        "CFBundleShortVersionString": expected_version,
        "CFBundleVersion": expected_build,
        "GTAReleaseSourceCommit": source_commit,
    }
    for key, expected in expected_values.items():
        observed = str(info.get(key, ""))
        if observed != expected:
            raise SystemExit(
                f"{label} screenshot app {key} is {observed or 'blank'}; expected {expected}"
            )
    executable_name = str(info.get("CFBundleExecutable", ""))
    executable = app_path / spec["executableDirectory"] / executable_name
    if not executable_name or executable.is_symlink() or not executable.is_file():
        raise SystemExit(f"Missing regular {label} screenshot app executable: {executable}")
    build_mtimes[label] = max(executable.stat().st_mtime_ns, info_path.stat().st_mtime_ns)
    apps[label] = {
        "bundleIdentifier": spec["bundleIdentifier"],
        "sourceCommit": source_commit,
        "executableSHA256": file_sha256(executable),
        "infoPlistSHA256": file_sha256(info_path),
    }

if mac_capture_session_path.is_symlink() or not mac_capture_session_path.is_file():
    raise SystemExit(
        f"Missing regular Mac capture session: {mac_capture_session_path}; run prepare-mac-screenshot-capture.sh"
    )
try:
    mac_capture_session_bytes = mac_capture_session_path.read_bytes()
    mac_capture_session = json.loads(mac_capture_session_bytes)
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"Unable to read valid Mac capture session: {error}")
if not isinstance(mac_capture_session, dict):
    raise SystemExit("Mac capture session root must be a JSON object")
expected_mac_session = {
    "schema": "GTA-FREE-STEM-MAC-CAPTURE-SESSION-v1",
    "sourceCommit": source_commit,
    "sourceTreeSHA256": source_tree_sha256,
    "appPath": str(app_specs["mac"]["path"].resolve()),
    "bundleIdentifier": app_specs["mac"]["bundleIdentifier"],
    "versionBuild": f"{expected_version} ({expected_build})",
    "executableSHA256": apps["mac"]["executableSHA256"],
    "infoPlistSHA256": apps["mac"]["infoPlistSHA256"],
}
for key, expected in expected_mac_session.items():
    if mac_capture_session.get(key) != expected:
        raise SystemExit(
            f"Mac capture session {key} is {mac_capture_session.get(key) or 'blank'}; expected {expected}"
        )
mac_prepared_at = mac_capture_session.get("preparedAtEpochNanoseconds")
if not isinstance(mac_prepared_at, int) or mac_prepared_at <= 0:
    raise SystemExit("Mac capture session preparedAtEpochNanoseconds must be a positive integer")
build_mtimes["mac"] = max(build_mtimes["mac"], mac_prepared_at)

image_suffixes = {".jpg", ".jpeg", ".png", ".heic", ".tif", ".tiff", ".gif", ".webp"}
package_symlinks = [path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_symlink()]
if package_symlinks:
    raise SystemExit("Screenshot package must not contain symlinks: " + ", ".join(package_symlinks))
actual_images = {
    path.relative_to(root).as_posix()
    for path in root.rglob("*")
    if path.suffix.lower() in image_suffixes and (path.is_file() or path.is_symlink())
}
missing = sorted(set(expected_screenshots) - actual_images)
unexpected = sorted(actual_images - set(expected_screenshots))
if missing:
    raise SystemExit("Missing screenshot files: " + ", ".join(missing))
if unexpected:
    raise SystemExit("Unexpected screenshot files: " + ", ".join(unexpected))

screenshots = []
for relative_path, (width, height, app_label) in expected_screenshots.items():
    screenshot = root / relative_path
    if screenshot.is_symlink() or not screenshot.is_file():
        raise SystemExit(f"Missing regular non-symlink screenshot: {relative_path}")
    if screenshot.stat().st_size < 25000:
        raise SystemExit(f"Screenshot is unexpectedly small: {relative_path}")
    observed_size = (
        int(sips_property(screenshot, "pixelWidth")),
        int(sips_property(screenshot, "pixelHeight")),
    )
    if observed_size != (width, height):
        raise SystemExit(
            f"Screenshot {relative_path} is {observed_size}; expected {(width, height)}"
        )
    if sips_property(screenshot, "format") != "jpeg" or sips_property(screenshot, "hasAlpha") != "no":
        raise SystemExit(f"Screenshot {relative_path} must be an opaque JPEG")
    if screenshot.stat().st_mtime_ns < build_mtimes[app_label]:
        raise SystemExit(
            f"Screenshot {relative_path} predates the exact {app_label} build metadata or executable; recapture it"
        )
    screenshots.append({"path": relative_path, "sha256": file_sha256(screenshot)})

receipt = {
    "schema": "GTA-FREE-STEM-SCREENSHOT-CAPTURE-v1",
    "sourceCommit": source_commit,
    "sourceTreeSHA256": source_tree_sha256,
    "sourceState": "CLEAN",
    "versionBuild": f"{expected_version} ({expected_build})",
    "apps": apps,
    "macCaptureSessionSHA256": hashlib.sha256(mac_capture_session_bytes).hexdigest(),
    "screenshots": screenshots,
    "createdAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
}
receipt_path.write_text(
    json.dumps(receipt, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

require_unchanged_screenshot_source "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"
rm -f -- "$VISUAL_QA_MANIFEST"
mv -f -- "$RECEIPT_TMP" "$CAPTURE_RECEIPT"
trap - EXIT

RECEIPT_SHA256="$(shasum -a 256 "$CAPTURE_RECEIPT" | awk '{print $1}')"
echo "Screenshot capture receipt created: $CAPTURE_RECEIPT"
echo "Source commit: $SOURCE_COMMIT"
echo "Source tree SHA-256: $SOURCE_TREE_SHA256"
echo "Capture receipt SHA-256: $RECEIPT_SHA256"
echo "FINAL_VISUAL_QA.md was invalidated and must be regenerated from the exact received files."
