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
  'Mac Delivery UUID'; do
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

gate_fixture() {
  local recorded_reachable_from_live="${3:-1}"
  local recorded_matches_live_source="${4:-1}"
  local local_matches_recorded_source="${5:-1}"
  local artifact_source_commit="${6:-$FIXTURE_COMMIT}"
  PUBLIC_GATE_TEST_FIXTURE_ONLY=1 \
    PUBLIC_GATE_TEST_LIVE_MAIN_COMMIT="$FIXTURE_LIVE_MAIN_COMMIT" \
    PUBLIC_GATE_TEST_TODAY="$FIXTURE_DATE" \
    PUBLIC_GATE_TEST_RECORDED_REACHABLE_FROM_LIVE="$recorded_reachable_from_live" \
    PUBLIC_GATE_TEST_RECORDED_MATCHES_LIVE_SOURCE="$recorded_matches_live_source" \
    PUBLIC_GATE_TEST_LOCAL_MATCHES_RECORDED_SOURCE="$local_matches_recorded_source" \
    PUBLIC_GATE_TEST_ARTIFACT_SOURCE_COMMIT="$artifact_source_commit" \
    RUN_RELEASE_AUDIT=0 \
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
    "$FIXTURE_MAC_PKG_SHA" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
mode = sys.argv[3]
commit, verification_date = sys.argv[4:6]
ios_archive, ios_archive_sha, ios_ipa, ios_ipa_sha = sys.argv[6:10]
mac_archive, mac_archive_sha, mac_pkg, mac_pkg_sha = sys.argv[10:14]
text = source.read_text(encoding="utf-8")

def replace_line(label, value):
    global text
    prefix = f"- {label}:"
    rows = []
    for row in text.splitlines():
        rows.append(f"{prefix} {value}" if row.startswith(prefix) else row)
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
        "Apple Watch": "Paired Watch companion loads compact live/cache data and remains readable.",
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
    "Network conditions tested": "Wi-Fi and offline fallback",
    "Accessibility settings tested": "VoiceOver, Large Text, Dark Mode",
    "Languages tested": "English, French, Spanish, Arabic",
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
    "App Store Connect status": "VALID",
    "TestFlight status": "BETA_INTERNAL_TESTING",
    "Public distribution platforms": "iphone,ipad,watch,mac",
    "Overall status": "Pass",
    "Accepted risks": "None",
    "Must-fix blockers": "None",
    "App Store Connect build selected": "1.0 (12)",
    "Archive provenance verified": "Strict gate verified signed iOS IPA with Watch and Mac package from the recorded build 1.0 (12) archives before unchanged delivery",
    "Screenshots uploaded": "11 screenshots verified: iPhone, iPad, Mac, and Watch",
    "Metadata/privacy/age rating entered": "Metadata, App Privacy, age rating, Made for Kids No, export compliance, and review notes entered",
    "Support contact verified": "Verified https://gta-free-stem.vercel.app/support/, confirmed GitHub Issues route, and monitored support email",
    "Production legal/support truthfulness verified": "Verified production https://gta-free-stem.vercel.app/support/ support, https://gta-free-stem.vercel.app/privacy/ privacy, and https://gta-free-stem.vercel.app/terms/ Terms pages match the submitted build",
    "App Review contact verified": "Verified in App Store Connect on 2026-08-06",
    "Copyright entered": "2026 Rupayon Haldar",
    "Platform record decision": "Verified Separate Mac record: Mac App ID 6779714460, SKU gta-free-stem-mac, com.rupayonhaldar.gtafreestem.maccatalyst",
    "Primary language verified": "Verified in App Store Connect on 2026-08-06",
    "Availability and DSA verified": "Verified in App Store Connect on 2026-08-06",
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
    replace_line("App Store Connect build selected", "1.0 (9)")
elif mode == "weak-screenshots":
    replace_line("Screenshots uploaded", "iPhone only")
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
    replace_line("Archive provenance verified", "Signed iOS build 1.0 (12) archive uploaded")
    replace_line("Screenshots uploaded", "4 screenshots verified: iPhone")
    replace_line("Platform record decision", "Pending")
    set_platform_row("iPad", "", "", "Pending", "")
    set_platform_row("Apple Watch", "", "", "Pending", "")
    set_platform_row("Mac", "", "", "Pending", "")
elif mode == "iphone-ipad":
    replace_line("Public distribution platforms", "iphone,ipad")
    replace_line("Archive provenance verified", "Signed iOS build 1.0 (12) archive with embedded Watch companion uploaded")
    replace_line("Screenshots uploaded", "8 screenshots verified: iPhone and iPad")
    replace_line("Platform record decision", "Pending")
    set_platform_row("Apple Watch", "", "", "Pending", "")
    set_platform_row("Mac", "", "", "Pending", "")
elif mode != "pass":
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

PASS="$TMP_DIR/pass.md"
WRONG_BUILD="$TMP_DIR/wrong-build.md"
WEAK_SCREENSHOTS="$TMP_DIR/weak-screenshots.md"
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

make_fixture pass "$PASS"
make_fixture wrong-build "$WRONG_BUILD"
make_fixture weak-screenshots "$WEAK_SCREENSHOTS"
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

MISSING_ARCHIVE_OUTPUT="$TMP_DIR/missing-archive-output.txt"
if RUN_RELEASE_AUDIT=0 SIGNOFF_PATH="$PASS" PUBLIC_RELEASE_PLATFORMS="iphone,ipad,watch,mac" bash "$GATE_SCRIPT" >"$MISSING_ARCHIVE_OUTPUT" 2>&1; then
  echo "Expected public release gate to require IOS_ARCHIVE_PATH."
  exit 1
fi
rg -Fq "IOS_ARCHIVE_PATH is required for public App Store signoff" "$MISSING_ARCHIVE_OUTPUT" || {
  echo "Missing IOS_ARCHIVE_PATH failure was not reported."
  sed -n '1,120p' "$MISSING_ARCHIVE_OUTPUT"
  exit 1
}

MISSING_IPA_OUTPUT="$TMP_DIR/missing-ipa-output.txt"
if RUN_RELEASE_AUDIT=0 IOS_ARCHIVE_PATH="$TMP_DIR/fixture-ios.xcarchive" SIGNOFF_PATH="$PASS" PUBLIC_RELEASE_PLATFORMS="iphone,ipad,watch,mac" bash "$GATE_SCRIPT" >"$MISSING_IPA_OUTPUT" 2>&1; then
  echo "Expected public release gate to require IOS_IPA_PATH."
  exit 1
fi
rg -Fq "IOS_IPA_PATH is required for public App Store signoff" "$MISSING_IPA_OUTPUT" || {
  echo "Missing IOS_IPA_PATH failure was not reported."
  sed -n '1,120p' "$MISSING_IPA_OUTPUT"
  exit 1
}

MISSING_MAC_ARCHIVE_OUTPUT="$TMP_DIR/missing-mac-archive-output.txt"
if RUN_RELEASE_AUDIT=0 IOS_ARCHIVE_PATH="$TMP_DIR/fixture-ios.xcarchive" IOS_IPA_PATH="$TMP_DIR/fixture-ios.ipa" SIGNOFF_PATH="$PASS" PUBLIC_RELEASE_PLATFORMS="iphone,ipad,watch,mac" bash "$GATE_SCRIPT" >"$MISSING_MAC_ARCHIVE_OUTPUT" 2>&1; then
  echo "Expected public release gate to require MAC_ARCHIVE_PATH when mac is selected."
  exit 1
fi
rg -Fq "MAC_ARCHIVE_PATH is required when mac is selected" "$MISSING_MAC_ARCHIVE_OUTPUT" || {
  echo "Missing MAC_ARCHIVE_PATH failure was not reported."
  sed -n '1,120p' "$MISSING_MAC_ARCHIVE_OUTPUT"
  exit 1
}

MISSING_MAC_PKG_OUTPUT="$TMP_DIR/missing-mac-pkg-output.txt"
if RUN_RELEASE_AUDIT=0 IOS_ARCHIVE_PATH="$FIXTURE_IOS_ARCHIVE" IOS_IPA_PATH="$FIXTURE_IOS_IPA" MAC_ARCHIVE_PATH="$FIXTURE_MAC_ARCHIVE" SIGNOFF_PATH="$PASS" PUBLIC_RELEASE_PLATFORMS="iphone,ipad,watch,mac" bash "$GATE_SCRIPT" >"$MISSING_MAC_PKG_OUTPUT" 2>&1; then
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
expect_fail "$IPHONE_ONLY" "PUBLIC_RELEASE_PLATFORMS: current binary requires ipad,watch; change the binary before omitting an enabled platform" "iphone"
expect_fail "$IPHONE_IPAD" "PUBLIC_RELEASE_PLATFORMS: current binary requires watch; change the binary before omitting an enabled platform" "iphone,ipad"
expect_fail "$WRONG_BUILD" "App Store Connect build selected: expected 1.0 (12)"
expect_fail "$WEAK_SCREENSHOTS" "Screenshots uploaded: missing ipad evidence"
expect_fail "$MISSING_SUPPORT" "Support contact verified: blank or pending"
expect_fail "$WEAK_SUPPORT_ROUTE" "Support contact verified: record the production support URL, GitHub Issues route, and monitored email or telephone contact"
expect_fail "$MISSING_PRODUCTION_TRUTHFULNESS" "Production legal/support truthfulness verified: blank or pending"
expect_fail "$WEAK_PRODUCTION_TRUTHFULNESS" "Production legal/support truthfulness verified: record a verified production review with distinct HTTPS support, privacy, and Terms URLs that match the submitted build"
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
expect_fail "$PLACEHOLDER_COPYRIGHT" "Copyright entered: record the exact year and confirmed legal-rights holder used in App Store Connect"
expect_fail "$MISSING_PLATFORM_DECISION" "Platform record decision: blank or pending"
expect_fail "$MISSING_AVAILABILITY_DSA" "Availability and DSA verified: blank or pending"
expect_fail "$WRONG_ARCHIVE_PROVENANCE" "Archive provenance verified: missing signed evidence"
expect_fail "$IPHONE_ONLY" "iPad: Pending" "iphone,ipad"
expect_fail "$IPHONE_ONLY" "PUBLIC_RELEASE_PLATFORMS: set an explicit comma-separated selection using iphone,ipad,watch,mac" ""
expect_fail "$IPHONE_ONLY" "PUBLIC_RELEASE_PLATFORMS: unsupported platform tv (use iphone,ipad,watch,mac)" "iphone,tv"

printf '%s\n' 'post-signoff mutation' >> "$FIXTURE_IOS_IPA"
expect_fail "$PASS" "iOS IPA SHA-256: verified"

echo "Public release gate self-test passed."
