# Public Release Runbook

Last updated: July 3, 2026

Use this as the short path from the current repo state to App Store submission for GTA FREE STEM.

## Current Candidate

- App: `GTA FREE STEM`
- App Apple ID: `6779714459`
- Bundle ID: `com.rupayonhaldar.gtafreestem`
- Apple Developer team: `FE33NM88XX`
- Apple ID email for App Store Connect: `rupayon244@gmail.com`
- Version/build: `1.0 (9)`
- Delivery UUID: `222e71fe-92f1-4da3-bad7-205b9eb7a3b3`
- App Store Connect import status: `VALID`
- TestFlight status: `BETA_INTERNAL_TESTING`
- Audience: `APP_STORE_ELIGIBLE`
- Non-exempt encryption: `false`

## One Command To Recheck The Repo

Run this before App Store submission:

```bash
bash docs/scripts/check-local-release-candidate.sh
```

Expected result:

- Release-readiness audit passes.
- Release build succeeds.
- Test suite passes with 43 tests.
- Simulator smoke test passes.
- Bundled and live feed translation coverage remains 370/370 opportunities.
- App Store screenshots are regenerated and rechecked.

## If App Store Connect Keeps Loading

The web UI is still needed to select the build, upload screenshots, enter metadata, and submit for review. If the page keeps loading, use command-line checks to confirm the build is valid, then retry App Store Connect in Safari/Chrome later.

Command-line TestFlight status check:

```bash
read -r -s APP_STORE_CONNECT_APP_PASSWORD
export APP_STORE_CONNECT_APP_PASSWORD
BUNDLE_VERSION=9 \
  DELIVERY_ID=222e71fe-92f1-4da3-bad7-205b9eb7a3b3 \
  APP_STORE_CONNECT_USERNAME=rupayon244@gmail.com \
  bash docs/scripts/check-testflight-build-status.sh
unset APP_STORE_CONNECT_APP_PASSWORD
```

Use an Apple app-specific password, not the normal Apple ID password.

## App Store Connect Values

Use `docs/APP_STORE_SUBMISSION_PACKET.md` as the paste-ready source.

- Name: `GTA FREE STEM`
- Subtitle: `Youth programs near you`
- Category: `Education`
- SKU: `gta-free-stem-ios`
- Marketing URL: `https://gta-free-stem.vercel.app/`
- Support URL: `https://gta-free-stem.vercel.app/accessibility-support/`
- Privacy Policy URL: `https://gta-free-stem.vercel.app/privacy/`
- Build to select: `1.0 (9)`

Screenshots to upload:

- `build/app-store-screenshots/iphone-6.9/01-home.png`
- `build/app-store-screenshots/iphone-6.9/02-opportunities.png`
- `build/app-store-screenshots/iphone-6.9/03-high-school.png`
- `build/app-store-screenshots/iphone-6.9/04-support-account.png`
- `build/app-store-screenshots/ipad-13/01-home.png`
- `build/app-store-screenshots/ipad-13/02-opportunities.png`
- `build/app-store-screenshots/ipad-13/03-high-school.png`
- `build/app-store-screenshots/ipad-13/04-support-account.png`

## Real-Device TestFlight Signoff

Install build `1.0 (9)` from TestFlight on a real iPhone.

Fill out:

```text
docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md
```

Required real-device coverage:

- Fresh install and launch.
- Search keywords and translated fields.
- Filters, sorting, map/list consistency, details, refresh, cache fallback, bundled fallback, and state restore.
- New-match messaging, location denied/allowed, notifications.
- Language switching, RTL layout, Dynamic Type, VoiceOver, and dark mode.
- Support privacy, account-limited paths, and public App Store URLs.

Use `Pass` only when tested. Use `Accepted Risk` only with notes and owner approval. Leave `Submitted for App Review` pending until the final submit click.

## Final Gate

Run:

```bash
bash docs/scripts/check-public-release-gates.sh
```

This must pass before public release. It intentionally fails while real-device QA or App Store Connect owner fields are still pending.

## Final Live Steps

1. Select build `1.0 (9)` in App Store Connect.
2. Upload the screenshots listed above.
3. Paste metadata, privacy, age rating, and review notes from `docs/APP_STORE_SUBMISSION_PACKET.md`.
4. Complete `docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md`.
5. Run `bash docs/scripts/check-public-release-gates.sh`.
6. Submit for App Review.
7. Rotate or revoke the app-specific Apple password generated during release setup.
