# App Store Metadata Draft

Last updated: July 2, 2026

Use this as the starting point for App Store Connect. Recheck every answer before submission if the production backend changes account, feedback, or submission handling.

## App Information

- App name: GTA FREE STEM
- Bundle ID: `com.rupayonhaldar.gtafreestem`
- SKU suggestion: `gta-free-stem-ios`
- Primary category: Education
- Subtitle suggestion: Free STEM opportunities in the GTA
- Content rights: the app displays source-backed public opportunity listings and links users to the original providers for registration.
- Encryption: `ITSAppUsesNonExemptEncryption` is `false`; the app uses standard HTTPS/TLS only.

## Description Draft

GTA FREE STEM helps students, parents, educators, and community groups find free STEM programs across the Greater Toronto Area.

Search by keyword, city, region, age, category, language, high-school pathway, distance, volunteer hours, co-op, mentorship, scholarships, and new finds. Browse in list or map view, save recent hunts locally, refresh from the public opportunity feed, and keep browsing from the bundled snapshot or local cache when the network is unavailable.

The app is designed for public browsing first. In the current TestFlight candidate, account-only actions are disabled until the production backend is connected; public discovery, search, map/list browsing, language switching, and refresh/offline fallback still work without an account.

## Keywords Draft

STEM, GTA, Toronto, education, youth, robotics, coding, science, engineering, math, volunteer, co-op, SHSM, mentorship, scholarships, students, families

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
- Data collection answer: for build `1.0 (5)`, answer as public browsing with no collected user data because account, feedback, and online submission endpoints are not connected in this iOS build. If those endpoints are connected before release, update App Privacy answers for account identifiers, feedback, submitted content, diagnostics, and deletion handling as implemented.

## Age Rating Notes

The app is intended for families and students and does not include ads, purchases, gambling, unrestricted web browsing, public chat, or public user-generated content feeds. External registration links open provider websites, so review App Store Connect age-rating questions against the final link handling before submission.

## Current External Follow-ups

- Public multilingual feed is live at `https://gta-free-stem.vercel.app/opportunities.json` with generated translation payloads for all public listings.
- App Store marketing/support/privacy URLs are live and return HTTP 200.
- App Store privacy URL is live at `https://gta-free-stem.vercel.app/privacy/`.
- Full dynamic content translation can still be upgraded later with reviewed title, organization, address, tag, and richer description translations in the companion feed pipeline.
- TestFlight upload is working from this Mac; build `1.0 (5)` uploaded successfully, the Build Uploads row is `Complete`, and the iOS build list shows `Ready to Submit` with internal group `Zenin` attached.
