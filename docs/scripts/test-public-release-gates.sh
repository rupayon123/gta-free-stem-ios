#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

BASE_SIGNOFF="docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md"
GATE_SCRIPT="docs/scripts/check-public-release-gates.sh"
TMP_DIR="$(mktemp -d -t gtafreestem-public-gates.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

rg -Fq 'bash docs/scripts/verify-app-store-archive.sh "$IOS_ARCHIVE_PATH"' "$GATE_SCRIPT" || {
  echo "Public release gate must verify the source iOS archive."
  exit 1
}
rg -Fq 'bash docs/scripts/verify-app-store-ipa.sh "$IOS_IPA_PATH" "$IOS_ARCHIVE_PATH"' "$GATE_SCRIPT" || {
  echo "Public release gate must verify the distribution IPA against its source archive."
  exit 1
}
rg -Fq 'bash docs/scripts/verify-mac-app-store-pkg.sh "$MAC_PKG_PATH" "$MAC_ARCHIVE_PATH"' "$GATE_SCRIPT" || {
  echo "Public release gate must verify the exported Mac App Store package against its source archive."
  exit 1
}
rg -Fq 'STRICT_TRANSLATION_CHECK=1 CHECK_APP_STORE_SCREENSHOTS=1 bash docs/scripts/check-release-readiness.sh' "$GATE_SCRIPT" || {
  echo "Public release mode must run the full strict readiness audit with screenshot checks forced on."
  exit 1
}
if rg -n -- '--upload-package|AppStoreConnectExportOptions|destination[=:]upload' \
  "$GATE_SCRIPT" docs/scripts/verify-mac-app-store-pkg.sh; then
  echo "Public release verification must remain no-upload."
  exit 1
fi
for required_binding in \
  'Published commit' \
  'Artifact verification date' \
  'iOS archive path' \
  'iOS archive SHA-256' \
  'iOS IPA path' \
  'iOS IPA SHA-256' \
  'iOS Delivery UUID' \
  'Mac archive path' \
  'Mac archive SHA-256' \
  'Mac package path' \
  'Mac package SHA-256' \
  'Mac Delivery UUID' \
  'Artifact binding status' \
  'iOS App Store Connect status' \
  'iOS BuildBetaDetail.internalBuildState' \
  'Mac App Store Connect status' \
  'Mac BuildBetaDetail.internalBuildState' \
  'iOS App Store Connect build selected' \
  'Mac App Store Connect build selected' \
  'Visual QA manifest SHA-256' \
  'Capture receipt SHA-256'; do
  rg -Fq "$required_binding" "$GATE_SCRIPT" "$BASE_SIGNOFF" || {
    echo "Public release gate is missing exact signoff binding: $required_binding"
    exit 1
  }
done
rg -Fq '["git", "merge-base", "--is-ancestor", recorded_commit, live_main_commit]' "$GATE_SCRIPT" || {
  echo "Public release gate must prove the recorded source commit is reachable from live origin/main."
  exit 1
}
rg -Fq '["git", "diff", "--quiet", recorded_commit, live_main_commit, "--"]' "$GATE_SCRIPT" || {
  echo "Public release gate must compare recorded source inputs with live origin/main."
  exit 1
}
rg -Fq '["git", "diff", "--quiet", recorded_commit, "--"]' "$GATE_SCRIPT" || {
  echo "Public release gate must compare local source inputs with the recorded source commit."
  exit 1
}
rg -Fq 'GTAReleaseSourceCommit' "$GATE_SCRIPT" || {
  echo "Public release gate must bind the signed artifact source commit to the signoff."
  exit 1
}

FIXTURE_IOS_ARCHIVE="$TMP_DIR/fixture-ios.xcarchive"
FIXTURE_IOS_IPA="$TMP_DIR/fixture-ios.ipa"
FIXTURE_MAC_ARCHIVE="$TMP_DIR/fixture-mac.xcarchive"
FIXTURE_MAC_PKG="$TMP_DIR/fixture-mac.pkg"
mkdir -p "$FIXTURE_IOS_ARCHIVE/Products" "$FIXTURE_MAC_ARCHIVE/Products"
printf '%s\n' 'fixture iOS archive' > "$FIXTURE_IOS_ARCHIVE/Products/payload.txt"
printf '%s\n' 'fixture iOS IPA' > "$FIXTURE_IOS_IPA"
printf '%s\n' 'fixture Mac archive' > "$FIXTURE_MAC_ARCHIVE/Products/payload.txt"
printf '%s\n' 'fixture Mac package' > "$FIXTURE_MAC_PKG"
FIXTURE_IOS_ARCHIVE="$(realpath "$FIXTURE_IOS_ARCHIVE")"
FIXTURE_IOS_IPA="$(realpath "$FIXTURE_IOS_IPA")"
FIXTURE_MAC_ARCHIVE="$(realpath "$FIXTURE_MAC_ARCHIVE")"
FIXTURE_MAC_PKG="$(realpath "$FIXTURE_MAC_PKG")"
FIXTURE_COMMIT="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
FIXTURE_LIVE_MAIN_COMMIT="cccccccccccccccccccccccccccccccccccccccc"
FIXTURE_SOURCE_TREE_SHA256="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
FIXTURE_DATE="2026-08-06"

if [ "$FIXTURE_COMMIT" = "$FIXTURE_LIVE_MAIN_COMMIT" ]; then
  echo "The signoff self-reference fixture must use a later, distinct live main commit."
  exit 1
fi

read -r FIXTURE_IOS_ARCHIVE_SHA FIXTURE_IOS_IPA_SHA FIXTURE_MAC_ARCHIVE_SHA FIXTURE_MAC_PKG_SHA < <(
  /usr/bin/python3 - "$FIXTURE_IOS_ARCHIVE" "$FIXTURE_IOS_IPA" "$FIXTURE_MAC_ARCHIVE" "$FIXTURE_MAC_PKG" <<'PY'
import hashlib
import os
import stat
import sys
from pathlib import Path

def file_sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def tree_sha(path):
    digest = hashlib.sha256()
    digest.update(b"GTA-FREE-STEM-RELEASE-TREE-SHA256-v1\0")
    for candidate in sorted(path.rglob("*"), key=lambda item: item.relative_to(path).as_posix()):
        relative = candidate.relative_to(path).as_posix().encode("utf-8")
        metadata = candidate.lstat()
        mode = stat.S_IMODE(metadata.st_mode)
        if stat.S_ISLNK(metadata.st_mode):
            digest.update(b"L\0" + relative + b"\0" + oct(mode).encode("ascii") + b"\0")
            digest.update(os.readlink(candidate).encode("utf-8") + b"\0")
        elif stat.S_ISDIR(metadata.st_mode):
            digest.update(b"D\0" + relative + b"\0" + oct(mode).encode("ascii") + b"\0")
        elif stat.S_ISREG(metadata.st_mode):
            payload = candidate.read_bytes()
            digest.update(b"F\0" + relative + b"\0" + oct(mode).encode("ascii") + b"\0")
            digest.update(str(len(payload)).encode("ascii") + b"\0" + payload + b"\0")
    return digest.hexdigest()

print(tree_sha(Path(sys.argv[1])), file_sha(Path(sys.argv[2])), tree_sha(Path(sys.argv[3])), file_sha(Path(sys.argv[4])))
PY
)

EXPECTED_SCREENSHOT_PATHS=(
  iphone-6.9/01-home.jpg
  iphone-6.9/02-opportunities.jpg
  iphone-6.9/03-high-school.jpg
  iphone-6.9/04-profile.jpg
  ipad-13/01-home.jpg
  ipad-13/02-opportunities.jpg
  ipad-13/03-high-school.jpg
  ipad-13/04-profile.jpg
  mac/01-home.jpg
  mac/02-opportunities.jpg
  mac/03-high-school.jpg
  mac/04-profile.jpg
  watch-series-11/01-home.jpg
)

