# App Store Screenshot Capture

Last updated: July 2, 2026

App Store Connect accepts one to ten screenshots per device display set. Because this app supports iPhone and iPad, prepare both the 6.9-inch iPhone set and the 13-inch iPad set. See Apple's screenshot specifications: `https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/`.

Generate screenshots from the current Release simulator build:

```bash
bash docs/scripts/capture-app-store-screenshots.sh
```

The script writes upload-ready PNG files to:

- `build/app-store-screenshots/iphone-6.9/`
- `build/app-store-screenshots/ipad-13/`

Latest verified local capture: July 2, 2026, after the privacy-safe Support update.

- 6.9-inch iPhone screenshots: `1320 x 2868`
- 13-inch iPad screenshots: `2064 x 2752`
- Support/account-limited screenshot: no personal-data fields; shows feedback and online submissions unavailable in this build.

Default simulator devices:

- iPhone: `iPhone 17 Pro Max`
- iPad: `iPad Pro 13-inch (M5)`

Default captured screens:

- Home discovery
- Opportunity search/list
- High-school pathways
- Support/account-limited state

Before uploading to App Store Connect, visually review each PNG for readable text, no personal data, correct light-mode appearance, and no loading spinners. Screenshot upload to App Store Connect is a public metadata change, so it should be done only after explicit confirmation.
