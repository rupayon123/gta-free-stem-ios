# TestFlight Guide

This guide covers the current GTA FREE STEM build, 1.0 (12).

## Prerequisites

- The selected Apple team must be enrolled in the Apple Developer Program or have an approved eligible fee waiver.
- The App Store Connect app record must use `com.rupayonhaldar.gtafreestem` and have upload permission for the release owner.
- Xcode Settings > Accounts must show team `FE33NM88XX`; keep automatic signing enabled.

A free Apple account can install a development build on a connected personal device, but TestFlight distribution requires Program eligibility.

## Immediate Direct Install On Your Own Phone

This is the no-upload path for seeing a source change on a connected iPhone or iPad. It is useful while TestFlight is unavailable, but it is a local development install and does not distribute an update to other devices.

1. Connect the phone to this Mac, unlock it, and accept the Trust prompt.
2. In Xcode, make sure the configured Apple team can development-sign `com.rupayonhaldar.gtafreestem`. Do not change the bundle ID just to get past signing; that would create a different app identity.
3. Get the exact device UUID with `xcrun devicectl list devices`.
4. From the iOS repository, run:

```bash
DEVICE_ID=<your-device-uuid> \\
ALLOW_PROVISIONING_UPDATES=1 \\
bash docs/scripts/install-connected-device.sh
```

The opt-in provisioning flag may register the selected device and create or refresh development provisioning under the Apple team already configured in Xcode. Use it only for a team and phone you control. Depending on the installed Xcode/CoreDevice version, the script accepts the selected device as `connected` or `available`; if it says `unavailable`, reconnect/unlock/trust it before building. It builds, installs, and launches the app; it never uploads, submits, or changes App Store Connect. If you prefer, select the connected phone in Xcode and press Run instead.

## Archive, Verify, And Upload

```bash
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
```

The helper first proves the app, Watch, Xcode project, and `project.yml` bytes match one exact Git commit, then embeds that commit in both signed bundles. The first verifier establishes that the archive is a trusted export source and checks that provenance. With automatic signing, that archive is normally Apple Development signed; its signed main and Watch entitlements must use the exact identifiers. Only a namespace-scoped terminal wildcard such as `FE33NM88XX.com.rupayonhaldar.*` may appear inside a development provisioning profile; the team-wide `FE33NM88XX.*` form is rejected. No wildcard is accepted as final distribution evidence.

`docs/AppStoreExportOptions.plist` uses `destination=export`, so the export is local and does not upload. The IPA verifier then requires Apple Distribution signing, exact main and Watch App Store profiles, the expected team, unexpired signing material, `get-task-allow=false`, current resources, and matching Mach-O UUIDs from the verified archive. Only an IPA that passes that verifier is the release distributable.

Uploading is a separate, irreversible action. Deliver that exact verified IPA with Apple's Transporter app, or with authenticated `xcrun altool --upload-package`; never put an app-specific password directly on the command line. Record the structured canonical archive/IPA paths and hashes, full published commit, current verification date, and resulting iOS delivery UUID in `docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md`. Do not rebuild, re-export, or upload a different IPA between verification and delivery.

If automatic signing fails, fix the reported Apple account/team/certificate/profile issue in Xcode rather than forcing a signing identity in the project.

## Get The Update On Your Phone

After App Store Connect shows build 12 as processed:

1. In App Store Connect > TestFlight, make sure your Apple ID is in an internal tester group. After build 12 finishes processing, add that build to the same group; adding a tester to the group alone does not make a build installable.
2. On your iPhone, open the TestFlight app, pull to refresh, and tap Update beside GTA FREE STEM.
3. Open the app once online, then follow `docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md`.
4. Use TestFlight screenshots and notes for feedback; the app's Support tab does not send forms online.

Internal testers can test after processing. External testers require beta review or a public TestFlight link.

## What Reaches Your Phone

- Opportunity and source-data updates can appear in the installed app after the public feed is refreshed and the app performs its next online refresh. The app deliberately bypasses HTTP cache when it checks the feed, opens from the latest usable local cache or bundled snapshot, and refreshes the public feed in the background. If neither local source is usable, the bounded launch preparation still hands off to the app, which presents its honest loading or error state while attempting the live refresh.
- Product-code changes—including new UI, bug fixes, bundled data, entitlements, or privacy changes—do **not** reach an installed app from a Git push alone. They require a new signed archive, App Store Connect processing, and a TestFlight **Update** on the phone.
- TestFlight can notify you about a processed build, but turn on automatic updates in TestFlight if you want eligible updates installed without manually tapping **Update**. Always open the new build once online before testing offline behaviour.

## What To Test

```text
Please test the launch handoff, search, filters, list/map mode, details, links, local saves, local profile deletion, refresh, cache and offline fallback, language switching, Dynamic Type, dark mode, and VoiceOver. Confirm the launch progress never restarts and reaches 100% immediately before browsing appears. If \`watch\` is selected for public distribution, also test the Watch companion. Report duplicate results, stale data, broken links, permission problems, untranslated UI, visual overlap, blank loading screens, or crashes through TestFlight feedback.
```

## App Review Is Separate

TestFlight availability does not submit the app to App Review. Complete `docs/APP_STORE_SUBMISSION_PACKET.md`, fresh platform screenshots, and real-device QA first. Submit only after the release owner intentionally chooses to do so.
