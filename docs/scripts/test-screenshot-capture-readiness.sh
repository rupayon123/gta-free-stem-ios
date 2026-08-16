#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/docs/scripts/capture-app-store-screenshots.sh"
WATCH_SCRIPT_PATH="$ROOT_DIR/docs/scripts/capture-watch-app-store-screenshot.sh"
LOCAL_CANDIDATE_SCRIPT_PATH="$ROOT_DIR/docs/scripts/check-local-release-candidate.sh"
FINALIZE_RECEIPT_SCRIPT_PATH="$ROOT_DIR/docs/scripts/finalize-screenshot-capture-receipt.sh"
VERIFY_PACKAGE_SCRIPT_PATH="$ROOT_DIR/docs/scripts/verify-screenshot-package.sh"
PREPARE_MAC_SCRIPT_PATH="$ROOT_DIR/docs/scripts/prepare-mac-screenshot-capture.sh"

/usr/bin/python3 - \
  "$SCRIPT_PATH" \
  "$WATCH_SCRIPT_PATH" \
  "$LOCAL_CANDIDATE_SCRIPT_PATH" \
  "$FINALIZE_RECEIPT_SCRIPT_PATH" \
  "$VERIFY_PACKAGE_SCRIPT_PATH" \
  "$PREPARE_MAC_SCRIPT_PATH" <<'PY'
from pathlib import Path
import json
import sqlite3
import sys

source = Path(sys.argv[1]).read_text()
watch_source = Path(sys.argv[2]).read_text()
local_candidate_source = Path(sys.argv[3]).read_text()
finalize_receipt_source = Path(sys.argv[4]).read_text()
verify_package_source = Path(sys.argv[5]).read_text()
prepare_mac_source = Path(sys.argv[6]).read_text()
capture_start = source.index("capture() {")
capture_end = source.index("\nprepare_device()", capture_start)
capture = source[capture_start:capture_end]
start = source.index("prepare_device() {")
end = source.index("\nwarm_up_device()", start)
prepare_device = source[start:end]
warm_up_start = source.index("warm_up_device() {")
warm_up_end = source.index("\nif [ \"$USE_DEDICATED_SIMULATORS\"", warm_up_start)
warm_up_device = source[warm_up_start:warm_up_end]

