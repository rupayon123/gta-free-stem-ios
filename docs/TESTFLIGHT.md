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

1. In Xcode, choose `Any iOS Device` as the run destination.
2. Go to Product > Archive.
3. When Organizer opens, choose Distribute App.
4. Select App Store Connect, then Upload.
5. Let Xcode manage signing unless you have a reason to use manual signing.
6. Wait for App Store Connect processing to finish.

Command-line archive check:

```bash
xcodebuild archive -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -configuration Release -destination 'generic/platform=iOS' -archivePath build/GTAFreeSTEM.xcarchive -allowProvisioningUpdates
```

If this fails with `No Accounts` or `No profiles`, open Xcode > Settings > Accounts, add the Apple Developer account, choose team `FE33NM88XX`, and allow automatic signing for `com.rupayonhaldar.gtafreestem`.

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

- Search by city, age, category, and high-school pathway.
- Search with multi-word terms like `robotics Toronto`, then switch sort between best match, soonest, and nearest.
- Apply and reset filters for program language, volunteer hours, co-op/SHSM, mentorship, scholarships, equity focus, and new finds.
- Try nearby search and deny location permission once to confirm the fallback is clear.
- Refresh repeatedly and confirm the app does not duplicate results, freeze, or show conflicting loading states.
- Open the app offline after one successful refresh and confirm saved results still appear.
- Switch language and dark mode.
- Check Arabic, Farsi/Persian, or Urdu for right-to-left layout.
- Open list and map views.
- Turn on VoiceOver and confirm opportunity rows, map pins, filters, detail facts, and form buttons are understandable.
- Tap a listing and check readability with large Dynamic Type.
- Try saving while signed out and confirm the account prompt is clear.
- Submit feedback and a missing opportunity.
- Report any English text that still appears in app UI controls or system prompts.
- Report opportunity content that remains English after switching languages; dynamic listing translations require the public feed to provide translated payloads.
- Confirm the support URL and privacy policy URL open from App Store Connect metadata.

## Cost Control

Use manual uploads and small tester groups at first. Xcode Cloud can be added later, but local archives plus App Store Connect are enough for the first TestFlight builds.
