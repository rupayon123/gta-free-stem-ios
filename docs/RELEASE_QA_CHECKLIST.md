# TestFlight Release QA Checklist

Use this checklist before each TestFlight upload so the release is repeatable and easy to review later.

## Build Readiness

- Regenerate the project with `xcodegen generate` if `project.yml` changed.
- Build the app on the current target simulator.
- Run the app test target from Xcode or with `xcodebuild test`.
- Confirm the bundled opportunity snapshot still decodes.
- Confirm no signing files, provisioning profiles, archives, or secrets are staged.

## Core Discovery Flow

- Launch signed out and confirm public browsing works.
- Search by keyword, city, age, category, pathway, and language.
- Open list view and map view from the same result set.
- Open a listing and verify title, date, location, cost, provider, and action link readability.
- Refresh the public feed and confirm the offline bundled snapshot fallback still appears when network access is unavailable.

## Location And Notifications

- Deny location permission and confirm nearby search explains the fallback.
- Allow location permission once and confirm nearby results update without continuous tracking copy.
- Toggle new-match notifications and confirm permission prompts are understandable.
- Confirm notification state does not block normal browsing.

## Account And Submission Paths

- Try saving while signed out and confirm the account prompt is clear.
- Open Sign in with Apple UI and confirm cancelling returns safely to the previous screen.
- Submit feedback or a missing opportunity through the available UI path, using test data only.
- Confirm no access tokens or private user data are written to `UserDefaults`.

## Accessibility And Localization

- Test Dynamic Type at a large size on the main list and detail screens.
- Test VoiceOver labels on search filters, map pins, save actions, and feedback controls.
- Switch light and dark mode.
- Check right-to-left layout for Arabic, Farsi/Persian, and Urdu resources.
- Confirm system permission copy is present for location and notifications.

## TestFlight Notes

- Update beta notes with the main flows testers should try.
- Include known limitations such as backend-only account features or unavailable source feeds.
- Add a support contact and privacy policy URL in App Store Connect.
- Keep the tester group small for the first build after major feed, auth, or map changes.
- Record the build number, test date, and any known blockers in the release notes.