required_fragments = (
    'BOOT_TIMEOUT="${BOOT_TIMEOUT:-120}"',
    'xcrun simctl clone "$source_id" "GTA STEM Screenshots ${display_name} $$"',
    'restore_source_boot=1',
    'run_simctl shutdown "$source_id"',
    'wait_for_device_state "$source_id" "Shutdown" "$BOOT_TIMEOUT"',
    'wait_for_device_state "$identifier" "Shutdown" "$BOOT_TIMEOUT"',
    'wait_for_device_state "$device" "Shutdown" "$BOOT_TIMEOUT"',
    'run_simctl boot "$source_id"',
    'if ! IPHONE_ID="$(clone_dedicated_device "$IPHONE_DEVICE")"',
    'subprocess.run(command, timeout=timeout)',
    'SIMCTL_COMMAND_TIMEOUT="$BOOT_TIMEOUT" run_simctl bootstatus "$device" -b',
    'run_simctl get_app_container "$device" "$BUNDLE_ID" app',
    'SCREENSHOT_READY_TIMEOUT="${SCREENSHOT_READY_TIMEOUT:-45}"',
    'SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-12}"',
    'OUTPUT_DIR="${OUTPUT_DIR:-$SCREENSHOT_ROOT/final}"',
    'RAW_OUTPUT_DIR="${RAW_OUTPUT_DIR:-$SCREENSHOT_ROOT/raw}"',
    'VISUAL_QA_MARKER="$OUTPUT_DIR/FINAL_VISUAL_QA.md"',
    'CAPTURE_RECEIPT="$OUTPUT_DIR/CAPTURE_RECEIPT.json"',
    'MAC_CAPTURE_SESSION="$OUTPUT_DIR/MAC_CAPTURE_SESSION.json"',
    'CONTACT_SHEET="$OUTPUT_DIR/contact-sheet.jpg"',
    'rm -f -- "$VISUAL_QA_MARKER" "$CAPTURE_RECEIPT" "$MAC_CAPTURE_SESSION" "$CONTACT_SHEET"',
    'SOURCE_COMMIT="$(screenshot_source_commit)"',
    'SOURCE_TREE_SHA256="$(screenshot_source_tree_sha256 "$SOURCE_COMMIT")"',
    'require_clean_screenshot_source "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"',
    'GTA_RELEASE_SOURCE_COMMIT="$SOURCE_COMMIT"',
    'verify_built_source_commit "$APP_PATH/Info.plist" "$SOURCE_COMMIT"',
    'require_unchanged_screenshot_source "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"',
    'live_feed_store_path() {',
    'read_live_feed_updated_at() {',
    'read_live_refresh_completed_at() {',
    'read_validated_live_feed_state() {',
    'wait_for_live_feed_refresh() {',
    'run_simctl get_app_container "$device" "$BUNDLE_ID" data',
    '/Library/Application Support/default.store',
    '/usr/bin/sqlite3 -readonly "$store"',
    "ZCACHEKEY = 'latest-opportunities'",
    'ZSEENOPPORTUNITYRECORD',
    'ZLASTSEENAT',
    'feed.ZUPDATEDAT > $previous_feed_updated_at',
    '> $previous_refresh_completed_at',
    "'$.meta.lastUpdated'",
    "'$.data'",
    'json_array_length',
    'Could not read the live-feed timestamp baseline',
    'Could not read the live-refresh timestamp baseline',
    'Aborting screenshot capture because live-feed readiness could not be verified.',
    'previous_feed_updated_at="$(read_live_feed_updated_at "$device")"',
    'previous_refresh_completed_at="$(read_live_refresh_completed_at "$device")"',
    'wait_for_live_feed_refresh "$device" "$previous_feed_updated_at" "$previous_refresh_completed_at"',
    'SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_QUERY="$screenshot_query"',
    "COALESCE(json_extract(CAST(feed.ZPAYLOAD AS TEXT), '$.meta.lastUpdated'), '') != ''",
    "COALESCE(json_array_length(json_extract(CAST(feed.ZPAYLOAD AS TEXT), '$.data')), 0) > 0",
    'sleep "$SCREENSHOT_DELAY"',
    '/02-opportunities.png" "$OUTPUT_DIR/iphone-6.9/02-opportunities.jpg" 1320 2868 -start-opportunities',
    '/02-opportunities.png" "$OUTPUT_DIR/ipad-13/02-opportunities.jpg" 2064 2752 -start-opportunities',
    '-start-high-school',
    '-start-account -localProfileName "STEM Explorer" -localProfileEnabled YES',
)
for fragment in required_fragments:
    if fragment not in source:
        raise SystemExit(f"Missing screenshot-readiness guard: {fragment}")

for line in source.splitlines():
    if "/02-opportunities.png" in line and "--screenshot-query" in line:
        raise SystemExit(
            "The release screenshot must use the current unfiltered feed instead of a keyword that can expire."
        )

if 'kill -0 "$command_pid"' in source:
    raise SystemExit("Screenshot capture must not poll an unreaped background simctl PID.")
if 'CREATED_SIMULATORS[@]' in source:
    raise SystemExit("Screenshot cleanup must be safe under the macOS Bash 3.2 empty-array behavior.")
if 'CREATED_IPHONE_ID=""' not in source or 'CREATED_IPAD_ID=""' not in source:
    raise SystemExit("Screenshot cleanup must track each task-created simulator explicitly.")

feed_baseline_start = source.index("read_live_feed_updated_at() {")
feed_baseline_end = source.index("\nread_live_refresh_completed_at()", feed_baseline_start)
refresh_baseline_start = feed_baseline_end + 1
refresh_baseline_end = source.index("\nread_validated_live_feed_state()", refresh_baseline_start)
baseline_source = source[feed_baseline_start:refresh_baseline_end]
if "2>/dev/null || true" in baseline_source:
    raise SystemExit("Baseline readers must abort SQLite/container failures instead of normalizing them to an empty value.")
if baseline_source.count("printf '%s\\n' \"-1\"") != 2:
    raise SystemExit("Each baseline reader must use -1 only for a confirmed not-yet-created store, not for read failures.")
if baseline_source.count('if [ ! -e "$store" ]') != 2:
    raise SystemExit("Baseline readers must distinguish a confirmed absent store from an unreadable existing store.")

