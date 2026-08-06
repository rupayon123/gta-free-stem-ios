#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

BUNDLED_FEED="GTAFreeSTEM/Resources/opportunities.json"
TMP_DIR="$(mktemp -d -t gtafreestem-feed-sync.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

# The exact current bundle must pass without modifying it.
bash docs/scripts/sync-bundled-feed.sh --check "$BUNDLED_FEED" >/dev/null

# A feed with identical IDs and freshness but changed user-visible content must
# fail. This prevents an ID-only comparison from blessing stale titles, dates,
# links, or translations.
MUTATED_FEED="$TMP_DIR/mutated-opportunities.json"
/usr/bin/python3 - "$BUNDLED_FEED" "$MUTATED_FEED" <<'PY'
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
payload = json.loads(source.read_text(encoding="utf-8"))
items = payload.get("opportunities") or payload.get("data") or []
if not items:
    raise SystemExit("Bundled fixture has no opportunities")
items[0]["title"] = f"{items[0].get('title', '')} stale-content-fixture"
target.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

OUTPUT="$TMP_DIR/mutated-output.txt"
if bash docs/scripts/sync-bundled-feed.sh --check "$MUTATED_FEED" >"$OUTPUT" 2>&1; then
  echo "Expected byte-mismatched feed content to fail the sync integrity check."
  exit 1
fi
rg -Fq "Bundled feed is not byte-identical to the canonical public feed" "$OUTPUT" || {
  echo "Expected byte-mismatch error was not reported."
  sed -n '1,120p' "$OUTPUT"
  exit 1
}

# A current non-empty payload without publisher-health evidence must never be
# accepted as a canonical replacement for the retained offline snapshot.
MISSING_HEALTH_FEED="$TMP_DIR/missing-health-opportunities.json"
/usr/bin/python3 - "$BUNDLED_FEED" "$MISSING_HEALTH_FEED" <<'PY'
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
payload = json.loads(source.read_text(encoding="utf-8"))
payload.pop("sourceHealth", None)
target.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

MISSING_HEALTH_OUTPUT="$TMP_DIR/missing-health-output.txt"
if bash docs/scripts/sync-bundled-feed.sh --check "$MISSING_HEALTH_FEED" >"$MISSING_HEALTH_OUTPUT" 2>&1; then
  echo "Expected a canonical feed without sourceHealth to fail."
  exit 1
fi
rg -Fq "Canonical public feed must contain sourceHealth" "$MISSING_HEALTH_OUTPUT" || {
  echo "Expected missing sourceHealth error was not reported."
  sed -n '1,120p' "$MISSING_HEALTH_OUTPUT"
  exit 1
}

echo "Bundled feed byte-integrity self-test passed."
