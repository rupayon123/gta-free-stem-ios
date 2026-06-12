# TestFlight Sharing Guide

Use this when you are ready to let friends test the iOS app through your Apple Developer Program membership.

## One-Time Setup

1. Open `GTAFreeSTEM.xcodeproj` in Xcode.
2. Select the `GTAFreeSTEM` target.
3. Set the bundle identifier to `com.rupayonhaldar.gtafreestem`.
4. Under Signing & Capabilities, choose your Apple Developer Team and keep automatic signing on.
5. In App Store Connect, create an app record named `GTA FREE STEM`.
6. Add the support URL, privacy policy URL, age rating, category, and App Privacy answers.

## Upload A Build

1. In Xcode, choose `Any iOS Device` as the run destination.
2. Go to Product > Archive.
3. When Organizer opens, choose Distribute App.
4. Select App Store Connect, then Upload.
5. Let Xcode manage signing unless you have a reason to use manual signing.
6. Wait for App Store Connect processing to finish.

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
- Try nearby search and deny location permission once to confirm the fallback is clear.
- Switch language and dark mode.
- Open list and map views.
- Tap a listing and check readability.
- Try saving while signed out and confirm the account prompt is clear.
- Submit feedback and a missing opportunity.
- Report any English text that still appears in app UI controls or system prompts.

## Cost Control

Use manual uploads and small tester groups at first. Xcode Cloud can be added later, but local archives plus App Store Connect are enough for the first TestFlight builds.
