# GTA FREE STEM iOS

[![SwiftUI](https://img.shields.io/badge/SwiftUI-iOS%2017+-0A84FF)](https://developer.apple.com/xcode/swiftui/)
[![MapKit](https://img.shields.io/badge/MapKit-enabled-30B0C7)](https://developer.apple.com/maps/)
[![TestFlight](https://img.shields.io/badge/TestFlight-ready-5856D6)](https://developer.apple.com/testflight/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Native iOS app for discovering free STEM opportunities across the Greater Toronto Area. The app is built for public browsing first, with account features reserved for saving, feedback, and submissions once the production backend is connected.

## What It Does

- Browse free GTA STEM opportunities without signing in.
- Search by keyword, city, region, age, category, language, high-school pathway, distance, volunteer hours, co-op/SHSM, mentorship, scholarships, and new finds.
- Switch between list and map discovery with MapKit.
- Use one-time nearby search through Core Location.
- Save recent hunts and public listing cache with SwiftData.
- Refresh the hunt manually from the shared public opportunity feed and support BackgroundTasks for light background refresh.
- Show optional new-match notifications with UserNotifications.
- Support Sign in with Apple UI for the account path.
- Provide light/dark themes, Dynamic Type-friendly layouts, VoiceOver labels, and right-to-left layout for Arabic, Farsi/Persian, and Urdu.

## Apple Frameworks Used

- SwiftUI for the full native interface.
- MapKit for maps, pins, distance-aware browsing, and directions flow.
- Core Location for one-time nearby search.
- SwiftData for local public cache, saved hunt state, and seen listing tracking.
- BackgroundTasks for scheduled app refresh when iOS grants time.
- UserNotifications for optional new-match alerts.
- AuthenticationServices for Sign in with Apple.
- Xcode localization resources for system permission copy.

## Search Hunting Engine

The app reads the same generated feed as the public website:

```text
https://gta-free-stem.vercel.app/opportunities.json
```

The current free engine path is:

1. GitHub Actions refreshes public GTA source-backed listings on a schedule.
2. The website exports `public/opportunities.json`.
3. The iOS app downloads that feed, filters it locally, caches it with SwiftData, and falls back to the bundled snapshot when offline.

Apple resources strengthen the app side through MapKit, Core Location, SwiftData, BackgroundTasks, UserNotifications, TestFlight, and Xcode Cloud. The actual web crawling still runs outside iOS because iOS apps cannot scrape public websites continuously in the background.

## Translated Opportunity Feed

The iOS app supports translated dynamic opportunity fields with English fallback. Existing English-only listings still work, and translated listings can add a `translations` object keyed by app language code or locale identifier.

```json
{
  "id": "library-robotics",
  "title": "Robotics Club",
  "organization": "Public Library",
  "description": "Build robots.",
  "summary": "Build robots.",
  "category": "Coding & Robotics",
  "city": "Toronto",
  "region": "Toronto",
  "language": ["en"],
  "translations": {
    "es": {
      "title": "Club de robotica",
      "organization": "Biblioteca publica",
      "description": "Construye robots.",
      "summary": "Construye robots.",
      "category": "Programacion y robotica",
      "city": "Toronto",
      "region": "Toronto",
      "cost": "Gratis",
      "tags": ["robotica"]
    }
  }
}
```

Search uses both translated fields and English fallback/source fields, so families can search in their selected app language while English source terms still work. The bundled snapshot currently includes translated payloads for only one listing and relies on fallbacks for the rest. Full production listing translation still requires the deployed companion feed to publish reviewed translated titles, organizations, addresses, source-specific tags, and richer descriptions.

## Project Layout

- `GTAFreeSTEM/` - app source, design system, views, models, API client, resources, and assets.
- `GTAFreeSTEMTests/` - decoding, localization, permission-copy, security, and local snapshot tests.
- `project.yml` - XcodeGen project source.
- `docs/TESTFLIGHT.md` - TestFlight sharing guide.
- `docs/APP_STORE_METADATA.md` - App Store Connect metadata, privacy, and signing notes.
- `docs/RELEASE_READINESS.md` - current release blockers and validation checklist.

## Run Locally

```bash
xcodegen generate
open GTAFreeSTEM.xcodeproj
```

In Xcode, choose an iPhone simulator and press Run.

Command-line checks:

```bash
xcodebuild -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild test -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Privacy And Security Defaults

- Browsing does not require an account.
- Location permission is optional and only used while browsing.
- Exact location is not continuously tracked.
- Public listings are cached locally only to make browsing faster and more reliable.
- Access tokens are not stored in `UserDefaults`.
- API traffic is restricted to HTTPS.
- Local signing files, provisioning profiles, certificates, archives, and secrets are ignored by git.

## Companion Website

The public website lives separately at [gta-free-stem-opportunities](https://github.com/rupayon123/gta-free-stem-opportunities). The app and website can share a backend contract later, but the codebases are kept separate for now.
