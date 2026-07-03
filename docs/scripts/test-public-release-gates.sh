#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

BASE_SIGNOFF="docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md"
GATE_SCRIPT="docs/scripts/check-public-release-gates.sh"
TMP_DIR="$(mktemp -d -t gtafreestem-public-gates.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [ ! -f "$BASE_SIGNOFF" ]; then
  echo "Missing $BASE_SIGNOFF"
  exit 1
fi

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
    lines = []
    replaced = False
    for line in text.splitlines():
        if line.startswith(prefix):
            lines.append(f"{prefix} {value}")
            replaced = True
        else:
            lines.append(line)
    if not replaced:
        raise SystemExit(f"Missing field: {label}")
    text = "\n".join(lines) + "\n"


def set_table_status(status, notes):
    global text
    lines = []
    for line in text.splitlines():
        if line.startswith("|") and "| Pending |" in line:
            line = line.replace("| Pending | |", f"| {status} | {notes} |")
        lines.append(line)
    text = "\n".join(lines) + "\n"


tester_values = {
    "Tester": "Release QA",
    "Date": "2026-07-03",
    "Device model": "iPhone 17",
    "iOS/iPadOS version": "iOS 26.5",
    "Install source": "TestFlight",
    "Network conditions tested": "Wi-Fi, Airplane Mode, location denied/allowed",
    "Accessibility settings tested": "VoiceOver, Large Accessibility Text, Dark Mode",
    "Languages tested": "English, French, Spanish, Punjabi, Japanese, Arabic",
}
owner_values = {
    "Overall status": "`Pass`",
    "Accepted risks": "None",
    "Must-fix blockers": "None",
    "App Store Connect build selected": "1.0 (10)",
    "Screenshots uploaded": "8 screenshots uploaded: 4 iPhone 6.9 + 4 iPad 13",
    "Metadata/privacy/age rating entered": "Metadata, App Privacy, age rating, export compliance, and review notes entered",
    "Submitted for App Review": "Pending until final click",
}

for field, value in tester_values.items():
    replace_line(field, value)
for field, value in owner_values.items():
    replace_line(field, value)
set_table_status("Pass", "Observed during gate self-test fixture.")

if mode == "pass":
    pass
elif mode == "wrong-build":
    replace_line("App Store Connect build selected", "1.0 (9)")
elif mode == "weak-screenshots":
    replace_line("Screenshots uploaded", "Yes")
elif mode == "weak-metadata":
    replace_line("Metadata/privacy/age rating entered", "Done")
elif mode == "missing-delivery":
    text = text.replace("Delivery UUID: `97c05d63-7f3d-45bc-941e-c10432694ca8`", "Delivery UUID: `missing`")
else:
    raise SystemExit(f"Unknown fixture mode: {mode}")

target.write_text(text, encoding="utf-8")
PY
}

expect_pass() {
  local label="$1"
  local fixture="$2"

  RUN_RELEASE_AUDIT=0 SIGNOFF_PATH="$fixture" bash "$GATE_SCRIPT" >/tmp/gtafreestem-gate-pass.out
  echo "PASS fixture accepted: $label"
}

expect_fail() {
  local label="$1"
  local fixture="$2"
  local expected="$3"
  local output="$TMP_DIR/${label}.out"

  set +e
  RUN_RELEASE_AUDIT=0 SIGNOFF_PATH="$fixture" bash "$GATE_SCRIPT" >"$output" 2>&1
  local status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "Expected gate fixture to fail but it passed: $label"
    cat "$output"
    exit 1
  fi
  if ! grep -Fq "$expected" "$output"; then
    echo "Gate fixture failed without expected message: $label"
    echo "Expected: $expected"
    cat "$output"
    exit 1
  fi
  echo "FAIL fixture rejected as expected: $label"
}

PASS_FIXTURE="$TMP_DIR/pass.md"
WRONG_BUILD_FIXTURE="$TMP_DIR/wrong-build.md"
WEAK_SCREENSHOTS_FIXTURE="$TMP_DIR/weak-screenshots.md"
WEAK_METADATA_FIXTURE="$TMP_DIR/weak-metadata.md"
MISSING_DELIVERY_FIXTURE="$TMP_DIR/missing-delivery.md"

make_fixture pass "$PASS_FIXTURE"
make_fixture wrong-build "$WRONG_BUILD_FIXTURE"
make_fixture weak-screenshots "$WEAK_SCREENSHOTS_FIXTURE"
make_fixture weak-metadata "$WEAK_METADATA_FIXTURE"
make_fixture missing-delivery "$MISSING_DELIVERY_FIXTURE"

expect_pass "complete signoff" "$PASS_FIXTURE"
expect_fail "wrong selected build" "$WRONG_BUILD_FIXTURE" "App Store Connect build selected: expected 1.0 (10)"
expect_fail "weak screenshot evidence" "$WEAK_SCREENSHOTS_FIXTURE" "Screenshots uploaded: include evidence for 8 screenshots, iPhone, and iPad"
expect_fail "weak metadata evidence" "$WEAK_METADATA_FIXTURE" "Metadata/privacy/age rating entered: mention metadata, privacy, and age rating"
expect_fail "missing delivery UUID" "$MISSING_DELIVERY_FIXTURE" "Real-device signoff is missing required build facts"

echo "Public release gate self-test passed."
