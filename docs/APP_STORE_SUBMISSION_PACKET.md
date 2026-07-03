# App Store Connect Submission Packet

Last updated: July 3, 2026

Use this packet when filling App Store Connect for the first public release. It is built from the current repo evidence and should be rechecked if the backend, account features, feedback forms, submission forms, analytics, or data collection change.

Do not submit App Review, upload screenshots, change live metadata, invite testers, or send external beta review without explicit release-time confirmation.

## Build To Select

This build is the current valid upload in App Store Connect. The repo now contains the refreshed 406-listing bundled offline snapshot; if that snapshot must ship in the submitted binary, upload a replacement TestFlight build and update this packet before selecting the build for App Review.

- App: `GTA FREE STEM`
- Apple app ID: `6779714459`
- Bundle ID: `com.rupayonhaldar.gtafreestem`
- Team: `FE33NM88XX`
- Version: `1.0`
- Build: `9`
- Delivery UUID: `222e71fe-92f1-4da3-bad7-205b9eb7a3b3`
- App Store Connect status: `VALID`
- TestFlight status: `BETA_INTERNAL_TESTING`
- Audience: `APP_STORE_ELIGIBLE`
- Encryption: `usesNonExemptEncryption = false`
- Device families: iPhone and iPad
- Live feed coverage: 406/406 translated opportunities
- Bundled snapshot in current repo: 406/406 translated opportunities

## Product Page Fields

- Name: `GTA FREE STEM`
- Subtitle: `Youth programs near you`
- Primary category: `Education`
- SKU: `gta-free-stem-ios`
- Content rights: the app displays source-backed public opportunity listings and links users to original providers for registration.
- Marketing URL: `https://gta-free-stem.vercel.app/`
- Support URL: `https://gta-free-stem.vercel.app/accessibility-support/`
- Privacy policy URL: `https://gta-free-stem.vercel.app/privacy/`

## Description

```text
GTA FREE STEM helps students, parents, educators, and community groups find free STEM programs across the Greater Toronto Area.

Search by keyword, city, region, age, category, language, high-school pathway, distance, volunteer hours, co-op, mentorship, scholarships, and new finds. Browse in list or map view, save recent hunts locally, refresh from the public opportunity feed, and keep browsing from the bundled snapshot or local cache when the network is unavailable.

The app is designed for public browsing first. In the current TestFlight candidate, account-only actions are disabled until the production backend is connected; public discovery, search, map/list browsing, language switching, and refresh/offline fallback still work without an account.
```

## Keywords

```text
Toronto,robotics,coding,science,engineering,math,volunteer,coop,SHSM,mentorship,scholarships
```

## App Review Notes

```text
GTA FREE STEM is a public discovery app for free STEM opportunities in the Greater Toronto Area.

No account is required to browse, search, filter, view details, switch languages, use map/list mode, or use the offline bundled snapshot. Account-only actions, in-app feedback, and missing-opportunity submissions are intentionally unavailable in this build while the production backend token exchange and privacy handling are not connected.

The app may request location permission only when the user taps nearby search. Location is used locally to sort/filter nearby opportunities and is not transmitted to the public opportunity feed.

The app uses standard HTTPS/TLS only and does not use non-exempt encryption.
```

## Demo Account

- Demo account required: `No`
- Login required for core review: `No`
- Reviewer path: launch the app, open Opportunities or High School, search/filter, switch language, open a listing, use map/list mode, and try Support/Settings to see account-limited messaging.

## App Privacy Answers

Use these answers only for build `1.0 (9)` as currently implemented.

- Tracking: `No`
- Data linked to the user: `None`
- Data used to track the user: `None`
- Data collection: `No collected user data`
- Third-party advertising: `No`
- Purchases: `No`
- Account identifiers: `No`, because account login/token exchange is unavailable in this build.
- Contact info: `No`, because Support does not collect name, email, messages, or missing-opportunity submissions in this build.
- Location: `Not collected`; nearby search uses device location locally while browsing and does not transmit device location to the public feed.
- Diagnostics/analytics: `No`, unless Apple crash diagnostics are handled by App Store Connect outside the app's declared collection.
- Required reason API: `UserDefaults`, reason `CA92.1`, declared in `GTAFreeSTEM/Resources/PrivacyInfo.xcprivacy`.

If account, feedback, submission, analytics, crash reporting, or backend telemetry is connected before public release, redo the App Privacy answers before submission.

## Age Rating Notes

Recommended direction for the current build:

- Kids category: `No`
- Unrestricted web access: `No`
- User-generated content or public chat: `No`
- Gambling, contests with real prizes, alcohol, tobacco, drugs, medical treatment, violence, sexual content: `No`
- Advertising: `No`
- In-app purchases: `No`
- External links: provider registration/source links may open outside the app; answer App Store Connect's external-link questions according to the final link handling shown in the submitted build.

## Export Compliance

- Uses encryption: standard HTTPS/TLS only.
- Non-exempt encryption: `No`
- `ITSAppUsesNonExemptEncryption` is `false`.

## Screenshot Upload Paths

Upload the current local PNGs only after visual review:

- `build/app-store-screenshots/iphone-6.9/01-home.png`
- `build/app-store-screenshots/iphone-6.9/02-opportunities.png`
- `build/app-store-screenshots/iphone-6.9/03-high-school.png`
- `build/app-store-screenshots/iphone-6.9/04-support-account.png`
- `build/app-store-screenshots/ipad-13/01-home.png`
- `build/app-store-screenshots/ipad-13/02-opportunities.png`
- `build/app-store-screenshots/ipad-13/03-high-school.png`
- `build/app-store-screenshots/ipad-13/04-support-account.png`

The release audit verifies all eight screenshots exist, are valid PNGs, are nonblank, and match the expected dimensions:

- 6.9-inch iPhone: `1320 x 2868`
- 13-inch iPad: `2064 x 2752`

## TestFlight What To Test

```text
Please test the full discovery flow: keyword search, city/region/age/language/category filters, high-school pathway filters, map/list switching, sorting, detail pages, refresh, offline fallback, saved hunt restore, language switching, RTL layout, Dynamic Type, dark mode, and VoiceOver. Report any duplicate results, stale updates, broken links, untranslated UI, untranslated opportunity content, confusing permission prompts, or crashes.
```

## Final Pre-Submit Gates

- `STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh` passes.
- `bash docs/scripts/check-public-release-gates.sh` passes after real-device QA and App Store Connect entry are recorded.
- `xcodebuild -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' build` passes.
- `xcodebuild test -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -destination 'platform=iOS Simulator,name=iPhone 17'` passes.
- `bash docs/scripts/smoke-release-simulator.sh` passes.
- Real-device TestFlight QA passes for search/hunt, refresh, cache/offline fallback, language switching, RTL, Dynamic Type, VoiceOver, dark mode, Support, and account-limited flows.
- `docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md` is filled out with the real-device pass/fail record.
- No secrets, provisioning profiles, archives, derived-data products, or generated screenshots are staged for commit.
- The app-specific Apple password generated during setup has been revoked or rotated after release work is finished.
