# Public Release Runbook

Last updated: August 6, 2026

This is the short, safe path for GTA FREE STEM 1.0 (12). It separates three different actions:

1. Build and upload to TestFlight so the owner can test on a real phone.
2. Complete App Store Connect metadata and platform assets.
3. Submit to App Review only after TestFlight QA and an explicit release decision.

## Current Candidate

- Version/build: \`1.0 (12)\`
- iOS/iPad bundle ID: \`com.rupayonhaldar.gtafreestem\`
- Mac Catalyst bundle ID: \`com.rupayonhaldar.gtafreestem.maccatalyst\`
- Watch bundle ID: \`com.rupayonhaldar.gtafreestem.watchkitapp\`
- Archive/upload state: See \`docs/APP_STORE_SUBMISSION_PACKET.md\`; do not trust an old build status. The local unsigned build-12 archive and \`build/GTAFreeSTEM-1.0-12.xcarchive\` (Apple Development-signed diagnostic only) are not uploadable. The generic \`build/GTAFreeSTEM.xcarchive\` is the historical build-4 archive.
- Live primary feed: GitHub raw \`opportunities.json\`. \`docs/scripts/sync-bundled-feed.sh\` copies the sibling website's verified-active public export into the offline fallback and rejects malformed, duplicate, or non-active records. Publish that exact website export before upload; \`docs/scripts/check-release-readiness.sh\` then requires the deployed GitHub feed and bundled fallback to have the same verified-active ID set. Pending-review records stay out of the consumer app until their details are confirmed.
- Launch resilience: opens from the on-device cache or bundled snapshot, then refreshes the live feed in the background; if neither local source is usable, it waits for live data.

## Local Verification

\`\`\`bash
bash docs/scripts/sync-bundled-feed.sh
RUN_SCREENSHOTS=0 bash docs/scripts/check-local-release-candidate.sh
\`\`\`

The tracked \`GTAFreeSTEM.xcodeproj\` is the release input and does not require XcodeGen. XcodeGen is an optional free maintenance tool only when a developer intentionally changes \`project.yml\`; if used, review the generated project diff before release verification. Use \`RUN_SCREENSHOTS=1\` once the simulator screenshot capture is ready. The full local pass includes strict translation checks, Release build, XCTest, and clean-install simulator smoke.

## Upload The Phone Build

The tracked export configuration uploads during the export step. It preserves build number 12 and lets Xcode manage distribution signing:

\`\`\`bash
xcodebuild archive \
  -project GTAFreeSTEM.xcodeproj \
  -scheme GTAFreeSTEM \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/GTAFreeSTEM-build12.xcarchive \
  -allowProvisioningUpdates

bash docs/scripts/verify-app-store-archive.sh \
  build/GTAFreeSTEM-build12.xcarchive

xcodebuild -exportArchive \
  -archivePath build/GTAFreeSTEM-build12.xcarchive \
  -exportOptionsPlist docs/AppStoreConnectExportOptions.plist \
  -exportPath build/export-build12 \
  -allowProvisioningUpdates
\`\`\`

The verifier must pass on that exact signed archive before export. The export plist uses \`destination=upload\`, so export is the irreversible upload step: do not rebuild between verification and export. Record the same archive path, verification date, and resulting Apple delivery UUID in the real-device signoff and pass that same path to the final public gate.

Release is configured to request Apple Distribution through automatic signing. Do not substitute a manually selected identity or change the team. If archive/export reports an account, agreement, team-role, certificate, or provisioning error, resolve that exact Apple-account issue before retrying.

After App Store Connect finishes processing:

1. Open TestFlight in App Store Connect.
2. Confirm version 1.0 build 12 is processed.
3. Add the owner to an internal tester group if they are not already included, then add build 12 to that group (or use automatic distribution for the group).
4. On the owner’s iPhone, open TestFlight, pull to refresh, and tap Update for GTA FREE STEM.
5. Record actual testing in \`docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md\`.

An internal tester can receive the build as soon as it processes. External testers need TestFlight beta review first. This TestFlight upload does not submit the app to App Review.

## App Store Connect Preparation

Use \`docs/APP_STORE_SUBMISSION_PACKET.md\` as the paste-ready source for:

- Product page metadata, price, category, marketing, support, privacy, and Terms URLs, plus the Standard-EULA choice.
- App Privacy, age rating, export-compliance, copyright, primary language, availability, DSA trader status, App Review contact, and review notes.
- Screenshots for the explicit platforms selected for public distribution.

Before public submission, add a dedicated monitored public support email or telephone number chosen by the release owner, then verify the public Support, Privacy, and Terms pages accurately describe the submitted build's on-device Profile, no in-app form collection, deletion controls, direct contact method, and public GitHub support route. Confirm both contact channels are monitored, leave the custom-EULA field blank so Apple's Standard EULA applies, and record the dated three-URL truthfulness verification in the signoff.

## Mac And Watch Distribution

- The iOS TestFlight archive embeds the Watch companion, so the Watch update arrives with the iPhone build.
- Mac Catalyst needs its own signed archive/upload. The current \`.maccatalyst\` bundle ID means it must use a separate Mac App Store Connect record for \`com.rupayonhaldar.gtafreestem.maccatalyst\`, with its own Mac App ID, SKU, primary language, agreements, and team access. Do not try to add that Mac build to the iOS record \`6779714459\`.
- If the owner instead chooses one universal iOS/macOS record, first confirm no separate released Mac product depends on the suffix, change the Catalyst bundle ID to \`com.rupayonhaldar.gtafreestem\`, regenerate the project, and add macOS to iOS Apple ID \`6779714459\`. Then create a new signed Mac archive; never reuse a build made with the previous identifier.
- Capture and upload the required Mac 16:10 screenshots and Apple Watch Series 11 screenshots before enabling those platforms for public sale.

After the separate Mac record and signing assets exist, archive, verify, and upload the exact same Mac artifact in this order:

\`\`\`bash
xcodebuild archive \
  -project GTAFreeSTEM.xcodeproj \
  -scheme GTAFreeSTEM \
  -configuration Release \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -archivePath build/GTAFreeSTEM-Mac-build12.xcarchive \
  -allowProvisioningUpdates

bash docs/scripts/verify-mac-app-store-archive.sh \
  build/GTAFreeSTEM-Mac-build12.xcarchive

xcodebuild -exportArchive \
  -archivePath build/GTAFreeSTEM-Mac-build12.xcarchive \
  -exportOptionsPlist docs/AppStoreConnectExportOptions.plist \
  -exportPath build/export-mac-build12 \
  -allowProvisioningUpdates
\`\`\`

As with iOS, the Mac verifier must pass before the upload export, and the verified archive must not be rebuilt or replaced between those commands.

## Final App Review Gate

Only after real-device QA and portal work are complete:

\`\`\`bash
IOS_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-1.0-12.xcarchive \
  PUBLIC_RELEASE_PLATFORMS=iphone,ipad,watch \
  bash docs/scripts/check-public-release-gates.sh
\`\`\`

Replace the example selection with the exact final public set using only \`iphone\`, \`ipad\`, \`watch\`, and \`mac\`; there is no default. That gate intentionally fails while selected-platform TestFlight evidence, screenshot-upload evidence, metadata/privacy/age-rating/copyright/reviewer-contact/availability/DSA evidence, the production legal/support truthfulness check, a real Apple delivery UUID, or a verified support route is pending. It requires the Mac record decision only when \`mac\` is selected. Do not mark \`Submitted for App Review\` complete until the final App Store Connect submit action is intentionally performed.
\`IOS_ARCHIVE_PATH\` must be a real signed iOS \`.xcarchive\`; the gate rejects development/ad-hoc signatures, debug entitlements or provisioning, missing dSYMs/privacy manifests, mismatched versions or identifiers, and stale main-app bundled opportunity data. The Watch companion receives saved-item updates through WatchConnectivity and does not bundle the full opportunity feed. When \`mac\` is selected, also set \`MAC_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-Mac-1.0-12.xcarchive\`; the gate independently verifies its Mac App Store signature, profile, sandbox entitlements, dSYM, privacy manifest, and bundled feed.

## Cost Constraint

Xcode simulator and personal-device development testing can be free. TestFlight and App Store distribution require an enrolled Apple Developer Program team, unless the team receives an Apple fee waiver for an eligible nonprofit, accredited educational institution, or government entity. There is no compliant free-account workaround for TestFlight distribution.
