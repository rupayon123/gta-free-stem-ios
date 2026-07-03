# GTA FREE STEM iOS — Release Readiness Checklist

## Current status snapshot

- App is wired for 18 languages with UI string and permission-copy localization tests.
- First launch now honors the user's supported system language before falling back to English, then persists that choice for search, cache fallback, errors, labels, and settings.
- Search/hunt engine supports translated listing fields with language-aware searching and English fallbacks.
- Search/hunt filters now include first-class pathway toggles for volunteer hours, co-op/SHSM, mentorship, scholarships, and new finds.
- Dynamic listing decoding now supports `translations`, `localizations`, and `localized` payloads.
- Opportunity rows and map labels are localized in browsing screens.
- App Store privacy manifest is bundled and declares app-only `UserDefaults` access with reason `CA92.1`, no tracking, and no collected data types.
- Last verified on July 3, 2026:
  - Bundled iOS snapshot: 406 public opportunities, all carrying generated translation payloads for every non-English launch language.
  - App UI strings: 178/178 keys for each launch language, with strict duplicate-English checks passing at 0 untranslated-equals-English strings.
  - Local companion public feed: 406 public opportunities, 100% generated summary/category/cost/title/description payload coverage.
  - Live public feed: 406 public opportunities, 406 translated payloads, and 100% live summary/category/cost/title/description coverage after Vercel production deployment `dpl_7YVnTcUxAREXTwxAfaEUBBvFR9en`.
  - Companion site marketing, support, and privacy URLs resolve in production with HTTP 200.
  - Release simulator build and 43-test XCTest suite pass.
  - Support tab is privacy-safe for the current build: feedback and online submissions are unavailable, no personal-data input fields are shown, and submission APIs require an account token before any network request.
  - Public fallback copy now says `Offline backup` instead of internal preview database wording.
  - Missing translated summaries preserve the English source summary once inside the localized fallback text.
  - Map VoiceOver labels now include the localized visible-result count, and tests guard background refresh cache/new-match-notification wiring.
  - Device archive and App Store Connect upload pass from this Mac with Apple team `FE33NM88XX`; TestFlight candidate `1.0 (9)` uploaded successfully and is now command-line-confirmed with import status `VALID`, build status `BETA_INTERNAL_TESTING`, `APP_STORE_ELIGIBLE`, and `usesNonExemptEncryption = false`.
  - After the July 3 public feed refresh, uploaded build `1.0 (9)` is still valid but predates the 406-item bundled snapshot; upload a replacement TestFlight build before App Review if the submitted binary must include the current offline fallback.

## Latest command results

- `STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh`: passed on July 3, 2026 against production; bundled and live feeds have 406/406 translated opportunity payloads and 100% summary/category/cost/title/description coverage.
  - App Store metadata limits now pass inside this script: app name 13/30 characters, subtitle 23/30 characters, description 758/4000 characters, keywords 92/100 bytes.
  - Apple Developer public status check now covers App Store Connect, App Processing, App Upload, TestFlight, and App Store Connect API; the July 3, 2026 run reported no active events for those services. This does not confirm a specific uploaded build.
