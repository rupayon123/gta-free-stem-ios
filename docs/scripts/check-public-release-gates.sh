#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

RUN_RELEASE_AUDIT="${RUN_RELEASE_AUDIT:-1}"
SIGNOFF_PATH="docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md"

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
    "Version/build: `1.0 (9)`",
    "App Store Connect status: `VALID`",
    "TestFlight status: `BETA_INTERNAL_TESTING`",
]
missing_facts = [fact for fact in required_facts if fact not in text]
if missing_facts:
    raise SystemExit("Real-device signoff is missing required build facts:\n" + "\n".join(f"- {fact}" for fact in missing_facts))

allowed_statuses = {"Pass", "Accepted Risk"}
not_ready = []
for line in text.splitlines():
    if not line.startswith("|") or "---" in line or "Required evidence" in line:
        continue
    cells = [cell.strip() for cell in line.strip("|").split("|")]
    if len(cells) < 4:
        continue
    area, evidence, status, notes = cells[:4]
    if status not in allowed_statuses:
        not_ready.append(f"{area}: {status or 'blank'}")

overall_match = re.search(r"^- Overall status:\s*`?([^`\n]+)`?", text, re.MULTILINE)
overall = overall_match.group(1).strip() if overall_match else ""
if overall not in allowed_statuses:
    not_ready.append(f"Overall status: {overall or 'blank'}")

owner_fields = [
    "App Store Connect build selected",
    "Screenshots uploaded",
    "Metadata/privacy/age rating entered",
]
for field in owner_fields:
    match = re.search(rf"^- {re.escape(field)}:\s*(.*)$", text, re.MULTILINE)
    value = match.group(1).strip() if match else ""
    if not value or value.lower() in {"pending", "no", "not yet", "todo", "tbd"}:
        not_ready.append(f"{field}: {value or 'blank'}")

submit_match = re.search(r"^- Submitted for App Review:\s*(.*)$", text, re.MULTILINE)
submitted_value = submit_match.group(1).strip() if submit_match else ""
if submitted_value.lower() in {"", "pending", "no", "not yet", "todo", "tbd"}:
    print("Submitted for App Review is not yet marked complete; this is acceptable before the final submit click.")

if not_ready:
    print("Public release gates are not complete yet:")
    for item in not_ready:
        print(f"- {item}")
    raise SystemExit(1)

print("Public release gates are complete for build 1.0 (9).")
PY
