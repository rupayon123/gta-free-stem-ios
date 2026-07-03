#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

RUN_RELEASE_AUDIT="${RUN_RELEASE_AUDIT:-1}"
SIGNOFF_PATH="${SIGNOFF_PATH:-docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md}"

if [ "$RUN_RELEASE_AUDIT" != "0" ]; then
  STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh
fi

/usr/bin/python3 - "$SIGNOFF_PATH" <<'PY'
import re
import sys
from pathlib import Path

signoff_path = Path(sys.argv[1])
if not signoff_path.exists():
    raise SystemExit(f"Missing {signoff_path}")

text = signoff_path.read_text(encoding="utf-8")

required_facts = [
    "Version/build: `1.0 (10)`",
    "Delivery UUID: `97c05d63-7f3d-45bc-941e-c10432694ca8`",
    "App Store Connect status: `VALID`",
    "TestFlight status: `BETA_INTERNAL_TESTING`",
]
missing_facts = [fact for fact in required_facts if fact not in text]
if missing_facts:
    raise SystemExit("Real-device signoff is missing required build facts:\n" + "\n".join(f"- {fact}" for fact in missing_facts))

allowed_statuses = {"Pass", "Accepted Risk"}
pending_values = {"", "pending", "no", "not yet", "todo", "tbd"}
empty_decision_values = pending_values | {"none", "n/a", "na", "not applicable"}
not_ready = []
accepted_risk_rows = []

def clean(value):
    return value.strip().strip("`").strip()

def field_value(field):
    match = re.search(rf"^- {re.escape(field)}:[ \t]*(.*)$", text, re.MULTILINE)
    return clean(match.group(1)) if match else ""

def is_pending(value):
    return clean(value).lower() in pending_values

tester_fields = [
    "Tester",
    "Date",
    "Device model",
    "iOS/iPadOS version",
    "Install source",
    "Network conditions tested",
    "Accessibility settings tested",
    "Languages tested",
]
for field in tester_fields:
    value = field_value(field)
    if is_pending(value):
        not_ready.append(f"{field}: {value or 'blank'}")

date_value = field_value("Date")
if date_value and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date_value):
    not_ready.append("Date: use YYYY-MM-DD")

install_source = field_value("Install source").lower()
if install_source and "testflight" not in install_source:
    not_ready.append(f"Install source: expected TestFlight, got {field_value('Install source')}")

for line in text.splitlines():
    if not line.startswith("|") or "---" in line or "Required evidence" in line:
        continue
    cells = [cell.strip() for cell in line.strip("|").split("|")]
    if len(cells) < 4:
        continue
    area, evidence, status, notes = [clean(cell) for cell in cells[:4]]
    if status not in allowed_statuses:
        not_ready.append(f"{area}: {status or 'blank'}")
    elif status == "Accepted Risk":
        accepted_risk_rows.append(area)
        if is_pending(notes):
            not_ready.append(f"{area}: Accepted Risk requires notes")

overall_match = re.search(r"^- Overall status:[ \t]*`?([^`\n]+)`?", text, re.MULTILINE)
overall = overall_match.group(1).strip() if overall_match else ""
if overall not in allowed_statuses:
    not_ready.append(f"Overall status: {overall or 'blank'}")

owner_fields = [
    "Accepted risks",
    "Must-fix blockers",
]
for field in owner_fields:
    value = field_value(field)
    if is_pending(value):
        not_ready.append(f"{field}: {value or 'blank'}")

selected_build = field_value("App Store Connect build selected")
if is_pending(selected_build):
    not_ready.append("App Store Connect build selected: blank")
elif "1.0 (10)" not in selected_build:
    not_ready.append(f"App Store Connect build selected: expected 1.0 (10), got {selected_build}")

screenshots = field_value("Screenshots uploaded")
screenshots_lower = screenshots.lower()
if is_pending(screenshots):
    not_ready.append("Screenshots uploaded: blank")
elif not (("8" in screenshots_lower or "eight" in screenshots_lower) and "iphone" in screenshots_lower and "ipad" in screenshots_lower):
    not_ready.append("Screenshots uploaded: include evidence for 8 screenshots, iPhone, and iPad")

metadata = field_value("Metadata/privacy/age rating entered")
metadata_lower = metadata.lower()
if is_pending(metadata):
    not_ready.append("Metadata/privacy/age rating entered: blank")
elif not all(fragment in metadata_lower for fragment in ["metadata", "privacy", "age"]):
    not_ready.append("Metadata/privacy/age rating entered: mention metadata, privacy, and age rating")

accepted_risks_value = field_value("Accepted risks").lower()
if (accepted_risk_rows or overall == "Accepted Risk") and accepted_risks_value in empty_decision_values:
    not_ready.append("Accepted risks: describe every accepted risk when any row or overall status is Accepted Risk")

submit_match = re.search(r"^- Submitted for App Review:[ \t]*(.*)$", text, re.MULTILINE)
submitted_value = clean(submit_match.group(1)) if submit_match else ""
if submitted_value.lower() in pending_values:
    print("Submitted for App Review is not yet marked complete; this is acceptable before the final submit click.")

if not_ready:
    print("Public release gates are not complete yet:")
    for item in not_ready:
        print(f"- {item}")
    raise SystemExit(1)

print("Public release gates are complete for build 1.0 (10).")
PY
