#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
LIVE_FEED_FILE=""
APPLE_STATUS_FILE=""
trap 'rm -f "$LIVE_FEED_FILE" "$APPLE_STATUS_FILE"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for JSON checks."
  exit 1
fi

STRICT_TRANSLATION_CHECK="${STRICT_TRANSLATION_CHECK:-0}"
CHECK_APP_STORE_SCREENSHOTS="${CHECK_APP_STORE_SCREENSHOTS:-1}"
if [ "$STRICT_TRANSLATION_CHECK" != "0" ]; then
  echo "Strict untranslated-language checks are enabled."
fi

echo "=== Static locale coverage checks ==="
APP_STRINGS_PATH="GTAFreeSTEM/Resources/app_strings.json"
OPPORTUNITIES_PATH="GTAFreeSTEM/Resources/opportunities.json"
SUPPORTED_TRANSLATION_LANGS='["fr","zh","yue","pa","ur","ta","tl","es","ar","fa","hi","pt","gu","bn","ja","ko","hu"]'

if [ -f "$APP_STRINGS_PATH" ]; then
  echo "app_strings.json:"
  jq -r 'keys[]' "$APP_STRINGS_PATH" >/dev/null
else
  echo "Missing GTAFreeSTEM/Resources/app_strings.json"
  exit 1
fi
if [ ! -f "$OPPORTUNITIES_PATH" ]; then
  echo "Missing GTAFreeSTEM/Resources/opportunities.json"
  exit 1
fi

