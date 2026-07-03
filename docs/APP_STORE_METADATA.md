# App Store Metadata Draft

Last updated: July 3, 2026

Use this as the starting point for App Store Connect. For the paste-ready submission packet, use `docs/APP_STORE_SUBMISSION_PACKET.md`. Recheck every answer before submission if the production backend changes account, feedback, or submission handling.

## App Information

- App name: GTA FREE STEM
- Bundle ID: `com.rupayonhaldar.gtafreestem`
- SKU suggestion: `gta-free-stem-ios`
- Primary category: Education
- Subtitle suggestion: Youth programs near you
- Content rights: the app displays source-backed public opportunity listings and links users to the original providers for registration.
- Encryption: `ITSAppUsesNonExemptEncryption` is `false`; the app uses standard HTTPS/TLS only.

## Description Draft

GTA FREE STEM helps students, parents, educators, and community groups find free STEM programs across the Greater Toronto Area.

Search by keyword, city, region, age, category, language, high-school pathway, distance, volunteer hours, co-op, mentorship, scholarships, and new finds. Browse in list or map view, save recent hunts locally, refresh from the public opportunity feed, and keep browsing from the bundled snapshot or local cache when the network is unavailable.

The app is designed for public browsing first. In the current TestFlight candidate, account-only actions are disabled until the production backend is connected; public discovery, search, map/list browsing, language switching, and refresh/offline fallback still work without an account.

## Keywords Draft

Toronto,robotics,coding,science,engineering,math,volunteer,coop,SHSM,mentorship,scholarships

## Metadata Limit Notes

- App name: 13/30 characters.
- Subtitle: 23/30 characters.
- Keywords: 92/100 bytes.
- Description: under the 4000-character App Store Connect limit.
- Apple references: [Creating your product page](https://developer.apple.com/app-store/product-page/) and [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).

## Support And Privacy URLs

- Support URL: `https://gta-free-stem.vercel.app/accessibility-support/`
- Marketing URL: `https://gta-free-stem.vercel.app/`
- Privacy policy URL: `https://gta-free-stem.vercel.app/privacy/`

The iOS app has an in-app privacy note in Settings, but App Store Connect should use the stable public web URL. The marketing, support, and privacy routes are live in Vercel production and return HTTP 200.

## App Privacy Notes

- Tracking: No.
- Third-party advertising: No.
- Purchases: No.
- Public browsing without account: Yes.
- Optional location: used only while browsing to sort nearby opportunities; current app logic does not transmit device location to the feed.
- Local cache: public opportunity data, saved hunt state, seen listing IDs, and settings are stored locally with SwiftData/UserDefaults.
- Required reason API manifest: `PrivacyInfo.xcprivacy` declares app-only UserDefaults access with reason `CA92.1`.
- Data collection answer: for build `1.0 (10)`, answer as public browsing with no collected user data because account, feedback, and online submission endpoints are not connected in this iOS build. If those endpoints are connected before release, update App Privacy answers for account identifiers, feedback, submitted content, diagnostics, and deletion handling as implemented.

## Age Rating Notes

The app is intended for families and students and does not include ads, purchases, gambling, unrestricted web browsing, public chat, or public user-generated content feeds. External registration links open provider websites, so review App Store Connect age-rating questions against the final link handling before submission.

## Screenshot Notes

- The app supports iPhone and iPad, so prepare screenshots for both the 6.9-inch iPhone and 13-inch iPad display sets.
- Use `bash docs/scripts/capture-app-store-screenshots.sh` to generate the current Release screenshot set under `build/app-store-screenshots/`.
- The screenshot set was regenerated on July 2, 2026 after the privacy-safe Support update and offline-fallback label polish. The local outputs are 6.9-inch iPhone PNGs at `1320 x 2868` and 13-inch iPad PNGs at `2064 x 2752`.
- The Support screenshot now shows the unavailable feedback/submission state and no name, email, message, or missing-opportunity input fields.
- Uploading screenshots to App Store Connect is a metadata change and should happen only after explicit confirmation.

## Current External Follow-ups

- Public multilingual feed is live at `https://gta-free-stem.vercel.app/opportunities.json` with generated translation payloads for all public listings.
- Current bundled iOS snapshot and live public feed both contain 406/406 translated public opportunities after the July 3, 2026 feed sync.
- App Store marketing/support/privacy URLs are live and return HTTP 200.
- App Store privacy URL is live at `https://gta-free-stem.vercel.app/privacy/`.
- Full dynamic content translation can still be upgraded later with reviewed organization, address, source-specific tag, and richer prose translations in the companion feed pipeline.
- TestFlight upload is working from this Mac; build `1.0 (10)` uploaded successfully with the first-launch system-language fix, privacy-safe Support update, public-facing offline fallback label, missing-translation summary fallback hardening, and refreshed 406-item bundled opportunity snapshot. Build `1.0 (10)` is command-line-confirmed by App Store Connect with import status `VALID`, build status `BETA_INTERNAL_TESTING`, `APP_STORE_ELIGIBLE`, and `usesNonExemptEncryption = false`.
