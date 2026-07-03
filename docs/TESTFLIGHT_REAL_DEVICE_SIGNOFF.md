# TestFlight Real-Device QA Signoff

Last updated: July 3, 2026

Use this document to record the real-device QA pass before App Review submission. Do not mark public release ready until every required row is `Pass` or a release owner explicitly accepts the risk.

## Build Under Test

- App: `GTA FREE STEM`
- Version/build: `1.0 (9)`
- Delivery UUID: `222e71fe-92f1-4da3-bad7-205b9eb7a3b3`
- App Store Connect status: `VALID`
- TestFlight status: `BETA_INTERNAL_TESTING`
- Device family required: iPhone
- Optional second pass: iPad

## Tester And Device

- Tester:
- Date:
- Device model:
- iOS/iPadOS version:
- Install source: TestFlight
- Network conditions tested:
- Accessibility settings tested:
- Languages tested:

## Required Passes

| Area | Required evidence | Status | Notes |
| --- | --- | --- | --- |
| Install and launch | Fresh TestFlight install opens without crash and shows public browsing. | Pending | |
| Search keywords | Multi-word search such as `robotics Toronto` returns relevant results. | Pending | |
| Search translated fields | Non-English app language can search translated listing content; English fallback terms still work. | Pending | |
| Filters | City, region, age, language, category, volunteer hours, co-op/SHSM, mentorship, scholarships, equity focus, new finds, and distance filters apply and reset correctly. | Pending | |
| Sorting | Best match, soonest, and nearest sorting behave as expected; nearest is used only after location/coordinate context. | Pending | |
| Map/list consistency | Map pins are a subset of the filtered list results and visible labels are understandable. | Pending | |
| Details | Listing detail pages show readable title, provider, date/deadline, location, cost, badges, and source/action links. | Pending | |
| Manual refresh | Repeated refreshes do not duplicate results, freeze, or show conflicting loading/error states. | Pending | |
| Cache fallback | After one successful refresh, offline reopen shows cached results. | Pending | |
| Bundled snapshot fallback | Clean install without network shows the bundled offline opportunity snapshot. | Pending | |
| State restore | Query, mode, filters, and latest visible results restore after app quit/reopen. | Pending | |
| New-match messaging | Repeated/background refresh does not spam duplicate new-match counts for already-seen listings. | Pending | |
| Location denied | Nearby search after denied location permission explains the city/filter fallback clearly. | Pending | |
| Location allowed | Nearby search updates distance/nearest behavior without continuous-tracking copy. | Pending | |
| Notifications | Notification permission copy is understandable and notification state does not block browsing. | Pending | |
| Language switching | UI controls, empty states, errors, detail pages, settings, support, and opportunity content switch language where payloads exist. | Pending | |
| RTL layout | Arabic, Farsi/Persian, and Urdu layout direction works on browse, filters, details, settings, and support. | Pending | |
| Dynamic Type | Large text remains readable on list, filters, detail, support, and settings without important overlap. | Pending | |
| VoiceOver rows | Opportunity rows read as one useful label with title, category, organization, age range, city, and relevant badges. | Pending | |
| VoiceOver map/details/forms | Map, detail facts, filter controls, save/account-limited actions, and support controls have useful labels/hints. | Pending | |
| Dark mode | Badges, cards, buttons, map area, empty states, and errors remain readable. | Pending | |
| Support privacy | Support tab does not collect name, email, message, or missing-opportunity details in build `1.0 (9)`. | Pending | |
| Account-limited paths | Account-only actions clearly say the feature is unavailable in this build; Sign in with Apple is not exposed without backend token exchange. | Pending | |
| App Store URLs | Marketing, support, and privacy URLs open and show expected public pages. | Pending | |

## Release Owner Decision

- Overall status: `Pending`
- Accepted risks:
- Must-fix blockers:
- App Store Connect build selected:
- Screenshots uploaded:
- Metadata/privacy/age rating entered:
- Submitted for App Review:

## Notes

- Send tester feedback through TestFlight, not in-app forms, for build `1.0 (9)`.
- Rotate or revoke the app-specific Apple password generated during setup after release work is finished.
- If backend account, feedback, submission, analytics, crash reporting, or telemetry behavior changes before release, redo App Privacy answers and rerun the release-readiness audit.