for fragment in (
    'SCREENSHOT_CAPTURE_ROOT="build/app-store-screenshots"',
    'SCREENSHOT_PACKAGE_ROOT="$SCREENSHOT_CAPTURE_ROOT/final"',
    'VISUAL_QA_MARKER="$SCREENSHOT_PACKAGE_ROOT/FINAL_VISUAL_QA.md"',
    'CAPTURE_RECEIPT="$SCREENSHOT_PACKAGE_ROOT/CAPTURE_RECEIPT.json"',
    'MAC_CAPTURE_SESSION="$SCREENSHOT_PACKAGE_ROOT/MAC_CAPTURE_SESSION.json"',
    'VERIFY_SCREENSHOT_PACKAGE_SCRIPT="docs/scripts/verify-screenshot-package.sh"',
    'existing Mac files cannot be treated as current',
    'rerun with RUN_SCREENSHOTS=0',
    'SCREENSHOT_PACKAGE_TEST_FIXTURE_ONLY=0',
    'SCREENSHOT_ROOT="$SCREENSHOT_PACKAGE_ROOT"',
    'OUTPUT_DIR="$SCREENSHOT_PACKAGE_ROOT"',
    'CAPTURE_RECEIPT_PATH="$CAPTURE_RECEIPT"',
    'VISUAL_QA_MANIFEST_PATH="$VISUAL_QA_MARKER"',
    'MAC_CAPTURE_SESSION_PATH="$MAC_CAPTURE_SESSION"',
    'bash "$VERIFY_SCREENSHOT_PACKAGE_SCRIPT"',
    'STRICT_TRANSLATION_CHECK=1 CHECK_APP_STORE_SCREENSHOTS=1 bash docs/scripts/check-release-readiness.sh',
):
    if fragment not in local_candidate_source:
        raise SystemExit(f"Local candidate must stop stale Mac screenshots from surviving a fresh automated capture: {fragment}")

if 'CHECK_APP_STORE_SCREENSHOTS="$RUN_SCREENSHOTS"' in local_candidate_source:
    raise SystemExit("RUN_SCREENSHOTS must control capture only; local verification must never disable screenshot checks.")

for fragment in (
    'GTA-FREE-STEM-SCREENSHOT-CAPTURE-v1',
    'SOURCE_PATHS=(GTAFreeSTEM GTAFreeSTEMWatch GTAFreeSTEM.xcodeproj project.yml)',
    'GTAReleaseSourceCommit',
    'CAPTURE_RECEIPT.json',
    'MAC_CAPTURE_SESSION.json',
    'Source tree changed while screenshots were being finalized',
):
    if fragment not in finalize_receipt_source:
        raise SystemExit(f"Screenshot receipt finalizer is missing provenance guard: {fragment}")

for fragment in (
    'GTA-FREE-STEM-SCREENSHOT-CAPTURE-v1',
    'CAPTURE_RECEIPT.json',
    'FINAL_VISUAL_QA.md',
    'Source tree is not clean',
    'Screenshot hash mismatch',
    'Capture receipt hash mismatch',
    'Mac capture session hash mismatch',
):
    if fragment not in verify_package_source:
        raise SystemExit(f"Screenshot package verifier is missing approval guard: {fragment}")

for fragment in (
    'GTA-FREE-STEM-MAC-CAPTURE-SESSION-v1',
    'PROJECT="GTAFreeSTEM.xcodeproj"',
    'SCHEME="GTAFreeSTEM"',
    'CONFIGURATION="Release"',
    'DESTINATION="platform=macOS,variant=Mac Catalyst,name=My Mac"',
    'MAC_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release-maccatalyst/GTAFreeSTEM.app"',
    'SOURCE_PATHS=(GTAFreeSTEM GTAFreeSTEMWatch GTAFreeSTEM.xcodeproj project.yml)',
    'GTA_RELEASE_SOURCE_COMMIT=$SOURCE_COMMIT',
    'MAC_CAPTURE_SESSION.json',
    'rm -f --',
    '"$MAC_OUTPUT_DIR/01-home.jpg"',
    'require_clean_source_match "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"',
    'require_unchanged_source "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"',
):
    if fragment not in prepare_mac_source:
        raise SystemExit(f"Mac screenshot preparation is missing provenance guard: {fragment}")

for forbidden in (
    'GTA_FREE_STEM_SCREENSHOT_MODE',
    'GTA_FREE_STEM_SCREENSHOT_READY_NONCE',
    'SCREENSHOT_READY_MARKER',
    'SCREENSHOT_READY_OVERRIDE',
    'wait_for_app_ready',
    'read_ready_nonce',
    'screenshotCaptureReady',
):
    if forbidden in source:
        raise SystemExit(f"iPhone/iPad capture must use the production feed path, not screenshot-mode readiness: {forbidden}")

