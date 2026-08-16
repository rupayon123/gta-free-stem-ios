#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

SCREENSHOT_ROOT="${SCREENSHOT_ROOT:-build/app-store-screenshots/final}"
CAPTURE_RECEIPT="${CAPTURE_RECEIPT_PATH:-$SCREENSHOT_ROOT/CAPTURE_RECEIPT.json}"
VISUAL_QA_MANIFEST="${VISUAL_QA_MANIFEST_PATH:-$SCREENSHOT_ROOT/FINAL_VISUAL_QA.md}"
MAC_CAPTURE_SESSION="${MAC_CAPTURE_SESSION_PATH:-$SCREENSHOT_ROOT/MAC_CAPTURE_SESSION.json}"
FIXTURE_ONLY="${SCREENSHOT_PACKAGE_TEST_FIXTURE_ONLY:-0}"

if [ "$FIXTURE_ONLY" = "1" ]; then
  if ! [[ "${SCREENSHOT_PACKAGE_TEST_SOURCE_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Fixture verifier requires SCREENSHOT_PACKAGE_TEST_SOURCE_COMMIT." >&2
    exit 1
  fi
  if ! [[ "${SCREENSHOT_PACKAGE_TEST_SOURCE_TREE_SHA256:-}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Fixture verifier requires SCREENSHOT_PACKAGE_TEST_SOURCE_TREE_SHA256." >&2
    exit 1
  fi
elif [ "$FIXTURE_ONLY" != "0" ]; then
  echo "SCREENSHOT_PACKAGE_TEST_FIXTURE_ONLY must be 0 or 1." >&2
  exit 1
fi

/usr/bin/python3 - \
  "$SCREENSHOT_ROOT" \
  "$CAPTURE_RECEIPT" \
  "$VISUAL_QA_MANIFEST" \
  "$MAC_CAPTURE_SESSION" \
  "$FIXTURE_ONLY" <<'PY'
import hashlib
import json
import os
import re
import subprocess
import sys
import datetime as dt
from pathlib import Path

root = Path(sys.argv[1])
receipt_path = Path(sys.argv[2])
manifest_path = Path(sys.argv[3])
mac_capture_session_path = Path(sys.argv[4])
fixture_only = sys.argv[5] == "1"
source_paths = ["GTAFreeSTEM", "GTAFreeSTEMWatch", "GTAFreeSTEM.xcodeproj", "project.yml"]
expected_paths = [
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
expected_dimensions = {
    **{path: (1320, 2868) for path in expected_paths if path.startswith("iphone-")},
    **{path: (2064, 2752) for path in expected_paths if path.startswith("ipad-")},
    **{path: (1440, 900) for path in expected_paths if path.startswith("mac/")},
    "watch-series-11/01-home.jpg": (416, 496),
}


def fail(message):
    raise SystemExit(message)


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(command, *, binary=False):
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=not binary,
        check=False,
    )


def git_source_tree_sha256(commit):
    result = run(
        ["git", "ls-tree", "-r", "-z", "--full-tree", commit, "--", *source_paths],
        binary=True,
    )
    if result.returncode != 0:
        fail(f"Screenshot source commit is unavailable: {commit}")
    return hashlib.sha256(result.stdout).hexdigest()


if receipt_path.is_symlink() or not receipt_path.is_file():
    fail(f"Capture receipt: missing regular non-symlink file {receipt_path}")
try:
    receipt_bytes = receipt_path.read_bytes()
    receipt = json.loads(receipt_bytes)
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    fail(f"Capture receipt: unable to read valid JSON from {receipt_path}: {error}")
if not isinstance(receipt, dict):
    fail("Capture receipt: root must be a JSON object")
if receipt.get("schema") != "GTA-FREE-STEM-SCREENSHOT-CAPTURE-v1":
    fail("Capture receipt: schema must be GTA-FREE-STEM-SCREENSHOT-CAPTURE-v1")
source_commit = receipt.get("sourceCommit")
source_tree_sha256 = receipt.get("sourceTreeSHA256")
if not isinstance(source_commit, str) or not re.fullmatch(r"[0-9a-f]{40}", source_commit):
    fail("Capture receipt: sourceCommit must be a full lowercase commit")
if not isinstance(source_tree_sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", source_tree_sha256):
    fail("Capture receipt: sourceTreeSHA256 must be a full lowercase SHA-256")
if receipt.get("sourceState") != "CLEAN":
    fail("Capture receipt: sourceState must be CLEAN")
if receipt.get("versionBuild") != "1.0 (12)":
    fail("Capture receipt: versionBuild must be 1.0 (12)")

if fixture_only:
    expected_source_commit = os.environ["SCREENSHOT_PACKAGE_TEST_SOURCE_COMMIT"]
    expected_source_tree = os.environ["SCREENSHOT_PACKAGE_TEST_SOURCE_TREE_SHA256"]
else:
    status = run(
        ["git", "status", "--porcelain=v1", "--untracked-files=all", "--", *source_paths]
    )
    if status.returncode != 0:
        fail("Source tree cleanliness could not be inspected")
    if status.stdout.strip():
        fail("Source tree is not clean for the screenshot build inputs")
    expected_source_commit = source_commit
    expected_source_tree = git_source_tree_sha256(source_commit)
    head = run(["git", "rev-parse", "--verify", "HEAD"])
    if head.returncode != 0:
        fail("Current source commit could not be resolved")
    current_tree = git_source_tree_sha256(head.stdout.strip())
    source_diff = run(["git", "diff", "--quiet", source_commit, "--", *source_paths])
    if source_diff.returncode != 0 or current_tree != expected_source_tree:
        fail("Current source inputs do not match the screenshot capture source commit")

if source_commit != expected_source_commit:
    fail(
        f"Capture receipt source commit mismatch: expected {expected_source_commit}, got {source_commit}"
    )
if source_tree_sha256 != expected_source_tree:
    fail(
        f"Capture receipt source tree mismatch: expected {expected_source_tree}, got {source_tree_sha256}"
    )

apps = receipt.get("apps")
expected_apps = {
    "ios": "com.rupayonhaldar.gtafreestem",
    "watch": "com.rupayonhaldar.gtafreestem.watchkitapp",
    "mac": "com.rupayonhaldar.gtafreestem.maccatalyst",
}
if not isinstance(apps, dict) or set(apps) != set(expected_apps):
    fail("Capture receipt: apps must contain exactly ios, watch, and mac")
for label, bundle_id in expected_apps.items():
    app = apps[label]
    if not isinstance(app, dict):
        fail(f"Capture receipt: {label} app record must be an object")
    if app.get("bundleIdentifier") != bundle_id:
        fail(f"Capture receipt: {label} bundle identifier mismatch")
    if app.get("sourceCommit") != source_commit:
        fail(f"Capture receipt: {label} source commit mismatch")
    if not re.fullmatch(r"[0-9a-f]{64}", str(app.get("executableSHA256", ""))):
        fail(f"Capture receipt: {label} executable SHA-256 is invalid")
    if not re.fullmatch(r"[0-9a-f]{64}", str(app.get("infoPlistSHA256", ""))):
        fail(f"Capture receipt: {label} Info.plist SHA-256 is invalid")

recorded_mac_session_hash = receipt.get("macCaptureSessionSHA256")
if not isinstance(recorded_mac_session_hash, str) or not re.fullmatch(
    r"[0-9a-f]{64}", recorded_mac_session_hash
):
    fail("Capture receipt: macCaptureSessionSHA256 must be a full lowercase SHA-256")
if mac_capture_session_path.is_symlink() or not mac_capture_session_path.is_file():
    fail(f"Mac capture session: missing regular non-symlink file {mac_capture_session_path}")
try:
    mac_capture_session_bytes = mac_capture_session_path.read_bytes()
    mac_capture_session = json.loads(mac_capture_session_bytes)
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    fail(f"Mac capture session: unable to read valid JSON: {error}")
actual_mac_session_hash = hashlib.sha256(mac_capture_session_bytes).hexdigest()
if actual_mac_session_hash != recorded_mac_session_hash:
    fail(
        f"Mac capture session hash mismatch: receipt records {recorded_mac_session_hash}, current session is {actual_mac_session_hash}"
    )
if not isinstance(mac_capture_session, dict):
    fail("Mac capture session: root must be a JSON object")
expected_mac_session = {
    "schema": "GTA-FREE-STEM-MAC-CAPTURE-SESSION-v1",
    "sourceCommit": source_commit,
    "sourceTreeSHA256": source_tree_sha256,
    "bundleIdentifier": expected_apps["mac"],
    "versionBuild": "1.0 (12)",
    "executableSHA256": apps["mac"]["executableSHA256"],
    "infoPlistSHA256": apps["mac"]["infoPlistSHA256"],
}
for key, expected in expected_mac_session.items():
    if mac_capture_session.get(key) != expected:
        fail(f"Mac capture session: {key} mismatch")
if not Path(str(mac_capture_session.get("appPath", ""))).is_absolute():
    fail("Mac capture session: appPath must be absolute")
prepared_at = mac_capture_session.get("preparedAtEpochNanoseconds")
if not isinstance(prepared_at, int) or prepared_at <= 0:
    fail("Mac capture session: preparedAtEpochNanoseconds must be a positive integer")

receipt_rows = receipt.get("screenshots")
if not isinstance(receipt_rows, list) or len(receipt_rows) != len(expected_paths):
    fail(f"Capture receipt: expected exactly {len(expected_paths)} screenshots")
receipt_hashes = {}
for row in receipt_rows:
    if not isinstance(row, dict):
        fail("Capture receipt: screenshot rows must be objects")
    relative_path = row.get("path")
    digest = row.get("sha256")
    if relative_path in receipt_hashes:
        fail(f"Capture receipt: duplicate screenshot path {relative_path}")
    if relative_path not in expected_paths:
        fail(f"Capture receipt: unexpected screenshot path {relative_path}")
    if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
        fail(f"Capture receipt: invalid screenshot hash for {relative_path}")
    receipt_hashes[relative_path] = digest
if list(receipt_hashes) != expected_paths:
    fail("Capture receipt: screenshot rows must use the canonical path order")

if manifest_path.is_symlink() or not manifest_path.is_file():
    fail(f"Visual QA manifest: missing {manifest_path}")
try:
    manifest_text = manifest_path.read_text(encoding="utf-8")
except (OSError, UnicodeError) as error:
    fail(f"Visual QA manifest: unable to read {manifest_path}: {error}")


def manifest_field(label):
    matches = re.findall(rf"^- {re.escape(label)}:[ \t]*(.*)$", manifest_text, re.MULTILINE)
    if len(matches) != 1:
        fail(f"Visual QA manifest Approval: expected exactly one '{label}' field, found {len(matches)}")
    return matches[0].strip().strip("`").strip()


manifest_commit = manifest_field("Published commit")
if manifest_commit != source_commit:
    fail(
        f"Visual QA manifest Published commit: expected exact value {source_commit}, got {manifest_commit or 'blank'}"
    )
recorded_receipt_hash = manifest_field("Capture receipt SHA-256")
actual_receipt_hash = hashlib.sha256(receipt_bytes).hexdigest()
if recorded_receipt_hash != actual_receipt_hash:
    fail(
        f"Capture receipt hash mismatch: manifest records {recorded_receipt_hash or 'blank'}, current receipt is {actual_receipt_hash}"
    )
exact_manifest_fields = {
    "Manifest schema": "GTA-FREE-STEM-FINAL-VISUAL-QA-v1",
    "Approval status": "PASS",
    "Review scope": "FULL_SIZE_ALL_13_NO_KNOWN_DEFECTS",
    "Version/build": "1.0 (12)",
    "Screenshot count": str(len(expected_paths)),
}
for label, required in exact_manifest_fields.items():
    value = manifest_field(label)
    if value != required:
        fail(
            f"Visual QA manifest {label}: expected exact value {required}, got {value or 'blank'}"
        )
reviewer = manifest_field("Reviewer")
if not reviewer or re.match(
    r"^(?:pending|no|not|none|unreviewed|unknown|nobody)\b",
    reviewer.lower(),
):
    fail("Visual QA manifest Reviewer: blank or pending")
reviewed_on = manifest_field("Reviewed on")
try:
    reviewed_date = dt.date.fromisoformat(reviewed_on)
except ValueError:
    fail("Visual QA manifest Reviewed on: use YYYY-MM-DD")
if reviewed_date > dt.date.today():
    fail("Visual QA manifest Reviewed on: date cannot be in the future")

approved_match = re.search(
    r"^## Approved Files\s*$\n(.*?)(?=^## |\Z)",
    manifest_text,
    re.MULTILINE | re.DOTALL,
)
if not approved_match:
    fail("Visual QA manifest Approved Files: missing section")
manifest_hashes = {}
for line in approved_match.group(1).splitlines():
    if not line.startswith("|") or "---" in line:
        continue
    cells = [cell.strip() for cell in line.strip("|").split("|")]
    if cells == ["Relative path", "SHA-256"]:
        continue
    if len(cells) != 2:
        fail("Visual QA manifest Approved Files: malformed table row")
    relative_path, digest = cells
    if relative_path in manifest_hashes:
        fail(f"Visual QA manifest Approved Files: duplicate path {relative_path}")
    manifest_hashes[relative_path] = digest
if list(manifest_hashes) != expected_paths:
    fail("Visual QA manifest Approved Files: paths must match the canonical 13-file order")

image_suffixes = {".jpg", ".jpeg", ".png", ".heic", ".tif", ".tiff", ".gif", ".webp"}
package_symlinks = [path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_symlink()]
if package_symlinks:
    fail("Screenshot package must not contain symlinks: " + ", ".join(package_symlinks))
actual_images = {
    path.relative_to(root).as_posix()
    for path in root.rglob("*")
    if path.suffix.lower() in image_suffixes and (path.is_file() or path.is_symlink())
}
if actual_images != set(expected_paths):
    missing = sorted(set(expected_paths) - actual_images)
    unexpected = sorted(actual_images - set(expected_paths))
    fail(
        "Screenshot package paths mismatch; missing={} unexpected={}".format(
            ",".join(missing) or "none", ",".join(unexpected) or "none"
        )
    )

for relative_path in expected_paths:
    screenshot = root / relative_path
    if screenshot.is_symlink() or not screenshot.is_file():
        fail(f"Visual QA screenshot {relative_path}: missing regular non-symlink file")
    actual_hash = file_sha256(screenshot)
    if receipt_hashes[relative_path] != actual_hash:
        fail(
            f"Visual QA screenshot {relative_path}: SHA-256 mismatch; "
            f"Screenshot hash mismatch for {relative_path}: receipt records "
            f"{receipt_hashes[relative_path]}, current file is {actual_hash}"
        )
    if manifest_hashes[relative_path] != actual_hash:
        fail(
            f"Visual QA screenshot {relative_path}: SHA-256 mismatch; manifest records {manifest_hashes[relative_path]}, current file is {actual_hash}"
        )

canonical_lines = [
    "# Final Screenshot Visual QA",
    "",
    "## Approval",
    "",
    "- Manifest schema: `GTA-FREE-STEM-FINAL-VISUAL-QA-v1`",
    "- Approval status: `PASS`",
    "- Review scope: `FULL_SIZE_ALL_13_NO_KNOWN_DEFECTS`",
    "- Version/build: `1.0 (12)`",
    f"- Published commit: `{source_commit}`",
    f"- Capture receipt SHA-256: `{recorded_receipt_hash}`",
    f"- Reviewer: `{reviewer}`",
    f"- Reviewed on: `{reviewed_on}`",
    f"- Screenshot count: `{len(expected_paths)}`",
    "",
    "## Approved Files",
    "",
    "| Relative path | SHA-256 |",
    "| --- | --- |",
]
for relative_path in expected_paths:
    canonical_lines.append(f"| {relative_path} | {manifest_hashes[relative_path]} |")
canonical_manifest = "\n".join(canonical_lines) + "\n"
if manifest_text != canonical_manifest:
    fail("Visual QA manifest: content must match the canonical schema and row order exactly")

if not fixture_only:
    for relative_path, expected_size in expected_dimensions.items():
        screenshot = root / relative_path
        if screenshot.stat().st_size < 25000:
            fail(f"Visual QA screenshot {relative_path}: file is unexpectedly small")
        values = {}
        for property_name in ("pixelWidth", "pixelHeight", "format", "hasAlpha"):
            result = run(["sips", "-g", property_name, str(screenshot)])
            if result.returncode != 0:
                fail(f"Visual QA screenshot {relative_path}: unable to inspect {property_name}")
            match = re.search(rf"{property_name}:\s*(.+)", result.stdout)
            values[property_name] = match.group(1).strip() if match else ""
        observed_size = (int(values["pixelWidth"]), int(values["pixelHeight"]))
        if observed_size != expected_size:
            fail(
                f"Visual QA screenshot {relative_path}: size {observed_size} does not match {expected_size}"
            )
        if values["format"] != "jpeg" or values["hasAlpha"] != "no":
            fail(f"Visual QA screenshot {relative_path}: must be an opaque JPEG")

print(
    "SCREENSHOT_PACKAGE_FIXTURE_PASS_NOT_RELEASE_SIGNOFF"
    if fixture_only
    else f"Screenshot package verified for source commit {source_commit}."
)
PY