write_capture_receipt() {
  local screenshot_root="$1"
  local source_commit="$2"
  /usr/bin/python3 - "$screenshot_root" "$source_commit" "$FIXTURE_SOURCE_TREE_SHA256" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
source_commit = sys.argv[2]
source_tree_sha256 = sys.argv[3]
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
    "screenshots": [
        {
            "path": relative_path,
            "sha256": hashlib.sha256((root / relative_path).read_bytes()).hexdigest(),
        }
        for relative_path in paths
    ],
    "createdAt": "2026-08-06T20:00:00Z",
}
(root / "CAPTURE_RECEIPT.json").write_text(
    json.dumps(receipt, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
}

write_visual_qa_manifest() {
  local screenshot_root="$1"
  local manifest_path="$2"
  local source_commit="$3"
  /usr/bin/python3 - \
    "$screenshot_root" \
    "$manifest_path" \
    "$source_commit" \
    "$FIXTURE_DATE" \
    "docs/FINAL_VISUAL_QA_TEMPLATE.md" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = Path(sys.argv[2])
source_commit = sys.argv[3]
reviewed_on = sys.argv[4]
template = Path(sys.argv[5])
receipt_sha = hashlib.sha256((root / "CAPTURE_RECEIPT.json").read_bytes()).hexdigest()
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
text = template.read_text(encoding="utf-8")
replacements = {
    "- Approval status: `PENDING`": "- Approval status: `PASS`",
    "- Published commit: `REPLACE_WITH_40_CHARACTER_LOWERCASE_COMMIT`": f"- Published commit: `{source_commit}`",
    "- Capture receipt SHA-256: `REPLACE_WITH_64_CHARACTER_LOWERCASE_SHA256`": f"- Capture receipt SHA-256: `{receipt_sha}`",
    "- Reviewer:": "- Reviewer: `Release QA`",
    "- Reviewed on: `YYYY-MM-DD`": f"- Reviewed on: `{reviewed_on}`",
}
for old, new in replacements.items():
    if text.count(old) != 1:
        raise SystemExit(f"Visual-QA template expected one placeholder: {old}")
    text = text.replace(old, new, 1)
for relative in paths:
    digest = hashlib.sha256((root / relative).read_bytes()).hexdigest()
    old = f"| {relative} | REPLACE_WITH_64_CHARACTER_LOWERCASE_SHA256 |"
    if text.count(old) != 1:
        raise SystemExit(f"Visual-QA template expected one screenshot row: {relative}")
    text = text.replace(old, f"| {relative} | {digest} |", 1)
manifest.write_text(text, encoding="utf-8")
PY
}

FIXTURE_SCREENSHOT_ROOT="$TMP_DIR/valid-screenshots"
for relative_path in "${EXPECTED_SCREENSHOT_PATHS[@]}"; do
  mkdir -p "$FIXTURE_SCREENSHOT_ROOT/$(dirname "$relative_path")"
  printf 'fixture screenshot bytes for %s\n' "$relative_path" > "$FIXTURE_SCREENSHOT_ROOT/$relative_path"
done
FIXTURE_VISUAL_QA_MANIFEST="$FIXTURE_SCREENSHOT_ROOT/FINAL_VISUAL_QA.md"
write_capture_receipt "$FIXTURE_SCREENSHOT_ROOT" "$FIXTURE_COMMIT"
write_visual_qa_manifest "$FIXTURE_SCREENSHOT_ROOT" "$FIXTURE_VISUAL_QA_MANIFEST" "$FIXTURE_COMMIT"
FIXTURE_VISUAL_QA_SHA="$(shasum -a 256 "$FIXTURE_VISUAL_QA_MANIFEST" | awk '{print $1}')"

MISSING_MANIFEST_ROOT="$TMP_DIR/missing-manifest-screenshots"
CHANGED_MANIFEST_ROOT="$TMP_DIR/changed-manifest-screenshots"
STALE_MANIFEST_ROOT="$TMP_DIR/stale-manifest-screenshots"
MUTATED_SCREENSHOT_ROOT="$TMP_DIR/mutated-screenshot-screenshots"
NO_REVIEWER_ROOT="$TMP_DIR/no-reviewer-screenshots"
MISSING_RECEIPT_ROOT="$TMP_DIR/missing-receipt-screenshots"
MUTATED_RECEIPT_ROOT="$TMP_DIR/mutated-receipt-screenshots"
MISSING_MAC_SESSION_ROOT="$TMP_DIR/missing-mac-session-screenshots"
MUTATED_MAC_SESSION_ROOT="$TMP_DIR/mutated-mac-session-screenshots"
ROGUE_IMAGE_ROOT="$TMP_DIR/rogue-image-screenshots"
cp -R "$FIXTURE_SCREENSHOT_ROOT" "$MISSING_MANIFEST_ROOT"
cp -R "$FIXTURE_SCREENSHOT_ROOT" "$CHANGED_MANIFEST_ROOT"
cp -R "$FIXTURE_SCREENSHOT_ROOT" "$STALE_MANIFEST_ROOT"
cp -R "$FIXTURE_SCREENSHOT_ROOT" "$MUTATED_SCREENSHOT_ROOT"
cp -R "$FIXTURE_SCREENSHOT_ROOT" "$NO_REVIEWER_ROOT"
cp -R "$FIXTURE_SCREENSHOT_ROOT" "$MISSING_RECEIPT_ROOT"
cp -R "$FIXTURE_SCREENSHOT_ROOT" "$MUTATED_RECEIPT_ROOT"
cp -R "$FIXTURE_SCREENSHOT_ROOT" "$MISSING_MAC_SESSION_ROOT"
cp -R "$FIXTURE_SCREENSHOT_ROOT" "$MUTATED_MAC_SESSION_ROOT"
cp -R "$FIXTURE_SCREENSHOT_ROOT" "$ROGUE_IMAGE_ROOT"
rm -f "$MISSING_MANIFEST_ROOT/FINAL_VISUAL_QA.md"
rm -f "$MISSING_RECEIPT_ROOT/CAPTURE_RECEIPT.json"
printf '%s\n' ' ' >> "$MUTATED_RECEIPT_ROOT/CAPTURE_RECEIPT.json"
rm -f "$MISSING_MAC_SESSION_ROOT/MAC_CAPTURE_SESSION.json"
printf '%s\n' ' ' >> "$MUTATED_MAC_SESSION_ROOT/MAC_CAPTURE_SESSION.json"
printf '%s\n' 'unexpected image' > "$ROGUE_IMAGE_ROOT/mac/extra.png"
printf '\npost-approval manifest mutation\n' >> "$CHANGED_MANIFEST_ROOT/FINAL_VISUAL_QA.md"
CHANGED_VISUAL_QA_SHA="$(shasum -a 256 "$CHANGED_MANIFEST_ROOT/FINAL_VISUAL_QA.md" | awk '{print $1}')"
write_visual_qa_manifest \
  "$STALE_MANIFEST_ROOT" \
  "$STALE_MANIFEST_ROOT/FINAL_VISUAL_QA.md" \
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
STALE_VISUAL_QA_SHA="$(shasum -a 256 "$STALE_MANIFEST_ROOT/FINAL_VISUAL_QA.md" | awk '{print $1}')"
printf '\npost-approval screenshot mutation\n' >> "$MUTATED_SCREENSHOT_ROOT/iphone-6.9/01-home.jpg"
/usr/bin/python3 - "$NO_REVIEWER_ROOT/FINAL_VISUAL_QA.md" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = "- Reviewer: `Release QA`"
if text.count(old) != 1:
    raise SystemExit("Expected exactly one fixture reviewer field")
path.write_text(text.replace(old, "- Reviewer: `None`"), encoding="utf-8")
PY
NO_REVIEWER_VISUAL_QA_SHA="$(shasum -a 256 "$NO_REVIEWER_ROOT/FINAL_VISUAL_QA.md" | awk '{print $1}')"

gate_fixture() {
  local recorded_reachable_from_live="${3:-1}"
  local recorded_matches_live_source="${4:-1}"
  local local_matches_recorded_source="${5:-1}"
  local artifact_source_commit="${6:-$FIXTURE_COMMIT}"
  local screenshot_root="${7:-$FIXTURE_SCREENSHOT_ROOT}"
  PUBLIC_GATE_TEST_FIXTURE_ONLY=1 \
    PUBLIC_GATE_TEST_LIVE_MAIN_COMMIT="$FIXTURE_LIVE_MAIN_COMMIT" \
    PUBLIC_GATE_TEST_TODAY="$FIXTURE_DATE" \
    PUBLIC_GATE_TEST_RECORDED_REACHABLE_FROM_LIVE="$recorded_reachable_from_live" \
    PUBLIC_GATE_TEST_RECORDED_MATCHES_LIVE_SOURCE="$recorded_matches_live_source" \
    PUBLIC_GATE_TEST_LOCAL_MATCHES_RECORDED_SOURCE="$local_matches_recorded_source" \
    PUBLIC_GATE_TEST_ARTIFACT_SOURCE_COMMIT="$artifact_source_commit" \
    PUBLIC_GATE_TEST_SCREENSHOT_SOURCE_COMMIT="$FIXTURE_COMMIT" \
    PUBLIC_GATE_TEST_SCREENSHOT_SOURCE_TREE_SHA256="$FIXTURE_SOURCE_TREE_SHA256" \
    RUN_RELEASE_AUDIT=0 \
    CHECK_APP_STORE_SCREENSHOTS=0 \
    PUBLIC_GATE_TEST_SCREENSHOT_ROOT="$screenshot_root" \
    PUBLIC_GATE_TEST_VISUAL_QA_MANIFEST="$screenshot_root/FINAL_VISUAL_QA.md" \
    IOS_ARCHIVE_PATH="$FIXTURE_IOS_ARCHIVE" \
    IOS_IPA_PATH="$FIXTURE_IOS_IPA" \
    MAC_ARCHIVE_PATH="$FIXTURE_MAC_ARCHIVE" \
    MAC_PKG_PATH="$FIXTURE_MAC_PKG" \
    SIGNOFF_PATH="$1" \
    PUBLIC_RELEASE_PLATFORMS="$2" \
    bash "$GATE_SCRIPT"
}

make_fixture() {
  local mode="$1"
  local output="$2"
  local visual_qa_sha="$FIXTURE_VISUAL_QA_SHA"
  if [ "$mode" = "stale-manifest" ]; then
    visual_qa_sha="$STALE_VISUAL_QA_SHA"
  elif [ "$mode" = "changed-manifest" ]; then
    visual_qa_sha="$CHANGED_VISUAL_QA_SHA"
  elif [ "$mode" = "no-reviewer-manifest" ]; then
    visual_qa_sha="$NO_REVIEWER_VISUAL_QA_SHA"
  fi

  /usr/bin/python3 - \
    "$BASE_SIGNOFF" \
    "$output" \
    "$mode" \
    "$FIXTURE_COMMIT" \
    "$FIXTURE_DATE" \
    "$FIXTURE_IOS_ARCHIVE" \
    "$FIXTURE_IOS_ARCHIVE_SHA" \
    "$FIXTURE_IOS_IPA" \
    "$FIXTURE_IOS_IPA_SHA" \
    "$FIXTURE_MAC_ARCHIVE" \
    "$FIXTURE_MAC_ARCHIVE_SHA" \
    "$FIXTURE_MAC_PKG" \
    "$FIXTURE_MAC_PKG_SHA" \
    "$visual_qa_sha" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
mode = sys.argv[3]
commit, verification_date = sys.argv[4:6]
ios_archive, ios_archive_sha, ios_ipa, ios_ipa_sha = sys.argv[6:10]
mac_archive, mac_archive_sha, mac_pkg, mac_pkg_sha = sys.argv[10:14]
visual_qa_sha = sys.argv[14]
text = source.read_text(encoding="utf-8")

FIELD_SECTIONS = {
    "Version/build": "Build Under Test",
    "iOS Delivery UUID": "Build Under Test",
    "Mac Delivery UUID": "Build Under Test",
    "iOS App Store Connect status": "Build Under Test",
    "iOS BuildBetaDetail.internalBuildState": "Build Under Test",
    "Mac App Store Connect status": "Build Under Test",
    "Mac BuildBetaDetail.internalBuildState": "Build Under Test",
    "Public distribution platforms": "Build Under Test",
    "Artifact binding status": "Verified Artifact Binding",
    "Published commit": "Verified Artifact Binding",
    "Artifact verification date": "Verified Artifact Binding",
    "iOS archive path": "Verified Artifact Binding",
    "iOS archive SHA-256": "Verified Artifact Binding",
    "iOS IPA path": "Verified Artifact Binding",
    "iOS IPA SHA-256": "Verified Artifact Binding",
    "Mac archive path": "Verified Artifact Binding",
    "Mac archive SHA-256": "Verified Artifact Binding",
    "Mac package path": "Verified Artifact Binding",
    "Mac package SHA-256": "Verified Artifact Binding",
    "Tester": "Tester And Device",
    "Date": "Tester And Device",
    "Install source": "Tester And Device",
    "Network conditions tested": "Tester And Device",
    "Accessibility settings tested": "Tester And Device",
    "Languages tested": "Tester And Device",
    "Overall status": "Release Owner Decision",
    "Accepted risks": "Release Owner Decision",
    "Must-fix blockers": "Release Owner Decision",
    "iOS App Store Connect build selected": "Release Owner Decision",
    "Mac App Store Connect build selected": "Release Owner Decision",
    "Archive provenance verified": "Release Owner Decision",
    "Screenshot visual QA": "Release Owner Decision",
    "Visual QA manifest SHA-256": "Release Owner Decision",
    "Screenshots uploaded": "Release Owner Decision",
    "Metadata/privacy/age rating entered": "Release Owner Decision",
    "Support contact verified": "Release Owner Decision",
    "Production legal/support truthfulness verified": "Release Owner Decision",
    "App Review contact verified": "Release Owner Decision",
    "Copyright entered": "Release Owner Decision",
    "Platform record decision": "Release Owner Decision",
    "Primary language verified": "Release Owner Decision",
    "Availability and DSA verified": "Release Owner Decision",
    "Submitted for App Review": "Release Owner Decision",
}


def field_indices(label):
    section = FIELD_SECTIONS[label]
    current_section = ""
    matches = []
    for index, row in enumerate(text.splitlines()):
        if row.startswith("## "):
            current_section = row[3:].strip()
        elif current_section == section and row.startswith(f"- {label}:"):
            matches.append(index)
    return matches

def replace_line(label, value):
    global text
    rows = text.splitlines()
    matches = field_indices(label)
    if len(matches) != 1:
        raise SystemExit(f"Fixture expected one structured {label} field, found {len(matches)}")
    rows[matches[0]] = f"- {label}: {value}"
    text = "\n".join(rows) + "\n"


def remove_field(label):
    global text
    rows = text.splitlines()
    matches = field_indices(label)
    if len(matches) != 1:
        raise SystemExit(f"Fixture expected one structured {label} field, found {len(matches)}")
    del rows[matches[0]]
    text = "\n".join(rows) + "\n"


def duplicate_field(label, value):
    global text
    rows = text.splitlines()
    matches = field_indices(label)
    if len(matches) != 1:
        raise SystemExit(f"Fixture expected one structured {label} field, found {len(matches)}")
    rows.insert(matches[0] + 1, f"- {label}: {value}")
    text = "\n".join(rows) + "\n"


def required_row_indices(area=None):
    current_section = ""
    matches = []
    for index, row in enumerate(text.splitlines()):
        if row.startswith("## "):
            current_section = row[3:].strip()
        elif current_section == "Required Passes" and row.startswith("|") and "---" not in row:
            cells = [cell.strip() for cell in row.strip("|").split("|")]
            if cells and cells[0] != "Area" and (area is None or cells[0] == area):
                matches.append(index)
    return matches


def remove_required_row(area):
    global text
    rows = text.splitlines()
    matches = required_row_indices(area)
    if len(matches) != 1:
        raise SystemExit(f"Fixture expected one Required Passes row for {area}, found {len(matches)}")
    del rows[matches[0]]
    text = "\n".join(rows) + "\n"


def duplicate_required_row(area):
    global text
    rows = text.splitlines()
    matches = required_row_indices(area)
    if len(matches) != 1:
        raise SystemExit(f"Fixture expected one Required Passes row for {area}, found {len(matches)}")
    rows.insert(matches[0] + 1, rows[matches[0]])
    text = "\n".join(rows) + "\n"


def replace_required_area(area, replacement):
    global text
    rows = text.splitlines()
    matches = required_row_indices(area)
    if len(matches) != 1:
        raise SystemExit(f"Fixture expected one Required Passes row for {area}, found {len(matches)}")
    rows[matches[0]] = rows[matches[0]].replace(f"| {area} |", f"| {replacement} |", 1)
    text = "\n".join(rows) + "\n"


def clear_required_rows():
    global text
    rows = text.splitlines()
    for index in reversed(required_row_indices()):
        del rows[index]
    text = "\n".join(rows) + "\n"

def pass_table_rows():
    global text
    rows = []
    for row in text.splitlines():
        if row.startswith("|") and "| Pending |" in row:
            row = row.replace("| Pending | |", "| Pass | Observed in fixture. |")
        rows.append(row)
    text = "\n".join(rows) + "\n"

def set_platform_row(platform, device, os_version, status="Pass", notes="Observed in fixture."):
    global text
    prefix = f"| {platform} |"
    required_evidence = {
        "iPhone": "Fresh TestFlight install; online and offline discovery flow.",
        "iPad": "TestFlight install; navigation and filter layout remain usable.",
        "Apple Watch": "Paired Watch receives the capped saved-opportunity set and archive status from the phone and remains readable; it is not a standalone full-feed search app.",
        "Mac": "Mac Catalyst launch, sidebar navigation, links, and window-scale appearance.",
    }[platform]
    replacement = f"| {platform} | {required_evidence} | {device} | {os_version} | {status} | {notes} |"
    rows = []
    for row in text.splitlines():
        rows.append(replacement if row.startswith(prefix) else row)
    text = "\n".join(rows) + "\n"

values = {
    "Tester": "Release QA",
    "Date": "2026-08-06",
    "Install source": "TestFlight",
    "Network conditions tested": "WI_FI_AND_OFFLINE_FALLBACK",
    "Accessibility settings tested": "VOICEOVER_LARGE_TEXT_DARK_MODE",
    "Languages tested": "ENGLISH_FRENCH_SPANISH_ARABIC_RTL",
    "iOS Delivery UUID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "Mac Delivery UUID": "11111111-2222-3333-4444-555555555555",
    "Published commit": commit,
    "Artifact verification date": verification_date,
    "iOS archive path": ios_archive,
    "iOS archive SHA-256": ios_archive_sha,
    "iOS IPA path": ios_ipa,
    "iOS IPA SHA-256": ios_ipa_sha,
    "Mac archive path": mac_archive,
    "Mac archive SHA-256": mac_archive_sha,
    "Mac package path": mac_pkg,
    "Mac package SHA-256": mac_pkg_sha,
    "iOS App Store Connect status": "VALID",
    "iOS BuildBetaDetail.internalBuildState": "IN_BETA_TESTING",
    "Mac App Store Connect status": "VALID",
    "Mac BuildBetaDetail.internalBuildState": "IN_BETA_TESTING",
    "Public distribution platforms": "iphone,ipad,watch,mac",
    "Overall status": "Pass",
    "Accepted risks": "None",
    "Must-fix blockers": "None",
    "Artifact binding status": "CURRENT_AND_VERIFIED",
    "iOS App Store Connect build selected": "1.0 (12)",
    "Mac App Store Connect build selected": "1.0 (12)",
    "Archive provenance verified": "VERIFIED_SIGNED_BUILD_1_0_12_IOS_WATCH_MAC",
    "Screenshot visual QA": "PASS",
    "Visual QA manifest SHA-256": visual_qa_sha,
    "Screenshots uploaded": "UPLOADED_13_IPHONE_IPAD_WATCH_MAC",
    "Metadata/privacy/age rating entered": "ENTERED_METADATA_PRIVACY_AGE_RATING_KIDS_NO_EXPORT_COMPLIANCE_REVIEW_NOTES",
    "Support contact verified": "VERIFIED: https://gta-free-stem.vercel.app/support/ | GITHUB_ISSUES | MONITORED_DIRECT_CONTACT",
    "Production legal/support truthfulness verified": "VERIFIED_MATCH_BUILD: https://gta-free-stem.vercel.app/support/ | https://gta-free-stem.vercel.app/privacy/ | https://gta-free-stem.vercel.app/terms/",
    "App Review contact verified": "VERIFIED_APP_STORE_CONNECT_2026-08-06",
    "Copyright entered": "ENTERED_APP_STORE_CONNECT_2026: Rupayon Haldar",
    "Platform record decision": "VERIFIED_SEPARATE_MAC_RECORD: app_id=6779714460; sku=gta-free-stem-mac; bundle_id=com.rupayonhaldar.gtafreestem.maccatalyst",
    "Primary language verified": "VERIFIED_APP_STORE_CONNECT_2026-08-06: primary_language=en-CA",
    "Availability and DSA verified": "VERIFIED_APP_STORE_CONNECT_2026-08-06",
    "Submitted for App Review": "Pending until final release decision",
}
for label, value in values.items():
    replace_line(label, value)
pass_table_rows()
set_platform_row("iPhone", "iPhone 17", "iOS 26.5")
set_platform_row("iPad", "iPad Pro 13-inch", "iPadOS 26.5")
set_platform_row("Apple Watch", "Apple Watch Series 11", "watchOS 26.5")
set_platform_row("Mac", "MacBook Air", "macOS 26.5")

if mode == "wrong-build":
    replace_line("iOS App Store Connect build selected", "1.0 (9)")
elif mode == "wrong-mac-build":
    replace_line("Mac App Store Connect build selected", "1.0 (9)")
elif mode == "mac-processing-failed":
    replace_line("Mac App Store Connect status", "PROCESSING_FAILED")
    replace_line("Mac BuildBetaDetail.internalBuildState", "PROCESSING_EXCEPTION")
elif mode == "superseded-artifacts":
    replace_line("Artifact binding status", "SUPERSEDED_PENDING_REBUILD")
elif mode == "weak-screenshots":
    replace_line("Screenshots uploaded", "UPLOADED_4_IPHONE")
elif mode == "missing-screenshot-visual-qa":
    replace_line("Screenshot visual QA", "PENDING")
elif mode == "legacy-ios-internal-state":
    replace_line("iOS BuildBetaDetail.internalBuildState", "BETA_INTERNAL_TESTING")
elif mode == "negative-ios-status":
    replace_line("iOS App Store Connect status", "NOT VALID")
elif mode == "negative-selected-build":
    replace_line("iOS App Store Connect build selected", "1.0 (12) is not selected")
elif mode == "negative-artifact-binding":
    replace_line("Artifact binding status", "not current but verified")
elif mode == "negative-screenshot-visual-qa":
    replace_line("Screenshot visual QA", "NOT PASS")
elif mode == "negative-screenshots-uploaded":
    replace_line("Screenshots uploaded", "13 screenshots not uploaded: iPhone, iPad, Watch, Mac")
elif mode == "negated-owner-evidence":
    replace_line("Archive provenance verified", "NOT VERIFIED_SIGNED_BUILD_1_0_12_IOS_WATCH_MAC")
    replace_line("Metadata/privacy/age rating entered", "NOT ENTERED_METADATA_PRIVACY_AGE_RATING_KIDS_NO_EXPORT_COMPLIANCE_REVIEW_NOTES")
    replace_line("Support contact verified", "NOT VERIFIED: https://gta-free-stem.vercel.app/support/ | GITHUB_ISSUES | MONITORED_DIRECT_CONTACT")
    replace_line("Production legal/support truthfulness verified", "NOT VERIFIED_MATCH_BUILD: https://gta-free-stem.vercel.app/support/ | https://gta-free-stem.vercel.app/privacy/ | https://gta-free-stem.vercel.app/terms/")
    replace_line("App Review contact verified", "NOT VERIFIED_APP_STORE_CONNECT_2026-08-06")
    replace_line("Primary language verified", "NOT VERIFIED_APP_STORE_CONNECT_2026-08-06: primary_language=en-CA")
    replace_line("Availability and DSA verified", "NOT VERIFIED_APP_STORE_CONNECT_2026-08-06")
    replace_line("Platform record decision", "NOT VERIFIED_SEPARATE_MAC_RECORD: app_id=6779714460; sku=gta-free-stem-mac; bundle_id=com.rupayonhaldar.gtafreestem.maccatalyst")
elif mode == "negated-test-context":
    replace_line("Install source", "Not TestFlight")
    replace_line("Network conditions tested", "NOT WI_FI_AND_OFFLINE_FALLBACK")
    replace_line("Accessibility settings tested", "NOT VOICEOVER_LARGE_TEXT_DARK_MODE")
    replace_line("Languages tested", "NOT ENGLISH_FRENCH_SPANISH_ARABIC_RTL")
elif mode == "uppercase-manifest-hash":
    replace_line("Visual QA manifest SHA-256", visual_qa_sha.upper())
elif mode == "duplicate-ios-build-field":
    duplicate_field("iOS App Store Connect build selected", "1.0 (12)")
elif mode == "missing-ios-build-field":
    remove_field("iOS App Store Connect build selected")
elif mode == "header-only-required-passes":
    clear_required_rows()
elif mode == "missing-required-pass":
    remove_required_row("Install and launch")
elif mode == "duplicate-required-pass":
    duplicate_required_row("Install and launch")
elif mode == "unexpected-required-pass":
    replace_required_area("Install and launch", "Invented release check")
elif mode == "missing-support":
    replace_line("Support contact verified", "Pending")
elif mode == "weak-support-route":
    replace_line("Support contact verified", "Verified route without a public address")
elif mode == "missing-production-truthfulness":
    replace_line("Production legal/support truthfulness verified", "Pending")
elif mode == "weak-production-truthfulness":
    replace_line("Production legal/support truthfulness verified", "Verified support and privacy pages")
elif mode == "missing-review-contact":
    replace_line("App Review contact verified", "Pending")
elif mode == "placeholder-copyright":
    replace_line("Copyright entered", "2026 Legal Rights Owner")
elif mode == "missing-platform-decision":
    replace_line("Platform record decision", "Pending")
elif mode == "missing-availability-dsa":
    replace_line("Availability and DSA verified", "Pending")
elif mode == "wrong-archive-provenance":
    replace_line("Archive provenance verified", "Unsigned iOS build 1.0 (12) archive with embedded Watch companion")
elif mode == "missing-delivery":
    replace_line("iOS Delivery UUID", "missing")
elif mode == "missing-mac-delivery":
    replace_line("Mac Delivery UUID", "missing")
elif mode == "same-mac-delivery":
    replace_line("Mac Delivery UUID", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
elif mode == "wrong-published-commit":
    replace_line("Published commit", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
elif mode == "wrong-verification-date":
    replace_line("Artifact verification date", "2026-08-05")
elif mode == "wrong-ios-archive-path":
    replace_line("iOS archive path", "/tmp/wrong-ios.xcarchive")
elif mode == "wrong-ios-archive-hash":
    replace_line("iOS archive SHA-256", "0" * 64)
elif mode == "wrong-ios-ipa-path":
    replace_line("iOS IPA path", "/tmp/wrong.ipa")
elif mode == "wrong-ios-ipa-hash":
    replace_line("iOS IPA SHA-256", "0" * 64)
elif mode == "wrong-mac-archive-path":
    replace_line("Mac archive path", "/tmp/wrong-mac.xcarchive")
elif mode == "wrong-mac-archive-hash":
    replace_line("Mac archive SHA-256", "0" * 64)
elif mode == "wrong-mac-package-path":
    replace_line("Mac package path", "/tmp/wrong.pkg")
elif mode == "wrong-mac-package-hash":
    replace_line("Mac package SHA-256", "0" * 64)
elif mode == "missing-date":
    replace_line("Date", "")
elif mode == "unresolved-blockers":
    replace_line("Must-fix blockers", "Support contact is still missing")
elif mode == "iphone-only":
    replace_line("Public distribution platforms", "iphone")
    replace_line("Archive provenance verified", "VERIFIED_SIGNED_BUILD_1_0_12_IOS")
    replace_line("Screenshots uploaded", "UPLOADED_4_IPHONE")
    replace_line("Platform record decision", "Pending")
    set_platform_row("iPad", "", "", "Pending", "")
    set_platform_row("Apple Watch", "", "", "Pending", "")
    set_platform_row("Mac", "", "", "Pending", "")
elif mode == "iphone-ipad":
    replace_line("Public distribution platforms", "iphone,ipad")
    replace_line("Archive provenance verified", "VERIFIED_SIGNED_BUILD_1_0_12_IOS")
    replace_line("Screenshots uploaded", "UPLOADED_8_IPHONE_IPAD")
    replace_line("Platform record decision", "Pending")
    set_platform_row("Apple Watch", "", "", "Pending", "")
    set_platform_row("Mac", "", "", "Pending", "")
elif mode == "iphone-ipad-watch":
    replace_line("Public distribution platforms", "iphone,ipad,watch")
    replace_line("Archive provenance verified", "VERIFIED_SIGNED_BUILD_1_0_12_IOS_WATCH")
    replace_line("Screenshots uploaded", "UPLOADED_9_IPHONE_IPAD_WATCH")
    replace_line("Platform record decision", "Pending")
    set_platform_row("Mac", "", "", "Pending", "")
elif mode not in {"pass", "stale-manifest", "changed-manifest", "no-reviewer-manifest"}:
    raise SystemExit(f"Unknown mode: {mode}")

target.write_text(text, encoding="utf-8")
PY
}

expect_pass() {
  local output="$TMP_DIR/pass-output.txt"
  local platforms="$2"
  if ! gate_fixture "$1" "$platforms" >"$output" 2>&1; then
    echo "Complete release-gate fixture unexpectedly failed:"
    sed -n '1,220p' "$output"
    exit 1
  fi
  rg -Fq "PUBLIC_GATE_FIXTURE_PASS_NOT_RELEASE_SIGNOFF" "$output" || {
    echo "Fixture success must emit the explicit non-release sentinel."
    sed -n '1,220p' "$output"
    exit 1
  }
  if rg -Fq "Public release gates are complete" "$output"; then
    echo "Fixture success must never use the real public-release completion wording."
    sed -n '1,220p' "$output"
    exit 1
  fi
}

expect_fail() {
  local fixture="$1"
  local expected="$2"
  local platforms="${3-iphone,ipad,watch,mac}"
  local output="$TMP_DIR/output.txt"
  if gate_fixture "$fixture" "$platforms" >"$output" 2>&1; then
    echo "Expected release-gate fixture to fail."
    exit 1
  fi
  rg -Fq "$expected" "$output" || { echo "Expected error missing: $expected"; sed -n '1,220p' "$output"; exit 1; }
}

expect_fail_all() {
  local fixture="$1"
  shift
  local output="$TMP_DIR/multi-error-output.txt"
  if gate_fixture "$fixture" "iphone,ipad,watch,mac" >"$output" 2>&1; then
    echo "Expected release-gate fixture to fail with multiple errors."
    exit 1
  fi
  local expected
  for expected in "$@"; do
    rg -Fq "$expected" "$output" || {
      echo "Expected error missing: $expected"
      sed -n '1,260p' "$output"
      exit 1
    }
  done
}

expect_source_state_fail() {
  local fixture="$1"
  local expected="$2"
  local recorded_reachable_from_live="$3"
  local recorded_matches_live_source="$4"
  local local_matches_recorded_source="$5"
  local output="$TMP_DIR/source-state-output.txt"
  if gate_fixture \
    "$fixture" \
    "iphone,ipad,watch,mac" \
    "$recorded_reachable_from_live" \
    "$recorded_matches_live_source" \
    "$local_matches_recorded_source" >"$output" 2>&1; then
    echo "Expected published-source state to fail."
    exit 1
  fi
  rg -Fq "$expected" "$output" || {
    echo "Expected published-source error missing: $expected"
    sed -n '1,220p' "$output"
    exit 1
  }
}

expect_artifact_source_fail() {
  local artifact_source_commit="$1"
  local expected="$2"
  local output="$TMP_DIR/artifact-source-output.txt"
  if gate_fixture \
    "$PASS" \
    "iphone,ipad,watch,mac" \
    1 1 1 \
    "$artifact_source_commit" >"$output" 2>&1; then
    echo "Expected signed artifact source commit mismatch to fail."
    exit 1
  fi
  rg -Fq "$expected" "$output" || {
    echo "Expected artifact-source error missing: $expected"
    sed -n '1,220p' "$output"
    exit 1
  }
}

expect_manifest_fail() {
  local fixture="$1"
  local screenshot_root="$2"
  local expected="$3"
  local output="$TMP_DIR/manifest-output.txt"
  if gate_fixture \
    "$fixture" \
    "iphone,ipad,watch,mac" \
    1 1 1 \
    "$FIXTURE_COMMIT" \
    "$screenshot_root" >"$output" 2>&1; then
    echo "Expected visual-QA manifest binding to fail."
    exit 1
  fi
  rg -Fq "$expected" "$output" || {
    echo "Expected visual-QA manifest error missing: $expected"
    sed -n '1,220p' "$output"
    exit 1
  }
}

PASS="$TMP_DIR/pass.md"
WRONG_BUILD="$TMP_DIR/wrong-build.md"
WRONG_MAC_BUILD="$TMP_DIR/wrong-mac-build.md"
MAC_PROCESSING_FAILED="$TMP_DIR/mac-processing-failed.md"
SUPERSEDED_ARTIFACTS="$TMP_DIR/superseded-artifacts.md"
WEAK_SCREENSHOTS="$TMP_DIR/weak-screenshots.md"
MISSING_SCREENSHOT_VISUAL_QA="$TMP_DIR/missing-screenshot-visual-qa.md"
MISSING_SUPPORT="$TMP_DIR/missing-support.md"
WEAK_SUPPORT_ROUTE="$TMP_DIR/weak-support-route.md"
MISSING_PRODUCTION_TRUTHFULNESS="$TMP_DIR/missing-production-truthfulness.md"
WEAK_PRODUCTION_TRUTHFULNESS="$TMP_DIR/weak-production-truthfulness.md"
MISSING_DELIVERY="$TMP_DIR/missing-delivery.md"
MISSING_MAC_DELIVERY="$TMP_DIR/missing-mac-delivery.md"
SAME_MAC_DELIVERY="$TMP_DIR/same-mac-delivery.md"
WRONG_PUBLISHED_COMMIT="$TMP_DIR/wrong-published-commit.md"
WRONG_VERIFICATION_DATE="$TMP_DIR/wrong-verification-date.md"
WRONG_IOS_ARCHIVE_PATH="$TMP_DIR/wrong-ios-archive-path.md"
WRONG_IOS_ARCHIVE_HASH="$TMP_DIR/wrong-ios-archive-hash.md"
WRONG_IOS_IPA_PATH="$TMP_DIR/wrong-ios-ipa-path.md"
WRONG_IOS_IPA_HASH="$TMP_DIR/wrong-ios-ipa-hash.md"
WRONG_MAC_ARCHIVE_PATH="$TMP_DIR/wrong-mac-archive-path.md"
WRONG_MAC_ARCHIVE_HASH="$TMP_DIR/wrong-mac-archive-hash.md"
WRONG_MAC_PACKAGE_PATH="$TMP_DIR/wrong-mac-package-path.md"
WRONG_MAC_PACKAGE_HASH="$TMP_DIR/wrong-mac-package-hash.md"
MISSING_DATE="$TMP_DIR/missing-date.md"
UNRESOLVED_BLOCKERS="$TMP_DIR/unresolved-blockers.md"
MISSING_REVIEW_CONTACT="$TMP_DIR/missing-review-contact.md"
PLACEHOLDER_COPYRIGHT="$TMP_DIR/placeholder-copyright.md"
MISSING_PLATFORM_DECISION="$TMP_DIR/missing-platform-decision.md"
MISSING_AVAILABILITY_DSA="$TMP_DIR/missing-availability-dsa.md"
WRONG_ARCHIVE_PROVENANCE="$TMP_DIR/wrong-archive-provenance.md"
IPHONE_ONLY="$TMP_DIR/iphone-only.md"
IPHONE_IPAD="$TMP_DIR/iphone-ipad.md"
IPHONE_IPAD_WATCH="$TMP_DIR/iphone-ipad-watch.md"
LEGACY_IOS_INTERNAL_STATE="$TMP_DIR/legacy-ios-internal-state.md"
NEGATIVE_IOS_STATUS="$TMP_DIR/negative-ios-status.md"
NEGATIVE_SELECTED_BUILD="$TMP_DIR/negative-selected-build.md"
NEGATIVE_ARTIFACT_BINDING="$TMP_DIR/negative-artifact-binding.md"
NEGATIVE_SCREENSHOT_VISUAL_QA="$TMP_DIR/negative-screenshot-visual-qa.md"
NEGATIVE_SCREENSHOTS_UPLOADED="$TMP_DIR/negative-screenshots-uploaded.md"
NEGATED_OWNER_EVIDENCE="$TMP_DIR/negated-owner-evidence.md"
NEGATED_TEST_CONTEXT="$TMP_DIR/negated-test-context.md"
UPPERCASE_MANIFEST_HASH="$TMP_DIR/uppercase-manifest-hash.md"
DUPLICATE_IOS_BUILD_FIELD="$TMP_DIR/duplicate-ios-build-field.md"
MISSING_IOS_BUILD_FIELD="$TMP_DIR/missing-ios-build-field.md"
HEADER_ONLY_REQUIRED_PASSES="$TMP_DIR/header-only-required-passes.md"
MISSING_REQUIRED_PASS="$TMP_DIR/missing-required-pass.md"
DUPLICATE_REQUIRED_PASS="$TMP_DIR/duplicate-required-pass.md"
UNEXPECTED_REQUIRED_PASS="$TMP_DIR/unexpected-required-pass.md"
STALE_MANIFEST_SIGNOFF="$TMP_DIR/stale-manifest.md"
CHANGED_MANIFEST_SIGNOFF="$TMP_DIR/changed-manifest.md"
NO_REVIEWER_SIGNOFF="$TMP_DIR/no-reviewer-manifest.md"

make_fixture pass "$PASS"
make_fixture wrong-build "$WRONG_BUILD"
make_fixture wrong-mac-build "$WRONG_MAC_BUILD"
make_fixture mac-processing-failed "$MAC_PROCESSING_FAILED"
make_fixture superseded-artifacts "$SUPERSEDED_ARTIFACTS"
make_fixture weak-screenshots "$WEAK_SCREENSHOTS"
make_fixture missing-screenshot-visual-qa "$MISSING_SCREENSHOT_VISUAL_QA"
make_fixture missing-support "$MISSING_SUPPORT"
make_fixture weak-support-route "$WEAK_SUPPORT_ROUTE"
make_fixture missing-production-truthfulness "$MISSING_PRODUCTION_TRUTHFULNESS"
make_fixture weak-production-truthfulness "$WEAK_PRODUCTION_TRUTHFULNESS"
make_fixture missing-delivery "$MISSING_DELIVERY"
make_fixture missing-mac-delivery "$MISSING_MAC_DELIVERY"
make_fixture same-mac-delivery "$SAME_MAC_DELIVERY"
make_fixture wrong-published-commit "$WRONG_PUBLISHED_COMMIT"
make_fixture wrong-verification-date "$WRONG_VERIFICATION_DATE"
make_fixture wrong-ios-archive-path "$WRONG_IOS_ARCHIVE_PATH"
make_fixture wrong-ios-archive-hash "$WRONG_IOS_ARCHIVE_HASH"
make_fixture wrong-ios-ipa-path "$WRONG_IOS_IPA_PATH"
make_fixture wrong-ios-ipa-hash "$WRONG_IOS_IPA_HASH"
make_fixture wrong-mac-archive-path "$WRONG_MAC_ARCHIVE_PATH"
make_fixture wrong-mac-archive-hash "$WRONG_MAC_ARCHIVE_HASH"
make_fixture wrong-mac-package-path "$WRONG_MAC_PACKAGE_PATH"
make_fixture wrong-mac-package-hash "$WRONG_MAC_PACKAGE_HASH"
make_fixture missing-date "$MISSING_DATE"
make_fixture unresolved-blockers "$UNRESOLVED_BLOCKERS"
make_fixture missing-review-contact "$MISSING_REVIEW_CONTACT"
make_fixture placeholder-copyright "$PLACEHOLDER_COPYRIGHT"
make_fixture missing-platform-decision "$MISSING_PLATFORM_DECISION"
make_fixture missing-availability-dsa "$MISSING_AVAILABILITY_DSA"
make_fixture wrong-archive-provenance "$WRONG_ARCHIVE_PROVENANCE"
make_fixture iphone-only "$IPHONE_ONLY"
make_fixture iphone-ipad "$IPHONE_IPAD"
make_fixture iphone-ipad-watch "$IPHONE_IPAD_WATCH"
make_fixture legacy-ios-internal-state "$LEGACY_IOS_INTERNAL_STATE"
make_fixture negative-ios-status "$NEGATIVE_IOS_STATUS"
make_fixture negative-selected-build "$NEGATIVE_SELECTED_BUILD"
make_fixture negative-artifact-binding "$NEGATIVE_ARTIFACT_BINDING"
make_fixture negative-screenshot-visual-qa "$NEGATIVE_SCREENSHOT_VISUAL_QA"
make_fixture negative-screenshots-uploaded "$NEGATIVE_SCREENSHOTS_UPLOADED"
make_fixture negated-owner-evidence "$NEGATED_OWNER_EVIDENCE"
make_fixture negated-test-context "$NEGATED_TEST_CONTEXT"
make_fixture uppercase-manifest-hash "$UPPERCASE_MANIFEST_HASH"
make_fixture duplicate-ios-build-field "$DUPLICATE_IOS_BUILD_FIELD"
make_fixture missing-ios-build-field "$MISSING_IOS_BUILD_FIELD"
make_fixture header-only-required-passes "$HEADER_ONLY_REQUIRED_PASSES"
make_fixture missing-required-pass "$MISSING_REQUIRED_PASS"
make_fixture duplicate-required-pass "$DUPLICATE_REQUIRED_PASS"
make_fixture unexpected-required-pass "$UNEXPECTED_REQUIRED_PASS"
make_fixture stale-manifest "$STALE_MANIFEST_SIGNOFF"
make_fixture changed-manifest "$CHANGED_MANIFEST_SIGNOFF"
make_fixture no-reviewer-manifest "$NO_REVIEWER_SIGNOFF"

AUDIT_BYPASS_OUTPUT="$TMP_DIR/audit-bypass-output.txt"
if RUN_RELEASE_AUDIT=0 CHECK_APP_STORE_SCREENSHOTS=1 bash "$GATE_SCRIPT" >"$AUDIT_BYPASS_OUTPUT" 2>&1; then
  echo "Expected real public release mode to reject RUN_RELEASE_AUDIT=0."
  exit 1
fi
rg -Fq "RUN_RELEASE_AUDIT must be 1 for public release signoff" "$AUDIT_BYPASS_OUTPUT" || {
  echo "Real-mode release-audit bypass failure was not reported."
  sed -n '1,120p' "$AUDIT_BYPASS_OUTPUT"
  exit 1
}

SCREENSHOT_BYPASS_OUTPUT="$TMP_DIR/screenshot-bypass-output.txt"
if RUN_RELEASE_AUDIT=1 CHECK_APP_STORE_SCREENSHOTS=0 bash "$GATE_SCRIPT" >"$SCREENSHOT_BYPASS_OUTPUT" 2>&1; then
  echo "Expected real public release mode to reject CHECK_APP_STORE_SCREENSHOTS=0."
  exit 1
fi
rg -Fq "CHECK_APP_STORE_SCREENSHOTS must be 1 for public release signoff" "$SCREENSHOT_BYPASS_OUTPUT" || {
  echo "Real-mode screenshot-check bypass failure was not reported."
  sed -n '1,120p' "$SCREENSHOT_BYPASS_OUTPUT"
  exit 1
}

FIXTURE_MODE_MISMATCH_OUTPUT="$TMP_DIR/fixture-mode-mismatch-output.txt"
if PUBLIC_GATE_TEST_FIXTURE_ONLY=1 RUN_RELEASE_AUDIT=1 bash "$GATE_SCRIPT" >"$FIXTURE_MODE_MISMATCH_OUTPUT" 2>&1; then
  echo "Expected fixture mode to require RUN_RELEASE_AUDIT=0."
  exit 1
fi
rg -Fq "PUBLIC_GATE_TEST_FIXTURE_ONLY=1 requires RUN_RELEASE_AUDIT=0" "$FIXTURE_MODE_MISMATCH_OUTPUT" || {
  echo "Fixture-mode release-audit mismatch was not reported."
  sed -n '1,120p' "$FIXTURE_MODE_MISMATCH_OUTPUT"
  exit 1
}

MISSING_ARCHIVE_OUTPUT="$TMP_DIR/missing-archive-output.txt"
if RUN_RELEASE_AUDIT=1 SIGNOFF_PATH="$PASS" PUBLIC_RELEASE_PLATFORMS="iphone,ipad,watch,mac" bash "$GATE_SCRIPT" >"$MISSING_ARCHIVE_OUTPUT" 2>&1; then
  echo "Expected public release gate to require IOS_ARCHIVE_PATH."
  exit 1
fi
rg -Fq "IOS_ARCHIVE_PATH is required for public App Store signoff" "$MISSING_ARCHIVE_OUTPUT" || {
  echo "Missing IOS_ARCHIVE_PATH failure was not reported."
  sed -n '1,120p' "$MISSING_ARCHIVE_OUTPUT"
  exit 1
}

MISSING_IPA_OUTPUT="$TMP_DIR/missing-ipa-output.txt"
if RUN_RELEASE_AUDIT=1 IOS_ARCHIVE_PATH="$TMP_DIR/fixture-ios.xcarchive" SIGNOFF_PATH="$PASS" PUBLIC_RELEASE_PLATFORMS="iphone,ipad,watch,mac" bash "$GATE_SCRIPT" >"$MISSING_IPA_OUTPUT" 2>&1; then
  echo "Expected public release gate to require IOS_IPA_PATH."
  exit 1
fi
rg -Fq "IOS_IPA_PATH is required for public App Store signoff" "$MISSING_IPA_OUTPUT" || {
  echo "Missing IOS_IPA_PATH failure was not reported."
  sed -n '1,120p' "$MISSING_IPA_OUTPUT"
  exit 1
}

MISSING_MAC_ARCHIVE_OUTPUT="$TMP_DIR/missing-mac-archive-output.txt"
if RUN_RELEASE_AUDIT=1 IOS_ARCHIVE_PATH="$TMP_DIR/fixture-ios.xcarchive" IOS_IPA_PATH="$TMP_DIR/fixture-ios.ipa" SIGNOFF_PATH="$PASS" PUBLIC_RELEASE_PLATFORMS="iphone,ipad,watch,mac" bash "$GATE_SCRIPT" >"$MISSING_MAC_ARCHIVE_OUTPUT" 2>&1; then
  echo "Expected public release gate to require MAC_ARCHIVE_PATH when mac is selected."
  exit 1
fi
rg -Fq "MAC_ARCHIVE_PATH is required when mac is selected" "$MISSING_MAC_ARCHIVE_OUTPUT" || {
  echo "Missing MAC_ARCHIVE_PATH failure was not reported."
  sed -n '1,120p' "$MISSING_MAC_ARCHIVE_OUTPUT"
  exit 1
}

MISSING_MAC_PKG_OUTPUT="$TMP_DIR/missing-mac-pkg-output.txt"
if RUN_RELEASE_AUDIT=1 IOS_ARCHIVE_PATH="$FIXTURE_IOS_ARCHIVE" IOS_IPA_PATH="$FIXTURE_IOS_IPA" MAC_ARCHIVE_PATH="$FIXTURE_MAC_ARCHIVE" SIGNOFF_PATH="$PASS" PUBLIC_RELEASE_PLATFORMS="iphone,ipad,watch,mac" bash "$GATE_SCRIPT" >"$MISSING_MAC_PKG_OUTPUT" 2>&1; then
  echo "Expected public release gate to require MAC_PKG_PATH when mac is selected."
  exit 1
fi
rg -Fq "MAC_PKG_PATH is required when mac is selected" "$MISSING_MAC_PKG_OUTPUT" || {
  echo "Missing MAC_PKG_PATH failure was not reported."
  sed -n '1,120p' "$MISSING_MAC_PKG_OUTPUT"
  exit 1
}

# The source commit deliberately predates the distinct live main fixture. This
# proves that a later docs-only signoff commit can advance main without creating
# an impossible tracked-file self-reference.
expect_pass "$PASS" "iphone,ipad,watch,mac"
expect_fail "$IPHONE_ONLY" "PUBLIC_RELEASE_PLATFORMS: current binary requires ipad,watch,mac; change the binary before omitting an enabled platform" "iphone"
expect_fail "$IPHONE_IPAD" "PUBLIC_RELEASE_PLATFORMS: current binary requires watch,mac; change the binary before omitting an enabled platform" "iphone,ipad"
expect_fail "$IPHONE_IPAD_WATCH" "PUBLIC_RELEASE_PLATFORMS: current binary requires mac; change the binary before omitting an enabled platform" "iphone,ipad,watch"
expect_fail "$WRONG_BUILD" "iOS App Store Connect build selected: expected exact value 1.0 (12), got 1.0 (9)"
expect_fail "$WRONG_MAC_BUILD" "Mac App Store Connect build selected: expected exact value 1.0 (12), got 1.0 (9)"
expect_fail "$MAC_PROCESSING_FAILED" "Mac App Store Connect status: expected exact value VALID, got PROCESSING_FAILED"
expect_fail "$SUPERSEDED_ARTIFACTS" "Artifact binding status: expected exact value CURRENT_AND_VERIFIED"
expect_fail "$WEAK_SCREENSHOTS" "Screenshots uploaded: expected exact value UPLOADED_13_IPHONE_IPAD_WATCH_MAC, got UPLOADED_4_IPHONE"
expect_fail "$MISSING_SCREENSHOT_VISUAL_QA" "Screenshot visual QA: expected exact value PASS, got PENDING"
expect_fail "$LEGACY_IOS_INTERNAL_STATE" "iOS BuildBetaDetail.internalBuildState: expected exact value IN_BETA_TESTING, got BETA_INTERNAL_TESTING"
expect_fail "$NEGATIVE_IOS_STATUS" "iOS App Store Connect status: expected exact value VALID, got NOT VALID"
expect_fail "$NEGATIVE_SELECTED_BUILD" "iOS App Store Connect build selected: expected exact value 1.0 (12), got 1.0 (12) is not selected"
expect_fail "$NEGATIVE_ARTIFACT_BINDING" "Artifact binding status: expected exact value CURRENT_AND_VERIFIED"
expect_fail "$NEGATIVE_SCREENSHOT_VISUAL_QA" "Screenshot visual QA: expected exact value PASS, got NOT PASS"
expect_fail "$NEGATIVE_SCREENSHOTS_UPLOADED" "Screenshots uploaded: expected exact value UPLOADED_13_IPHONE_IPAD_WATCH_MAC"
expect_fail "$UPPERCASE_MANIFEST_HASH" "Visual QA manifest SHA-256: record the full lowercase digest"
expect_fail "$DUPLICATE_IOS_BUILD_FIELD" "Release Owner Decision: expected exactly one 'iOS App Store Connect build selected' field, found 2"
expect_fail "$MISSING_IOS_BUILD_FIELD" "Release Owner Decision: expected exactly one 'iOS App Store Connect build selected' field, found 0"
expect_fail "$HEADER_ONLY_REQUIRED_PASSES" "Required Passes: expected exactly 20 canonical rows, found 0"
expect_fail "$MISSING_REQUIRED_PASS" "Required Passes: missing required area Install and launch"
expect_fail "$DUPLICATE_REQUIRED_PASS" "Required Passes: duplicate area Install and launch"
expect_fail "$UNEXPECTED_REQUIRED_PASS" "Required Passes: unexpected area Invented release check"
expect_fail "$MISSING_SUPPORT" "Support contact verified: blank or pending"
expect_fail "$WEAK_SUPPORT_ROUTE" "Support contact verified: expected exact value VERIFIED: https://gta-free-stem.vercel.app/support/ | GITHUB_ISSUES | MONITORED_DIRECT_CONTACT"
expect_fail "$MISSING_PRODUCTION_TRUTHFULNESS" "Production legal/support truthfulness verified: blank or pending"
expect_fail "$WEAK_PRODUCTION_TRUTHFULNESS" "Production legal/support truthfulness verified: expected exact value VERIFIED_MATCH_BUILD:"
expect_fail "$MISSING_DELIVERY" "iOS Delivery UUID: real build-12 Apple delivery UUID required"
expect_fail "$MISSING_MAC_DELIVERY" "Mac Delivery UUID: separate real Apple delivery UUID required"
expect_fail "$SAME_MAC_DELIVERY" "Mac Delivery UUID: must be separate from the iOS delivery UUID"
expect_source_state_fail \
  "$WRONG_PUBLISHED_COMMIT" \
  "Published commit: recorded source commit bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb is not reachable from live origin/main $FIXTURE_LIVE_MAIN_COMMIT" \
  0 1 1
expect_fail "$WRONG_VERIFICATION_DATE" "Artifact verification date: exact artifacts were verified today ($FIXTURE_DATE), recorded 2026-08-05"
expect_fail "$WRONG_IOS_ARCHIVE_PATH" "iOS archive path: signoff must equal verified artifact $FIXTURE_IOS_ARCHIVE"
expect_fail "$WRONG_IOS_ARCHIVE_HASH" "iOS archive SHA-256: verified $FIXTURE_IOS_ARCHIVE_SHA"
expect_fail "$WRONG_IOS_IPA_PATH" "iOS IPA path: signoff must equal verified artifact $FIXTURE_IOS_IPA"
expect_fail "$WRONG_IOS_IPA_HASH" "iOS IPA SHA-256: verified $FIXTURE_IOS_IPA_SHA"
expect_fail "$WRONG_MAC_ARCHIVE_PATH" "Mac archive path: signoff must equal verified artifact $FIXTURE_MAC_ARCHIVE"
expect_fail "$WRONG_MAC_ARCHIVE_HASH" "Mac archive SHA-256: verified $FIXTURE_MAC_ARCHIVE_SHA"
expect_fail "$WRONG_MAC_PACKAGE_PATH" "Mac package path: signoff must equal verified artifact $FIXTURE_MAC_PKG"
expect_fail "$WRONG_MAC_PACKAGE_HASH" "Mac package SHA-256: verified $FIXTURE_MAC_PKG_SHA"

expect_source_state_fail \
  "$PASS" \
  "Published source: recorded source commit app, Watch, and Xcode project inputs must byte-match live origin/main" \
  1 0 1
expect_source_state_fail \
  "$PASS" \
  "Published source: current local app, Watch, and Xcode project inputs must byte-match the recorded published source commit" \
  1 1 0
expect_artifact_source_fail \
  "dddddddddddddddddddddddddddddddddddddddd" \
  "iOS archive source commit: signed artifact embeds dddddddddddddddddddddddddddddddddddddddd, but signoff records $FIXTURE_COMMIT"
expect_fail "$MISSING_DATE" "Date: blank or pending"
expect_fail "$UNRESOLVED_BLOCKERS" "Must-fix blockers: write None only after all must-fix issues are resolved"
expect_fail "$MISSING_REVIEW_CONTACT" "App Review contact verified: blank or pending"
expect_fail "$PLACEHOLDER_COPYRIGHT" "Copyright entered: expected exact format ENTERED_APP_STORE_CONNECT_<year>: <confirmed legal-rights holder>"
expect_fail "$MISSING_PLATFORM_DECISION" "Platform record decision: blank or pending"
expect_fail "$MISSING_AVAILABILITY_DSA" "Availability and DSA verified: blank or pending"
expect_fail "$WRONG_ARCHIVE_PROVENANCE" "Archive provenance verified: expected exact value VERIFIED_SIGNED_BUILD_1_0_12_IOS_WATCH_MAC"
expect_fail "$IPHONE_ONLY" "iPad: Pending" "iphone,ipad"
expect_fail "$IPHONE_ONLY" "PUBLIC_RELEASE_PLATFORMS: set an explicit comma-separated selection using iphone,ipad,watch,mac" ""
expect_fail "$IPHONE_ONLY" "PUBLIC_RELEASE_PLATFORMS: unsupported platform tv (use iphone,ipad,watch,mac)" "iphone,tv"

expect_fail_all \
  "$NEGATED_OWNER_EVIDENCE" \
  "Archive provenance verified: expected exact value VERIFIED_SIGNED_BUILD_1_0_12_IOS_WATCH_MAC" \
  "Metadata/privacy/age rating entered: expected exact value ENTERED_METADATA_PRIVACY_AGE_RATING_KIDS_NO_EXPORT_COMPLIANCE_REVIEW_NOTES" \
  "Support contact verified: expected exact value VERIFIED:" \
  "Production legal/support truthfulness verified: expected exact value VERIFIED_MATCH_BUILD:" \
  "App Review contact verified: expected exact value VERIFIED_APP_STORE_CONNECT_2026-08-06" \
  "Primary language verified: expected exact format VERIFIED_APP_STORE_CONNECT_2026-08-06: primary_language=<locale>" \
  "Availability and DSA verified: expected exact value VERIFIED_APP_STORE_CONNECT_2026-08-06" \
  "Platform record decision: expected exact format VERIFIED_SEPARATE_MAC_RECORD:"

expect_fail_all \
  "$NEGATED_TEST_CONTEXT" \
  "Install source: expected exact value TestFlight, got Not TestFlight" \
  "Network conditions tested: expected exact value WI_FI_AND_OFFLINE_FALLBACK" \
  "Accessibility settings tested: expected exact value VOICEOVER_LARGE_TEXT_DARK_MODE" \
  "Languages tested: expected exact value ENGLISH_FRENCH_SPANISH_ARABIC_RTL"

expect_manifest_fail "$PASS" "$MISSING_MANIFEST_ROOT" "Visual QA manifest: missing $MISSING_MANIFEST_ROOT/FINAL_VISUAL_QA.md"
expect_manifest_fail "$PASS" "$CHANGED_MANIFEST_ROOT" "Visual QA manifest: content must match the canonical schema and row order exactly"
expect_manifest_fail "$CHANGED_MANIFEST_SIGNOFF" "$CHANGED_MANIFEST_ROOT" "Visual QA manifest: content must match the canonical schema and row order exactly"
expect_manifest_fail "$STALE_MANIFEST_SIGNOFF" "$STALE_MANIFEST_ROOT" "Visual QA manifest Published commit: expected exact value $FIXTURE_COMMIT, got bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
expect_manifest_fail "$PASS" "$MUTATED_SCREENSHOT_ROOT" "Visual QA screenshot iphone-6.9/01-home.jpg: SHA-256 mismatch"
expect_manifest_fail "$NO_REVIEWER_SIGNOFF" "$NO_REVIEWER_ROOT" "Visual QA manifest Reviewer: blank or pending"
expect_manifest_fail "$PASS" "$MISSING_RECEIPT_ROOT" "Capture receipt: missing regular non-symlink file"
expect_manifest_fail "$PASS" "$MUTATED_RECEIPT_ROOT" "Capture receipt hash mismatch"
expect_manifest_fail "$PASS" "$MISSING_MAC_SESSION_ROOT" "Mac capture session: missing regular non-symlink file"
expect_manifest_fail "$PASS" "$MUTATED_MAC_SESSION_ROOT" "Mac capture session hash mismatch"
expect_manifest_fail "$PASS" "$ROGUE_IMAGE_ROOT" "unexpected=mac/extra.png"

printf '%s\n' 'post-signoff mutation' >> "$FIXTURE_IOS_IPA"
expect_fail "$PASS" "iOS IPA SHA-256: verified"

echo "Public release gate self-test passed."
