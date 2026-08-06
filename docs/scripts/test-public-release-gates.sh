#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

BASE_SIGNOFF="docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md"
GATE_SCRIPT="docs/scripts/check-public-release-gates.sh"
TMP_DIR="$(mktemp -d -t gtafreestem-public-gates.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

make_fixture() {
  local mode="$1"
  local output="$2"

  /usr/bin/python3 - "$BASE_SIGNOFF" "$output" "$mode" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
mode = sys.argv[3]
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
    "Delivery UUID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "App Store Connect status": "VALID",
    "TestFlight status": "BETA_INTERNAL_TESTING",
    "Public distribution platforms": "iphone,ipad,watch,mac",
    "Overall status": "Pass",
    "Accepted risks": "None",
    "Must-fix blockers": "None",
    "App Store Connect build selected": "1.0 (12)",
    "Archive provenance verified": "Signed iOS and Mac build 1.0 (12) archives with embedded Watch companion uploaded",
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
    replace_line("Delivery UUID", "missing")
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
  if ! RUN_RELEASE_AUDIT=0 PUBLIC_GATE_TEST_FIXTURE_ONLY=1 SIGNOFF_PATH="$1" PUBLIC_RELEASE_PLATFORMS="$platforms" bash "$GATE_SCRIPT" >"$output" 2>&1; then
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
  if RUN_RELEASE_AUDIT=0 PUBLIC_GATE_TEST_FIXTURE_ONLY=1 SIGNOFF_PATH="$fixture" PUBLIC_RELEASE_PLATFORMS="$platforms" bash "$GATE_SCRIPT" >"$output" 2>&1; then
    echo "Expected release-gate fixture to fail."
    exit 1
  fi
  rg -Fq "$expected" "$output" || { echo "Expected error missing: $expected"; sed -n '1,220p' "$output"; exit 1; }
}

PASS="$TMP_DIR/pass.md"
WRONG_BUILD="$TMP_DIR/wrong-build.md"
WEAK_SCREENSHOTS="$TMP_DIR/weak-screenshots.md"
MISSING_SUPPORT="$TMP_DIR/missing-support.md"
WEAK_SUPPORT_ROUTE="$TMP_DIR/weak-support-route.md"
MISSING_PRODUCTION_TRUTHFULNESS="$TMP_DIR/missing-production-truthfulness.md"
WEAK_PRODUCTION_TRUTHFULNESS="$TMP_DIR/weak-production-truthfulness.md"
MISSING_DELIVERY="$TMP_DIR/missing-delivery.md"
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

MISSING_MAC_ARCHIVE_OUTPUT="$TMP_DIR/missing-mac-archive-output.txt"
if RUN_RELEASE_AUDIT=0 IOS_ARCHIVE_PATH="$TMP_DIR/fixture-ios.xcarchive" SIGNOFF_PATH="$PASS" PUBLIC_RELEASE_PLATFORMS="iphone,ipad,watch,mac" bash "$GATE_SCRIPT" >"$MISSING_MAC_ARCHIVE_OUTPUT" 2>&1; then
  echo "Expected public release gate to require MAC_ARCHIVE_PATH when mac is selected."
  exit 1
fi
rg -Fq "MAC_ARCHIVE_PATH is required when mac is selected" "$MISSING_MAC_ARCHIVE_OUTPUT" || {
  echo "Missing MAC_ARCHIVE_PATH failure was not reported."
  sed -n '1,120p' "$MISSING_MAC_ARCHIVE_OUTPUT"
  exit 1
}

expect_pass "$PASS" "iphone,ipad,watch,mac"
expect_fail "$IPHONE_ONLY" "PUBLIC_RELEASE_PLATFORMS: current binary requires ipad,watch; change the binary before omitting an enabled platform" "iphone"
expect_fail "$IPHONE_IPAD" "PUBLIC_RELEASE_PLATFORMS: current binary requires watch; change the binary before omitting an enabled platform" "iphone,ipad"
expect_fail "$WRONG_BUILD" "App Store Connect build selected: expected 1.0 (12)"
expect_fail "$WEAK_SCREENSHOTS" "Screenshots uploaded: missing ipad evidence"
expect_fail "$MISSING_SUPPORT" "Support contact verified: blank or pending"
expect_fail "$WEAK_SUPPORT_ROUTE" "Support contact verified: record the production support URL, GitHub Issues route, and monitored email or telephone contact"
expect_fail "$MISSING_PRODUCTION_TRUTHFULNESS" "Production legal/support truthfulness verified: blank or pending"
expect_fail "$WEAK_PRODUCTION_TRUTHFULNESS" "Production legal/support truthfulness verified: record a verified production review with distinct HTTPS support, privacy, and Terms URLs that match the submitted build"
expect_fail "$MISSING_DELIVERY" "Delivery UUID: real build-12 delivery UUID required"
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

echo "Public release gate self-test passed."