TOTAL_OPPS=$(jq '(.opportunities // .data) | length' "$OPPORTUNITIES_PATH")
TRANSLATED_OPPS=$(jq '[(.opportunities // .data)[] | select(((.translations // .localizations // .localized // {}) | length) > 0)] | length' "$OPPORTUNITIES_PATH")
SUMMARY_TRANSLATED_OPPS=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.summary // "")] | any(. != ""))] | length' "$OPPORTUNITIES_PATH")
CATEGORY_TRANSLATED_OPPS=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.category // "")] | any(. != ""))] | length' "$OPPORTUNITIES_PATH")
COST_TRANSLATED_OPPS=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.cost // "")] | any(. != "" and . != "Free"))] | length' "$OPPORTUNITIES_PATH")
TITLE_TRANSLATED_OPPS=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.title // "")] | any(. != ""))] | length' "$OPPORTUNITIES_PATH")
DESCRIPTION_TRANSLATED_OPPS=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.description // "")] | any(. != ""))] | length' "$OPPORTUNITIES_PATH")
CATEGORY_ONLY_TRANSLATED_OPPS=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.category // "")] | any(. != ""))] | length' "$OPPORTUNITIES_PATH")
CITY_TRANSLATED_OPPS=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.city // "")] | any(. != ""))] | length' "$OPPORTUNITIES_PATH")
REGION_TRANSLATED_OPPS=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.region // "")] | any(. != ""))] | length' "$OPPORTUNITIES_PATH")
ADDRESS_TRANSLATED_OPPS=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.address // "")] | any(. != ""))] | length' "$OPPORTUNITIES_PATH")
ALL_LANGUAGE_SUMMARY_OPPS=$(jq --argjson langs "$SUPPORTED_TRANSLATION_LANGS" '
  [(.opportunities // .data)[] | select(
    (.translations // .localizations // .localized // {}) as $translations
    | $langs | all(. as $lang | (($translations[$lang].summary // "") != ""))
  )] | length
' "$OPPORTUNITIES_PATH")
ALL_LANGUAGE_CATEGORY_OPPS=$(jq --argjson langs "$SUPPORTED_TRANSLATION_LANGS" '
  [(.opportunities // .data)[] | select(
    (.translations // .localizations // .localized // {}) as $translations
    | $langs | all(. as $lang | (($translations[$lang].category // "") != ""))
  )] | length
' "$OPPORTUNITIES_PATH")
ALL_LANGUAGE_COST_OPPS=$(jq --argjson langs "$SUPPORTED_TRANSLATION_LANGS" '
  [(.opportunities // .data)[] | select(
    (.translations // .localizations // .localized // {}) as $translations
    | $langs | all(. as $lang | (($translations[$lang].cost // "") != "" and ($translations[$lang].cost // "") != "Free"))
  )] | length
' "$OPPORTUNITIES_PATH")
ALL_LANGUAGE_TITLE_OPPS=$(jq --argjson langs "$SUPPORTED_TRANSLATION_LANGS" '
  [(.opportunities // .data)[] | select(
    (.translations // .localizations // .localized // {}) as $translations
    | $langs | all(. as $lang | (($translations[$lang].title // "") != ""))
  )] | length
' "$OPPORTUNITIES_PATH")
ALL_LANGUAGE_DESCRIPTION_OPPS=$(jq --argjson langs "$SUPPORTED_TRANSLATION_LANGS" '
  [(.opportunities // .data)[] | select(
    (.translations // .localizations // .localized // {}) as $translations
    | $langs | all(. as $lang | (($translations[$lang].description // "") != ""))
  )] | length
' "$OPPORTUNITIES_PATH")

TOTAL_OPPORTUNITIES_WITH_TRANSLATION_KEYS=$(jq '[(.opportunities // .data)[] | select(((.translations // .localizations // .localized // {}) | length) > 0)] | length' "$OPPORTUNITIES_PATH")

echo "Total opportunities: ${TOTAL_OPPS}"
echo "Opportunities with any translation payload: ${TRANSLATED_OPPS}"
echo "Opportunities with any translated/generated summary: ${SUMMARY_TRANSLATED_OPPS}"
echo "Opportunities with any translated/generated category: ${CATEGORY_TRANSLATED_OPPS}"
echo "Opportunities with localized cost: ${COST_TRANSLATED_OPPS}"
echo "Opportunities with any translated title: ${TITLE_TRANSLATED_OPPS}"
echo "Opportunities with any translated description: ${DESCRIPTION_TRANSLATED_OPPS}"
echo "Opportunities with summaries for every non-English launch language: ${ALL_LANGUAGE_SUMMARY_OPPS}"
echo "Opportunities with categories for every non-English launch language: ${ALL_LANGUAGE_CATEGORY_OPPS}"
echo "Opportunities with costs for every non-English launch language: ${ALL_LANGUAGE_COST_OPPS}"
echo "Opportunities with titles for every non-English launch language: ${ALL_LANGUAGE_TITLE_OPPS}"
echo "Opportunities with descriptions for every non-English launch language: ${ALL_LANGUAGE_DESCRIPTION_OPPS}"
echo "Opportunity translation key coverage (any non-empty per locale): ${TOTAL_OPPORTUNITIES_WITH_TRANSLATION_KEYS}"
if [ "${TOTAL_OPPS}" -eq 0 ]; then
  echo "Translation coverage: 0%"
else
  echo "Summary translation coverage: $(( SUMMARY_TRANSLATED_OPPS * 100 / TOTAL_OPPS ))%"
  echo "Category translation coverage: $(( CATEGORY_TRANSLATED_OPPS * 100 / TOTAL_OPPS ))%"
  echo "Cost translation coverage: $(( COST_TRANSLATED_OPPS * 100 / TOTAL_OPPS ))%"
  echo "Title translation coverage: $(( TITLE_TRANSLATED_OPPS * 100 / TOTAL_OPPS ))%"
  echo "Description translation coverage: $(( DESCRIPTION_TRANSLATED_OPPS * 100 / TOTAL_OPPS ))%"
fi

for language in fr zh yue pa ur ta tl es ar fa hi pt gu bn ja ko hu; do
  MATCHED=$(jq -r --arg lang "$language" '
    . as $root
    | ($root.en // {}) as $en
    | ($root[$lang] // {}) as $localized
    | [ $en | to_entries[] | select(($localized[.key] // "") == .value and .value != "") ] | length
  ' "$APP_STRINGS_PATH")
  EN_KEY_COUNT=$(jq '.en | length' "$APP_STRINGS_PATH")
  echo "${language}: ${MATCHED}/${EN_KEY_COUNT} strings still match English"
  if [ "$MATCHED" -ne 0 ]; then
    echo "  ${language} untranslated keys:"
    jq -r --arg lang "$language" '
      . as $root
      | ($root.en // {}) as $en
      | ($root[$lang] // {}) as $localized
      | [ $en | to_entries[] | select(($localized[.key] // "") == .value and .value != "") ]
      | .[]?.key
    ' "$APP_STRINGS_PATH" | sed 's/^/    - /'
  fi
done

echo -e "\n=== Launch language count ==="
EN_KEYS=$(jq '.en | length' "$APP_STRINGS_PATH")
for language in en fr zh yue pa ur ta tl es ar fa hi pt gu bn ja ko hu; do
  COUNT=$(jq -r ".\"${language}\" | length // 0" "$APP_STRINGS_PATH")
  if [ "${COUNT}" -eq 0 ] || [ -z "${COUNT}" ] || [ "${COUNT}" = "null" ]; then
    echo "Language ${language} missing from app_strings.json"
  else
    echo "${language}: ${COUNT}/${EN_KEYS}"
  fi
done

echo -e "\n=== Permission copy checks ==="
locale_dir() {
  case "$1" in
    zh) echo "zh-Hans" ;;
    yue) echo "yue-Hant" ;;
    tl) echo "fil" ;;
    *) echo "$1" ;;
  esac
}
for language in en fr zh yue pa ur ta tl es ar fa hi pt gu bn ja ko hu; do
  locale=$(locale_dir "$language")
  if [ -f "GTAFreeSTEM/Resources/${locale}.lproj/InfoPlist.strings" ]; then
    :
  else
    echo "Missing InfoPlist.strings for ${language}"
  fi
done

echo -e "\n=== Privacy manifest checks ==="
PRIVACY_MANIFEST_PATH="GTAFreeSTEM/Resources/PrivacyInfo.xcprivacy"
if [ ! -f "$PRIVACY_MANIFEST_PATH" ]; then
  echo "Missing GTAFreeSTEM/Resources/PrivacyInfo.xcprivacy"
  exit 1
fi
PRIVACY_MANIFEST_JSON="$(plutil -convert json -o - "$PRIVACY_MANIFEST_PATH")"
if ! echo "$PRIVACY_MANIFEST_JSON" | jq -e '
  (.NSPrivacyTracking == false) and
  ((.NSPrivacyTrackingDomains // []) | length == 0) and
  ((.NSPrivacyCollectedDataTypes // []) | length == 0) and
  ((.NSPrivacyAccessedAPITypes // [])
    | map(select(
      .NSPrivacyAccessedAPIType == "NSPrivacyAccessedAPICategoryUserDefaults" and
      ((.NSPrivacyAccessedAPITypeReasons // []) | index("CA92.1"))
    ))
    | length > 0)
' >/dev/null; then
  echo "PrivacyInfo.xcprivacy must declare app-only UserDefaults use with reason CA92.1 and no tracking."
  exit 1
fi
echo "PrivacyInfo.xcprivacy declares app-only UserDefaults use with no tracking."

echo -e "\n=== App Store public URL checks ==="
if command -v curl >/dev/null 2>&1; then
  APP_STORE_URLS=(
    "Marketing URL|https://gta-free-stem.vercel.app/"
    "Support URL|https://gta-free-stem.vercel.app/accessibility-support/"
    "Privacy URL|https://gta-free-stem.vercel.app/privacy/"
  )
  for entry in "${APP_STORE_URLS[@]}"; do
    label="${entry%%|*}"
    url="${entry#*|}"
    status=$(curl -fsSIL --max-time 15 -o /dev/null -w "%{http_code}" "$url" || true)
    if [ "$status" != "200" ]; then
      echo "${label} failed: ${url} returned HTTP ${status:-unreachable}"
      exit 1
    fi
    echo "${label}: ${url} returns HTTP 200"
  done
else
  echo "Skipped App Store URL checks: curl is not installed."
fi

echo -e "\n=== Apple Developer service status check ==="
if command -v curl >/dev/null 2>&1; then
  APPLE_STATUS_FILE="$(mktemp)"
  if curl -fsSL --max-time 15 "https://developer.apple.com/system-status/data/system_status_en_US.js" -o "$APPLE_STATUS_FILE"; then
    /usr/bin/python3 - "$APPLE_STATUS_FILE" <<'PY'
import json
import re
import sys
from pathlib import Path

status_path = Path(sys.argv[1])
raw = status_path.read_text(encoding="utf-8").strip()
match = re.match(r"^jsonCallback\((.*)\);?$", raw, re.DOTALL)
payload = json.loads(match.group(1) if match else raw)

watched_services = [
    "App Store Connect",
    "App Store Connect - App Processing",
    "App Store Connect - App Upload",
    "App Store Connect - TestFlight",
    "App Store Connect API",
]
services = {
    str(service.get("serviceName", "")).strip(): service
    for service in payload.get("services", [])
}

active_events = []
missing = []
for service_name in watched_services:
    service = services.get(service_name)
    if service is None:
        missing.append(service_name)
        continue
    for event in service.get("events") or []:
        status = str(event.get("eventStatus", "")).lower()
        if status != "resolved" and not event.get("endDate"):
            active_events.append((service_name, event))

if missing:
    print("Apple status feed did not include expected services: " + ", ".join(missing))

if active_events:
    print("Apple developer status has active App Store Connect/TestFlight events:")
    for service_name, event in active_events:
        status_type = event.get("statusType", "Issue")
        message = event.get("message", "No message provided")
        start = event.get("startDate", "unknown start")
        print(f"- {service_name}: {status_type} since {start}: {message}")
    raise SystemExit(1)

print("App Store Connect/TestFlight developer services: no active events.")
print("Note: this checks Apple's public service status only; it does not confirm a specific uploaded build.")
PY
  else
    echo "Skipped Apple Developer service status check: status feed was unreachable."
  fi
else
  echo "Skipped Apple Developer service status check: curl is not installed."
fi

echo -e "\n=== App Store metadata checks ==="
/usr/bin/python3 - <<'PY'
from pathlib import Path
import re
import sys

metadata = Path("docs/APP_STORE_METADATA.md").read_text(encoding="utf-8")

def first_match(pattern, label):
    match = re.search(pattern, metadata, re.MULTILINE)
    if not match:
        raise SystemExit(f"Missing {label} in docs/APP_STORE_METADATA.md")
    return match.group(1).strip()

def section(name, next_name):
    pattern = rf"^## {re.escape(name)}\n\n(.*?)(?=\n## {re.escape(next_name)}\n)"
    match = re.search(pattern, metadata, re.MULTILINE | re.DOTALL)
    if not match:
        raise SystemExit(f"Missing {name} section in docs/APP_STORE_METADATA.md")
    return match.group(1).strip()

app_name = first_match(r"^- App name:\s*(.+)$", "app name")
subtitle = first_match(r"^- Subtitle suggestion:\s*(.+)$", "subtitle suggestion")
keywords = section("Keywords Draft", "Metadata Limit Notes").replace("\n", "").strip()
description = section("Description Draft", "Keywords Draft")

checks = [
    ("App name", len(app_name), 30, app_name),
    ("Subtitle", len(subtitle), 30, subtitle),
    ("Description", len(description), 4000, ""),
]
for label, length, limit, value in checks:
    print(f"{label}: {length}/{limit} characters")
    if length > limit:
        extra = f": {value}" if value else ""
        raise SystemExit(f"{label} exceeds App Store limit{extra}")

keyword_bytes = len(keywords.encode("utf-8"))
print(f"Keywords: {keyword_bytes}/100 bytes")
if keyword_bytes > 100:
    raise SystemExit("Keywords exceed App Store 100-byte limit")
if ", " in keywords:
    raise SystemExit("Keywords should be comma-separated without spaces")
if not keywords:
    raise SystemExit("Keywords are empty")
PY

echo -e "\n=== App Store submission packet checks ==="
/usr/bin/python3 - <<'PY'
from pathlib import Path

packet_path = Path("docs/APP_STORE_SUBMISSION_PACKET.md")
if not packet_path.exists():
    raise SystemExit("Missing docs/APP_STORE_SUBMISSION_PACKET.md")

packet = packet_path.read_text(encoding="utf-8")
required_fragments = [
    "Version: `1.0`",
    "Build: `9`",
    "Delivery UUID: `222e71fe-92f1-4da3-bad7-205b9eb7a3b3`",
    "App Store Connect status: `VALID`",
    "TestFlight status: `BETA_INTERNAL_TESTING`",
    "Marketing URL: `https://gta-free-stem.vercel.app/`",
    "Support URL: `https://gta-free-stem.vercel.app/accessibility-support/`",
    "Privacy policy URL: `https://gta-free-stem.vercel.app/privacy/`",
    "build/app-store-screenshots/iphone-6.9/01-home.png",
    "build/app-store-screenshots/ipad-13/01-home.png",
    "docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md",
]
missing = [fragment for fragment in required_fragments if fragment not in packet]
if missing:
    raise SystemExit("Submission packet is missing required release facts:\n" + "\n".join(f"- {item}" for item in missing))
print("Submission packet includes confirmed build, URLs, and screenshot paths.")
PY

echo -e "\n=== Public release runbook checks ==="
/usr/bin/python3 - <<'PY'
from pathlib import Path

runbook_path = Path("docs/PUBLIC_RELEASE_RUNBOOK.md")
if not runbook_path.exists():
    raise SystemExit("Missing docs/PUBLIC_RELEASE_RUNBOOK.md")

runbook = runbook_path.read_text(encoding="utf-8")
required_fragments = [
    "Version/build: `1.0 (9)`",
    "Delivery UUID: `222e71fe-92f1-4da3-bad7-205b9eb7a3b3`",
    "App Store Connect import status: `VALID`",
    "TestFlight status: `BETA_INTERNAL_TESTING`",
    "docs/APP_STORE_SUBMISSION_PACKET.md",
    "docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md",
    "bash docs/scripts/check-local-release-candidate.sh",
    "bash docs/scripts/check-ci-release-readiness.sh",
    "bash docs/scripts/check-public-release-gates.sh",
    "build/app-store-screenshots/iphone-6.9/01-home.png",
    "build/app-store-screenshots/ipad-13/01-home.png",
    "https://gta-free-stem.vercel.app/privacy/",
    "Use an Apple app-specific password, not the normal Apple ID password.",
]
missing = [fragment for fragment in required_fragments if fragment not in runbook]
if missing:
    raise SystemExit("Public release runbook is missing required release facts:\n" + "\n".join(f"- {item}" for item in missing))
print("Public release runbook includes build facts, manual gates, URLs, screenshots, and credential safety.")
PY

echo -e "\n=== Real-device QA signoff check ==="
/usr/bin/python3 - <<'PY'
from pathlib import Path

signoff_path = Path("docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md")
if not signoff_path.exists():
    raise SystemExit("Missing docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md")
signoff = signoff_path.read_text(encoding="utf-8")
required_fragments = [
    "Version/build: `1.0 (9)`",
    "App Store Connect status: `VALID`",
    "TestFlight status: `BETA_INTERNAL_TESTING`",
    "Overall status: `Pending`",
]
missing = [fragment for fragment in required_fragments if fragment not in signoff]
if missing:
    raise SystemExit("Real-device QA signoff is missing required release facts:\n" + "\n".join(f"- {item}" for item in missing))
print("Real-device QA signoff template is present and still marked Pending.")
PY

echo -e "\n=== App Store screenshot checks ==="
if [ "$CHECK_APP_STORE_SCREENSHOTS" != "0" ]; then
  /usr/bin/python3 - <<'PY'
from pathlib import Path
import struct
import zlib

expected = {
    "build/app-store-screenshots/iphone-6.9/01-home.png": (1320, 2868),
    "build/app-store-screenshots/iphone-6.9/02-opportunities.png": (1320, 2868),
    "build/app-store-screenshots/iphone-6.9/03-high-school.png": (1320, 2868),
    "build/app-store-screenshots/iphone-6.9/04-support-account.png": (1320, 2868),
    "build/app-store-screenshots/ipad-13/01-home.png": (2064, 2752),
    "build/app-store-screenshots/ipad-13/02-opportunities.png": (2064, 2752),
    "build/app-store-screenshots/ipad-13/03-high-school.png": (2064, 2752),
    "build/app-store-screenshots/ipad-13/04-support-account.png": (2064, 2752),
}


def paeth(a, b, c):
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def png_info(path):
    blob = path.read_bytes()
    if len(blob) < 100_000:
        raise SystemExit(f"{path} is unexpectedly small: {len(blob)} bytes")
    if not blob.startswith(b"\x89PNG\r\n\x1a\n"):
        raise SystemExit(f"{path} is not a PNG")

    offset = 8
    width = height = bit_depth = color_type = None
    idat = bytearray()
    while offset < len(blob):
        length = struct.unpack(">I", blob[offset:offset + 4])[0]
        kind = blob[offset + 4:offset + 8]
        data = blob[offset + 8:offset + 8 + length]
        offset += length + 12
        if kind == b"IHDR":
            width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", data)
        elif kind == b"IDAT":
            idat.extend(data)
        elif kind == b"IEND":
            break

    if width is None or height is None:
        raise SystemExit(f"{path} is missing PNG dimensions")
    if bit_depth != 8 or color_type not in (0, 2, 6):
        return width, height, None

    channels = {0: 1, 2: 3, 6: 4}[color_type]
    stride = width * channels
    raw = zlib.decompress(bytes(idat))
    rows = []
    cursor = 0
    previous = bytearray(stride)
    for _ in range(height):
        filter_type = raw[cursor]
        cursor += 1
        current = bytearray(raw[cursor:cursor + stride])
        cursor += stride
        for index, value in enumerate(current):
            left = current[index - channels] if index >= channels else 0
            up = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 1:
                current[index] = (value + left) & 0xFF
            elif filter_type == 2:
                current[index] = (value + up) & 0xFF
            elif filter_type == 3:
                current[index] = (value + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                current[index] = (value + paeth(left, up, upper_left)) & 0xFF
            elif filter_type != 0:
                raise SystemExit(f"{path} has unsupported PNG filter {filter_type}")
        rows.append(current)
        previous = current

    sampled = set()
    y_step = max(1, height // 80)
    x_step = max(1, width // 80)
    for y in range(0, height, y_step):
        row = rows[y]
        for x in range(0, width, x_step):
            start = x * channels
            sampled.add(tuple(row[start:start + min(channels, 3)]))
    return width, height, len(sampled)


for relative_path, expected_size in expected.items():
    path = Path(relative_path)
    if not path.exists():
        raise SystemExit(f"Missing App Store screenshot: {relative_path}")
    width, height, sampled_colors = png_info(path)
    if (width, height) != expected_size:
        raise SystemExit(f"{relative_path} is {width} x {height}; expected {expected_size[0]} x {expected_size[1]}")
    if sampled_colors is not None and sampled_colors < 24:
        raise SystemExit(f"{relative_path} appears blank or nearly blank: {sampled_colors} sampled colors")
    suffix = f", {sampled_colors} sampled colors" if sampled_colors is not None else ""
    print(f"{relative_path}: {width} x {height}{suffix}")
PY
else
  echo "Skipped App Store screenshot checks because CHECK_APP_STORE_SCREENSHOTS=0."
fi

echo -e "\n=== Feed translation sanity check (sample) ==="
SAMPLE_LANGS="es zh yue pa"
for language in $SAMPLE_LANGS; do
  COUNT=$(jq -r --arg lang "$language" '[(.opportunities // .data)[] | select((.translations // .localizations // .localized // {})[$lang] != null)] | length' "$OPPORTUNITIES_PATH")
  echo "Listings with ${language} translation key: ${COUNT}/${TOTAL_OPPS}"
done

echo -e "\n=== Live public feed translation check ==="
LIVE_FEED_URL="${LIVE_FEED_URL:-https://gta-free-stem.vercel.app/opportunities.json}"
if command -v curl >/dev/null 2>&1; then
  LIVE_FEED_FILE="$(mktemp)"
  if curl -fsSL --max-time 15 "$LIVE_FEED_URL" -o "$LIVE_FEED_FILE"; then
    LIVE_TOTAL=$(jq '(.opportunities // .data) | length' "$LIVE_FEED_FILE")
    LIVE_TRANSLATED=$(jq '[(.opportunities // .data)[] | select(((.translations // .localizations // .localized // {}) | length) > 0)] | length' "$LIVE_FEED_FILE")
    LIVE_SUMMARY_TRANSLATED=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.summary // "")] | any(. != ""))] | length' "$LIVE_FEED_FILE")
    LIVE_CATEGORY_TRANSLATED=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.category // "")] | any(. != ""))] | length' "$LIVE_FEED_FILE")
    LIVE_COST_TRANSLATED=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.cost // "")] | any(. != "" and . != "Free"))] | length' "$LIVE_FEED_FILE")
    LIVE_TITLE_TRANSLATED=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.title // "")] | any(. != ""))] | length' "$LIVE_FEED_FILE")
    LIVE_DESCRIPTION_TRANSLATED=$(jq '[(.opportunities // .data)[] | select([(.translations // .localizations // .localized // {})[]? | (.description // "")] | any(. != ""))] | length' "$LIVE_FEED_FILE")
    LIVE_ALL_LANGUAGE_SUMMARY=$(jq --argjson langs "$SUPPORTED_TRANSLATION_LANGS" '
      [(.opportunities // .data)[] | select(
        (.translations // .localizations // .localized // {}) as $translations
        | $langs | all(. as $lang | (($translations[$lang].summary // "") != ""))
      )] | length
    ' "$LIVE_FEED_FILE")
    LIVE_ALL_LANGUAGE_CATEGORY=$(jq --argjson langs "$SUPPORTED_TRANSLATION_LANGS" '
      [(.opportunities // .data)[] | select(
        (.translations // .localizations // .localized // {}) as $translations
        | $langs | all(. as $lang | (($translations[$lang].category // "") != ""))
      )] | length
    ' "$LIVE_FEED_FILE")
    LIVE_ALL_LANGUAGE_COST=$(jq --argjson langs "$SUPPORTED_TRANSLATION_LANGS" '
      [(.opportunities // .data)[] | select(
        (.translations // .localizations // .localized // {}) as $translations
        | $langs | all(. as $lang | (($translations[$lang].cost // "") != "" and ($translations[$lang].cost // "") != "Free"))
      )] | length
    ' "$LIVE_FEED_FILE")
    LIVE_ALL_LANGUAGE_TITLE=$(jq --argjson langs "$SUPPORTED_TRANSLATION_LANGS" '
      [(.opportunities // .data)[] | select(
        (.translations // .localizations // .localized // {}) as $translations
        | $langs | all(. as $lang | (($translations[$lang].title // "") != ""))
      )] | length
    ' "$LIVE_FEED_FILE")
    LIVE_ALL_LANGUAGE_DESCRIPTION=$(jq --argjson langs "$SUPPORTED_TRANSLATION_LANGS" '
      [(.opportunities // .data)[] | select(
        (.translations // .localizations // .localized // {}) as $translations
        | $langs | all(. as $lang | (($translations[$lang].description // "") != ""))
      )] | length
    ' "$LIVE_FEED_FILE")
    echo "Live feed: ${LIVE_FEED_URL}"
    echo "Live opportunities: ${LIVE_TOTAL}"
    echo "Live opportunities with any translation payload: ${LIVE_TRANSLATED}"
    echo "Live opportunities with any translated/generated summary: ${LIVE_SUMMARY_TRANSLATED}"
    echo "Live opportunities with any translated/generated category: ${LIVE_CATEGORY_TRANSLATED}"
    echo "Live opportunities with localized cost: ${LIVE_COST_TRANSLATED}"
    echo "Live opportunities with any translated title: ${LIVE_TITLE_TRANSLATED}"
    echo "Live opportunities with any translated description: ${LIVE_DESCRIPTION_TRANSLATED}"
    echo "Live opportunities with summaries for every non-English launch language: ${LIVE_ALL_LANGUAGE_SUMMARY}"
    echo "Live opportunities with categories for every non-English launch language: ${LIVE_ALL_LANGUAGE_CATEGORY}"
    echo "Live opportunities with costs for every non-English launch language: ${LIVE_ALL_LANGUAGE_COST}"
    echo "Live opportunities with titles for every non-English launch language: ${LIVE_ALL_LANGUAGE_TITLE}"
    echo "Live opportunities with descriptions for every non-English launch language: ${LIVE_ALL_LANGUAGE_DESCRIPTION}"
    if [ "${LIVE_TOTAL}" -eq 0 ]; then
      echo "Live translation coverage: 0%"
    else
      echo "Live summary translation coverage: $(( LIVE_SUMMARY_TRANSLATED * 100 / LIVE_TOTAL ))%"
      echo "Live category translation coverage: $(( LIVE_CATEGORY_TRANSLATED * 100 / LIVE_TOTAL ))%"
      echo "Live cost translation coverage: $(( LIVE_COST_TRANSLATED * 100 / LIVE_TOTAL ))%"
      echo "Live title translation coverage: $(( LIVE_TITLE_TRANSLATED * 100 / LIVE_TOTAL ))%"
      echo "Live description translation coverage: $(( LIVE_DESCRIPTION_TRANSLATED * 100 / LIVE_TOTAL ))%"
    fi
    if [ "$STRICT_TRANSLATION_CHECK" != "0" ] && [ "${LIVE_TOTAL}" -gt 0 ]; then
      if [ "${LIVE_TRANSLATED}" -ne "${LIVE_TOTAL}" ] ||
        [ "${LIVE_ALL_LANGUAGE_SUMMARY}" -ne "${LIVE_TOTAL}" ] ||
        [ "${LIVE_ALL_LANGUAGE_CATEGORY}" -ne "${LIVE_TOTAL}" ] ||
        [ "${LIVE_ALL_LANGUAGE_COST}" -ne "${LIVE_TOTAL}" ] ||
        [ "${LIVE_ALL_LANGUAGE_TITLE}" -ne "${LIVE_TOTAL}" ] ||
        [ "${LIVE_ALL_LANGUAGE_DESCRIPTION}" -ne "${LIVE_TOTAL}" ]; then
        echo "ERROR: live public feed is missing generated translation payload coverage."
        echo "  Push and deploy the companion feed repo before treating multilingual release readiness as complete."
        exit 1
      fi
    fi
  else
    echo "Skipped live feed check: ${LIVE_FEED_URL} was not reachable."
  fi
else
  echo "Skipped live feed check: curl is not installed."
fi

echo -e "\n=== App string quality checks ==="
UNLOCALIZED_COUNT=0
for language in fr zh yue pa ur ta tl es ar fa hi pt gu bn ja ko hu; do
  MATCHED=$(jq -r --arg lang "$language" '
    . as $root
    | ($root.en // {}) as $en
    | ($root[$lang] // {}) as $localized
    | [ $en | to_entries[] | select(($localized[.key] // "") == .value and .value != "") ] | length
  ' "$APP_STRINGS_PATH")
  if [ "$MATCHED" -gt 0 ]; then
    UNLOCALIZED_COUNT=$((UNLOCALIZED_COUNT + MATCHED))
  fi
  if [ "$STRICT_TRANSLATION_CHECK" != "0" ] && [ "$MATCHED" -gt 0 ]; then
    echo "ERROR: ${language} has untranslated duplicate strings in app_strings.json"
    echo "  Set STRICT_TRANSLATION_CHECK=0 to run advisory mode"
    exit 1
  fi
done

echo "App string untranslated-equals-English total: ${UNLOCALIZED_COUNT}"

echo "Release checks completed."
exit 0
