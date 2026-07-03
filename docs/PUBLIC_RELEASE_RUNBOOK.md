# Public Release Runbook

Last updated: July 3, 2026

Use this as the short path from the current repo state to App Store submission for GTA FREE STEM.

## Current Local Release Candidate

- App: `GTA FREE STEM`
- App Apple ID: `6779714459`
- Bundle ID: `com.rupayonhaldar.gtafreestem`
- Apple Developer team: `FE33NM88XX`
- Apple ID email for App Store Connect: `rupayon244@gmail.com`
- Version/build: `1.0 (11)`
- Delivery UUID: `Pending build 11 upload`
- App Store Connect import status: `Pending build 11 upload`
- TestFlight status: `Pending build 11 upload`
- Last confirmed uploaded build: `1.0 (10)`, delivery UUID `97c05d63-7f3d-45bc-941e-c10432694ca8`, status `VALID` / `BETA_INTERNAL_TESTING`
- Audience: `Pending build 11 upload`
- Non-exempt encryption: `false`

## Current Repo/Feed State

- Public site/feed deployment: `dpl_F2wScPMS6rqR8PB4djdyFhcV6cC2`
- Public site/feed URL: `https://gta-free-stem.vercel.app/`
- Live feed URL: `https://gta-free-stem.vercel.app/opportunities.json`
- Bundled iOS snapshot: 382 translated opportunities
- Live public feed: 382 translated opportunities
- Local build `1.0 (11)` includes the refreshed 382-item bundled snapshot and can also refresh from the live public feed online. Archive/upload is pending macOS keychain authorization for the Apple signing key.

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
- Bundled and live feed translation coverage remains 382/382 opportunities.
- App Store screenshots are regenerated and rechecked.

## GitHub CI Guard

GitHub Actions runs `.github/workflows/ios-release-readiness.yml` on pushes to `main`, pull requests, and manual dispatch. It runs `bash docs/scripts/check-ci-release-readiness.sh`, which validates strict release readiness, a Release simulator build, and the XCTest suite without requiring App Store Connect credentials or locally generated screenshot artifacts.

## If App Store Connect Keeps Loading

The web UI is still needed to select the build, upload screenshots, enter metadata, and submit for review. If the page keeps loading, use command-line checks to confirm the build is valid, then retry App Store Connect in Safari/Chrome later.

Command-line TestFlight status check:

```bash
read -r -s APP_STORE_CONNECT_APP_PASSWORD
export APP_STORE_CONNECT_APP_PASSWORD
BUNDLE_VERSION=11 \
  DELIVERY_ID=<build-11-delivery-uuid-after-upload> \
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
- Build to select: `1.0 (11)` after App Store Connect reports build 11 as `VALID`

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

Install build `1.0 (11)` from TestFlight on a real iPhone after upload and processing complete.

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

The final gate also has a fixture self-test that CI runs automatically:

```bash
bash docs/scripts/test-public-release-gates.sh
```

This verifies that a complete temporary signoff passes and weak App Store evidence, wrong build selection, or a missing delivery UUID fail.

## Final Live Steps

1. Select build `1.0 (11)` in App Store Connect after it is uploaded and processed.
2. Upload the screenshots listed above.
3. Paste metadata, privacy, age rating, and review notes from `docs/APP_STORE_SUBMISSION_PACKET.md`.
4. Complete `docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md`.
5. Run `bash docs/scripts/check-public-release-gates.sh`.
6. Submit for App Review.
7. Rotate or revoke the app-specific Apple password generated during release setup.
