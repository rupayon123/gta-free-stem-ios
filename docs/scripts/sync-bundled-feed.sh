#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="$ROOT_DIR/GTAFreeSTEM/Resources/opportunities.json"
# The website export is the local source of truth for the offline app snapshot.
# A hosted URL can still be supplied explicitly after that exact export is published.
CANONICAL_PUBLIC_FEED="${CANONICAL_PUBLIC_FEED:-$ROOT_DIR/../gta-free-stem-opportunities/public/opportunities.json}"
CHECK_ONLY=0
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=1
  shift
fi
if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [--check] [public-feed-file-or-https-url]"
  exit 1
fi
SOURCE="${1:-${GTA_PUBLIC_FEED_FILE:-$CANONICAL_PUBLIC_FEED}}"
TEMP_SOURCE=""
TEMP_TARGET=""

cleanup() {
  [ -z "$TEMP_SOURCE" ] || rm -f "$TEMP_SOURCE"
  [ -z "$TEMP_TARGET" ] || rm -f "$TEMP_TARGET"
}
trap cleanup EXIT

for command in jq python3 mktemp mv curl cmp; do
  command -v "$command" >/dev/null 2>&1 || { echo "$command is required."; exit 1; }
done

if [[ "$SOURCE" == http://* ]]; then
  echo "Public feed source must use HTTPS: $SOURCE"
  exit 1
fi

if [[ "$SOURCE" == https://* ]]; then
  TEMP_SOURCE="$(mktemp "${TMPDIR:-/tmp}/gta-free-stem-feed.XXXXXX")"
  curl -fsSL --max-time 30 "$SOURCE" -o "$TEMP_SOURCE"
  SOURCE="$TEMP_SOURCE"
fi

test -f "$SOURCE" || { echo "Public feed file not found: $SOURCE"; exit 1; }

TEMP_TARGET="$(mktemp "$TARGET.XXXXXX")"
SOURCE="$SOURCE" TARGET="$TEMP_TARGET" python3 - <<'PY'
import json
import os
from datetime import date, datetime, timezone
from pathlib import Path

source = Path(os.environ["SOURCE"])
target = Path(os.environ["TARGET"])
try:
    payload = json.loads(source.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"Cannot read a valid JSON feed: {error}")

items = payload.get("opportunities") or payload.get("data") or []
if not isinstance(items, list) or not items:
    raise SystemExit("Public feed must contain at least one opportunity.")
if payload.get("count") is not None and payload["count"] != len(items):
    raise SystemExit("Public feed count does not match its opportunities array.")

updated = payload.get("lastDataChange") or (payload.get("meta") or {}).get("lastUpdated")
if not isinstance(updated, str) or not updated:
    raise SystemExit("Public feed is missing lastDataChange/meta.lastUpdated.")
try:
    updated_date = datetime.fromisoformat(updated.replace("Z", "+00:00")).date()
except ValueError:
    try:
        updated_date = date.fromisoformat(updated)
    except ValueError as error:
        raise SystemExit(f"Public feed has an invalid update date: {updated}") from error

age = (datetime.now(timezone.utc).date() - updated_date).days
if age < 0 or age > 14:
    raise SystemExit(f"Public feed is not fresh enough to bundle: {updated} ({age} days old).")

source_health = payload.get("sourceHealth")
if not isinstance(source_health, dict):
    raise SystemExit("Canonical public feed must contain sourceHealth.")
library_health = source_health.get("library")
discovery_health = source_health.get("discovery")
if not isinstance(library_health, dict) or not isinstance(discovery_health, dict):
    raise SystemExit("Canonical public feed sourceHealth must contain library and discovery objects.")
unhealthy = [
    name
    for name, health in (("library", library_health), ("discovery", discovery_health))
    if health.get("status") != "healthy"
]
if unhealthy:
    raise SystemExit(f"Public feed sourceHealth is not healthy: {', '.join(unhealthy)}")

def require_number(record, key, source_name):
    value = record.get(key)
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise SystemExit(f"Public feed {source_name} sourceHealth is missing numeric {key}.")
    return value

attempted_pages = require_number(library_health, "attemptedPages", "library")
successful_pages = require_number(library_health, "successfulPages", "library")
page_ratio = require_number(library_health, "pageSuccessRatio", "library")
minimum_page_ratio = require_number(library_health, "minimumPageSuccessRatio", "library")
accepted_listings = require_number(library_health, "acceptedListings", "library")
minimum_accepted = require_number(library_health, "minimumAcceptedListings", "library")
if attempted_pages <= 0 or not 0 <= successful_pages <= attempted_pages:
    raise SystemExit("Public feed library page counters are invalid.")
if page_ratio < minimum_page_ratio or successful_pages / attempted_pages < minimum_page_ratio:
    raise SystemExit("Public feed library page coverage is below its declared threshold.")
if accepted_listings < minimum_accepted or len(items) < minimum_accepted:
    raise SystemExit("Public feed listing count is below its declared healthy threshold.")

sources_checked = require_number(discovery_health, "sourcesChecked", "discovery")
successful_sources = require_number(discovery_health, "successfulSources", "discovery")
source_ratio = require_number(discovery_health, "sourceSuccessRatio", "discovery")
minimum_source_ratio = require_number(discovery_health, "minimumSourceSuccessRatio", "discovery")
if sources_checked <= 0 or not 0 <= successful_sources <= sources_checked:
    raise SystemExit("Public feed discovery source counters are invalid.")
if source_ratio < minimum_source_ratio or successful_sources / sources_checked < minimum_source_ratio:
    raise SystemExit("Public feed discovery coverage is below its declared threshold.")

if any(not isinstance(item, dict) for item in items):
    raise SystemExit("Public feed contains a malformed opportunity record.")

statuses = sorted({str(item.get("status", "")).strip().lower() or "<missing>" for item in items})
if statuses != ["active"]:
    raise SystemExit(
        "Canonical public feed must contain only verified active opportunities; "
        f"found statuses: {', '.join(statuses)}"
    )

ids = [str(item.get("id", "")).strip() for item in items]
if not all(ids):
    raise SystemExit("Canonical public feed contains an opportunity without an ID.")
if len(ids) != len(set(ids)):
    raise SystemExit("Canonical public feed contains duplicate opportunity IDs.")

# Preserve the canonical payload byte-for-byte so the bundle is provably the
# same public snapshot rather than a locally rewritten approximation.
target.write_bytes(source.read_bytes())
print(
    f"Validated {len(items)} verified active canonical opportunities "
    f"updated {updated} ({age} days old)."
)
PY

if [ "$CHECK_ONLY" = "1" ]; then
  if ! cmp -s "$TEMP_TARGET" "$TARGET"; then
    echo "Bundled feed is not byte-identical to the canonical public feed. Run $0, then retry."
    exit 1
  fi
  echo "Verified canonical public feed without changing $TARGET"
  exit 0
fi

mv "$TEMP_TARGET" "$TARGET"
TEMP_TARGET=""

echo "Synced verified active public feed into $TARGET"
