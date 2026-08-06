# Release Readiness

Last updated: August 6, 2026

## Candidate

- Version/build: \`1.0 (12)\`
- Compiled targets: iPhone, iPad, Mac Catalyst, Apple Watch companion. Because the current iOS binary enables iPhone and iPad and embeds the Watch app, \`iphone,ipad,watch\` is the minimum public release set. Mac remains an optional separate record decision.
- The bundled fallback is copied from the sibling website's verified-active public export. Run \`docs/scripts/sync-bundled-feed.sh\` immediately before release validation, publish that exact export, then run the release-readiness script; it rejects any deployed GitHub/live-feed ID drift before upload.
- App Review submission: not submitted.
- TestFlight upload: not uploaded; there is no processed TestFlight build or delivery UUID.
- Source publication: verified source commit \`42c138436ece43ecca120ff76edbf1c4f90b17ff\` was published through pull request #4, merged into \`origin/main\` at \`1350072af9181808006d089a90cf975f5de49901\`, and remains reachable from current \`origin/main\`.

## Completed Local Release Work

- iOS/iPad Release build includes a warm branded loader and no blank-white launch screen path.
- Dynamic public-feed retrieval, cache restore, bundled fallback, local search/filter engine, local saves, on-device Profile, and Settings deletion flow are implemented.
- Watch target has its own AppIcon and privacy manifest; both iOS and Watch declare local UserDefaults reason \`CA92.1\`. The iOS/iPadOS/Mac Catalyst manifest conservatively declares feed-provider Coarse Location and Other Diagnostic Data, while Watch declares no independent collection.
- Build number is 12 in project source and generated Xcode configuration.
- App Store metadata, review notes, privacy answers, public Privacy Policy, Terms of Use, screenshot plan, TestFlight guide, and real-device QA template are updated for the actual local-only Profile behavior. The public Support route exists, but it is not submission-ready until it exposes a real monitored email or telephone number.

## Verification Recorded August 6, 2026

- The published artifact source commit `42c138436ece43ecca120ff76edbf1c4f90b17ff` passed the fresh full iPad Simulator suite, `108/108` tests with zero failures. The result bundle is `build/DerivedData-final-tests-source-provenance-20260806/Logs/Test/Test-GTAFreeSTEM-2026.08.06_16-54-57--0400.xcresult`.
- Published source commit `42c138436ece43ecca120ff76edbf1c4f90b17ff` is reachable from live `origin/main`, and the scoped release inputs byte-match current main.
- A fresh normal iOS Release archive at `build/final-release-ios-20260806-r6-published-source.xcarchive` succeeded and embeds the Watch companion. Both bundles report `1.0 (12)` and embed the published source commit. Its 52/52 pre-export checks pass with exact main and Watch development provisioning identifiers. Its deterministic archive-tree SHA-256 is `443c03f13685caa34eb36b6f875d18bee8226476fd288187f22104ae42228dd5`.
- The unchanged safe no-upload App Store export at `build/final-release-ios-20260806-r6-export/GTAFreeSTEM.ipa` is Apple Distribution signed and passes 62/62 strict exported-IPA checks, including exact main/Watch App Store profiles, `get-task-allow=false`, unexpired signing material, source provenance, and archive-to-IPA UUID provenance. Its SHA-256 is `8cf97134ce8985f1a9ca62c6dd52cb1680e876ca7a56eafe6ee31cdd901081eb`. This proves a valid local distributable; it is not upload or TestFlight evidence.
- A fresh normal Mac Catalyst Release archive at `build/final-release-mac-20260806-r3-published-source.xcarchive` succeeded, embeds the published source commit, and passes all 36 pre-export archive-verifier checks. Its deterministic archive-tree SHA-256 is `450e335911c8babedeecfaa0d68841c95543c83a978f38d5eed85d92b641b5b6`. The correctly signed no-upload Mac App Store package is `build/final-release-mac-20260806-r3-export/GTAFreeSTEM.pkg`, SHA-256 `b9afd175d605ea9ba588702d92df71a31044714cf893ad9633cff126f1320f34`, and passes 48/48 strict package checks.
- The fresh Mac Release app was manually launched. Its loader completed a single handoff at 100%, search and listing-detail navigation worked, and the Release QA local Profile persisted across a relaunch.
- The website production build, typecheck, semantic-search QA, and dependency audit all passed. The live feed reports 125 unique active opportunities with healthy source and discovery status, and the latest 10 scheduled refresh runs succeeded.
- The website public export and iOS bundled fallback are byte-identical, with SHA-256 `3b78333b166ac6c2c7569ae2e4d795379cfa47a1708fec0ec50258295b2cda41` for 125 unique active opportunities.
- An earlier build `1.0 (12)` was installed in place and launched successfully on the connected iPhone 16 Pro without deleting its app container. That proves the earlier connected-device installation path only. The exact published-source candidate has not been installed because Xcode/CoreDevice report Kurihara unavailable and live USB inspection does not enumerate the phone, so current phone verification remains pending.
- Vercel production deployment `dpl_Mm6r3jVeiVqDN8t3TqPXbbgZLvnp` is live at `https://gta-free-stem.vercel.app`. Direct checks returned HTTP `200` for `/`, `/support/`, `/privacy/`, `/terms/`, and `/opportunities.json`. A maximum-coverage public-gate run using `iphone,ipad,watch,mac` passed strict artifact verification, 18-language coverage, privacy and platform configuration, and all public URL checks, then stopped at the missing monitored public support email or telephone number. It did not reach or establish the still-pending TestFlight and real-device signoff. No personal address was invented or published.
- Apple Developer Program team `FE33NM88XX` was verified active through June 10, 2027. No additional membership purchase is currently required.