watch_required_fragments = (
    'BOOT_TIMEOUT="${BOOT_TIMEOUT:-120}"',
    'xcrun simctl clone "$source_id" "GTA STEM Watch Screenshot $$"',
    'subprocess.run(command, timeout=timeout)',
    'SIMCTL_COMMAND_TIMEOUT="$BOOT_TIMEOUT" run_simctl bootstatus "$WATCH_ID" -b',
    'wait_for_device_state "$identifier" "Shutdown" "$BOOT_TIMEOUT"',
    'wait_for_device_state "$WATCH_ID" "Shutdown" "$BOOT_TIMEOUT"',
    'run_simctl get_app_container "$WATCH_ID" "$WATCH_BUNDLE_ID" app',
    'OUTPUT_DIR="${OUTPUT_DIR:-$SCREENSHOT_ROOT/final}"',
    'RAW_OUTPUT_DIR="${RAW_OUTPUT_DIR:-$SCREENSHOT_ROOT/raw}"',
    'VISUAL_QA_MARKER="$OUTPUT_DIR/FINAL_VISUAL_QA.md"',
    'CAPTURE_RECEIPT="$OUTPUT_DIR/CAPTURE_RECEIPT.json"',
    'MAC_CAPTURE_SESSION="$OUTPUT_DIR/MAC_CAPTURE_SESSION.json"',
    'CONTACT_SHEET="$OUTPUT_DIR/contact-sheet.jpg"',
    'rm -f -- "$VISUAL_QA_MARKER" "$CAPTURE_RECEIPT" "$MAC_CAPTURE_SESSION" "$CONTACT_SHEET"',
    'SOURCE_COMMIT="$(screenshot_source_commit)"',
    'SOURCE_TREE_SHA256="$(screenshot_source_tree_sha256 "$SOURCE_COMMIT")"',
    'require_clean_screenshot_source "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"',
    'GTA_RELEASE_SOURCE_COMMIT="$SOURCE_COMMIT"',
    'verify_built_source_commit "$APP_PATH/Info.plist" "$SOURCE_COMMIT"',
    'require_unchanged_screenshot_source "$SOURCE_COMMIT" "$SOURCE_TREE_SHA256"',
)
for fragment in watch_required_fragments:
    if fragment not in watch_source:
        raise SystemExit(f"Missing Watch screenshot-readiness guard: {fragment}")

if 'kill -0 "$command_pid"' in watch_source:
    raise SystemExit("Watch capture must not poll an unreaped background simctl PID.")

def verify_visual_qa_invalidation(script_source, label):
    function_start = script_source.index("invalidate_visual_qa() {")
    function_end = script_source.index("\n}", function_start) + 2
    call = script_source.index("\ninvalidate_visual_qa\n", function_end)
    directory_setup = script_source.index("mkdir -p", function_end)
    first_build = script_source.index("xcodebuild", call)
    if not function_end < directory_setup < call < first_build:
        raise SystemExit(
            f"{label} must invalidate stale visual QA after directory setup and before any build/capture work."
        )

verify_visual_qa_invalidation(source, "iPhone/iPad capture")
verify_visual_qa_invalidation(watch_source, "Watch capture")

readiness_start = source.index("read_validated_live_feed_state() {")
readiness_end = source.index("\nwait_for_live_feed_refresh()", readiness_start)
readiness_source = source[readiness_start:readiness_end]
query_start = readiness_source.index('"SELECT ')
query_end = readiness_source.index(';\")', query_start) + 1
query_template = readiness_source[query_start + 1:query_end]

database = sqlite3.connect(":memory:")
database.execute(
    "CREATE TABLE ZOPPORTUNITYCACHERECORD "
    "(ZUPDATEDAT REAL, ZCACHEKEY TEXT, ZPAYLOAD BLOB)"
)
database.execute("CREATE TABLE ZSEENOPPORTUNITYRECORD (ZLASTSEENAT REAL)")
valid_payload = json.dumps(
    {"meta": {"lastUpdated": "2026-08-06"}, "data": [{"id": "live-1"}]},
    separators=(",", ":"),
)
database.execute(
    "INSERT INTO ZOPPORTUNITYCACHERECORD VALUES (?, ?, ?)",
    (100.0, "latest-opportunities", valid_payload),
)
database.execute("INSERT INTO ZSEENOPPORTUNITYRECORD VALUES (?)", (50.0,))

