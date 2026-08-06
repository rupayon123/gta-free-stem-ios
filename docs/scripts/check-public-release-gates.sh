#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

RUN_RELEASE_AUDIT="${RUN_RELEASE_AUDIT:-1}"
SIGNOFF_PATH="${SIGNOFF_PATH:-docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md}"
EXPECTED_BUILD="1.0 (12)"
IOS_ARCHIVE_PATH="${IOS_ARCHIVE_PATH:-}"
MAC_ARCHIVE_PATH="${MAC_ARCHIVE_PATH:-}"
# The metadata fixture suite sets this together with RUN_RELEASE_AUDIT=0. It is
# never a valid public-release signoff mode.
PUBLIC_GATE_TEST_FIXTURE_ONLY="${PUBLIC_GATE_TEST_FIXTURE_ONLY:-0}"
# This deliberately has no default. The release owner must state which product
# platforms are actually being enabled for public distribution.
PUBLIC_RELEASE_PLATFORMS="${PUBLIC_RELEASE_PLATFORMS:-}"

if [ "$PUBLIC_GATE_TEST_FIXTURE_ONLY" = "1" ]; then
  if [ "$RUN_RELEASE_AUDIT" != "0" ]; then
    echo "PUBLIC_GATE_TEST_FIXTURE_ONLY=1 requires RUN_RELEASE_AUDIT=0 and cannot be used for release signoff."
    exit 1
  fi
  echo "Skipping signed archive verification in explicit metadata-fixture mode."
else
  NORMALIZED_PUBLIC_PLATFORMS="$(printf '%s' "$PUBLIC_RELEASE_PLATFORMS" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  MAC_SELECTED=0
  case ",$NORMALIZED_PUBLIC_PLATFORMS," in
    *,mac,*|*,maccatalyst,*) MAC_SELECTED=1 ;;
  esac

  if [ -z "$IOS_ARCHIVE_PATH" ]; then
    echo "IOS_ARCHIVE_PATH is required for public App Store signoff and must point to the signed .xcarchive."
    exit 1
  fi
  if [ "$MAC_SELECTED" = "1" ] && [ -z "$MAC_ARCHIVE_PATH" ]; then
    echo "MAC_ARCHIVE_PATH is required when mac is selected and must point to the signed Mac Catalyst .xcarchive."
    exit 1
  fi
  echo
  echo "=== Strict iOS/iPadOS/watchOS App Store archive verification ==="
  bash docs/scripts/verify-app-store-archive.sh "$IOS_ARCHIVE_PATH"
  if [ "$MAC_SELECTED" = "1" ]; then
    echo
    echo "=== Strict Mac Catalyst App Store archive verification ==="
    bash docs/scripts/verify-mac-app-store-archive.sh "$MAC_ARCHIVE_PATH"
  fi
fi

if [ "$RUN_RELEASE_AUDIT" != "0" ]; then
  STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh
fi

/usr/bin/python3 - "$SIGNOFF_PATH" "$EXPECTED_BUILD" "$PUBLIC_RELEASE_PLATFORMS" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected_build = sys.argv[2]
configured_platforms_raw = sys.argv[3]
if not path.exists():
    raise SystemExit(f"Missing {path}")
text = path.read_text(encoding="utf-8")

def clean(value):
    return value.strip().replace(r"\`", "`").strip(chr(96)).strip()

def field_value(label):
    # Do not let a blank field consume the next Markdown line. The release
    # template intentionally leaves several fields blank until portal QA.
    match = re.search(rf"^- {re.escape(label)}:[ \t]*(.*)$", text, re.MULTILINE)
    return clean(match.group(1)) if match else ""

def is_pending(value):
    normalized = clean(value).lower()
    return normalized in {
        "", "pending", "pending upload", "not uploaded", "not submitted",
        "no", "not yet", "todo", "tbd", "n/a", "na",
    } or normalized.startswith(("include ", "record ", "enter ", "confirm "))

PLATFORM_ORDER = ("iphone", "ipad", "watch", "mac")
PLATFORM_LABELS = {
    "iphone": "iPhone",
    "ipad": "iPad",
    "watch": "Apple Watch",
    "mac": "Mac",
}
PLATFORM_ALIASES = {
    "iphone": "iphone",
    "ipad": "ipad",
    "watch": "watch",
    "apple watch": "watch",
    "mac": "mac",
    "mac catalyst": "mac",
}


