#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/docs/scripts/capture-app-store-screenshots.sh"
WATCH_SCRIPT_PATH="$ROOT_DIR/docs/scripts/capture-watch-app-store-screenshot.sh"

/usr/bin/python3 - "$SCRIPT_PATH" "$WATCH_SCRIPT_PATH" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
watch_source = Path(sys.argv[2]).read_text()
start = source.index("prepare_device() {")
end = source.index("\nwarm_up_device()", start)
prepare_device = source[start:end]

required_fragments = (
    'BOOT_TIMEOUT="${BOOT_TIMEOUT:-120}"',
    'xcrun simctl clone "$source_id" "GTA STEM Screenshots ${display_name} $$"',
    'restore_source_boot=1',
    'run_simctl shutdown "$source_id"',
    'run_simctl boot "$source_id"',
    'if ! IPHONE_ID="$(clone_dedicated_device "$IPHONE_DEVICE")"',
    'subprocess.run(command, timeout=timeout)',
    'SIMCTL_COMMAND_TIMEOUT="$BOOT_TIMEOUT" run_simctl bootstatus "$device" -b',
    'run_simctl get_app_container "$device" "$BUNDLE_ID" app',
    'SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_MODE=1',
    'SIMCTL_CHILD_GTA_FREE_STEM_SCREENSHOT_READY_NONCE="$ready_nonce"',
    'SCREENSHOT_READY_TIMEOUT="${SCREENSHOT_READY_TIMEOUT:-45}"',
    'wait_for_app_ready "$device" "$ready_nonce"',
    'run_simctl get_app_container "$device" "$BUNDLE_ID" data',
    '/Library/Caches/$SCREENSHOT_READY_MARKER',
)
for fragment in required_fragments:
    if fragment not in source:
        raise SystemExit(f"Missing screenshot-readiness guard: {fragment}")

if 'kill -0 "$command_pid"' in source:
    raise SystemExit("Screenshot capture must not poll an unreaped background simctl PID.")
if 'CREATED_SIMULATORS[@]' in source:
    raise SystemExit("Screenshot cleanup must be safe under the macOS Bash 3.2 empty-array behavior.")
if 'CREATED_IPHONE_ID=""' not in source or 'CREATED_IPAD_ID=""' not in source:
    raise SystemExit("Screenshot cleanup must track each task-created simulator explicitly.")
if 'defaults read "$BUNDLE_ID" screenshotCaptureReady' in source or 'screenshotCaptureReady -bool false' in source:
    raise SystemExit("Screenshot readiness must come from a per-launch marker in the app sandbox, not simulator-global defaults.")

watch_required_fragments = (
    'BOOT_TIMEOUT="${BOOT_TIMEOUT:-120}"',
    'xcrun simctl clone "$source_id" "GTA STEM Watch Screenshot $$"',
    'subprocess.run(command, timeout=timeout)',
    'SIMCTL_COMMAND_TIMEOUT="$BOOT_TIMEOUT" run_simctl bootstatus "$WATCH_ID" -b',
    'run_simctl get_app_container "$WATCH_ID" "$WATCH_BUNDLE_ID" app',
)
for fragment in watch_required_fragments:
    if fragment not in watch_source:
        raise SystemExit(f"Missing Watch screenshot-readiness guard: {fragment}")

if 'kill -0 "$command_pid"' in watch_source:
    raise SystemExit("Watch capture must not poll an unreaped background simctl PID.")

bootstatus = prepare_device.index('run_simctl bootstatus "$device" -b')
app_check = prepare_device.index('run_simctl get_app_container "$device" "$BUNDLE_ID" app')
uninstall = prepare_device.index('run_simctl uninstall "$device" "$BUNDLE_ID"')
if not bootstatus < app_check < uninstall:
    raise SystemExit("Simulator readiness and app-presence checks must precede uninstall.")

print("Screenshot capture readiness guard passed.")
PY
