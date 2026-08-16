# TestFlight Real-Device QA Signoff

Last updated: August 6, 2026

Record observed real-device evidence for build 1.0 (12) here. The public release gate only passes when each required row is \`Pass\` or a release owner has explicitly recorded \`Accepted Risk\` with notes. Simulator-only evidence never counts as a real-device pass.

## Build Under Test

- App: \`GTA FREE STEM\`
- Version/build: \`1.0 (12)\`
- iOS Delivery UUID: \`Pending upload\`
- Mac Delivery UUID: \`Pending upload\`
- iOS App Store Connect status: \`Not uploaded\`
- iOS BuildBetaDetail.internalBuildState: \`Not uploaded\`
- Mac App Store Connect status: \`Not uploaded\`
- Mac BuildBetaDetail.internalBuildState: \`Not uploaded\`
- App Review status: \`Not submitted\`
- Public distribution platforms: \`iphone,ipad,watch,mac\`
- Mac App Store record strategy: \`Separate record selected for com.rupayonhaldar.gtafreestem.maccatalyst; portal Mac App ID and SKU pending\`
- Screenshot package status: \`13 local files passed structural and full-size visual inspection 2026-08-06; clean-source exact-build recapture, CAPTURE_RECEIPT.json, repeated visual QA, and source-bound manifest pending\`

## Verified Artifact Binding

- Artifact binding status: \`SUPERSEDED_PENDING_REBUILD\`
- Published commit: \`42c138436ece43ecca120ff76edbf1c4f90b17ff\`
- Artifact verification date: \`2026-08-06\`
- iOS archive path: \`/Users/rh_mac/Documents/Codex/2026-07-01/bri/work/gta-free-stem-ios/build/final-release-ios-20260806-r6-published-source.xcarchive\`
- iOS archive SHA-256: \`443c03f13685caa34eb36b6f875d18bee8226476fd288187f22104ae42228dd5\`
- iOS IPA path: \`/Users/rh_mac/Documents/Codex/2026-07-01/bri/work/gta-free-stem-ios/build/final-release-ios-20260806-r6-export/GTAFreeSTEM.ipa\`
- iOS IPA SHA-256: \`8cf97134ce8985f1a9ca62c6dd52cb1680e876ca7a56eafe6ee31cdd901081eb\`
- Mac archive path: \`/Users/rh_mac/Documents/Codex/2026-07-01/bri/work/gta-free-stem-ios/build/final-release-mac-20260806-r3-published-source.xcarchive\`
- Mac archive SHA-256: \`450e335911c8babedeecfaa0d68841c95543c83a978f38d5eed85d92b641b5b6\`
- Mac package path: \`/Users/rh_mac/Documents/Codex/2026-07-01/bri/work/gta-free-stem-ios/build/final-release-mac-20260806-r3-export/GTAFreeSTEM.pkg\`
- Mac package SHA-256: \`b9afd175d605ea9ba588702d92df71a31044714cf893ad9633cff126f1320f34\`

The paths, hashes, and commit above are retained only as superseded historical evidence; do not upload them. After the current source is committed, rebuild, re-sign, and reverify all four artifacts, replace every binding field, and set \`Artifact binding status\` to exactly \`CURRENT_AND_VERIFIED\`. The archive hashes are deterministic tree SHA-256 values calculated by the public-release gate; the IPA and package hashes are ordinary file SHA-256 values. Record canonical absolute paths. The published commit must be the full source commit embedded as \`GTAReleaseSourceCommit\` in every signed archive and exported package. It must be reachable from live \`origin/main\`, and its app, Watch, Xcode project, and \`project.yml\` inputs must byte-match both live main and the local verification inputs. Later docs-only signoff commits may advance main without changing this recorded source commit. The verification date must be the date the gate reruns the strict verifiers on those exact bytes.

Replace the pending upload fields only after App Store Connect reports actual values.

Superseded local archive/export evidence is not an upload candidate or TestFlight evidence:

- iOS archive \`build/final-release-ios-20260806-r6-published-source.xcarchive\` is a valid development-signed export source and passes 52/52 checks with exact main and Watch development provisioning identifiers and published-source provenance.
- Exported IPA \`build/final-release-ios-20260806-r6-export/GTAFreeSTEM.ipa\` is a safe no-upload Apple Distribution export and passes 62/62 strict checks with exact main/Watch App Store profiles, matching archive UUIDs, and published-source provenance. SHA-256: \`8cf97134ce8985f1a9ca62c6dd52cb1680e876ca7a56eafe6ee31cdd901081eb\`.
- Mac Catalyst archive \`build/final-release-mac-20260806-r3-published-source.xcarchive\` is a valid development-signed export source and passes 36/36 pre-export checks. The correctly signed no-upload package is \`build/final-release-mac-20260806-r3-export/GTAFreeSTEM.pkg\`, SHA-256 \`b9afd175d605ea9ba588702d92df71a31044714cf893ad9633cff126f1320f34\`, and passes 48/48 strict package checks.
- The published artifact source commit \`42c138436ece43ecca120ff76edbf1c4f90b17ff\` passed 108/108 tests in the fresh full iPad Simulator suite recorded at \`build/DerivedData-final-tests-source-provenance-20260806/Logs/Test/Test-GTAFreeSTEM-2026.08.06_16-54-57--0400.xcresult\`. A fresh Mac Release launch also completed a single loader handoff at 100%; search, details, and local Profile persistence across relaunch were manually verified.
- Development signing on these archives is not itself a failure. Xcode re-signs the packaged app for distribution during App Store export.
- Source commit \`42c138436ece43ecca120ff76edbf1c4f90b17ff\` was published through pull request #4 and is reachable from current \`origin/main\`. The exact final tree has not yet been installed on the iPhone. Xcode reports Kurihara unavailable and live USB inspection does not enumerate the phone. Do not record an install or launch pass until the published build is installed and observed.
- No build has been uploaded or processed in TestFlight, so all TestFlight and real-device rows remain pending.

The current release scope is locked to \`iphone,ipad,watch,mac\`. Pass that exact value through \`PUBLIC_RELEASE_PLATFORMS\` and provide platform-specific evidence for all four values. The Watch companion is embedded in the iOS upload. Mac uses the separately uploaded \`com.rupayonhaldar.gtafreestem.maccatalyst\` product. The generic gate deliberately has no platform default so a future release must still declare its scope explicitly.

## Tester And Device

- Tester:
- Date:
- Install source: TestFlight
- Network conditions tested:
- Accessibility settings tested:
- Languages tested:

After completing the minimum test matrix, record exactly \`TestFlight\`, \`WI_FI_AND_OFFLINE_FALLBACK\`, \`VOICEOVER_LARGE_TEXT_DARK_MODE\`, and \`ENGLISH_FRENCH_SPANISH_ARABIC_RTL\` in the four corresponding fields above. Add any extra coverage in Notes rather than changing these gate values.

## Required Passes

| Area | Required evidence | Status | Notes |
| --- | --- | --- | --- |
| Install and launch | Fresh TestFlight install opens without crash and reaches public browsing. | Pending | |
| Warm launch experience | The branded loader completes its bounded cache/bundle preparation checkpoint; progress moves forward, reaches 100% once, never restarts, and never leaves a blank white screen. Confirm that a valid local snapshot is immediately browsable and that a missing local snapshot hands off to the interactive loading/error state while live refresh continues. | Pending | |
| Live feed | Online launch shows a current feed and a coherent data-source state. | Pending | |
| Search keywords | Multi-word search such as \`robotics Toronto\` returns relevant results. | Pending | |
| Search translations | Non-English listing content is searchable while English fallback terms still work. | Pending | |
| Filters and sorting | City, region, age, language, category, high-school, volunteer, co-op, mentorship, scholarship, equity, new-find, distance, and sorting controls apply and reset correctly. | Pending | |
| Map/list consistency | Display-only map pins and list results agree for the current filtered hunt; actions remain in listing details and external provider/directions links. | Pending | |
| Details and external links | Listing details are readable and provider/directions links open correctly. | Pending | |
| Local saves | Saving and removing an opportunity works without a network account. | Pending | |
| Local profile deletion | Create a local Profile, then delete it in Settings and confirm saved opportunities and hunt history clear. | Pending | |
| Manual refresh | Repeated refreshes do not duplicate results, freeze, or show conflicting states. | Pending | |
| Cache fallback | After a successful refresh, offline reopening shows the cached feed. | Pending | |
| Bundled fallback | A clean offline install opens with the bundled snapshot rather than failing. | Pending | |
| State restore | Query, mode, filters, and visible results restore after quit/reopen. | Pending | |
| Location | Denied and allowed nearby search cases are clear, local-only, and never block browsing. | Pending | |
| Notifications | Declining and allowing the optional local new-opportunity alert are both understandable, do not block browsing, and do not send data or register for remote push. Confirm copy does not promise a fixed schedule because Apple controls background-refresh timing. | Pending | |
| Localization and RTL | Language switching works; Arabic, Farsi/Persian, or Urdu layouts remain usable. | Pending | |
| Accessibility | Large text, VoiceOver, light/dark appearance, and contrast are usable. | Pending | |
| Support privacy | Support collects no name, email, message, or missing-opportunity submission in this build. | Pending | |
| App Store URLs | Marketing, support, privacy, and Terms URLs load; legal links open from Settings/Support; GitHub Issues accepts a non-sensitive test ticket. | Pending | |

## Platform-Specific Evidence

Record the actual device, operating-system version, and observed result for iPhone, iPad, paired Apple Watch, and Mac below. A simulator never substitutes for the real-device evidence required by this four-platform release.

| Platform | Required evidence | Device model | OS version | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| iPhone | Fresh TestFlight install; online and offline discovery flow. | | | Pending | |
| iPad | TestFlight install; navigation and filter layout remain usable. | | | Pending | |
| Apple Watch | Paired Watch receives the capped saved-opportunity set and archive status from the phone and remains readable; it is not a standalone full-feed search app. | | | Pending | |
| Mac | Mac Catalyst launch, sidebar navigation, links, and window-scale appearance. | | | Pending | |

## Release Owner Decision

- Overall status: \`Pending\`
- Accepted risks:
- Must-fix blockers:
- iOS App Store Connect build selected:
- Mac App Store Connect build selected:
- Archive provenance verified:
- Screenshot visual QA: \`PENDING\`
- Visual QA manifest SHA-256:
- Screenshots uploaded: \`PENDING\`
- Metadata/privacy/age rating entered:
- Support contact verified:
- Production legal/support truthfulness verified:
- App Review contact verified:
- Copyright entered:
- Platform record decision: \`Selected Separate Mac App Store record for com.rupayonhaldar.gtafreestem.maccatalyst; Mac App ID and SKU pending App Store Connect creation\`
- Primary language verified:
- Availability and DSA verified:
- Submitted for App Review:

## Evidence Instructions

Expected evidence once the portal is completed. These instructions are deliberately outside the structured release-owner section so they can never be parsed as observed evidence:

- Artifact binding status: record exactly \`CURRENT_AND_VERIFIED\` only after the exact recorded source and all four replacement artifacts are current and verified.
- iOS App Store Connect build selected: \`1.0 (12)\` from the processed iOS/Watch upload.
- Mac App Store Connect build selected: \`1.0 (12)\` from the separately processed Mac upload.
- iOS App Store Connect status and iOS \`BuildBetaDetail.internalBuildState\`: record exactly \`VALID\` and \`IN_BETA_TESTING\` only after the documented App Store Connect API fields report those states for the iOS/Watch product.
- Mac App Store Connect status and Mac \`BuildBetaDetail.internalBuildState\`: independently record exactly \`VALID\` and \`IN_BETA_TESTING\` only after the documented App Store Connect API fields report those states for the separate Mac product.
- Archive provenance verified: after completing every structured field in \`Verified Artifact Binding\`, record exactly \`VERIFIED_SIGNED_BUILD_1_0_12_IOS_WATCH_MAC\`. A development-signed archive may be the valid pre-export source; each exported distributable must carry App Store distribution signing and match its archive.
- Screenshot visual QA: record exactly \`PASS\` only after `CAPTURE_RECEIPT.json` binds the clean published source, source-embedded iOS/Watch/Mac executables, and all 13 JPEGs; the complete receipt-bound set has then passed full-size review; and no receipt, manifest, or screenshot bytes have changed.
- Visual QA manifest SHA-256: create \`build/app-store-screenshots/final/FINAL_VISUAL_QA.md\` from \`docs/FINAL_VISUAL_QA_TEMPLATE.md\`, record the generated capture-receipt SHA-256, exact published commit and build, reviewer/date, and all 13 current JPEG SHA-256 values, run `verify-screenshot-package.sh`, and enter the approved manifest file's lowercase SHA-256 here.
- Screenshots uploaded: record exactly \`UPLOADED_13_IPHONE_IPAD_WATCH_MAC\` after App Store Connect accepts four iPhone, four iPad, four Mac, and one Watch image from \`build/app-store-screenshots/final/\`.
- Metadata/privacy/age rating entered: after entering metadata, App Privacy, age rating, Made for Kids = No, export compliance, and review notes, record exactly \`ENTERED_METADATA_PRIVACY_AGE_RATING_KIDS_NO_EXPORT_COMPLIANCE_REVIEW_NOTES\`.
- Support contact verified: after verifying the production Support URL, GitHub Issues route, and a monitored public email or telephone contact, record exactly \`VERIFIED: https://gta-free-stem.vercel.app/support/ | GITHUB_ISSUES | MONITORED_DIRECT_CONTACT\`. Do not copy the private contact value here.
- Production legal/support truthfulness verified: after the three production pages are checked against the submitted build, record exactly \`VERIFIED_MATCH_BUILD: https://gta-free-stem.vercel.app/support/ | https://gta-free-stem.vercel.app/privacy/ | https://gta-free-stem.vercel.app/terms/\`.
- App Review contact verified: record exactly \`VERIFIED_APP_STORE_CONNECT_YYYY-MM-DD\` using today's verification date; do not commit the reviewer email or phone number.
- Copyright entered: use exactly \`ENTERED_APP_STORE_CONNECT_YYYY: Confirmed Rights Holder\`, replacing the year and holder with the public App Store value.
- Platform record decision: after verifying the selected Separate Mac record, use exactly \`VERIFIED_SEPARATE_MAC_RECORD: app_id=NUMERIC_APP_ID; sku=ACTUAL-SKU; bundle_id=com.rupayonhaldar.gtafreestem.maccatalyst\`.
- Primary language verified: use exactly \`VERIFIED_APP_STORE_CONNECT_YYYY-MM-DD: primary_language=LOCALE\`, for example \`primary_language=en-CA\`.
- Availability and DSA verified: after checking territories and trader status, record exactly \`VERIFIED_APP_STORE_CONNECT_YYYY-MM-DD\` using today's verification date.

## Notes

- Send tester feedback through TestFlight for this build; the in-app Support tab intentionally has no online form.
- A TestFlight upload is not an App Review submission.
- A prior in-place development install does not satisfy these rows. Reinstall the exact final published build without deleting the app, confirm the existing data container still opens, and then test the processed TestFlight build separately.
- The local Profile is on-device only; do not test or advertise password login, cloud recovery, or server account sync.
- Automated coverage does not replace paired-Watch QA, persistent-store migration from older installed schemas, or full end-to-end UI journey testing.
- If profile, location, feedback, submission, analytics, crash reporting, or telemetry behavior changes, redo App Privacy and reviewer notes before public submission.
