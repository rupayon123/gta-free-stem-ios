# TestFlight Real-Device QA Signoff

Last updated: August 6, 2026

Record observed real-device evidence for build 1.0 (12) here. The public release gate only passes when each required row is \`Pass\` or a release owner has explicitly recorded \`Accepted Risk\` with notes. Simulator-only evidence never counts as a real-device pass.

## Build Under Test

- App: \`GTA FREE STEM\`
- Version/build: \`1.0 (12)\`
- iOS Delivery UUID: \`Pending upload\`
- Mac Delivery UUID: \`Pending upload\`
- App Store Connect status: \`Not uploaded\`
- TestFlight status: \`Not uploaded\`
- App Review status: \`Not submitted\`
- Public distribution platforms: \`Pending\`

## Verified Artifact Binding

- Published commit: \`Pending\`
- Artifact verification date: \`Pending\`
- iOS archive path: \`Pending\`
- iOS archive SHA-256: \`Pending\`
- iOS IPA path: \`Pending\`
- iOS IPA SHA-256: \`Pending\`
- Mac archive path: \`Pending\`
- Mac archive SHA-256: \`Pending\`
- Mac package path: \`Pending\`
- Mac package SHA-256: \`Pending\`

The archive hashes are deterministic tree SHA-256 values calculated by the public-release gate; the IPA and package hashes are ordinary file SHA-256 values. Record canonical absolute paths. The published commit must be the full source commit embedded as \`GTAReleaseSourceCommit\` in every signed archive and exported package. It must be reachable from live \`origin/main\`, and its app, Watch, Xcode project, and \`project.yml\` inputs must byte-match both live main and the local verification inputs. Later docs-only signoff commits may advance main without changing this recorded source commit. The verification date must be the date the gate reruns the strict verifiers on those exact bytes.

Replace the pending upload fields only after App Store Connect reports actual values.

Current local archive/export evidence is not TestFlight evidence:

- iOS archive \`build/final-release-ios-20260806-r4-exact-dev.xcarchive\` is a valid development-signed export source and passes 49/49 checks with exact main and Watch development provisioning identifiers.
- Exported IPA \`build/final-release-ios-20260806-r4-export/GTAFreeSTEM.ipa\` is a safe no-upload Apple Distribution export and passes 53/53 strict checks with exact main/Watch App Store profiles and matching archive UUIDs. SHA-256: \`97abd09803140cce746767acfaab157fc2f5aa42dd61cf189de58c1195319b68\`.
- Mac Catalyst archive \`build/final-release-mac-20260806/GTAFreeSTEM-Mac.xcarchive\` is a valid development-signed export source and passes 35/35 pre-export checks. The correctly signed no-upload package is \`build/final-release-mac-20260806-export/GTAFreeSTEM.pkg\`, SHA-256 \`47a448ec7dc88c531c7d3e78f5b49ebcf4a9bddbf9542eb06c1fe4f0c55a8515\`.
- The exact current source passed 108/108 tests in the full iPad Simulator suite recorded at \`build/final-full-ipad-tests-20260806.log\`. A fresh Mac Release launch also completed a single loader handoff at 100%; search, details, and local Profile persistence across relaunch were manually verified.
- Development signing on these archives is not itself a failure. Xcode re-signs the packaged app for distribution during App Store export.
- The current signing-repair source tree has not yet been published, and the exact final tree has not been installed on the iPhone. Xcode reports Kurihara disconnected and CoreDevice reports it unavailable. Do not record an install or launch pass until the published build is installed and observed.
- No build has been uploaded or processed in TestFlight, so all TestFlight and real-device rows remain pending.

Before running the final public-release gate, record the exact platforms enabled by the submitted binary and pass the same canonical, comma-separated set through \`PUBLIC_RELEASE_PLATFORMS\`. There is intentionally no default. The current binary enables iPhone and iPad and embeds the Watch companion, so its minimum set is \`iphone,ipad,watch\`; omitting iPad or Watch requires changing the binary first. Add \`,mac\` only if the optional separate Mac product is included. The gate requires platform-specific evidence for every selected platform.

## Tester And Device

- Tester:
- Date:
- Install source: TestFlight
- Network conditions tested:
- Accessibility settings tested:
- Languages tested:

## Required Passes

| Area | Required evidence | Status | Notes |
| --- | --- | --- | --- |
| Install and launch | Fresh TestFlight install opens without crash and reaches public browsing. | Pending | |
| Warm launch experience | The branded loader only gates a usable local, bundled, or live snapshot; progress moves forward, reaches 100% once before usable browsing, never restarts, and never leaves a blank white screen. Confirm that a live refresh can continue after handoff without blocking browsing. | Pending | |
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

For every value in \`Public distribution platforms\`, record the actual device, operating-system version, and observed result below. Leave unselected platforms pending; the gate ignores their rows. A simulator never substitutes for a selected platform's real-device evidence.

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
- App Store Connect build selected:
- Archive provenance verified:
- Screenshots uploaded:
- Metadata/privacy/age rating entered:
- Support contact verified:
- Production legal/support truthfulness verified:
- App Review contact verified:
- Copyright entered:
- Platform record decision:
- Primary language verified:
- Availability and DSA verified:
- Submitted for App Review:

Expected evidence once the portal is completed:

- App Store Connect build selected: \`1.0 (12)\`
- Archive provenance verified: complete every structured field in \`Verified Artifact Binding\` for build \`1.0 (12)\`, plus the separate iOS and Mac Apple delivery UUIDs when those products are selected. A development-signed archive may be the valid pre-export source; each exported distributable must carry App Store distribution signing and match its archive. Use those exact paths in the public-release gate, and do not select unsigned, historical, or separately re-exported artifacts.
- Screenshots uploaded: platform-specific evidence only for the values selected in \`Public distribution platforms\`.
- Metadata/privacy/age rating entered: includes metadata, App Privacy, age rating, Made for Kids = No, export compliance, and review notes
- Support contact verified: include the verified production Support URL, confirmed GitHub Issues route, and confirmation of a monitored public support email or telephone number; do not copy the private App Review contact here.
- Production legal/support truthfulness verified: record a verified production review with distinct HTTPS support, privacy, and Terms URLs that match the submitted build, plus confirmation that GitHub Issues and the direct public support contact are enabled and watched. Do not copy the actual contact value into this file.
- App Review contact verified: \`Verified in App Store Connect on YYYY-MM-DD\`; do not commit the reviewer email or phone number here.
- Copyright entered: record the exact public App Store value, with the confirmed legal-rights holder and year.
- Platform record decision: required only when \`mac\` is selected. Record either a verified Universal iOS/macOS decision with the shared bundle ID, or a verified Separate Mac app record with its Mac App ID, SKU, and \`.maccatalyst\` bundle ID.
- Primary language verified: record only \`Verified in App Store Connect on YYYY-MM-DD\`; ensure the product-page fallback language matches the selected language.
- Availability and DSA verified: record only \`Verified in App Store Connect on YYYY-MM-DD\`; this includes selected territories and the trader-status self-assessment.

## Notes

- Send tester feedback through TestFlight for this build; the in-app Support tab intentionally has no online form.
- A TestFlight upload is not an App Review submission.
- A prior in-place development install does not satisfy these rows. Reinstall the exact final published build without deleting the app, confirm the existing data container still opens, and then test the processed TestFlight build separately.
- The local Profile is on-device only; do not test or advertise password login, cloud recovery, or server account sync.
- Automated coverage does not replace paired-Watch QA, persistent-store migration from older installed schemas, or full end-to-end UI journey testing.
- If profile, location, feedback, submission, analytics, crash reporting, or telemetry behavior changes, redo App Privacy and reviewer notes before public submission.
