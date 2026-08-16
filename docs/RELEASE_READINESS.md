# Release Readiness

Last updated: August 6, 2026

## Candidate

- Version/build: \`1.0 (12)\`
- Public release scope: iPhone, iPad, Apple Watch companion, and Mac Catalyst (\`iphone,ipad,watch,mac\`). The Watch companion is embedded in the iOS upload. Mac ships as the selected separate Mac App Store product using \`com.rupayonhaldar.gtafreestem.maccatalyst\`; creation and verification of that portal record, Mac App ID, SKU, processed build, and delivery UUID remain pending.
- The bundled fallback is copied from the sibling website's verified-active public export. Run \`docs/scripts/sync-bundled-feed.sh\` immediately before release validation, publish that exact export, then run the release-readiness script; it rejects any deployed GitHub/live-feed ID drift before upload.
- App Review submission: not submitted.
- TestFlight upload: not uploaded; there is no processed TestFlight build or delivery UUID.
- Source publication: the prior verified source commit \`42c138436ece43ecca120ff76edbf1c4f90b17ff\` remains historical evidence, but current app and Watch changes supersede every archive/export bound to it. A replacement source commit and artifacts are pending.

## Completed Local Release Work

- iOS/iPad Release build includes a warm branded loader and no blank-white launch screen path.
- Dynamic public-feed retrieval, cache restore, bundled fallback, local search/filter engine, local saves, on-device Profile, and Settings deletion flow are implemented.
- Watch target has its own AppIcon and privacy manifest; both iOS and Watch declare local UserDefaults reason \`CA92.1\`. The iOS/iPadOS/Mac Catalyst manifest conservatively declares feed-provider Coarse Location and Other Diagnostic Data, while Watch declares no independent collection.
- Build number is 12 in project source and generated Xcode configuration.
- App Store metadata, review notes, privacy answers, public Privacy Policy, Terms of Use, screenshot plan, TestFlight guide, and real-device QA template are updated for the actual local-only Profile behavior. The public Support route exists, but it is not submission-ready until it exposes a real monitored email or telephone number.

## Verification Recorded August 6, 2026

- Superseded evidence: source commit `42c138436ece43ecca120ff76edbf1c4f90b17ff` passed `108/108` tests in `build/DerivedData-final-tests-source-provenance-20260806/Logs/Test/Test-GTAFreeSTEM-2026.08.06_16-54-57--0400.xcresult`. Current source changes invalidate that result as final-candidate evidence.
- Superseded evidence: `build/final-release-ios-20260806-r6-published-source.xcarchive` and `build/final-release-ios-20260806-r6-export/GTAFreeSTEM.ipa` remain bound to the prior commit. Their recorded hashes and 52/52 and 62/62 verifier results are historical only; do not upload them.
- Superseded evidence: `build/final-release-mac-20260806-r3-published-source.xcarchive` and `build/final-release-mac-20260806-r3-export/GTAFreeSTEM.pkg` remain bound to the prior commit. Their recorded hashes and 36/36 and 48/48 verifier results are historical only; do not upload them.
- The fresh Mac Release app was manually launched. Its loader completed a single handoff at 100%, search and listing-detail navigation worked, and the Release QA local Profile persisted across a relaunch.
- The website production build, typecheck, semantic-search QA, and dependency audit all passed. The live feed reports 125 unique active opportunities with healthy source and discovery status, and the latest 10 scheduled refresh runs succeeded.
- The website public export and iOS bundled fallback are byte-identical, with SHA-256 `3b78333b166ac6c2c7569ae2e4d795379cfa47a1708fec0ec50258295b2cda41` for 125 unique active opportunities.
- An earlier build `1.0 (12)` was installed in place and launched successfully on the connected iPhone 16 Pro without deleting its app container. That proves the earlier connected-device installation path only. The exact published-source candidate has not been installed because Xcode/CoreDevice report Kurihara unavailable and live USB inspection does not enumerate the phone, so current phone verification remains pending.
- Vercel production deployment `dpl_Mm6r3jVeiVqDN8t3TqPXbbgZLvnp` is live at `https://gta-free-stem.vercel.app`. Direct checks returned HTTP `200` for `/`, `/support/`, `/privacy/`, `/terms/`, and `/opportunities.json`. The prior maximum-coverage public-gate run is historical; the current gate must remain blocked until replacement artifacts are rebound and a monitored public support email or telephone number is published.
- The canonical screenshot package is `build/app-store-screenshots/final/` and contains 13 platform JPEGs: four iPhone, four iPad, four Mac, and one Watch image. Every current file has the required dimensions and opacity, and the complete August 6, 2026 local set passed independent full-size visual inspection. It is not release-signoff evidence: the Watch image predates the final Watch source edit and no clean-source `CAPTURE_RECEIPT.json` exists. A full exact-build recapture, receipt generation, and repeated 13-file review remain pending.
- Apple Developer Program team `FE33NM88XX` was verified active through June 10, 2027. No additional membership purchase is currently required.

