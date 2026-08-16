# App Store Screenshot Capture

Last updated: August 6, 2026

The screenshot set belongs to release candidate \`1.0 (12)\`. Do not reuse the July 3 build-11 assets: the app now has a new on-device Profile flow, updated live-feed behavior, a revised loader, and a Watch companion.

Apple accepts one to ten \`.jpeg\`, \`.jpg\`, or \`.png\` screenshots per display set. Submitted screenshots cannot include alpha or transparency.

The build 1.0 (12) public scope is \`iphone,ipad,watch,mac\`. Its canonical upload package is \`build/app-store-screenshots/final/\` and contains 13 platform JPEGs: four iPhone, four iPad, four Mac, and one Watch image.

**Current status: all 13 local files passed independent full-size visual inspection on August 6, 2026, but they are not release-signoff evidence.** The Watch image predates the final Watch source edit, and the set has no generated clean-source capture receipt. After the app source is committed, recapture every platform from that clean commit, generate `CAPTURE_RECEIPT.json`, and repeat the full-size review before creating `FINAL_VISUAL_QA.md` or uploading anything.

## iPhone And iPad

Generate the opaque JPEG set from the Release simulator build:

\`\`\`bash
export SCREENSHOT_SOURCE_COMMIT="REPLACE_WITH_THE_40_CHARACTER_ARTIFACT_SOURCE_COMMIT"
bash docs/scripts/capture-app-store-screenshots.sh
\`\`\`

Starting either the iPhone/iPad or Watch capture invalidates and removes any existing \`CAPTURE_RECEIPT.json\`, \`FINAL_VISUAL_QA.md\`, and contact sheet before build/capture work. Each script refuses dirty app, Watch, Xcode-project, or `project.yml` inputs, embeds the exact clean Git commit in the built app metadata, and verifies that the source does not change during capture. A new receipt and approval record may be created only after all 13 current-build JPEGs are recaptured and reviewed together.

Outputs:

- \`build/app-store-screenshots/final/iphone-6.9/01-home.jpg\`
- \`build/app-store-screenshots/final/iphone-6.9/02-opportunities.jpg\`
- \`build/app-store-screenshots/final/iphone-6.9/03-high-school.jpg\`
- \`build/app-store-screenshots/final/iphone-6.9/04-profile.jpg\`
- \`build/app-store-screenshots/final/ipad-13/01-home.jpg\`
- \`build/app-store-screenshots/final/ipad-13/02-opportunities.jpg\`
- \`build/app-store-screenshots/final/ipad-13/03-high-school.jpg\`
- \`build/app-store-screenshots/final/ipad-13/04-profile.jpg\`

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
export SCREENSHOT_SOURCE_COMMIT="REPLACE_WITH_THE_40_CHARACTER_ARTIFACT_SOURCE_COMMIT"
bash docs/scripts/capture-watch-app-store-screenshot.sh
\`\`\`

Output:

- \`build/app-store-screenshots/final/watch-series-11/01-home.jpg\`

Required size for the Series 11 simulator: \`416 x 496\`. Use the same Watch screenshot size consistently for every localization.

## Mac Catalyst

Prepare and launch the clean-source Release Mac Catalyst app, then capture four opaque JPEGs from the active app window:

\`\`\`bash
export SCREENSHOT_SOURCE_COMMIT="REPLACE_WITH_THE_40_CHARACTER_ARTIFACT_SOURCE_COMMIT"
bash docs/scripts/prepare-mac-screenshot-capture.sh
\`\`\`

Save:

- \`build/app-store-screenshots/final/mac/01-home.jpg\`
- \`build/app-store-screenshots/final/mac/02-opportunities.jpg\`
- \`build/app-store-screenshots/final/mac/03-high-school.jpg\`
- \`build/app-store-screenshots/final/mac/04-profile.jpg\`

The preparer refuses dirty or source-mismatched inputs, deletes all four prior Mac JPEGs, embeds and verifies the artifact source commit, records the exact app executable and `Info.plist` hashes in `MAC_CAPTURE_SESSION.json`, and launches that app. Each new Mac screenshot must be one accepted 16:10 size. This release uses \`1440 x 900\`. Keep the window active, fully framed, and readable; do not submit inactive gray chrome, clipped edges, or excess empty padding.

After all 13 images exist, generate the source-bound receipt from the exact three Release app bundles. The finalizer rejects dirty or changed source inputs, incorrect bundle/version/build/source metadata, stale screenshots that predate their platform executable, missing or unexpected files, incorrect dimensions, alpha, and invalid JPEGs. It invalidates any previous visual-QA manifest:

\`\`\`bash
MAC_SCREENSHOT_APP_PATH="$PWD/build/DerivedData-app-store-mac-screenshots/Build/Products/Release-maccatalyst/GTAFreeSTEM.app" \
  SCREENSHOT_SOURCE_COMMIT="$SCREENSHOT_SOURCE_COMMIT" \
  bash docs/scripts/finalize-screenshot-capture-receipt.sh
\`\`\`

Use the exact commit embedded in the signed iOS/Watch and Mac release candidates. The scripts permit a later docs-only `HEAD` only when the current app, Watch, Xcode project, and `project.yml` inputs byte-match that artifact commit. Record the printed `Capture receipt SHA-256` in the new visual-QA manifest. `CAPTURE_RECEIPT.json` binds the clean source tree and commit, the Mac preparation-session hash, each built executable and app-bundle metadata hash, and every screenshot hash.

## Final Review

Before uploading anything to App Store Connect:

1. Run \`CHECK_APP_STORE_SCREENSHOTS=1 STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh\`.
2. Confirm the checker reports all 13 canonical platform JPEGs: 4 iPhone + 4 iPad + 4 Mac + 1 Watch.
3. Generate `CAPTURE_RECEIPT.json`, then inspect every JPEG at full size for legibility, visual polish, current copy, truthful data-source state, complete framing, no truncation, and no alpha.
4. Create the canonical \`FINAL_VISUAL_QA.md\` from `docs/FINAL_VISUAL_QA_TEMPLATE.md` only after every defect is resolved. Record the receipt hash, exact published source commit, reviewer, review date, and all 13 hashes.
5. Run `bash docs/scripts/verify-screenshot-package.sh`; then record the manifest SHA-256 and \`Screenshot visual QA: PASS\` in \`docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md\`.
6. Confirm all four platform sets match the exact iOS/Watch and Mac builds being selected, then upload only after both App Store Connect records are complete and the release owner approves the public metadata change.
