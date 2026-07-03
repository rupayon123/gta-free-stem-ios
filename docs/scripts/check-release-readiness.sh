#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
LIVE_FEED_FILE=""
trap 'rm -f "$LIVE_FEED_FILE"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for JSON checks."
  exit 1
fi

STRICT_TRANSLATION_CHECK="${STRICT_TRANSLATION_CHECK:-0}"
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
