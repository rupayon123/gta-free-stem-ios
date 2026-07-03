# TestFlight Real-Device QA Signoff

Last updated: July 3, 2026

Use this document to record the real-device QA pass before App Review submission. Do not mark public release ready until every required row is `Pass` or a release owner explicitly accepts the risk.

After filling this out, run `bash docs/scripts/check-public-release-gates.sh`. It should fail while this document is still pending and pass only after required real-device and App Store Connect gates are recorded.

Allowed row statuses are `Pass`, `Fail`, `Pending`, and `Accepted Risk`; the final gate passes only when every required row is `Pass` or `Accepted Risk`. Every `Accepted Risk` row must include notes and must be summarized in `Accepted risks`.

## Build Under Test

These facts describe the current valid TestFlight upload with the refreshed 406-listing bundled snapshot.

- App: `GTA FREE STEM`
- Version/build: `1.0 (10)`
- Delivery UUID: `97c05d63-7f3d-45bc-941e-c10432694ca8`
- App Store Connect status: `VALID`
- TestFlight status: `BETA_INTERNAL_TESTING`
- Device family required: iPhone
- Optional second pass: iPad

## Tester And Device

- Fill every line before public-release signoff. Use `YYYY-MM-DD` for the date.
- Tester:
- Date:
- Device model:
- iOS/iPadOS version:
- Install source: TestFlight
- Network conditions tested:
- Accessibility settings tested:
- Languages tested:

## Suggested Real-Device Flow

Use this flow to fill the table below. Record actual observations in `Notes`; do not mark a row `Pass` from simulator-only evidence.

1. Fresh-install build `1.0 (10)` from TestFlight on an iPhone, launch once online, and confirm public browsing opens without account prompts.
2. Search `robotics Toronto`, then try a second multi-word query with a city or category from a visible result. Confirm results are relevant and sorting defaults to best match.
3. Apply city, region, age, language, category, volunteer hours, co-op/SHSM, mentorship, scholarships, equity focus, new finds, and distance filters one at a time, then reset them.
4. Switch between list and map mode after filters are applied. Confirm pins match the filtered result set and detail pages open from both modes where available.
5. Tap refresh repeatedly while online. Confirm loading state, data source label, result count, and any new-match messaging stay stable and do not duplicate listings.
6. Quit and reopen the app. Confirm the last query, mode, filters, and visible results restore.
7. After one successful online refresh, enable Airplane Mode, reopen the app, and confirm cached results appear. Then fresh-install or clear app data, launch without network, and confirm the bundled offline snapshot appears.
8. Deny location permission when prompted by nearby/distance behavior, then repeat with location allowed if available. Confirm the app explains fallback behavior and uses nearest sorting only when location context exists.
9. Switch app language to at least French, Spanish, one South Asian language, and one CJK language. Search translated content and an English fallback term in each language.
10. Switch to Arabic, Farsi/Persian, or Urdu and inspect browse, filters, details, settings, and support for right-to-left layout issues.
11. Enable Large Accessibility Text, Dark Mode, and VoiceOver. Confirm rows, filters, map/detail controls, account-limited actions, and support controls are understandable and do not overlap.
12. Open the marketing, support, and privacy URLs from App Store Connect or Safari on the device. Confirm they load the public pages.

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
| Support privacy | Support tab does not collect name, email, message, or missing-opportunity details in build `1.0 (10)`. | Pending | |
| Account-limited paths | Account-only actions clearly say the feature is unavailable in this build; Sign in with Apple is not exposed without backend token exchange. | Pending | |
| App Store URLs | Marketing, support, and privacy URLs open and show expected public pages. | Pending | |

## Release Owner Decision

- Write `None` for `Accepted risks` or `Must-fix blockers` only when none apply.
- `Submitted for App Review` may stay pending until the final App Store Connect submit click.
- Overall status: `Pending`
- Accepted risks:
- Must-fix blockers:
- App Store Connect build selected:
- Screenshots uploaded:
- Metadata/privacy/age rating entered:
- Submitted for App Review:

## Notes

- Send tester feedback through TestFlight, not in-app forms, for build `1.0 (10)`.
- Rotate or revoke the app-specific Apple password generated during setup after release work is finished.
- If backend account, feedback, submission, analytics, crash reporting, or telemetry behavior changes before release, redo App Privacy answers and rerun the release-readiness audit.