- `LIVE_FEED_URL=file:///Users/rh_mac/Documents/Codex/2026-07-01/bri/work/gta-free-stem-opportunities/public/opportunities.json STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh`: passed, proving the local feed artifact clears strict multilingual coverage before deployment.
- `xcodebuild -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' build`: passed.
- `xcodebuild test -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -destination 'platform=iOS Simulator,name=iPhone 17'`: passed, 43 tests, 0 failures.
- `bash docs/scripts/smoke-release-simulator.sh`: passed on July 3, 2026 for `iPhone 17`. The script built the Release app, clean-installed it on the simulator, verified the built bundle contains 406 opportunities, captured nonblank screenshots for home, opportunities, high-school, and support routes, and saved outputs under `build/release-smoke/`.
- `bash docs/scripts/capture-app-store-screenshots.sh`: passed; regenerated local App Store screenshots at `build/app-store-screenshots/` for 6.9-inch iPhone (`1320 x 2868`) and 13-inch iPad (`2064 x 2752`). Home screenshots show `Loaded from Offline backup`; Support screenshots show the unavailable feedback/submission state and no personal-data fields.
- The release audit now verifies the eight App Store screenshot PNGs exist, have exact upload dimensions, and are not blank. Latest run passed with iPhone screenshots at `1320 x 2868`, iPad screenshots at `2064 x 2752`, and more than 1,300 sampled colors on every screenshot.
- `xcodebuild archive -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -configuration Release -destination 'generic/platform=iOS' -archivePath build/GTAFreeSTEM-build9.xcarchive -allowProvisioningUpdates`: passed for `com.rupayonhaldar.gtafreestem` version `1.0`, build `9`.
- `xcodebuild -exportArchive -archivePath build/GTAFreeSTEM-build9.xcarchive -exportOptionsPlist docs/AppStoreConnectExportOptions.plist -exportPath build/export-build9 -allowProvisioningUpdates`: passed and uploaded `GTAFreeSTEM.ipa` build `1.0 (9)` to App Store Connect. Xcode distribution logs show build upload ID `222e71fe-92f1-4da3-bad7-205b9eb7a3b3`, upload-time state `PROCESSING`, uploaded date `2026-07-03 03:36:06 +0000`, and no upload errors.
- Xcode export evidence for build `9`: the local archive was created with automatic development signing, then the App Store Connect export pipeline remotely re-signed the uploaded payload with `Apple Distribution: RUPAYON HALDAR (FE33NM88XX)` and `get-task-allow = 0`. Do not force `CODE_SIGN_IDENTITY = Apple Distribution` while automatic signing is using the development archive path; it conflicts with Xcode's working export flow.
- `APP_STORE_CONNECT_USERNAME=rupayon244@gmail.com APP_STORE_CONNECT_KEYCHAIN_ITEM=GTA_FREE_STEM_ASC DELIVERY_ID=6b35d0b9-e7ce-498f-a36b-a8aa449dca35 bash docs/scripts/check-testflight-build-status.sh`: passed on July 3, 2026. App Store Connect reports build `1.0 (8)` with delivery UUID `6b35d0b9-e7ce-498f-a36b-a8aa449dca35`, import status `VALID`, build status `BETA_INTERNAL_TESTING`, `APP_STORE_ELIGIBLE`, `usesNonExemptEncryption = false`, uploaded date `2026-07-02 8:57:09 PM`, and expiration date `2026-09-30 8:57:09 PM`.
- `BUNDLE_VERSION=9 APP_STORE_CONNECT_USERNAME=rupayon244@gmail.com APP_STORE_CONNECT_KEYCHAIN_ITEM=GTA_FREE_STEM_ASC DELIVERY_ID=222e71fe-92f1-4da3-bad7-205b9eb7a3b3 bash docs/scripts/check-testflight-build-status.sh`: attempted after the build `9` upload. The saved Keychain item exists, but direct secret retrieval stalled and direct `@keychain:GTA_FREE_STEM_ASC` lookup cannot find the item by service name. A one-off app-specific-password run initially reached App Store Connect, then Apple's `read-build-info` endpoint returned HTTP 500 internal server error with request ID `7BCHCAO7PVHTKSJ32H2R2UHNOQ`; the later one-off password status check below confirmed build `9`.
- `APP_STORE_CONNECT_KEYCHAIN_SECRET_TIMEOUT=2 BUNDLE_VERSION=9 APP_STORE_CONNECT_USERNAME=rupayon244@gmail.com APP_STORE_CONNECT_KEYCHAIN_ITEM=GTA_FREE_STEM_ASC DELIVERY_ID=222e71fe-92f1-4da3-bad7-205b9eb7a3b3 bash docs/scripts/check-testflight-build-status.sh`: retried on July 3, 2026. Local Keychain secret access still timed out, and altool's `@keychain:` lookup still reported `Failed to find item GTA_FREE_STEM_ASC for user rupayon244@gmail.com in keychain`, so the script now prints safe recovery options for a one-off app-specific password, a re-stored Keychain item, or App Store Connect API-key auth.
- `BUNDLE_VERSION=9 DELIVERY_ID=222e71fe-92f1-4da3-bad7-205b9eb7a3b3 APP_STORE_CONNECT_USERNAME=rupayon244@gmail.com bash docs/scripts/check-testflight-build-status.sh` with a one-off app-specific password: passed on July 3, 2026. App Store Connect reports build `1.0 (9)` with delivery UUID `222e71fe-92f1-4da3-bad7-205b9eb7a3b3`, import status `VALID`, build status `BETA_INTERNAL_TESTING`, `APP_STORE_ELIGIBLE`, `usesNonExemptEncryption = false`, uploaded date `2026-07-02, 11:52:17 PM`, and expiration date `2026-09-30, 11:52:17 PM`.
- Browser check for `https://appstoreconnect.apple.com/apps/6779714459/testflight/ios`: unauthenticated `curl` receives the expected login redirect, but logged-in Brave and Safari sessions stayed blank/loading during this pass, matching the App Store Connect availability issue above.
- `docs/scripts/check-testflight-build-status.sh`: repeatable command-line status check for App Store Connect build processing. It uses app Apple ID `6779714459` and supports either App Store Connect API credentials, an app-specific password stored in Keychain, or a one-off `APP_STORE_CONNECT_APP_PASSWORD` environment variable.
- Companion repo `./node_modules/.bin/tsc --noEmit`: passed with bundled Node.
- Companion repo `./node_modules/.bin/tsx scripts/export-public-opportunities.ts && ./node_modules/.bin/tsx scripts/qa-check.ts`: passed; QA now rejects non-English translation payloads that are English copies.
- Companion repo `pnpm run build`: passed, regenerates `public/opportunities.json`, and exports `/privacy`.
- Companion repo `git push origin main`: passed after token-based HTTPS auth.
- iOS repo `git push origin main`: passed after token-based HTTPS auth.
- `pnpm dlx vercel deploy --prod --yes --scope rupayon-s-projects`: passed and aliased production to `https://gta-free-stem.vercel.app`. Latest clean deployment used the tracked npm project path and excluded local pnpm metadata with `.vercelignore`.
- Live `https://gta-free-stem.vercel.app/privacy/`: returns HTTP 200.
- Live `https://gta-free-stem.vercel.app/accessibility-support/`: returns HTTP 200.
- Live `https://gta-free-stem.vercel.app/`: returns HTTP 200.
- Live `https://gta-free-stem.vercel.app/opportunities.json`: returns 406 opportunities, 406 translated opportunity payloads.

