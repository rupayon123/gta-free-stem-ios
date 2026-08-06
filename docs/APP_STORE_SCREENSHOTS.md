# App Store Screenshot Capture

Last updated: August 6, 2026

The screenshot set belongs to release candidate \`1.0 (12)\`. Do not reuse the July 3 build-11 assets: the app now has a new on-device Profile flow, updated live-feed behavior, a revised loader, and a Watch companion.

Apple accepts one to ten \`.jpeg\`, \`.jpg\`, or \`.png\` screenshots per display set. Submitted screenshots cannot include alpha or transparency.

Capture and upload only the display sets named by the final \`Public distribution platforms\` selection in \`docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md\`; the sections below document every available target.

## iPhone And iPad

Generate the opaque JPEG set from the Release simulator build:

\`\`\`bash
bash docs/scripts/capture-app-store-screenshots.sh
\`\`\`

Outputs:

- \`build/app-store-screenshots/iphone-6.9/01-home.jpg\`
- \`build/app-store-screenshots/iphone-6.9/02-opportunities.jpg\`
- \`build/app-store-screenshots/iphone-6.9/03-high-school.jpg\`
- \`build/app-store-screenshots/iphone-6.9/04-profile.jpg\`
- \`build/app-store-screenshots/ipad-13/01-home.jpg\`
- \`build/app-store-screenshots/ipad-13/02-opportunities.jpg\`
- \`build/app-store-screenshots/ipad-13/03-high-school.jpg\`
- \`build/app-store-screenshots/ipad-13/04-profile.jpg\`

Required sizes:

- 6.9-inch iPhone: \`1320 x 2868\`.
- 13-inch iPad: \`2064 x 2752\`.

Visual review criteria:

- Home clearly shows the warm GTA FREE STEM identity and current data state.
- Opportunities and High School show search, filters, refresh, nearby, and list/map controls.
- Profile shows a clearly fictional \`STEM Explorer\` on-device profile, saved-events access, language/theme controls, and legal links. The capture script seeds that value only inside its disposable simulator.
- Support is reviewed separately during real-device QA so its production URL, privacy-safe no-form state, and legal links are tested without spending a storefront slot on a limitation screen.
- No personal name, email, message, actual home/work location, or debugging status is visible.

## Apple Watch

Generate the Watch companion screenshot:

\`\`\`bash
bash docs/scripts/capture-watch-app-store-screenshot.sh
\`\`\`

Output:

- \`build/app-store-screenshots/watch-series-11/01-home.jpg\`

Required size for the Series 11 simulator: \`416 x 496\`. Use the same Watch screenshot size consistently for every localization.

## Mac Catalyst

Build and launch the Release Mac Catalyst app, then capture two opaque JPEGs from the app window:

\`\`\`bash
xcodebuild build -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -configuration Release -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac'
\`\`\`

Save:

- \`build/app-store-screenshots/mac/01-home.jpg\`
- \`build/app-store-screenshots/mac/02-opportunities.jpg\`

Each Mac screenshot must be one accepted 16:10 size. This release uses \`1440 x 900\`.

## Final Review

Before uploading anything to App Store Connect:

1. Run \`CHECK_APP_STORE_SCREENSHOTS=1 STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh\`.
2. Inspect every JPEG at full size for legibility, visual polish, current copy, and no alpha.
3. Confirm every selected platform's screenshots match the exact build being selected; Mac and Watch evidence is required only when those platforms are selected.
4. Upload only after the App Store Connect record is complete and a release owner approves the public metadata change.
