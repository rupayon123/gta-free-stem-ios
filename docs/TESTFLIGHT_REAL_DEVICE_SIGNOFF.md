# TestFlight Real-Device QA Signoff

Last updated: August 6, 2026

Record observed real-device evidence for build 1.0 (12) here. The public release gate only passes when each required row is \`Pass\` or a release owner has explicitly recorded \`Accepted Risk\` with notes. Simulator-only evidence never counts as a real-device pass.

## Build Under Test

- App: \`GTA FREE STEM\`
- Version/build: \`1.0 (12)\`
- Delivery UUID: \`Pending upload\`
- App Store Connect status: \`Not uploaded\`
- TestFlight status: \`Not uploaded\`
- App Review status: \`Not submitted\`
- Public distribution platforms: \`Pending\`

Replace the pending upload fields only after App Store Connect reports actual values.

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
| Warm launch experience | The branded loading experience feels intentional; progress only moves forward, reaches 100% immediately before usable browsing appears, never restarts, and never leaves a blank white screen. | Pending | |
| Live feed | Online launch shows a current feed and a coherent data-source state. | Pending | |
| Search keywords | Multi-word search such as \`robotics Toronto\` returns relevant results. | Pending | |
| Search translations | Non-English listing content is searchable while English fallback terms still work. | Pending | |
| Filters and sorting | City, region, age, language, category, high-school, volunteer, co-op, mentorship, scholarship, equity, new-find, distance, and sorting controls apply and reset correctly. | Pending | |
| Map/list consistency | Map pins and list results agree for the current filtered hunt. | Pending | |
| Details and external links | Listing details are readable and provider/directions links open correctly. | Pending | |
| Local saves | Saving and removing an opportunity works without a network account. | Pending | |
| Local profile deletion | Create a local Profile, then delete it in Settings and confirm saved opportunities and hunt history clear. | Pending | |
| Manual refresh | Repeated refreshes do not duplicate results, freeze, or show conflicting states. | Pending | |
| Cache fallback | After a successful refresh, offline reopening shows the cached feed. | Pending | |
| Bundled fallback | A clean offline install opens with the bundled snapshot rather than failing. | Pending | |
| State restore | Query, mode, filters, and visible results restore after quit/reopen. | Pending | |
| Location | Denied and allowed nearby search cases are clear, local-only, and never block browsing. | Pending | |
| Notifications | Declining and allowing the optional local new-opportunity alert are both understandable, do not block browsing, and do not send data or register for remote push. | Pending | |
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
| Apple Watch | Paired Watch companion loads compact live/cache data and remains readable. | | | Pending | |
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
- Archive provenance verified: record the exact absolute path and verification date for the signed build \`1.0 (12)\` archive that passed the platform verifier, plus the Apple delivery UUID produced when that same unchanged archive was uploaded. Use that same archive path in the final public-release gate; do not select the local unsigned build-12 archive or the historical build-4 archive.
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
- A test-flight upload is not an App Review submission.
- If profile, location, feedback, submission, analytics, crash reporting, or telemetry behavior changes, redo App Privacy and reviewer notes before public submission.
