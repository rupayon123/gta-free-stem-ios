# App Store Screenshot Capture

Last updated: July 3, 2026

App Store Connect accepts one to ten screenshots per device display set. Because this app supports iPhone and iPad, prepare both the 6.9-inch iPhone set and the 13-inch iPad set. See Apple's screenshot specifications: `https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/`.

Generate screenshots from the current Release simulator build:

```bash
bash docs/scripts/capture-app-store-screenshots.sh
```

The script writes upload-ready PNG files to:

- `build/app-store-screenshots/iphone-6.9/`
- `build/app-store-screenshots/ipad-13/`

Latest verified local capture: July 3, 2026, for TestFlight candidate `1.0 (10)` after the refreshed 406-listing bundled snapshot, privacy-safe Support update, and offline-fallback label polish.

- 6.9-inch iPhone screenshots: `1320 x 2868`
- 13-inch iPad screenshots: `2064 x 2752`
- Home screenshots show `406 visible` and the bundled fallback as `Offline backup`, not internal preview wording.
- Opportunity and high-school screenshots show search, filter, refresh, nearby, alert, and list/map controls.
- Support/account-limited screenshots: no personal-data fields; show feedback and online submissions unavailable in this build.
- July 3 visual review: iPhone and iPad screenshots are readable, nonblank, light-mode, free of loading spinners, and do not display name, email, message, or missing-opportunity input fields.

Default simulator devices:

- iPhone: `iPhone 17 Pro Max`
- iPad: `iPad Pro 13-inch (M5)`

Default captured screens:

- Home discovery
- Opportunity search/list
- High-school pathways
- Support/account-limited state

Before uploading to App Store Connect, visually review each PNG for readable text, no personal data, correct light-mode appearance, and no loading spinners. Screenshot upload to App Store Connect is a public metadata change, so it should be done only after explicit confirmation.

The release audit also verifies these eight screenshot files with `STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh`; missing, incorrectly sized, invalid, or nearly blank screenshots fail the audit.
