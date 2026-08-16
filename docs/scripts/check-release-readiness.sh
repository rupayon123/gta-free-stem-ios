#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

STRICT_TRANSLATION_CHECK="${STRICT_TRANSLATION_CHECK:-0}"
CHECK_APP_STORE_SCREENSHOTS="${CHECK_APP_STORE_SCREENSHOTS:-1}"
REQUIRE_DIRECT_SUPPORT_CONTACT="${REQUIRE_DIRECT_SUPPORT_CONTACT:-1}"
LIVE_FEED_URL="${LIVE_FEED_URL:-https://raw.githubusercontent.com/rupayon123/gta-free-stem-opportunities/main/public/opportunities.json}"
APP_STRINGS="GTAFreeSTEM/Resources/app_strings.json"
BUNDLED_FEED="GTAFreeSTEM/Resources/opportunities.json"
LANGS='["fr","zh","yue","pa","ur","ta","tl","es","ar","fa","hi","pt","gu","bn","ja","ko","hu"]'

for command in jq plutil sips curl cmp mktemp; do
  command -v "$command" >/dev/null 2>&1 || { echo "$command is required."; exit 1; }
done

echo "=== Version and project configuration ==="
rg -Fq 'MARKETING_VERSION: "1.0"' project.yml
rg -Fq 'CURRENT_PROJECT_VERSION: "12"' project.yml
rg -Fq 'GTA_RELEASE_SOURCE_COMMIT: UNSET' project.yml
rg -Fq 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon' project.yml
for info_plist in GTAFreeSTEM/Info.plist GTAFreeSTEM/MacCatalyst-Info.plist GTAFreeSTEMWatch/Info.plist; do
  [ "$(plutil -extract GTAReleaseSourceCommit raw -o - "$info_plist")" = '$(GTA_RELEASE_SOURCE_COMMIT)' ] || {
    echo "$info_plist must embed GTA_RELEASE_SOURCE_COMMIT in the signed bundle metadata."
    exit 1
  }
done
rg -Fq '"GTA_RELEASE_SOURCE_COMMIT=$SOURCE_COMMIT"' docs/scripts/install-connected-device.sh
echo "Version/build: 1.0 (12)"

