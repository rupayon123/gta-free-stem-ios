# TestFlight Release QA Checklist

Use this checklist before each TestFlight upload so the release is repeatable and easy to review later.

Record the real-device pass in `docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md` before App Review submission.

## Build Readiness

- Run `STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh` and save the opportunity count, live-feed translation coverage, and UI string coverage in the release notes.
- Regenerate the project with `xcodegen generate` if `project.yml` changed.
- Increment `CURRENT_PROJECT_VERSION` once, then confirm `project.yml`, `GTAFreeSTEM.xcodeproj/project.pbxproj`, and the archive metadata agree.
- Build the app on the current target simulator.
- Run the app test target from Xcode or with `xcodebuild test`.
- Confirm the bundled opportunity snapshot still decodes.
- Run `bash docs/scripts/smoke-release-simulator.sh` to clean-install the Release build on a simulator, verify the bundled opportunity count, and capture nonblank launch screenshots for the home, opportunities, high-school, and support entry screens.
- Use `docs/AppStoreConnectExportOptions.plist` for command-line App Store Connect uploads so Xcode does not auto-change the build number.
- Confirm no signing files, provisioning profiles, archives, or secrets are staged.

## Core Discovery Flow

- Launch signed out and confirm public browsing works.
- Search by keyword across multiple fields:
  - `robotics Toronto` should find Toronto robotics listings.
  - A provider name should match the organization field.
  - A category word such as `scholarship`, `mentorship`, or `volunteer` should match category/tags.
- Search in a non-English app language and confirm translated listing text is searchable while English terms still work as fallback.
- Apply filters one at a time for city, region, age, language, category, volunteer hours, co-op/SHSM, mentorship, scholarships, equity focus, new finds, and distance.
- Switch sorting between best match, soonest, and nearest; nearest should only be available/useful after a nearby search or saved coordinate.
- Open list view and map view from the same filtered result set, then confirm map pins are a subset of the visible list results.
- Open a listing and verify title, date, location, cost, provider, and action link readability.
- Refresh the public feed repeatedly and confirm the app does not duplicate results, freeze, or show conflicting loading/error states.
- Turn off network after one successful refresh and confirm cached results appear; on a clean install without cache, confirm the bundled offline snapshot appears.
- Quit and reopen the app after a search and confirm query, mode, filters, and the latest visible results restore.

## Location And Notifications

- Deny location permission and confirm nearby search explains the fallback.
- Allow location permission once and confirm nearby results update without continuous tracking copy.
- Toggle new-match notifications and confirm permission prompts are understandable.
- Confirm notification state does not block normal browsing.
- After a background or repeated refresh, confirm new-match messaging does not spam duplicate counts for already-seen listings.

## Account And Submission Paths

- Try account-only actions and confirm the unavailable-in-this-build message is clear.
- Confirm Sign in with Apple is not shown unless the iOS app exchanges Apple credentials for a backend API token.
- Confirm the Support tab does not show name, email, message, or missing-opportunity input fields while the online backend is unavailable for this build.
- Send tester feedback through TestFlight rather than in-app forms unless a future build connects an online backend and updates App Privacy answers.
- Confirm no access tokens or private user data are written to `UserDefaults`.

## Accessibility And Localization

- Test Dynamic Type at a large size on the main list and detail screens.
- Test VoiceOver labels on opportunity rows, search filters, map pins, detail facts, save actions, and support/account-limited controls.
- Confirm each opportunity row reads as one useful summary: title, category, organization, age range, city, and relevant badges.
- Confirm the map announces the localized visible-result count before map interaction.
- Switch light and dark mode and visually inspect contrast on badges, buttons, maps, cards, empty states, and error text.
- Check right-to-left layout for Arabic, Farsi/Persian, and Urdu resources, including filters, detail pages, settings, and support.
- Spot-check at least French, Spanish, Chinese, Punjabi, Urdu, Tamil, Tagalog/Filipino, Arabic, Hindi, Portuguese, Gujarati, Bengali, Japanese, Korean, and Hungarian for visible untranslated UI controls.
- Confirm opportunity titles, descriptions, summaries, categories, and costs switch language where the feed has payloads, with readable English fallback where source-specific fields stay English.
- Confirm system permission copy is present for location and notifications.

## Public Release Must Pass

- TestFlight build `1.0 (9)` or newer is processed and selectable in App Store Connect.
- App Store metadata, support URL, marketing URL, privacy URL, privacy answers, age rating, and screenshots are entered and reviewed.
- Search/hunt, refresh, cache/offline fallback, multilingual switching, RTL layout, Dynamic Type, VoiceOver, and support/account-limited flows pass on at least one real iPhone TestFlight install.
- No secrets, provisioning profiles, archives, derived-data products, or local screenshots are staged for commit.
- The generated app-specific Apple password used during setup has been revoked or rotated after release work is finished.

## TestFlight Notes

- Update beta notes with the main flows testers should try.
- Include known limitations such as backend-only account features or unavailable source feeds.
- Add a support contact and privacy policy URL in App Store Connect.
- Generate and visually review iPhone 6.9-inch and iPad 13-inch screenshots with `bash docs/scripts/capture-app-store-screenshots.sh` before public App Store submission.
- After processing, confirm App Store Connect shows the same version/build as the repo.
- Keep the tester group small for the first build after major feed, auth, or map changes.
- Record the build number, test date, and any known blockers in the release notes.
