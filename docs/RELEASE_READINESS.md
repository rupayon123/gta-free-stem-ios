# Release Readiness

Last updated: August 6, 2026

## Candidate

- Version/build: \`1.0 (12)\`
- Compiled targets: iPhone, iPad, Mac Catalyst, Apple Watch companion. Because the current iOS binary enables iPhone and iPad and embeds the Watch app, \`iphone,ipad,watch\` is the minimum public release set. Mac remains an optional separate record decision.
- The bundled fallback is copied from the sibling website's verified-active public export. Run \`docs/scripts/sync-bundled-feed.sh\` immediately before release validation, publish that exact export, then run the release-readiness script; it rejects any deployed GitHub/live-feed ID drift before upload.
- App Review submission: not submitted.
- TestFlight upload: pending the signed archive/export step.

## Completed Local Release Work

- iOS/iPad Release build includes a warm branded loader and no blank-white launch screen path.
- Dynamic public-feed retrieval, cache restore, bundled fallback, local search/filter engine, local saves, on-device Profile, and Settings deletion flow are implemented.
- Watch target has its own AppIcon and privacy manifest; both iOS and Watch declare local UserDefaults reason \`CA92.1\`. The iOS/iPadOS/Mac Catalyst manifest conservatively declares feed-provider Coarse Location and Other Diagnostic Data, while Watch declares no independent collection.
- Build number is 12 in project source and generated Xcode configuration.
- App Store metadata, review notes, privacy answers, public Privacy Policy, Terms of Use, no-cost support route, screenshot plan, TestFlight guide, and real-device QA template are updated for the actual local-only Profile behavior.

## Verification Recorded August 6, 2026

- `105/105` Mac Catalyst tests passed with no failures; the fresh run is recorded in `build/full-maccatalyst-final-green.log`.
- A fresh unsigned iPhone Release build passed (`BUILD SUCCEEDED`) and embeds the Watch companion. Both bundles report `1.0 (12)`.
- The website production build, typecheck, semantic-search QA, and dependency audit all passed. QA validated 18 languages and 125 public active results after irrelevant library listings and misleading source tags were removed.
- The website public export and iOS bundled fallback are byte-identical, with SHA-256 `3b78333b166ac6c2c7569ae2e4d795379cfa47a1708fec0ec50258295b2cda41` for 125 active opportunities.
- A signed Development build was installed in place on the connected iPhone 16 Pro with `docs/scripts/install-connected-device.sh` and launched successfully as `com.rupayonhaldar.gtafreestem` version `1.0 (12)`. The post-install process query reported the app alive from its new application bundle path. This proves the connected-device build, install, launch, and existing SwiftData-container opening path; it is not a TestFlight signoff.
- Vercel production deployment `dpl_Mm6r3jVeiVqDN8t3TqPXbbgZLvnp` is live at `https://gta-free-stem.vercel.app`. Direct checks returned HTTP `200` for `/`, `/support/`, `/privacy/`, `/terms/`, and `/opportunities.json`. The Support page intentionally still reports public release blocked until the owner explicitly supplies a dedicated monitored `NEXT_PUBLIC_SUPPORT_EMAIL`; no personal address was invented or published.

## Still Required Before Public App Review

1. Upload and wait for TestFlight processing of build 12.
2. Record \`iphone,ipad,watch\` as the minimum public platform set for the current binary and decide whether the optional separate Mac product is also included.
3. Test the update and capture/visually review fresh screenshots on every selected platform.
4. Choose and publish a dedicated monitored public support email or telephone number, redeploy, and verify its direct contact link on the public Support page; keep GitHub Issues enabled and monitored; and confirm the pages do not promise unsupported online accounts, submissions, or feedback. The Support, Privacy, and Terms routes themselves are already deployed and return HTTP `200`.
5. If \`mac\` is selected, choose the Mac strategy: retain the current separate \`.maccatalyst\` product and create a distinct Mac app record, or deliberately change to the shared iOS bundle ID before creating a universal iOS/macOS record.
6. Complete App Store Connect platform settings, metadata, App Privacy, age rating, availability, export compliance, copyright, primary language, DSA trader status, and the private App Review contact fields.
7. Verify the live Support, Privacy, and Terms pages accurately describe the submitted build, leave the App Store Connect custom-EULA field blank so Apple's Standard EULA applies, then run \`IOS_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-1.0-12.xcarchive PUBLIC_RELEASE_PLATFORMS=iphone,ipad,watch bash docs/scripts/check-public-release-gates.sh\`; if the separate Mac product is included, also set \`MAC_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-Mac-1.0-12.xcarchive\` and add \`,mac\`.
8. Explicitly choose whether to submit to App Review.

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