echo
echo "=== Localized UI coverage ==="
test -f "$APP_STRINGS"
test -f "$BUNDLED_FEED"
EN_COUNT="$(jq '.en | length' "$APP_STRINGS")"
for lang in fr zh yue pa ur ta tl es ar fa hi pt gu bn ja ko hu; do
  count="$(jq -r --arg lang "$lang" '.[$lang] | length // 0' "$APP_STRINGS")"
  [ "$count" = "$EN_COUNT" ] || { echo "$lang has $count keys; expected $EN_COUNT."; exit 1; }
  duplicates="$(jq -r --arg lang "$lang" '
    . as $root
    | ($root.en // {}) as $en
    | ($root[$lang] // {}) as $localized
    | [$en | to_entries[] | select(($localized[.key] // "") == .value and .value != "")] | length
  ' "$APP_STRINGS")"
  echo "$lang: $count/$EN_COUNT strings; $duplicates exact-English duplicates"
  if [ "$STRICT_TRANSLATION_CHECK" != "0" ] && [ "$duplicates" != "0" ]; then
    echo "Strict translation check failed for $lang."
    exit 1
  fi
done

echo
echo "=== Privacy and Watch release assets ==="
IOS_PRIVACY_MANIFEST="GTAFreeSTEM/Resources/PrivacyInfo.xcprivacy"
WATCH_PRIVACY_MANIFEST="GTAFreeSTEMWatch/PrivacyInfo.xcprivacy"
for manifest in "$IOS_PRIVACY_MANIFEST" "$WATCH_PRIVACY_MANIFEST"; do
  test -f "$manifest" || { echo "Missing $manifest"; exit 1; }
  plutil -convert json -o - "$manifest" | jq -e '
    (.NSPrivacyTracking == false) and
    ((.NSPrivacyTrackingDomains // []) | length == 0) and
    ((.NSPrivacyAccessedAPITypes // []) | map(select(
      .NSPrivacyAccessedAPIType == "NSPrivacyAccessedAPICategoryUserDefaults" and
      ((.NSPrivacyAccessedAPITypeReasons // []) | index("CA92.1"))
    )) | length > 0)
  ' >/dev/null || { echo "Invalid common privacy declaration in $manifest"; exit 1; }
done
plutil -convert json -o - "$IOS_PRIVACY_MANIFEST" | jq -e '
  (.NSPrivacyCollectedDataTypes // []) as $types |
  ($types | length == 2) and
  (["NSPrivacyCollectedDataTypeCoarseLocation", "NSPrivacyCollectedDataTypeOtherDiagnosticData"] | all(. as $expected |
    any($types[];
      .NSPrivacyCollectedDataType == $expected and
      .NSPrivacyCollectedDataTypeLinked == true and
      .NSPrivacyCollectedDataTypeTracking == false and
      ((.NSPrivacyCollectedDataTypePurposes // []) | sort) == ([
        "NSPrivacyCollectedDataTypePurposeAnalytics",
        "NSPrivacyCollectedDataTypePurposeAppFunctionality"
      ] | sort)
    )
  ))
' >/dev/null || { echo "iOS privacy manifest must match the conservative feed-request disclosure."; exit 1; }
plutil -convert json -o - "$WATCH_PRIVACY_MANIFEST" | jq -e '
  ((.NSPrivacyCollectedDataTypes // []) | length == 0)
' >/dev/null || { echo "Watch privacy manifest must declare no independent collection."; exit 1; }
echo "Verified iOS/Mac feed-request disclosures and Watch local-only privacy declaration."

jq -e '
  ([.images[] | select(.idiom == "watch-marketing" and .filename == "icon-1024.png")] | length == 1) and
  ([.images[] | select(.role == "appLauncher")] | length >= 6)
' GTAFreeSTEMWatch/Assets.xcassets/AppIcon.appiconset/Contents.json >/dev/null || {
  echo "Watch AppIcon manifest is incomplete."
  exit 1
}
echo "Watch AppIcon manifest is complete."

echo
echo "=== Mac Catalyst App Store configuration ==="
MAC_ENTITLEMENTS="GTAFreeSTEM/MacCatalyst.entitlements"
MAC_INFO_PLIST="GTAFreeSTEM/MacCatalyst-Info.plist"
PBXPROJ="GTAFreeSTEM.xcodeproj/project.pbxproj"
test -f "$MAC_ENTITLEMENTS" || { echo "Missing $MAC_ENTITLEMENTS"; exit 1; }
test -f "$MAC_INFO_PLIST" || { echo "Missing $MAC_INFO_PLIST"; exit 1; }
[ -f project.yml ] || { echo "Missing project.yml"; exit 1; }
[ -f "$PBXPROJ" ] || { echo "Missing $PBXPROJ"; exit 1; }
plutil -convert json -o - "$MAC_ENTITLEMENTS" | jq -e '
  .["com.apple.security.app-sandbox"] == true and
  .["com.apple.security.network.client"] == true and
  .["com.apple.security.personal-information.location"] == true
' >/dev/null || { echo "Invalid Mac Catalyst sandbox entitlements."; exit 1; }
plutil -convert json -o - "$MAC_INFO_PLIST" | jq -e '
  .LSApplicationCategoryType == "public.app-category.education" and
  .NSHumanReadableCopyright == "© 2026 Rupayon Haldar"
' >/dev/null || { echo "Invalid Mac Catalyst App Store metadata."; exit 1; }
for setting in \
  '"INFOPLIST_FILE[sdk=macosx*]": GTAFreeSTEM/MacCatalyst-Info.plist' \
  '"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": GTAFreeSTEM/MacCatalyst.entitlements' \
  '"ENABLE_APP_SANDBOX[sdk=macosx*]": "YES"' \
  '"ENABLE_HARDENED_RUNTIME[sdk=macosx*]": "YES"'; do
  rg -Fq "$setting" project.yml || { echo "Missing Mac Catalyst setting: $setting"; exit 1; }
done
if rg -n 'CODE_SIGN_IDENTITY' project.yml "$PBXPROJ"; then
  echo "Automatic signing must not hard-code a signing identity; Xcode selects development for archive and distribution at export."
  exit 1
fi
echo "Verified Mac Catalyst sandbox, metadata, release settings, and automatic-signing configuration."

echo
echo "=== Public URL availability ==="
for url in \
  https://gta-free-stem.vercel.app/ \
  https://gta-free-stem.vercel.app/support/ \
  https://gta-free-stem.vercel.app/privacy/ \
  https://gta-free-stem.vercel.app/terms/; do
  status="$(curl -fsSIL --max-time 15 -o /dev/null -w '%{http_code}' "$url" || true)"
  [ "$status" = "200" ] || { echo "$url returned $status"; exit 1; }
  echo "$url returns HTTP 200"
done
if [ "$REQUIRE_DIRECT_SUPPORT_CONTACT" != "0" ]; then
  SUPPORT_PAGE_FILE="$(mktemp "${TMPDIR:-/tmp}/gta-free-stem-support.XXXXXX")"
  if ! curl -fsSL --max-time 15 https://gta-free-stem.vercel.app/support/ -o "$SUPPORT_PAGE_FILE"; then
    rm -f "$SUPPORT_PAGE_FILE"
    echo "Could not download the production Support page."
    exit 1
  fi
  if ! rg -qi 'href=["'\''`](mailto|tel):' "$SUPPORT_PAGE_FILE"; then
    rm -f "$SUPPORT_PAGE_FILE"
    echo "The production Support page must expose a monitored email or telephone contact, not only GitHub Issues."
    exit 1
  fi
  rm -f "$SUPPORT_PAGE_FILE"
  echo "Production Support page exposes direct contact information."
else
  echo "Skipping the release-owner support-contact check in CI; the local/public release gates still require it."
fi

echo
echo "=== Release documentation ==="
/usr/bin/python3 - <<'PY'
from pathlib import Path
import re

metadata = Path("docs/APP_STORE_METADATA.md").read_text(encoding="utf-8")
submission_packet = Path("docs/APP_STORE_SUBMISSION_PACKET.md").read_text(encoding="utf-8")
expected_storefront_copyright = "Copyright draft: \\`2026 Rupayon Haldar\\`"
for path, content in {
    "docs/APP_STORE_METADATA.md": metadata,
    "docs/APP_STORE_SUBMISSION_PACKET.md": submission_packet,
}.items():
    if expected_storefront_copyright not in content:
        raise SystemExit(f"{path} must use the exact App Store copyright value 2026 Rupayon Haldar")
for label, limit in [("App name", 30), ("Subtitle suggestion", 30)]:
    match = re.search(rf"^- {re.escape(label)}:\s*(.+)$", metadata, re.MULTILINE)
    if not match:
        raise SystemExit(f"Missing {label}")
    value = match.group(1).strip().strip(chr(96))
    if len(value) > limit:
        raise SystemExit(f"{label} exceeds {limit} characters")
    print(f"{label}: {len(value)}/{limit}")

sections = re.search(r"^## Description Draft\n\n(.*?)(?=^## Keywords Draft\n)", metadata, re.M | re.S)
keywords = re.search(r"^## Keywords Draft\n\n(.*?)(?=^## Metadata Limit Notes\n)", metadata, re.M | re.S)
if not sections or not keywords:
    raise SystemExit("Metadata description or keyword section is missing")
if len(sections.group(1).strip()) > 4000:
    raise SystemExit("Description exceeds 4000 characters")
keyword_value = "".join(line.strip() for line in keywords.group(1).splitlines())
if not keyword_value or len(keyword_value.encode("utf-8")) > 100 or ", " in keyword_value:
    raise SystemExit("Keywords must be nonempty, no more than 100 bytes, and comma-separated without spaces")
print(f"Keywords: {len(keyword_value.encode('utf-8'))}/100 bytes")

required = {
    "README.md": ["1.0 (12)", "on-device", "Apple Watch"],
    "docs/RELEASE_READINESS.md": ["iphone,ipad,watch,mac", "selected separate Mac App Store", "build/app-store-screenshots/final/"],
    "docs/APP_STORE_METADATA.md": ["iphone,ipad,watch,mac", "selected separate Mac App Store", "does not independently request or cache the public feed", "build/app-store-screenshots/final/"],
    "docs/APP_STORE_SUBMISSION_PACKET.md": ["Build:", "12", "iOS App Store Connect status:", "iOS TestFlight status:", "Mac App Store Connect status:", "Mac TestFlight status:", "App Review status:", "Watch bundle ID:", "Production legal/support truthfulness verified", "Terms of Use URL", "Custom EULA", "PUBLIC_RELEASE_PLATFORMS", "Coarse Location", "Other Diagnostic Data", "build/app-store-screenshots/final/", "13-file canonical package"],
    "docs/PUBLIC_RELEASE_RUNBOOK.md": ["1.0 (12)", "TestFlight", "App Review", "Apple Developer Program", "PUBLIC_RELEASE_PLATFORMS=iphone,ipad,watch,mac", "truthfulness", "Standard EULA", "selected separate Mac App Store"],
    "docs/APP_STORE_SCREENSHOTS.md": ["1320 x 2868", "2064 x 2752", "1440 x 900", "416 x 496", "alpha", "build/app-store-screenshots/final/", "Screenshot visual QA"],
    "docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md": ["1.0 (12)", "Warm launch experience", "Local profile deletion", "Watch companion", "Public distribution platforms", "iphone,ipad,watch,mac", "Artifact binding status", "iOS App Store Connect status", "Mac App Store Connect status", "iOS App Store Connect build selected", "Mac App Store Connect build selected", "Platform-Specific Evidence", "Screenshot visual QA", "Production legal/support truthfulness verified"],
    "docs/RELEASE_QA_CHECKLIST.md": ["iphone,ipad,watch,mac", "capped saved-opportunity sync", "build/app-store-screenshots/final/"],
}
for raw_path, fragments in required.items():
    text = Path(raw_path).read_text(encoding="utf-8")
    missing = [fragment for fragment in fragments if fragment not in text]
    if missing:
        raise SystemExit(f"{raw_path} missing: {', '.join(missing)}")

stale = [
    "1.0 (11)",
    "build 11",
    "382 translated opportunities",
    "processing status unverified",
    "account-only actions",
    "Mac remains an optional separate record decision",
    "Pending only if mac is selected and uploaded",
    "compact live/cache data",
]
for path in [Path("README.md"), *Path("docs").glob("*.md")]:
    text = path.read_text(encoding="utf-8")
    hit = [needle for needle in stale if needle in text]
    if hit:
        raise SystemExit(f"{path} contains stale release wording: {', '.join(hit)}")
print("Release documentation matches build 1.0 (12).")
PY

echo
echo "=== Dynamic feed freshness ==="
LIVE_FEED_FILE="$(mktemp "${TMPDIR:-/tmp}/gta-free-stem-live-feed.XXXXXX")"
trap 'rm -f "$LIVE_FEED_FILE"' EXIT
curl -fsSL --max-time 20 "$LIVE_FEED_URL" -o "$LIVE_FEED_FILE"
LIVE_FACTS="$(jq --argjson langs "$LANGS" '
  (.opportunities // .data // []) as $items |
  {
    total: ($items | length),
    updated: (.lastDataChange // .meta.lastUpdated // ""),
    translated: ([$items[] | select(((.translations // .localizations // .localized // {}) | length) > 0)] | length),
    titles: ([$items[] | select((.translations // .localizations // .localized // {}) as $t | $langs | all(. as $lang | (($t[$lang].title // "") != "")))] | length),
    summaries: ([$items[] | select((.translations // .localizations // .localized // {}) as $t | $langs | all(. as $lang | (($t[$lang].summary // "") != "")))] | length)
  }
' "$LIVE_FEED_FILE")"
echo "$LIVE_FACTS"
LIVE_FACTS="$LIVE_FACTS" STRICT_TRANSLATION_CHECK="$STRICT_TRANSLATION_CHECK" /usr/bin/python3 - <<'PY'
import json
import os
from datetime import date, datetime, timezone

facts = json.loads(os.environ["LIVE_FACTS"])
if facts["total"] <= 0 or not facts["updated"]:
    raise SystemExit("Live feed needs nonempty entries and lastDataChange/lastUpdated")
try:
    updated = datetime.fromisoformat(facts["updated"].replace("Z", "+00:00")).date()
except ValueError:
    updated = date.fromisoformat(facts["updated"])
age = (datetime.now(timezone.utc).date() - updated).days
if age < 0 or age > 14:
    raise SystemExit(f"Live feed freshness exceeds 14 days: {facts['updated']}")
if os.environ["STRICT_TRANSLATION_CHECK"] != "0":
    for key in ["translated", "titles", "summaries"]:
        if facts[key] != facts["total"]:
            raise SystemExit(f"Live feed lacks full {key} coverage")
print(f"Current live feed: {facts['total']} entries, {facts['updated']}, {age} days old")
PY

BUNDLED_FACTS="$(jq '
  (.opportunities // .data // []) as $items |
  {
    total: ($items | length),
    updated: (.lastDataChange // .meta.lastUpdated // ""),
    healthySources: ([.sourceHealth? | objects | to_entries[]? | select(.value.status == "healthy")] | length),
    declaredSources: ([.sourceHealth? | objects | to_entries[]?] | length)
  }
' "$BUNDLED_FEED")"
echo "$BUNDLED_FACTS"
BUNDLED_FACTS="$BUNDLED_FACTS" /usr/bin/python3 - <<'PY'
import json
import os
from datetime import date, datetime, timezone

facts = json.loads(os.environ["BUNDLED_FACTS"])
if facts["total"] <= 0 or not facts["updated"]:
    raise SystemExit("Bundled fallback needs nonempty entries and lastDataChange/lastUpdated")
try:
    updated = datetime.fromisoformat(facts["updated"].replace("Z", "+00:00")).date()
except ValueError:
    updated = date.fromisoformat(facts["updated"])
age = (datetime.now(timezone.utc).date() - updated).days
if age < 0 or age > 14:
    raise SystemExit(f"Bundled fallback freshness exceeds 14 days: {facts['updated']}")
if facts["declaredSources"] and facts["healthySources"] != facts["declaredSources"]:
    raise SystemExit("Bundled fallback contains an unhealthy sourceHealth declaration")
print(f"Bundled fallback: {facts['total']} entries, {facts['updated']}, {age} days old")
PY

if ! cmp -s "$LIVE_FEED_FILE" "$BUNDLED_FEED"; then
  echo "Bundled fallback is not byte-identical to the canonical public feed. Run docs/scripts/sync-bundled-feed.sh, publish that exact feed, then retry."
  exit 1
fi

LIVE_FEED_FILE="$LIVE_FEED_FILE" BUNDLED_FEED="$BUNDLED_FEED" /usr/bin/python3 - <<'PY'
import json
import os
from pathlib import Path

def items(payload):
    return payload.get("opportunities") or payload.get("data") or []

live = json.loads(Path(os.environ["LIVE_FEED_FILE"]).read_text(encoding="utf-8"))
bundled = json.loads(Path(os.environ["BUNDLED_FEED"]).read_text(encoding="utf-8"))
expected = [
    item for item in items(live)
    if isinstance(item, dict) and str(item.get("status", "active")).strip().lower() == "active"
]
actual = items(bundled)
if not expected:
    raise SystemExit("Canonical live feed has no verified active opportunities.")
if any(str(item.get("status", "active")).strip().lower() != "active" for item in actual if isinstance(item, dict)):
    raise SystemExit("Bundled fallback contains a non-active opportunity.")
if actual != expected:
    raise SystemExit("Bundled fallback content does not match the canonical verified-active opportunity set. Run docs/scripts/sync-bundled-feed.sh, then retry.")
if bundled.get("count") is not None and bundled["count"] != len(actual):
    raise SystemExit("Bundled fallback count does not match its verified-active opportunity set.")
print(f"Bundled fallback matches {len(actual)} verified active canonical opportunities.")
PY

echo
echo "=== App Store screenshot files ==="
if [ "$CHECK_APP_STORE_SCREENSHOTS" = "0" ]; then
  echo "Skipped screenshot-file checks because CHECK_APP_STORE_SCREENSHOTS=0."
else
  /usr/bin/python3 - <<'PY'
from pathlib import Path
import re
import subprocess

expected = {
    **{f"build/app-store-screenshots/final/iphone-6.9/{name}.jpg": (1320, 2868) for name in ["01-home", "02-opportunities", "03-high-school", "04-profile"]},
    **{f"build/app-store-screenshots/final/ipad-13/{name}.jpg": (2064, 2752) for name in ["01-home", "02-opportunities", "03-high-school", "04-profile"]},
    **{f"build/app-store-screenshots/final/mac/{name}.jpg": (1440, 900) for name in ["01-home", "02-opportunities", "03-high-school", "04-profile"]},
    "build/app-store-screenshots/final/watch-series-11/01-home.jpg": (416, 496),
}

actual = {
    str(path)
    for directory in ["iphone-6.9", "ipad-13", "mac", "watch-series-11"]
    for path in (Path("build/app-store-screenshots/final") / directory).glob("*.jpg")
}
unexpected = sorted(actual - set(expected))
if unexpected:
    raise SystemExit("Unexpected platform JPEGs in canonical screenshot package: " + ", ".join(unexpected))

def sips_property(path, name):
    output = subprocess.check_output(["sips", "-g", name, str(path)], text=True)
    found = re.search(rf"{re.escape(name)}:\s*(.+)", output)
    return found.group(1).strip() if found else ""

for name, size in expected.items():
    path = Path(name)
    if not path.exists() or path.stat().st_size < 25000:
        raise SystemExit(f"Missing or undersized screenshot: {path}")
    observed = (int(sips_property(path, "pixelWidth")), int(sips_property(path, "pixelHeight")))
    if observed != size:
        raise SystemExit(f"{path} is {observed}; expected {size}")
    if sips_property(path, "format") != "jpeg" or sips_property(path, "hasAlpha") != "no":
        raise SystemExit(f"{path} must be an opaque JPEG")
    print(f"Verified {path}: {observed[0]} x {observed[1]}, opaque JPEG")
print(f"Verified {len(expected)} canonical platform JPEGs. Structural checks do not replace the pending full-size visual QA.")
PY
fi

echo
echo "Release-readiness checks passed."
