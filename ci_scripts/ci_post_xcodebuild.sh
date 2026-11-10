#!/bin/bash
set -euo pipefail

[[ "${CI_XCODE_CLOUD:-}" == "TRUE" ]] || { echo 'Missing Xcode Cloud environment'; exit 1; }
[[ "${CI_XCODEBUILD_ACTION:-}" == "archive" ]] || exit 0
[[ "${CI_XCODEBUILD_EXIT_CODE:-}" == "0" ]] || { echo 'Archive action failed'; exit 1; }
commit="${CI_COMMIT:-}"
number="${CI_BUILD_NUMBER:-}"
archive="${CI_ARCHIVE_PATH:-}"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid or missing CI_COMMIT'; exit 1; }
[[ "$number" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid or missing Cloud build number'; exit 1; }
[[ -d "$archive/Products/Applications" ]] || { echo 'Cloud archive applications unavailable'; exit 1; }
shopt -s nullglob
apps=("$archive"/Products/Applications/*.app)
[[ ${#apps[@]} -eq 1 ]] || { echo 'Expected exactly one iOS app in archive'; exit 1; }
app="${apps[0]}"
watches=("$app"/Watch/*.app)
[[ ${#watches[@]} -eq 1 ]] || { echo 'Expected exactly one embedded Watch app'; exit 1; }
read_plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist"; }
archive_number="$(read_plist "$app" CFBundleVersion)"
[[ "$archive_number" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid archive build number'; exit 1; }
for bundle in "$app" "${watches[0]}"; do
  [[ "$(read_plist "$bundle" GTAReleaseSourceCommit)" == "$commit" ]] || { echo 'Bundle source commit mismatch'; exit 1; }
  [[ "$(read_plist "$bundle" CFBundleShortVersionString)" == '1.0' ]] || { echo 'Unexpected marketing version'; exit 1; }
  [[ "$(read_plist "$bundle" CFBundleVersion)" == "$archive_number" ]] || { echo 'App and Watch archive builds differ'; exit 1; }
  codesign --verify --strict "$bundle"
done
[[ "$(read_plist "$app" CFBundleIdentifier)" == 'com.rupayonhaldar.gtafreestem' ]] || { echo 'Unexpected app identifier'; exit 1; }
[[ "$(read_plist "${watches[0]}" CFBundleIdentifier)" == 'com.rupayonhaldar.gtafreestem.watchkitapp' ]] || { echo 'Unexpected Watch identifier'; exit 1; }
[[ "$(read_plist "${watches[0]}" WKCompanionAppBundleIdentifier)" == 'com.rupayonhaldar.gtafreestem' ]] || { echo 'Unexpected Watch companion'; exit 1; }
echo "Verified iOS and Watch archive metadata: source $commit, version 1.0 ($archive_number); Cloud build $number. Verify the uploaded build separately."
