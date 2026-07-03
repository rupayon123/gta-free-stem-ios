# TestFlight Sharing Guide

Use this when you are ready to let friends test the iOS app through your Apple Developer Program membership.

## One-Time Setup

1. Open `GTAFreeSTEM.xcodeproj` in Xcode.
2. Select the `GTAFreeSTEM` target.
3. Set the bundle identifier to `com.rupayonhaldar.gtafreestem`.
4. Under Signing & Capabilities, choose your Apple Developer Team and keep automatic signing on.
5. In App Store Connect, create an app record named `GTA FREE STEM`.
6. Add the support URL, privacy policy URL, age rating, category, and App Privacy answers.
7. Use `docs/APP_STORE_METADATA.md` as the metadata/privacy draft.

## Upload A Build

1. Increment `CURRENT_PROJECT_VERSION` in both `project.yml` and `GTAFreeSTEM.xcodeproj/project.pbxproj`.
2. In Xcode, choose `Any iOS Device` as the run destination.
3. Go to Product > Archive.
4. When Organizer opens, choose Distribute App.
5. Select App Store Connect, then Upload.
6. Let Xcode manage signing unless you have a reason to use manual signing.
7. Wait for App Store Connect processing to finish.
8. Confirm the processed TestFlight build number matches the repo build number.

Command-line archive and upload:

```bash
xcodebuild archive -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -configuration Release -destination 'generic/platform=iOS' -archivePath build/GTAFreeSTEM.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/GTAFreeSTEM.xcarchive -exportOptionsPlist docs/AppStoreConnectExportOptions.plist -exportPath build/export -allowProvisioningUpdates
```

Use `docs/AppStoreConnectExportOptions.plist` for command-line uploads. It disables Xcode's automatic App Store Connect build-number management so the uploaded package uses the exact `CFBundleVersion` from the repo.

Keep automatic signing on for local archives. With the current Apple account setup, Xcode creates a development-signed archive and the App Store Connect export step re-signs the uploaded payload with Apple Distribution and release entitlements. Forcing `CODE_SIGN_IDENTITY = Apple Distribution` in the project conflicts with that automatic signing path.

If this fails with `No Accounts` or `No profiles`, open Xcode > Settings > Accounts, add the Apple Developer account, choose team `FE33NM88XX`, and allow automatic signing for `com.rupayonhaldar.gtafreestem`.

Check App Store Connect processing status from the command line after upload:

```bash
bash docs/scripts/check-testflight-build-status.sh
```

The status check uses app Apple ID `6779714459`, current repo build number, platform `ios`, and provider `4bfabe71-697b-4d97-bc76-4c8d5be25591` by default. It requires either `APP_STORE_CONNECT_API_KEY` plus `APP_STORE_CONNECT_API_ISSUER`, or a saved app-specific password keychain item:

```bash
xcrun altool --store-password-in-keychain-item --item GTA_FREE_STEM_ASC \
  -u rupayon244@gmail.com -p '<app-specific-password>'
APP_STORE_CONNECT_USERNAME=rupayon244@gmail.com \
  APP_STORE_CONNECT_KEYCHAIN_ITEM=GTA_FREE_STEM_ASC \
  bash docs/scripts/check-testflight-build-status.sh
```

If macOS stalls while releasing the saved Keychain secret, the script times out that local read after 8 seconds and falls back to altool's normal `@keychain:` lookup. You can change that with `APP_STORE_CONNECT_KEYCHAIN_SECRET_TIMEOUT=0` to wait indefinitely, or use a one-off app-specific password without storing it:

```bash
read -r -s APP_STORE_CONNECT_APP_PASSWORD
export APP_STORE_CONNECT_APP_PASSWORD
BUNDLE_VERSION=10 \
  DELIVERY_ID=97c05d63-7f3d-45bc-941e-c10432694ca8 \
  APP_STORE_CONNECT_USERNAME=rupayon244@gmail.com \
  bash docs/scripts/check-testflight-build-status.sh
unset APP_STORE_CONNECT_APP_PASSWORD
```

If the command says `Failed to find item GTA_FREE_STEM_ASC for user ... in keychain`, the saved item is not usable by altool's `@keychain:` lookup. Use the one-off app-specific password pattern above, re-run the `--store-password-in-keychain-item` command with a fresh app-specific password, or switch to App Store Connect API-key auth.

Do not use or store the normal Apple ID password for this command.

## Internal Testers

Internal testers are the easiest first step.

1. In App Store Connect, open the app.
2. Go to TestFlight.
3. Add internal testers from Users and Access.
4. Select the processed build.
5. Send invites.

Internal testers usually do not need beta review.

## External Friends

External testing is what you use for friends outside your developer account.

1. In TestFlight, create an external tester group.
2. Add your friends by email, or create a public TestFlight link after beta review.
3. Fill in beta app review information, including contact info, demo notes, and what testers should try.
4. Submit the build for beta review.
5. After approval, send the TestFlight invite or public link.

Friends install Apple’s TestFlight app, open the invite, install GTA FREE STEM, and send feedback through TestFlight screenshots or notes.

## What To Ask Friends To Test

Paste this into the TestFlight "What to Test" field:

```text
Please test the full discovery flow: keyword search, city/region/age/language/category filters, high-school pathway filters, map/list switching, sorting, detail pages, refresh, offline fallback, saved hunt restore, language switching, RTL layout, Dynamic Type, dark mode, and VoiceOver. Report any duplicate results, stale updates, broken links, untranslated UI, untranslated opportunity content, confusing permission prompts, or crashes.
```

- Search by city, age, category, and high-school pathway.
- Search with multi-word terms like `robotics Toronto`, then switch sort between best match, soonest, and nearest.
- Apply and reset filters for program language, volunteer hours, co-op/SHSM, mentorship, scholarships, equity focus, and new finds.
- Try nearby search and deny location permission once to confirm the fallback is clear.
- Refresh repeatedly and confirm the app does not duplicate results, freeze, or show conflicting loading states.
- Open the app offline after one successful refresh and confirm saved results still appear.
- Switch language and dark mode.
- Check Arabic, Farsi/Persian, or Urdu for right-to-left layout.
- Open list and map views.
- Turn on VoiceOver and confirm opportunity rows, map pins, filters, detail facts, and support/account-limited controls are understandable.
- Tap a listing and check readability with large Dynamic Type.
- Try account-only actions and confirm the app clearly says account features are not available in this build.
- Confirm the Support tab does not collect name, email, message, or missing-opportunity details while the online backend is unavailable for this build.
- Send tester feedback through TestFlight unless a future build connects an online backend and updates App Privacy answers.
- Report any English text that still appears in app UI controls or system prompts.
- Report opportunity content that remains English after switching languages; dynamic listing translations require the public feed to provide translated payloads.
- Confirm the support URL and privacy policy URL open from App Store Connect metadata.

## Cost Control

Use manual uploads and small tester groups at first. Xcode Cloud can be added later, but local archives plus App Store Connect are enough for the first TestFlight builds.