## Verified Scope And Limitations

- The Profile is on-device only. There is no server account, password, email login, cloud recovery, or cross-device account sync.
- The loader gates entry on a usable local, bundled, or live snapshot. A live feed refresh can continue after the main interface appears.
- Background refresh is scheduled by Apple and is not guaranteed to run at a specific time.
- The Watch app is a companion for a capped set of saved opportunities and archive status; it is not a standalone full-feed search app.
- Map pins are display-only. Listing actions live in the detail view and external provider or directions links.
- Automated tests do not replace a paired-Watch test, a persistent-store migration test from every older installed schema, or full end-to-end UI journey automation. Those remain explicit real-device QA work.

## Still Required Before Public App Review

1. Reconnect and unlock the iPhone, install the exact final published build in place, then verify its version, launch, and preservation of the existing app data container.
2. Choose and publish a dedicated monitored public support email or telephone number, redeploy, and verify its direct contact link on the public Support page; keep GitHub Issues enabled and monitored; and confirm the pages do not promise unsupported online accounts, submissions, or feedback. The Support, Privacy, and Terms routes themselves are already deployed and return HTTP `200`.
3. Record \`iphone,ipad,watch\` as the minimum public platform set for the current binary and decide whether the optional separate Mac product is also included. If \`mac\` is selected, retain the current \`.maccatalyst\` product and create a distinct Mac app record, or deliberately change to the shared iOS bundle ID before creating a universal iOS/macOS record.
4. Upload the unchanged verified App Store distribution IPA and, if Mac is selected, the unchanged verified Mac package; wait for App Store Connect processing and record the actual delivery UUIDs. Local archive, IPA, and package evidence is not processed TestFlight evidence.
5. Test the processed TestFlight build and capture or visually review fresh screenshots on every selected real platform.
6. Complete App Store Connect platform settings, metadata, App Privacy, age rating, availability, export compliance, copyright, primary language, DSA trader status, and the private App Review contact fields.
7. Verify the live Support, Privacy, and Terms pages accurately describe the submitted build, leave the App Store Connect custom-EULA field blank so Apple's Standard EULA applies, then rerun the public-release gate with the exact recorded artifacts and selected platforms. Its latest maximum-coverage run advanced through the artifact, localization, privacy, platform-configuration, and public-URL checks before stopping at the missing monitored direct support contact; the later TestFlight and real-device signoff checks remain pending.
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
