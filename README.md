# GTA FREE STEM iOS

[![SwiftUI](https://img.shields.io/badge/SwiftUI-iOS%2017+-0A84FF)](https://developer.apple.com/xcode/swiftui/)
[![MapKit](https://img.shields.io/badge/MapKit-enabled-30B0C7)](https://developer.apple.com/maps/)
[![TestFlight](https://img.shields.io/badge/TestFlight-ready-5856D6)](https://developer.apple.com/testflight/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Native iOS app for discovering free STEM opportunities across the Greater Toronto Area. The app is built for public browsing first, with account features reserved for saving, feedback, and submissions once the production backend is connected.

## What It Does

- Browse free GTA STEM opportunities without signing in.
- Search by keyword, city, region, age, category, language, high-school pathway, and distance.
- Switch between list and map discovery with MapKit.
- Use one-time nearby search through Core Location.
- Save recent hunts and public listing cache with SwiftData.
- Refresh the hunt manually and support BackgroundTasks for light background refresh.
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

## Project Layout

- `GTAFreeSTEM/` - app source, design system, views, models, API client, resources, and assets.
- `GTAFreeSTEMTests/` - decoding, localization, permission-copy, security, and local snapshot tests.
- `project.yml` - XcodeGen project source.
- `docs/TESTFLIGHT.md` - TestFlight sharing guide.

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