def readiness(previous_feed, previous_refresh):
    query = query_template.replace("$previous_feed_updated_at", str(previous_feed))
    query = query.replace("$previous_refresh_completed_at", str(previous_refresh))
    return database.execute(query).fetchone()

if readiness(100.0, 50.0) is not None:
    raise SystemExit("An unchanged cache with no new live-success witness must not pass readiness.")

database.execute("UPDATE ZOPPORTUNITYCACHERECORD SET ZUPDATEDAT = 101.0")
if readiness(100.0, 50.0) is None:
    raise SystemExit("A newer valid nonempty public-feed cache must pass readiness.")

database.execute("UPDATE ZOPPORTUNITYCACHERECORD SET ZUPDATEDAT = 100.0")
database.execute("UPDATE ZSEENOPPORTUNITYRECORD SET ZLASTSEENAT = 51.0")
if readiness(100.0, 50.0) is None:
    raise SystemExit("An unchanged valid payload with a newer live-success witness must pass readiness.")

empty_payload = json.dumps(
    {"meta": {"lastUpdated": "2026-08-06"}, "data": []},
    separators=(",", ":"),
)
database.execute(
    "UPDATE ZOPPORTUNITYCACHERECORD SET ZUPDATEDAT = 101.0, ZPAYLOAD = ?",
    (empty_payload,),
)
if readiness(100.0, 50.0) is not None:
    raise SystemExit("A live-success witness must not make an empty feed capture-ready.")

missing_date_payload = json.dumps(
    {"meta": {"lastUpdated": ""}, "data": [{"id": "live-1"}]},
    separators=(",", ":"),
)
database.execute("UPDATE ZOPPORTUNITYCACHERECORD SET ZPAYLOAD = ?", (missing_date_payload,))
if readiness(100.0, 50.0) is not None:
    raise SystemExit("A live-success witness must not make undated feed data capture-ready.")

database.execute("DELETE FROM ZOPPORTUNITYCACHERECORD")
database.execute("UPDATE ZSEENOPPORTUNITYRECORD SET ZLASTSEENAT = 52.0")
if readiness(-1.0, 50.0) is not None:
    raise SystemExit("Bundled-only state without a persisted public feed must not pass readiness.")

baseline_feed = capture.index('previous_feed_updated_at="$(read_live_feed_updated_at "$device")"')
baseline_refresh = capture.index('previous_refresh_completed_at="$(read_live_refresh_completed_at "$device")"')
launch_positions = []
offset = 0
while True:
    try:
        launch = capture.index('run_simctl launch "$device" "$BUNDLE_ID"', offset)
    except ValueError:
        break
    launch_positions.append(launch)
    offset = launch + 1
if len(launch_positions) != 2:
    raise SystemExit("Capture must retain exactly the query and non-query launch paths.")
wait = capture.index('wait_for_live_feed_refresh "$device" "$previous_feed_updated_at" "$previous_refresh_completed_at"')
settle = capture.index('sleep "$SCREENSHOT_DELAY"')
screenshot = capture.index('run_simctl io "$device" screenshot "$raw_output"')
if not max(baseline_feed, baseline_refresh) < min(launch_positions) <= max(launch_positions) < wait < settle < screenshot:
    raise SystemExit("Capture must baseline the cache, launch, require a newer validated feed, settle the UI, then take the screenshot.")

warm_baseline_feed = warm_up_device.index('previous_feed_updated_at="$(read_live_feed_updated_at "$device")"')
warm_baseline_refresh = warm_up_device.index('previous_refresh_completed_at="$(read_live_refresh_completed_at "$device")"')
warm_launch = warm_up_device.index('run_simctl launch "$device" "$BUNDLE_ID"')
warm_wait = warm_up_device.index('wait_for_live_feed_refresh "$device" "$previous_feed_updated_at" "$previous_refresh_completed_at"')
if not max(warm_baseline_feed, warm_baseline_refresh) < warm_launch < warm_wait:
    raise SystemExit("Warm-up must also wait for a feed refresh newer than its pre-launch cache state.")

bootstatus = prepare_device.index('run_simctl bootstatus "$device" -b')
app_check = prepare_device.index('run_simctl get_app_container "$device" "$BUNDLE_ID" app')
uninstall = prepare_device.index('run_simctl uninstall "$device" "$BUNDLE_ID"')
if not bootstatus < app_check < uninstall:
    raise SystemExit("Simulator readiness and app-presence checks must precede uninstall.")

print("Screenshot capture readiness guard passed.")
PY
