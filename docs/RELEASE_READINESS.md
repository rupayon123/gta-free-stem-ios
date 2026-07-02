# GTA FREE STEM iOS — Release Readiness Checklist

## Current status snapshot

- App is wired for 18 languages with UI string and permission-copy localization tests.
- Search/hunt engine supports translated listing fields with language-aware searching and English fallbacks.
- Search/hunt filters now include first-class pathway toggles for volunteer hours, co-op/SHSM, mentorship, scholarships, and new finds.
- Dynamic listing decoding now supports `translations`, `localizations`, and `localized` payloads.
- Opportunity rows and map labels are localized in browsing screens.
- App Store privacy manifest is bundled and declares app-only `UserDefaults` access with reason `CA92.1`, no tracking, and no collected data types.
- Last verified on July 2, 2026:
  - Bundled iOS snapshot: 370 public opportunities, all carrying generated translation payloads for every non-English launch language.
  - App UI strings: 178/178 keys for each launch language, with strict duplicate-English checks passing at 0 untranslated-equals-English strings.
  - Local companion public feed: 370 public opportunities, 100% generated summary/category/cost/title/description payload coverage.
  - Live public feed: 370 public opportunities, 370 translated payloads, and 100% live summary/category/cost/title/description coverage after Vercel production deployment `dpl_4SjBikyTa6FQrCyjRafTz2cgJPjX`.
  - Companion site `/privacy/` resolves in production with HTTP 200.
  - Release simulator build and unit tests pass.
  - Device archive and App Store Connect upload pass from this Mac with Apple team `FE33NM88XX`; TestFlight candidate `1.0 (4)` is uploaded, processed, and attached to the internal `Zenin` tester group in App Store Connect.

## Latest command results

- `bash docs/scripts/check-release-readiness.sh`: passed in advisory mode.
- `LIVE_FEED_URL=file:///Users/rh_mac/Documents/Codex/2026-07-01/bri/work/gta-free-stem-opportunities/public/opportunities.json STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh`: passed, proving the local feed artifact clears strict multilingual coverage before deployment.
- `STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh`: passed against production; live feed has 370/370 translated opportunity payloads and 100% summary/category/cost/title/description coverage.
- `xcodebuild -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' build`: passed.
- `xcodebuild test -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -destination 'platform=iOS Simulator,name=iPhone 17'`: passed, 33 tests, 0 failures.
- `xcodebuild archive -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -configuration Release -destination 'generic/platform=iOS' -archivePath build/GTAFreeSTEM.xcarchive -allowProvisioningUpdates`: passed for `com.rupayonhaldar.gtafreestem` version `1.0` after signing into Apple account `rupayon244@gmail.com`.
- `xcodebuild -exportArchive -archivePath build/GTAFreeSTEM.xcarchive -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates`: passed and uploaded `GTAFreeSTEM.ipa` build `1.0 (4)` to App Store Connect for processing because the local ignored export plist had Xcode's default `manageAppVersionAndBuildNumber` behavior enabled. Future command-line uploads should use tracked `docs/AppStoreConnectExportOptions.plist`.
- Companion repo `./node_modules/.bin/tsc --noEmit`: passed with bundled Node.
- Companion repo `./node_modules/.bin/tsx scripts/export-public-opportunities.ts && ./node_modules/.bin/tsx scripts/qa-check.ts`: passed; QA now rejects non-English translation payloads that are English copies.
- Companion repo `pnpm run build`: passed, regenerates `public/opportunities.json`, and exports `/privacy`.
- Companion repo `git push origin main`: passed after token-based HTTPS auth.
- iOS repo `git push origin main`: passed after token-based HTTPS auth.
- `pnpm dlx vercel deploy --prod --yes --scope rupayon-s-projects`: passed and aliased production to `https://gta-free-stem.vercel.app`. Latest clean deployment used the tracked npm project path and excluded local pnpm metadata with `.vercelignore`.
- Live `https://gta-free-stem.vercel.app/privacy/`: returns HTTP 200.
- Live `https://gta-free-stem.vercel.app/opportunities.json`: returns 370 opportunities, 370 translated opportunity payloads.

## What is still required for public release

1. **Feed translation coverage**
   - The bundled iOS snapshot and local companion feed now include generated multilingual summaries, titles, descriptions, localized category metadata, localized cost metadata, and category tags for all 370 public listings.
   - Production `opportunities.json` now includes the same payloads.
   - Human/API-reviewed title, organization, address, source-specific tags, and richer description translations remain a quality upgrade after the generated-coverage release gate.
   - Companion feed repo status on July 2, 2026: `/Users/rh_mac/Documents/Codex/2026-07-01/bri/work/gta-free-stem-opportunities` is pushed to GitHub with the `.vercelignore` reproducibility guard and deployed to Vercel production at `dpl_4SjBikyTa6FQrCyjRafTz2cgJPjX` with 370/370 translated live listings.
   - The iOS repo is pushed to GitHub with the synced bundled opportunity snapshot and release-readiness docs.

2. **Release validation commands**
   - Build release:
     - `xcodebuild -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' build`
   - Smoke tests (simulator):
     - `xcodebuild test -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -destination 'platform=iOS Simulator,name=iPhone 17'`
   - Feed translation audit (local):
     - `jq '(.opportunities // .data) | length' GTAFreeSTEM/Resources/opportunities.json`
     - `jq '((.opportunities // .data) | map((.translations // .localizations // .localized // {}) | length > 0) | map(select(. == true)) | length)' GTAFreeSTEM/Resources/opportunities.json`
   - Full audit script:
     - `bash docs/scripts/check-release-readiness.sh`

3. **Accessibility readiness review**
   - Confirm VoiceOver can read each row as a single label (title, org, city, ages) with the localized open-details hint.
   - Confirm map/list mode controls expose labels.

4. **Update flow checklist**
   - Confirm last hunt state restores on reopen (query, mode, filters).
   - Confirm latest cached results appear on reopen while live refresh is running.
   - Confirm manual refresh and background refresh both update `isLoading`, `dataSourceLabel`, and notifications.

5. **App Store**
   - Verify `docs/TESTFLIGHT.md`, update App Store Connect metadata, and process a release build.
   - Use `docs/APP_STORE_METADATA.md` as the first metadata/privacy draft.
   - Use `https://gta-free-stem.vercel.app/privacy/` for App Store Connect; the route is live.
   - Apple Developer account `rupayon244@gmail.com` is signed into Xcode, team `FE33NM88XX` is available, and Xcode created/downloaded a provisioning profile for `com.rupayonhaldar.gtafreestem`.
   - The latest IPA upload succeeded for TestFlight candidate `1.0 (4)`; App Store Connect shows it as `Ready to Submit` and attached to internal group `Zenin`.

## Mac setup to keep development unblocked

- Xcode 16+/17+ with Apple Developer membership.
- Git, GitHub CLI (`gh`) and repository push credentials.
- Optional: `xcodegen` (used by this repo’s project.yml).

Current Mac status:

- Xcode is installed and command-line builds pass.
- Command-line archive signing and App Store Connect upload are working after Apple account login.
- Git is installed.
- Homebrew is not installed.
- GitHub CLI (`gh`) is not installed.
- Repository pushes succeeded with temporary token-based HTTPS auth. Configure a persistent GitHub credential helper or GitHub CLI login before the next push.
