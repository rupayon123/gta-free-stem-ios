#!/usr/bin/env bash
set -euo pipefail

# Creates a no-upload Release archive whose signed bundle metadata records the
# exact Git source commit. The scoped source inputs must be clean and byte-match
# that commit, so an artifact cannot be attributed to a different revision.

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

PLATFORM="${1:-}"
SOURCE_COMMIT="${SOURCE_COMMIT:-$(git rev-parse HEAD)}"
SOURCE_PATHS=(GTAFreeSTEM GTAFreeSTEMWatch GTAFreeSTEM.xcodeproj project.yml)

if [ "${#SOURCE_COMMIT}" -ne 40 ] || [[ "$SOURCE_COMMIT" == *[!0-9a-f]* ]]; then
  echo "SOURCE_COMMIT must be a full lowercase 40-character Git commit."
  exit 2
fi

if ! git cat-file -e "${SOURCE_COMMIT}^{commit}" 2>/dev/null; then
  echo "SOURCE_COMMIT does not resolve to a local Git commit: $SOURCE_COMMIT"
  exit 2
fi

if [ -n "$(git status --porcelain=v1 --untracked-files=all -- "${SOURCE_PATHS[@]}")" ] || \
   ! git diff --quiet "$SOURCE_COMMIT" -- "${SOURCE_PATHS[@]}"; then
  echo "App, Watch, project, or project.yml inputs do not exactly match SOURCE_COMMIT=$SOURCE_COMMIT."
  echo "Commit the intended source before creating a release archive."
  exit 2
fi

case "$PLATFORM" in
  ios)
    DESTINATION='generic/platform=iOS'
    ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/GTAFreeSTEM-build12.xcarchive}"
    ;;
  mac)
    DESTINATION='generic/platform=macOS,variant=Mac Catalyst'
    ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/GTAFreeSTEM-Mac-build12.xcarchive}"
    ;;
  *)
    echo "Usage: $0 ios|mac"
    echo "Optional: SOURCE_COMMIT=<40-hex> ARCHIVE_PATH=/absolute/output.xcarchive $0 ios|mac"
    exit 2
    ;;
esac

if [ -e "$ARCHIVE_PATH" ]; then
  echo "Archive path already exists; choose a new ARCHIVE_PATH so verified artifacts are never overwritten:"
  echo "  $ARCHIVE_PATH"
  exit 2
fi

echo "Archiving ${PLATFORM} source commit ${SOURCE_COMMIT}..."
xcodebuild archive \
  -project GTAFreeSTEM.xcodeproj \
  -scheme GTAFreeSTEM \
  -configuration Release \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  "GTA_RELEASE_SOURCE_COMMIT=$SOURCE_COMMIT"

echo "Created source-bound archive: $ARCHIVE_PATH"