## What is still required for public release

1. **Translation quality follow-up**
   - The bundled iOS snapshot and local companion feed now include generated multilingual summaries, titles, descriptions, localized category metadata, localized cost metadata, and category tags for all 406 public listings.
   - Production `opportunities.json` now includes the same payloads.
   - Human/API-reviewed organization, address, source-specific tag, and richer prose translations remain a quality upgrade after the generated-coverage release gate; they are not blocking the current generated-coverage release gate.
   - Companion feed repo status on July 3, 2026: `/Users/rh_mac/Documents/Codex/2026-07-01/bri/work/gta-free-stem-opportunities` is pushed to GitHub with broader public search fields and deployed to Vercel production at `dpl_7YVnTcUxAREXTwxAfaEUBBvFR9en` with 406/406 translated live listings.
   - The iOS repo now contains the synced 406-listing bundled opportunity snapshot and matching release-readiness docs.

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
   - Clean-install simulator smoke:
     - `bash docs/scripts/smoke-release-simulator.sh`

3. **Accessibility readiness review**
   - Confirm VoiceOver can read each row as a single label (title, org, city, ages) with the localized open-details hint.
   - Confirm map/list mode controls expose labels.

4. **Update flow checklist**
   - Confirm last hunt state restores on reopen (query, mode, filters).
   - Confirm latest cached results appear on reopen while live refresh is running.
   - Confirm manual refresh and background refresh both update `isLoading`, `dataSourceLabel`, and notifications.

5. **App Store**
   - Start with `docs/PUBLIC_RELEASE_RUNBOOK.md` for the shortest current path from uploaded build `1.0 (9)` to App Store submission.
   - Because the repo now bundles the refreshed 406-listing snapshot, upload a new TestFlight build before App Review if the final submitted binary should include that current offline fallback; build `1.0 (9)` will still refresh from the live feed online, but its bundled offline snapshot predates this sync.
   - Verify `docs/TESTFLIGHT.md`, update App Store Connect metadata, select confirmed build `1.0 (9)`, upload final screenshots, complete App Privacy and age-rating forms, and submit the app for App Review.
   - Use `docs/APP_STORE_METADATA.md` as the metadata/privacy draft and `docs/APP_STORE_SUBMISSION_PACKET.md` as the paste-ready App Store Connect packet. The draft is checked by `docs/scripts/check-release-readiness.sh` for App Store name, subtitle, description, and keyword limits.
   - Use `bash docs/scripts/check-public-release-gates.sh` after real-device QA and App Store Connect entry are recorded; it intentionally fails while `docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md` remains pending.
   - Use `https://gta-free-stem.vercel.app/`, `https://gta-free-stem.vercel.app/accessibility-support/`, and `https://gta-free-stem.vercel.app/privacy/` for App Store Connect marketing/support/privacy URLs; all three routes are live.
   - Apple Developer account `rupayon244@gmail.com` is signed into Xcode, team `FE33NM88XX` is available, and Xcode created/downloaded a provisioning profile for `com.rupayonhaldar.gtafreestem`.
   - The latest IPA upload succeeded for TestFlight candidate `1.0 (9)`, and build `9` is now command-line-confirmed as `VALID` and `BETA_INTERNAL_TESTING`.
   - Future processing and beta status checks for build `9` can use `BUNDLE_VERSION=9 DELIVERY_ID=222e71fe-92f1-4da3-bad7-205b9eb7a3b3 APP_STORE_CONNECT_USERNAME=rupayon244@gmail.com bash docs/scripts/check-testflight-build-status.sh` with a one-off app-specific password, or App Store Connect API-key auth. The saved Keychain item still exists but is not usable by altool's `@keychain:` lookup on this Mac.
   - Account-only and submission features are release-safe in build `1.0 (9)`: unfinished Apple sign-in/token exchange UI is hidden, the Support tab no longer collects feedback or missing-opportunity submissions, and account-dependent copy says the feature is not available in this build instead of exposing backend setup instructions.

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
- App Store Connect upload works from Xcode on this Mac. The saved app-specific password keychain item `GTA_FREE_STEM_ASC` exists, but secret retrieval stalled during the build `9` status check; the status script now times out that local read and documents one-off password/API-key fallback paths. Rotate/revoke the app-specific password after release work because it was generated interactively during this setup.