## Verified Scope And Limitations

- The Profile is on-device only. There is no server account, password, email login, cloud recovery, or cross-device account sync.
- The loader completes a bounded preparation checkpoint, using a valid cache or bundled snapshot when available. If neither local source is usable, it still hands off without trapping the user; the interactive app shows its honest loading or error state while the live refresh continues.
- Background refresh is scheduled by Apple and is not guaranteed to run at a specific time.
- The Watch app is a companion for a capped set of saved opportunities and archive status; it is not a standalone full-feed search app.
- Map pins are display-only. Listing actions live in the detail view and external provider or directions links.
- Automated tests do not replace a paired-Watch test, a persistent-store migration test from every older installed schema, or full end-to-end UI journey automation. Those remain explicit real-device QA work.

## Still Required Before Public App Review

1. Reconnect and unlock the iPhone, install the exact final published build in place, then verify its version, launch, and preservation of the existing app data container.
2. Choose and publish a dedicated monitored public support email or telephone number, redeploy, and verify its direct contact link on the public Support page; keep GitHub Issues enabled and monitored; and confirm the pages do not promise unsupported online accounts, submissions, or feedback. The Support, Privacy, and Terms routes themselves are already deployed and return HTTP `200`.
3. Create and verify the selected separate Mac App Store record for \`com.rupayonhaldar.gtafreestem.maccatalyst\`, including its Mac App ID and SKU. Do not change to the universal-record bundle ID without rebuilding, re-signing, and reverifying the Mac candidate.
4. From the clean published source, recapture all 13 canonical screenshots, generate `CAPTURE_RECEIPT.json`, repeat the complete full-size review, bind the receipt and image hashes in `FINAL_VISUAL_QA.md`, and record that manifest's hash before upload. Any changed screenshot requires a new receipt and complete review.
5. Commit the current source, rebuild/re-sign/reverify replacement iOS/Watch and Mac artifacts, update every binding field, then upload only those replacements after explicit authorization. Wait for each separate App Store Connect product to process and independently record its delivery UUID, App Store Connect status, TestFlight status, and selected build.
6. Test the processed builds on iPhone, iPad, paired Apple Watch, and Mac.
7. Complete App Store Connect platform settings, metadata, App Privacy, age rating, availability, export compliance, copyright, primary language, DSA trader status, and the private App Review contact fields.
8. Verify the live Support, Privacy, and Terms pages accurately describe the submitted build, leave the App Store Connect custom-EULA field blank so Apple's Standard EULA applies, then rerun the public-release gate with `PUBLIC_RELEASE_PLATFORMS=iphone,ipad,watch,mac` and the exact recorded iOS and Mac artifacts. Its latest run advanced through the artifact, localization, privacy, platform-configuration, and public-URL checks before stopping at the missing monitored direct support contact; screenshot manifest binding and upload, TestFlight processing, portal evidence, and real-device signoff remain pending.
9. Explicitly choose whether to submit to App Review.

## Verification Commands

\`\`\`bash
CHECK_APP_STORE_SCREENSHOTS=0 STRICT_TRANSLATION_CHECK=1 \
  bash docs/scripts/check-release-readiness.sh

xcodebuild test \
  -project GTAFreeSTEM.xcodeproj \
  -scheme GTAFreeSTEM \
  -destination 'platform=iOS Simulator,name=iPhone 17'

bash docs/scripts/smoke-release-simulator.sh
\`\`\`

Use \`docs/PUBLIC_RELEASE_RUNBOOK.md\` for the actual archive/upload process. Do not treat a simulator build or local archive as evidence that App Store Connect accepted a build.
