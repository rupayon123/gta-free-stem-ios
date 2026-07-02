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
  - App UI strings: 177/177 keys for each launch language, with strict duplicate-English checks passing at 0 untranslated-equals-English strings.
  - Local companion public feed: 370 public opportunities, 100% generated summary/category/cost/title/description payload coverage.
  - Live public feed: 394 opportunities, 0 translated opportunity payloads until Vercel production redeploys the pushed companion feed repo.
  - Companion site production build includes `/privacy`, but the live route still returns 404 until Vercel production redeploys.
  - Release simulator build and unit tests pass.
  - Device archive is blocked on this Mac because Xcode command-line signing has no Apple account or provisioning profile for `com.rupayonhaldar.gtafreestem`.

## Latest command results

- `bash docs/scripts/check-release-readiness.sh`: passed in advisory mode.
- `LIVE_FEED_URL=file:///Users/rh_mac/Documents/Codex/2026-07-01/bri/work/gta-free-stem-opportunities/public/opportunities.json STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh`: passed, proving the local feed artifact clears strict multilingual coverage before deployment.
- `STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh`: still fails against production until the companion feed deploys because the live public feed has 0/394 translated opportunity payloads.
- `xcodebuild -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' build`: passed.
- `xcodebuild test -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -destination 'platform=iOS Simulator,name=iPhone 17'`: passed, 32 tests, 0 failures.
- `xcodebuild archive -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -configuration Release -destination 'generic/platform=iOS' -archivePath build/GTAFreeSTEM.xcarchive -allowProvisioningUpdates`: failed with `No Accounts` and `No profiles for 'com.rupayonhaldar.gtafreestem' were found`.
- Companion repo `./node_modules/.bin/tsc --noEmit`: passed with bundled Node.
- Companion repo `./node_modules/.bin/tsx scripts/export-public-opportunities.ts && ./node_modules/.bin/tsx scripts/qa-check.ts`: passed; QA now rejects non-English translation payloads that are English copies.
- Companion repo `pnpm run build`: passed, regenerates `public/opportunities.json`, and exports `/privacy`.
- Companion repo `git push origin main`: passed after token-based HTTPS auth.
- iOS repo `git push origin main`: passed after token-based HTTPS auth.
- Live `https://gta-free-stem.vercel.app/privacy/`: currently returns 404 until the companion repo deploys.
- Live `https://gta-free-stem.vercel.app/opportunities.json`: currently 394 opportunities, 0 translated opportunity payloads.

## What is still required for public release

1. **Feed translation coverage**
   - The bundled iOS snapshot and local companion feed now include generated multilingual summaries, titles, descriptions, localized category metadata, localized cost metadata, and category tags for all 370 public listings.
   - Public release still needs the deployed `opportunities.json` to include the same payloads.
   - Human/API-reviewed title, organization, address, source-specific tags, and richer description translations remain a quality upgrade after the generated-coverage release gate.
   - Local companion feed repo status on July 2, 2026: `/Users/rh_mac/Documents/Codex/2026-07-01/bri/work/gta-free-stem-opportunities` is pushed to GitHub at `f6dd050`.
   - The iOS repo is pushed to GitHub at `36fbd51`, including the synced bundled opportunity snapshot.
   - These changes are not live in production yet because Vercel has not created a new production deployment for the pushed companion feed commit.

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
   - Confirm VoiceOver can read each row as a single label (title, org, city, ages).
   - Confirm map/list mode controls expose labels.

4. **Update flow checklist**
   - Confirm last hunt state restores on reopen (query, mode, filters).
   - Confirm latest cached results appear on reopen while live refresh is running.
   - Confirm manual refresh and background refresh both update `isLoading`, `dataSourceLabel`, and notifications.

5. **App Store**
   - Verify `docs/TESTFLIGHT.md`, update App Store Connect metadata, and process a release build.
   - Use `docs/APP_STORE_METADATA.md` as the first metadata/privacy draft.
   - Use `https://gta-free-stem.vercel.app/privacy/` for App Store Connect after the companion site deploy confirms the route is live.
   - Add an Apple Developer account in Xcode Settings > Accounts, select team `FE33NM88XX`, and let Xcode create/download a profile for `com.rupayonhaldar.gtafreestem`.
   - Current archive command failure:
     - `No Accounts: Add a new account in Accounts settings.`
     - `No profiles for 'com.rupayonhaldar.gtafreestem' were found.`

## Mac setup to keep development unblocked

- Xcode 16+/17+ with Apple Developer membership.
- Git, GitHub CLI (`gh`) and repository push credentials.
- Optional: `xcodegen` (used by this repo’s project.yml).

Current Mac status:

- Xcode is installed and command-line builds pass.
- Command-line archive signing is not ready because Xcode has no Apple account configured.
- Git is installed.
- Homebrew is not installed.
- GitHub CLI (`gh`) is not installed.
- Repository pushes succeeded with temporary token-based HTTPS auth. Configure a persistent GitHub credential helper or GitHub CLI login before the next push.