def parse_platforms(value, source):
    raw = clean(value)
    if not raw:
        return set(), [
            f"{source}: set an explicit comma-separated selection using iphone,ipad,watch,mac"
        ]
    if is_pending(raw):
        return set(), [f"{source}: blank or pending"]

    platforms = set()
    problems = []
    for token in raw.split(","):
        candidate = token.strip().lower()
        canonical = PLATFORM_ALIASES.get(candidate)
        if not canonical:
            problems.append(
                f"{source}: unsupported platform {token.strip() or 'blank'} "
                "(use iphone,ipad,watch,mac)"
            )
            continue
        if canonical in platforms:
            problems.append(f"{source}: duplicate platform {canonical}")
            continue
        platforms.add(canonical)
    if not platforms and not problems:
        problems.append(
            f"{source}: set an explicit comma-separated selection using iphone,ipad,watch,mac"
        )
    return platforms, problems


def section_contents(heading):
    match = re.search(
        rf"^## {re.escape(heading)}\s*$\n?(.*?)(?=^## |\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    return match.group(1) if match else ""


def table_rows(section, expected_columns, header):
    for line in section.splitlines():
        if not line.startswith("|") or "---" in line:
            continue
        cells = [clean(cell) for cell in line.strip("|").split("|")]
        if len(cells) < expected_columns or cells[0].lower() == header.lower():
            continue
        yield cells[:expected_columns]


not_ready = []
selected_platforms, platform_errors = parse_platforms(
    configured_platforms_raw,
    "PUBLIC_RELEASE_PLATFORMS",
)
not_ready.extend(platform_errors)

project_path = Path("project.yml")
project_text = project_path.read_text(encoding="utf-8") if project_path.exists() else ""
required_platforms = set()
device_family_match = re.search(r'^\s*TARGETED_DEVICE_FAMILY:\s*["\']?([^"\'\n#]+)', project_text, re.MULTILINE)
device_families = {
    token.strip()
    for token in (device_family_match.group(1).split(",") if device_family_match else [])
}
if "1" in device_families:
    required_platforms.add("iphone")
if "2" in device_families:
    required_platforms.add("ipad")
if re.search(r"^\s*-\s*target:\s*GTAFreeSTEMWatch\s*$", project_text, re.MULTILINE):
    required_platforms.add("watch")

missing_required_platforms = required_platforms - selected_platforms
if missing_required_platforms:
    missing = ",".join(platform for platform in PLATFORM_ORDER if platform in missing_required_platforms)
    not_ready.append(
        "PUBLIC_RELEASE_PLATFORMS: current binary requires "
        f"{missing}; change the binary before omitting an enabled platform"
    )

recorded_platforms = field_value("Public distribution platforms")
if is_pending(recorded_platforms):
    not_ready.append("Public distribution platforms: blank or pending")
elif selected_platforms:
    recorded_set, recorded_errors = parse_platforms(
        recorded_platforms,
        "Public distribution platforms",
    )
    not_ready.extend(recorded_errors)
    if not recorded_errors and recorded_set != selected_platforms:
        expected = ",".join(platform for platform in PLATFORM_ORDER if platform in selected_platforms)
        observed = ",".join(platform for platform in PLATFORM_ORDER if platform in recorded_set)
        not_ready.append(
            "Public distribution platforms: signoff must match "
            f"PUBLIC_RELEASE_PLATFORMS ({expected}; recorded {observed})"
        )

required_build_facts = {
    "Version/build": expected_build,
    "App Store Connect status": "VALID",
    "TestFlight status": "BETA_INTERNAL_TESTING",
}
for label, required in required_build_facts.items():
    value = field_value(label)
    if required not in value:
        not_ready.append(f"{label}: expected {required}, got {value or 'blank'}")

delivery = field_value("Delivery UUID")
if not re.fullmatch(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", delivery):
    not_ready.append("Delivery UUID: real build-12 delivery UUID required")

for label in [
    "Tester", "Date", "Install source",
    "Network conditions tested", "Accessibility settings tested", "Languages tested",
]:
    if is_pending(field_value(label)):
        not_ready.append(f"{label}: blank or pending")

date = field_value("Date")
if date and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
    not_ready.append("Date: use YYYY-MM-DD")
if "testflight" not in field_value("Install source").lower():
    not_ready.append("Install source: expected TestFlight")

allowed = {"Pass", "Accepted Risk"}
accepted_rows = []


def validate_status(area, status, notes):
    if status not in allowed:
        not_ready.append(f"{area}: {status or 'blank'}")
    elif status == "Accepted Risk":
        accepted_rows.append(area)
        if is_pending(notes):
            not_ready.append(f"{area}: Accepted Risk needs notes")


required_passes = section_contents("Required Passes")
if not required_passes:
    not_ready.append("Required Passes: missing section")
else:
    for area, _, status, notes in table_rows(required_passes, 4, "Area"):
        validate_status(area, status, notes)

platform_evidence = {}
platform_section = section_contents("Platform-Specific Evidence")
if selected_platforms and not platform_section:
    not_ready.append("Platform-Specific Evidence: missing section")
elif platform_section:
    for platform_name, _, device, os_version, status, notes in table_rows(
        platform_section,
        6,
        "Platform",
    ):
        platform = PLATFORM_ALIASES.get(platform_name.lower())
        if not platform:
            not_ready.append(
                f"Platform-Specific Evidence: unsupported platform {platform_name or 'blank'}"
            )
            continue
        if platform in platform_evidence:
            not_ready.append(f"Platform-Specific Evidence: duplicate {PLATFORM_LABELS[platform]} row")
            continue
        platform_evidence[platform] = (device, os_version, status, notes)

for platform in PLATFORM_ORDER:
    if platform not in selected_platforms:
        continue
    label = PLATFORM_LABELS[platform]
    evidence = platform_evidence.get(platform)
    if not evidence:
        not_ready.append(f"{label}: missing platform-specific evidence")
        continue
    device, os_version, status, notes = evidence
    if is_pending(device):
        not_ready.append(f"{label} device model: blank or pending")
    if is_pending(os_version):
        not_ready.append(f"{label} OS version: blank or pending")
    validate_status(label, status, notes)

overall = field_value("Overall status")
if overall not in allowed:
    not_ready.append(f"Overall status: {overall or 'blank'}")

accepted_risks = field_value("Accepted risks")
if accepted_rows or overall == "Accepted Risk":
    if is_pending(accepted_risks):
        not_ready.append("Accepted risks: required when any risk is accepted")
elif accepted_risks.lower() not in {"none", "no accepted risks"}:
    not_ready.append("Accepted risks: write None when no risk is accepted")

for label in [
    "App Store Connect build selected", "Archive provenance verified",
    "Screenshots uploaded", "Metadata/privacy/age rating entered",
    "Support contact verified", "App Review contact verified",
    "Copyright entered", "Production legal/support truthfulness verified",
    "Primary language verified", "Availability and DSA verified",
]:
    if is_pending(field_value(label)):
        not_ready.append(f"{label}: blank or pending")
if "mac" in selected_platforms and is_pending(field_value("Platform record decision")):
    not_ready.append("Platform record decision: blank or pending")

must_fix = field_value("Must-fix blockers").lower()
if must_fix not in {"none", "no known blockers"}:
    not_ready.append("Must-fix blockers: write None only after all must-fix issues are resolved")

if expected_build not in field_value("App Store Connect build selected"):
    not_ready.append(f"App Store Connect build selected: expected {expected_build}")

screenshots = field_value("Screenshots uploaded").lower()
for platform in PLATFORM_ORDER:
    if platform not in selected_platforms:
        continue
    if platform not in screenshots:
        not_ready.append(f"Screenshots uploaded: missing {platform} evidence")

metadata = field_value("Metadata/privacy/age rating entered").lower()
for token in ["metadata", "privacy", "age", "kids", "export", "review"]:
    if token not in metadata:
        not_ready.append(f"Metadata/privacy/age rating entered: missing {token}")

archive = field_value("Archive provenance verified").lower()
if not is_pending(archive):
    archive_tokens = [expected_build.lower()]
    if selected_platforms & {"iphone", "ipad"}:
        archive_tokens.append("ios")
    if "watch" in selected_platforms:
        archive_tokens.append("watch")
    if "mac" in selected_platforms:
        archive_tokens.append("mac")
    for token in archive_tokens:
        if token not in archive:
            not_ready.append(f"Archive provenance verified: missing {token} evidence")
    if not re.search(r"\bsigned\b", archive):
        not_ready.append("Archive provenance verified: missing signed evidence")

support = field_value("Support contact verified").lower()
if not is_pending(support) and (
    "verified" not in support
    or "https://gta-free-stem.vercel.app/support/" not in support
    or "github issues" not in support
    or not any(token in support for token in ["email", "telephone", "phone"])
):
    not_ready.append(
        "Support contact verified: record the production support URL, GitHub Issues route, and monitored email or telephone contact"
    )

production_support_privacy = field_value("Production legal/support truthfulness verified")
production_support_privacy_lower = production_support_privacy.lower()
production_urls = {
    url.rstrip(".,;:")
    for url in re.findall(r"https://[^\s`<>()[\]]+", production_support_privacy_lower)
}
required_production_urls = {
    "https://gta-free-stem.vercel.app/support/",
    "https://gta-free-stem.vercel.app/privacy/",
    "https://gta-free-stem.vercel.app/terms/",
}
if not is_pending(production_support_privacy) and (
    any(token not in production_support_privacy_lower for token in ["verified", "production", "support", "privacy", "terms"])
    or not required_production_urls.issubset(production_urls)
    or "match" not in production_support_privacy_lower
):
    not_ready.append(
        "Production legal/support truthfulness verified: record a verified production review with "
        "distinct HTTPS support, privacy, and Terms URLs that match the submitted build"
    )

review_contact = field_value("App Review contact verified").lower()
if not is_pending(review_contact) and ("verified" not in review_contact or "app store connect" not in review_contact):
    not_ready.append("App Review contact verified: record portal verification without committing private contact details")

for label in ["Primary language verified", "Availability and DSA verified"]:
    value = field_value(label).lower()
    if not is_pending(value) and ("verified" not in value or "app store connect" not in value):
        not_ready.append(f"{label}: record App Store Connect verification without committing private compliance data")

copyright = field_value("Copyright entered")
copyright_lower = copyright.lower()
copyright_placeholders = {"pending", "tbd", "todo", "legal rights owner", "rights holder", "copyright owner"}
if not is_pending(copyright) and (
    not re.search(r"\b20\d{2}\b", copyright)
    or any(placeholder in copyright_lower for placeholder in copyright_placeholders)
    or len(re.sub(r"[^A-Za-z]", "", copyright)) < 5
):
    not_ready.append("Copyright entered: record the exact year and confirmed legal-rights holder used in App Store Connect")

ios_bundle_match = re.search(r"^\s*PRODUCT_BUNDLE_IDENTIFIER:\s*([^\s#]+)", project_text, re.MULTILINE)
mac_bundle_match = re.search(
    r'^\s*["\']?PRODUCT_BUNDLE_IDENTIFIER\[sdk=macosx\*\]["\']?:\s*([^\s#]+)',
    project_text,
    re.MULTILINE,
)
ios_bundle = ios_bundle_match.group(1).strip('"\'') if ios_bundle_match else ""
mac_bundle = mac_bundle_match.group(1).strip('"\'') if mac_bundle_match else ios_bundle
platform_decision = field_value("Platform record decision")
platform_lower = platform_decision.lower()
if "mac" in selected_platforms:
    if is_pending(platform_decision):
        pass
    elif "universal" in platform_lower:
        for token in ["verified", "macos", "6779714459", ios_bundle.lower()]:
            if token and token not in platform_lower:
                not_ready.append(f"Platform record decision: universal path missing {token} evidence")
        if not ios_bundle or mac_bundle != ios_bundle:
            not_ready.append("Platform record decision: universal path requires Catalyst to use the iOS bundle ID")
    elif "separate" in platform_lower:
        for token in ["verified", "mac app id", "sku", "com.rupayonhaldar.gtafreestem.maccatalyst"]:
            if token not in platform_lower:
                not_ready.append(f"Platform record decision: separate path missing {token} evidence")
        if mac_bundle != "com.rupayonhaldar.gtafreestem.maccatalyst":
            not_ready.append("Platform record decision: separate path requires the configured Catalyst bundle ID")
    else:
        not_ready.append("Platform record decision: choose verified Universal or Separate Mac record evidence")

submitted = field_value("Submitted for App Review")
if is_pending(submitted):
    print("Submitted for App Review is pending; that is acceptable until the final release decision.")

if not_ready:
    print("Public release gates are not complete:")
    for item in not_ready:
        print(f"- {item}")
    raise SystemExit(1)

print(f"Public release gates are complete for build {expected_build}.")
PY
