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
- Public release platforms: \`iphone,ipad,watch,mac\`
- Distribution model: the Watch companion is embedded in the iOS upload; Mac uses a selected separate Mac App Store record and upload for \`com.rupayonhaldar.gtafreestem.maccatalyst\`.
- Archive/upload state: See \`docs/APP_STORE_SUBMISSION_PACKET.md\`; do not trust an old build status. A fresh automatic-signing archive may correctly carry an Apple Development signature before export; the export step re-signs it for App Store distribution. Old unsigned, stale-source, or historical archives are not valid release inputs. The generic \`build/GTAFreeSTEM.xcarchive\` is the historical build-4 archive.
- Live primary feed: GitHub raw \`opportunities.json\`. \`docs/scripts/sync-bundled-feed.sh\` copies the sibling website's verified-active public export into the offline fallback and rejects malformed, duplicate, or non-active records. Publish that exact website export before upload; \`docs/scripts/check-release-readiness.sh\` then requires the deployed GitHub feed and bundled fallback to have the same verified-active ID set. Pending-review records stay out of the consumer app until their details are confirmed.
- Launch resilience: prepares the on-device cache or bundled snapshot when available, then refreshes the live feed in the background. If neither local source is usable, the branded loader still hands off after its bounded preparation checkpoint and the interactive app shows its honest loading or error state while the live request runs.

## Local Verification

\`\`\`bash
bash docs/scripts/sync-bundled-feed.sh
RUN_SCREENSHOTS=0 bash docs/scripts/check-local-release-candidate.sh
\`\`\`

The tracked \`GTAFreeSTEM.xcodeproj\` is the release input and does not require XcodeGen. XcodeGen is an optional free maintenance tool only when a developer intentionally changes \`project.yml\`; if used, review the generated project diff before release verification. After committing the exact app source, use \`RUN_SCREENSHOTS=1\` to recapture iPhone, iPad, and Watch. That capture-only run intentionally stops after invalidating the old receipt and visual approval. Run `prepare-mac-screenshot-capture.sh` for the same commit; it removes the stale Mac files and creates a source/app-bound capture session. Capture all four Mac images from that launched app, run `finalize-screenshot-capture-receipt.sh`, review all 13 images, create `FINAL_VISUAL_QA.md`, and rerun with `RUN_SCREENSHOTS=0`. The rerun forces real (non-fixture) verification of the session, receipt, manifest, screenshot hashes, and structural screenshot checks before it can pass. The full local pass also includes strict translation checks, Release build, XCTest, and clean-install simulator smoke.

## Export And Upload The Phone Build

First create a local, distribution-signed IPA. This is reversible and does not upload:

\`\`\`bash
ARCHIVE_PATH="$PWD/build/GTAFreeSTEM-build12.xcarchive" \
  bash docs/scripts/archive-release-candidate.sh ios

bash docs/scripts/verify-app-store-archive.sh \
  build/GTAFreeSTEM-build12.xcarchive

xcodebuild -exportArchive \
  -archivePath build/GTAFreeSTEM-build12.xcarchive \
  -exportOptionsPlist docs/AppStoreExportOptions.plist \
  -exportPath build/export-build12 \
  -allowProvisioningUpdates

bash docs/scripts/verify-app-store-ipa.sh \
  build/export-build12/GTAFreeSTEM.ipa \
  build/GTAFreeSTEM-build12.xcarchive
\`\`\`

The archive helper refuses dirty or mismatched app/project inputs and embeds the exact 40-character source commit in the signed main and Watch metadata. The archive verifier must pass before export, and the exported IPA verifier must then pass on the exact distributable. The local export plist uses \`destination=export\`; it cannot upload. The IPA check requires Apple Distribution signing, exact main and Watch App Store identifiers and profiles, release entitlements, unexpired signing material, matching embedded source commits, and executable UUIDs that match the source archive.

Only after those checks pass, upload that exact IPA with Apple's Transporter app or the installed Xcode toolchain's IPA command:

\`\`\`bash
xcrun altool --upload-package build/export-build12/GTAFreeSTEM.ipa \\
  --api-key 'REPLACE_WITH_KEY_ID' \\
  --api-issuer 'REPLACE_WITH_ISSUER_UUID'
\`\`\`

Xcode 26.6's own \`altool --help\` identifies \`--upload-package\` as the IPA upload command. Keep the authentication values out of the repository, and replace the placeholders at execution time with one supported authentication method. Upload is the irreversible step. Do not rebuild or re-export between verification and delivery. Record the archive path, IPA path and SHA-256, verification date, and resulting Apple delivery UUID in the real-device signoff.

Release uses automatic signing without a hard-coded identity. Xcode signs the archive for development and selects the distribution identity and profiles during App Store export. Do not manually override the identity or change the team. If archive/export reports an account, agreement, team-role, certificate, or provisioning error, resolve that exact Apple-account issue before retrying.

After App Store Connect finishes processing:

1. Open TestFlight in App Store Connect.
2. Confirm version 1.0 build 12 is processed for the iOS/Watch product. Separately confirm the Mac build is processed in its own Mac App Store record.
3. In the iOS/Watch record, add the owner to an internal tester group if needed and add the processed iOS build 12 to that group (or use automatic distribution for that group).
4. In the separate Mac record, add the owner to its internal tester group and explicitly add the processed Mac build 12 to that group. Do not treat iOS group membership as evidence that the Mac build was distributed.
5. On the owner’s iPhone, open TestFlight, pull to refresh, and tap Update for GTA FREE STEM. Verify the paired Watch receives the embedded companion from that iOS build.
6. On the owner’s Mac, open TestFlight, install or update the separately processed Mac build 12, launch it, and complete the Mac rows in the required functional test table.
7. Record the independent iOS and Mac App Store Connect statuses, exact TestFlight API fields and values, selected builds, tester groups, and actual device testing in \`docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md\`.

An internal tester can receive the build as soon as it processes. External testers need TestFlight beta review first. This TestFlight upload does not submit the app to App Review.

## App Store Connect Preparation

Use \`docs/APP_STORE_SUBMISSION_PACKET.md\` as the paste-ready source for:

- Product page metadata, price, category, marketing, support, privacy, and Terms URLs, plus the Standard-EULA choice.
- App Privacy, age rating, export-compliance, copyright, primary language, availability, DSA trader status, App Review contact, and review notes.
- The canonical 13-file screenshot package under \`build/app-store-screenshots/final/\`: four iPhone, four iPad, four Mac, and one Watch image. The August 6 local set passed full-size visual inspection but lacks final exact-build provenance and cannot be uploaded. Recapture it from the clean published source, generate `CAPTURE_RECEIPT.json`, repeat the visual review, and bind the receipt hash, screenshot hashes, and published commit in \`FINAL_VISUAL_QA.md\`.

Before public submission, add a dedicated monitored public support email or telephone number chosen by the release owner, then verify the public Support, Privacy, and Terms pages accurately describe the submitted build's on-device Profile, no in-app form collection, deletion controls, direct contact method, and public GitHub support route. Confirm both contact channels are monitored, leave the custom-EULA field blank so Apple's Standard EULA applies, and record the dated three-URL truthfulness verification in the signoff.

## Mac And Watch Distribution

- The iOS TestFlight archive embeds the Watch companion, so the Watch update arrives with the iPhone build.
- Mac Catalyst uses its own signed archive/upload and the selected separate Mac App Store Connect record for \`com.rupayonhaldar.gtafreestem.maccatalyst\`, with its own Mac App ID, SKU, primary language, agreements, team access, processed build, and delivery UUID. Do not try to add that Mac build to the iOS record \`6779714459\`.
- Do not change the current Mac candidate to the universal iOS bundle ID. Such a strategy change requires a new bundle ID configuration, archive, export, signature verification, screenshot package, and signoff.
- Preserve the four Mac 16:10 images and one Apple Watch Series 11 image together with the eight iPhone/iPad images only after the source-bound receipt and final visual approval are complete. Any recapture invalidates both `CAPTURE_RECEIPT.json` and \`FINAL_VISUAL_QA.md\` and requires a new receipt plus all-platform review before upload.

After the separate Mac record and signing assets exist, archive and create a safe local export first:

\`\`\`bash
ARCHIVE_PATH="$PWD/build/GTAFreeSTEM-Mac-build12.xcarchive" \
  bash docs/scripts/archive-release-candidate.sh mac

bash docs/scripts/verify-mac-app-store-archive.sh \
  build/GTAFreeSTEM-Mac-build12.xcarchive

xcodebuild -exportArchive \
  -archivePath build/GTAFreeSTEM-Mac-build12.xcarchive \
  -exportOptionsPlist docs/AppStoreExportOptions.plist \
  -exportPath build/export-mac-build12 \
  -allowProvisioningUpdates

bash docs/scripts/verify-mac-app-store-pkg.sh \
  build/export-mac-build12/GTAFreeSTEM.pkg \
  build/GTAFreeSTEM-Mac-build12.xcarchive
\`\`\`

The local export does not upload. The package verifier separately requires the Apple installer signature, Apple Distribution app signature, exact Mac App Store profile and sandbox entitlements, the same embedded source commit as the selected archive, safe script-free package layout, current resources, and executable/non-signing-content provenance. Only then upload that unchanged package and record its own Apple delivery UUID; it is never interchangeable with the iOS delivery UUID.

## Final App Review Gate

Only after real-device QA and portal work are complete:

\`\`\`bash
IOS_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-1.0-12.xcarchive \
  IOS_IPA_PATH=/absolute/path/to/GTAFreeSTEM-1.0-12.ipa \
  MAC_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-Mac-1.0-12.xcarchive \
  MAC_PKG_PATH=/absolute/path/to/GTAFreeSTEM.pkg \
  PUBLIC_RELEASE_PLATFORMS=iphone,ipad,watch,mac \
  bash docs/scripts/check-public-release-gates.sh
\`\`\`

Keep \`PUBLIC_RELEASE_PLATFORMS=iphone,ipad,watch,mac\` for this release. The generic gate deliberately has no default so future releases must state their scope, but the current Catalyst-enabled build rejects omission of any of these four platforms. It intentionally fails while the exact replacement artifacts are not current and verified; either the iOS/Watch or Mac product lacks its own processed/selected/TestFlight evidence; four-platform real-device evidence, screenshot visual-QA and upload evidence, metadata/privacy/age-rating/copyright/reviewer-contact/availability/DSA evidence, the production legal/support truthfulness check, separate real Apple delivery UUIDs, or a verified support route is pending. Do not mark \`Submitted for App Review\` complete until the final App Store Connect submit action is intentionally performed.
\`IOS_ARCHIVE_PATH\` must be the real signed export-source \`.xcarchive\`, and \`IOS_IPA_PATH\` must be the distribution-signed IPA exported from it. The pre-export gate permits only an exact identifier or a trusted namespace-scoped terminal development wildcard such as \`FE33NM88XX.com.rupayonhaldar.*\`; it rejects the team-wide \`FE33NM88XX.*\` form, and the signed entitlement must always remain exact. The IPA gate never accepts wildcards: it rejects development/ad-hoc signing, debug entitlements, mismatched identifiers or teams, expired or enterprise/device profiles, wrong signing certificates, stale resources, unsafe ZIP layouts, and archive-to-IPA UUID drift. The Watch companion receives the capped saved-opportunity set and archive status through WatchConnectivity and does not independently request or bundle the public feed. The current four-platform scope also requires both exact Mac artifacts and a separate Mac delivery UUID.

The signoff's canonical paths, deterministic archive tree hashes, IPA/package file hashes, verification date, and full published source commit must match what the gate calculates. The signed archives and exported packages must embed that same commit in \`GTAReleaseSourceCommit\`. The recorded commit must be reachable from live \`origin/main\`, and its app, Watch, Xcode project, and \`project.yml\` inputs must byte-match both live main and the local verification inputs. `CAPTURE_RECEIPT.json` must reproduce that source tree, identify source-embedded iOS, Watch, and Mac executables, and hash-match the canonical manifest and all 13 JPEGs. This allows later docs-only signoff commits without weakening source provenance; descriptive prose alone cannot satisfy artifact or screenshot provenance.

## Cost Constraint

Xcode simulator and personal-device development testing can be free. Team \`FE33NM88XX\` currently has an active Apple Developer Program membership through June 10, 2027, so this release needs no additional Apple membership purchase now. Future TestFlight and App Store distribution still require an active enrolled team unless Apple approves a fee waiver for an eligible nonprofit, accredited educational institution, or government entity. There is no compliant free-account workaround for distribution after membership expires.
