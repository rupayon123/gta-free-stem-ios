# App Store Connect Submission Packet

Last updated: August 6, 2026

Use this packet to prepare App Store Connect for GTA FREE STEM build 1.0 (12). It is deliberately honest about upload and review state: do not invent a delivery UUID, build status, tester invite, or App Review submission.

## Build Pending Rebuild, Upload, And Selection

- App: \`GTA FREE STEM\`
- Apple app ID: \`6779714459\`
- Team: \`FE33NM88XX\`
- iOS/iPad bundle ID: \`com.rupayonhaldar.gtafreestem\`
- Mac Catalyst bundle ID: \`com.rupayonhaldar.gtafreestem.maccatalyst\`
- Watch bundle ID: \`com.rupayonhaldar.gtafreestem.watchkitapp\`
- Version: \`1.0\`
- Build: \`12\`
- iOS archive status: \`Previous artifact superseded by current source changes; replacement pending rebuild\`
- iOS IPA status: \`Previous artifact superseded by current source changes; replacement pending rebuild and export\`
- Mac archive status: \`Previous artifact superseded by current source changes; replacement pending rebuild\`
- Mac package status: \`Previous artifact superseded by current source changes; replacement pending rebuild and export\`
- iOS Delivery UUID: \`Pending upload\`
- Mac Delivery UUID: \`Pending upload\`
- Public distribution platforms: \`iphone,ipad,watch,mac\`
- Mac record strategy: \`Separate Mac App Store record selected for com.rupayonhaldar.gtafreestem.maccatalyst; portal Mac App ID and SKU pending\`
- Screenshot status: \`13 local files passed structural and full-size visual inspection 2026-08-06; clean-source exact-build recapture, CAPTURE_RECEIPT.json, repeated visual QA, and source-bound manifest pending\`
- iOS App Store Connect status: \`Not uploaded\`
- iOS TestFlight status: \`Not uploaded\`
- Mac App Store Connect status: \`Not uploaded\`
- Mac TestFlight status: \`Not uploaded\`
- App Review status: \`Not submitted\`
- Encryption: \`usesNonExemptEncryption = false\`
- Price: \`Free\`

After Xcode uploads and App Store Connect processes the build, replace the pending fields with observed values. Do not upload until the release owner explicitly authorizes it; App Review is a separate, later decision.

Local archive/export evidence is deliberately not upload evidence. The prior published-source iOS export-source archive is \`build/final-release-ios-20260806-r6-published-source.xcarchive\`. It embeds source commit \`42c138436ece43ecca120ff76edbf1c4f90b17ff\`, is development-signed, and passed 52/52 pre-export checks for that older source. Current app and Watch changes supersede it.

The prior distribution export is \`build/final-release-ios-20260806-r6-export/GTAFreeSTEM.ipa\` with SHA-256 \`8cf97134ce8985f1a9ca62c6dd52cb1680e876ca7a56eafe6ee31cdd901081eb\`. It passed 62/62 strict IPA checks for commit \`42c138436ece43ecca120ff76edbf1c4f90b17ff\`, but it is now superseded and must not be uploaded. Rebuild and reverify a replacement from the committed current source.

The prior Mac Catalyst archive is \`build/final-release-mac-20260806-r3-published-source.xcarchive\`; it embeds source commit \`42c138436ece43ecca120ff76edbf1c4f90b17ff\` and passed 36/36 checks. Its prior package is \`build/final-release-mac-20260806-r3-export/GTAFreeSTEM.pkg\`, SHA-256 \`b9afd175d605ea9ba588702d92df71a31044714cf893ad9633cff126f1320f34\`, and passed 48/48 checks. Both are superseded and must not be uploaded. The replacement still belongs to the selected separate Mac product \`com.rupayonhaldar.gtafreestem.maccatalyst\`; its record, App ID, SKU, processed build, and delivery UUID remain pending.

The superseded source commit \`42c138436ece43ecca120ff76edbf1c4f90b17ff\` passed 108/108 tests in \`build/DerivedData-final-tests-source-provenance-20260806/Logs/Test/Test-GTAFreeSTEM-2026.08.06_16-54-57--0400.xcresult\`. Keep that as historical evidence only. Do not select it or the older archives at \`build/Unsigned-iOS-build12.xcarchive\`, \`build/GTAFreeSTEM-1.0-12.xcarchive\`, or \`build/GTAFreeSTEM.xcarchive\`. Root will replace the commit, test result, paths, hashes, and verifier totals after the current source is committed and rebuilt.

## Product Page Fields

- Name: \`GTA FREE STEM\`
- Subtitle: \`Youth programs near you\`
- Primary category: \`Education\`
- SKU: \`gta-free-stem-ios\`
- Copyright draft: \`2026 Rupayon Haldar\` (from \`LICENSE\`; the legal-rights holder must confirm this exact App Store Connect value before it is entered).
- Primary language: Pending confirmation in the existing App Store Connect record. Select the language that should act as the storefront fallback; do not infer it from the binary's localizations.
- Availability: Pending the release owner's deliberate territory selection in Pricing and Availability.
- Digital Services Act (DSA) status: Pending the release owner's App Store Connect self-assessment. Apple asks for this status even if the app will not be distributed in the EU.
- Marketing URL: \`https://gta-free-stem.vercel.app/\`
- Support URL: \`https://gta-free-stem.vercel.app/support/\`
- Privacy policy URL: \`https://gta-free-stem.vercel.app/privacy/\`
- Terms of Use URL: \`https://gta-free-stem.vercel.app/terms/\`
- Custom EULA: Leave the App Store Connect custom-EULA field blank. Apple's Standard EULA applies: \`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/\`.
- Content rights: The app aggregates source-backed public opportunity listings and links to original providers for registration.

Before the final release gate, the release owner must choose a dedicated monitored public support email or telephone number and publish it on the Support page; do not infer or commit a private value. Open the actual production Support, Privacy, and Terms URLs. Confirm that each page accurately describes the submitted build's on-device-only Profile, lack of in-app feedback/submission collection, deletion controls, direct contact method, and public GitHub support route. Confirm that GitHub Issues is enabled and receives a test ticket without sensitive information. Record a dated verification with all three distinct HTTPS URLs in the real-device signoff's \`Production legal/support truthfulness verified\` field.

## Description

\`\`\`text
GTA FREE STEM helps students, families, educators, and community groups find free STEM opportunities across the Greater Toronto Area.

Search by keyword, city, region, age, category, language, high-school pathway, distance, volunteer hours, co-op, mentorship, scholarships, and new finds. Browse in list or map view, open the original provider link, and save opportunities and a recent hunt on your device.

The app refreshes from a public, source-backed opportunity feed. If the network is unavailable, it opens with the latest on-device cache or bundled snapshot so discovery can continue. Nearby search uses location only on the device to sort or filter results.

No sign-in is required. A profile name and saved opportunities stay on the device and can be deleted in Settings.
\`\`\`

## Keywords

\`\`\`text
Toronto,robotics,coding,science,engineering,math,volunteer,coop,SHSM,mentorship,scholarships
\`\`\`

## App Review Notes

\`\`\`text
GTA FREE STEM is a public discovery app for free STEM opportunities in the Greater Toronto Area.

No account is required to browse, search, filter, view details, switch languages, use map/list mode, or save an opportunity. The optional Profile is entirely on-device: it stores a display name locally, and Settings can delete that profile, saved opportunities, and personal hunt history.

The app loads the public opportunity feed from a GitHub-hosted JSON endpoint. At launch, it prepares a usable on-device cache or bundled snapshot when available, then lets the live refresh continue after the main interface appears. If no usable local snapshot exists, the branded loader still hands off after a bounded preparation checkpoint; the interactive app then shows the live loading or error state instead of trapping launch behind a network timeout. It validates every response and its declared age. The jsDelivr CDN mirror is only used when its declared content is no more than 14 days old.

GitHub and jsDelivr receive the request IP address and technical request details and may retain them for delivery, security, diagnostics, service analytics, and improvement. App Privacy therefore conservatively discloses linked Coarse Location and Other Diagnostic Data for App Functionality and Analytics, with tracking disabled. No local Profile, search, save, device location, advertising identifier, or GTA FREE STEM user ID is attached to the feed request.

The app may request location permission only after the user starts nearby search. Location is used locally to sort/filter nearby opportunities and is not sent to the public feed.

The app may request notification permission only after the user chooses to enable alerts. If allowed, an Apple-scheduled background refresh can create an on-device alert for newly found public listings; refresh timing is controlled by the operating system and is not guaranteed. There is no remote push token, notification service, account, or notification analytics.

Map pins are display-only; actions remain in the listing detail and external provider or directions links. The Watch companion displays a capped set of saved opportunities and archive status synced from the phone. It does not independently fetch the public feed or provide the full search and filter interface.

There is no login, advertising, purchase flow, in-app feedback form, or user-submitted-content flow in this build. The Support tab does not collect personal information.

The app uses standard HTTPS/TLS only and does not use non-exempt encryption.
\`\`\`

## Demo Account

- Demo account required: No.
- Login required for core review: No.
- Reviewer path: Launch the app, open Opportunities or High School, search and filter, switch list/map, open a listing, save it, create and delete a local Profile in Settings, then open Support.

## App Privacy Answers

Use these answers only for build \`1.0 (12)\`.

- Tracking: No.
- Data linked to the user: Coarse Location and Other Diagnostic Data from retained feed-request records.
- Data used to track the user: None.
- Data collection: Yes. Conservatively disclose Coarse Location and Other Diagnostic Data for App Functionality and Analytics because GitHub and jsDelivr receive request IP addresses and technical request details and may retain them.
- Account identifiers and contact info: No. The app has no online account or form submission.
- Precise device location: Not collected. A one-time nearby-search location stays on device. The Coarse Location disclosure covers general location inferred by a feed provider from a request IP address.
- Notifications: Not collected. Optional local alert permission and alert content stay on device; there is no remote push service.
- Diagnostics and analytics: No analytics or crash-reporting SDK. Other Diagnostic Data is disclosed for feed-provider request records used for delivery, security, diagnostics, service analytics, and improvement.
- Privacy manifests: the iOS/iPadOS/Mac Catalyst manifest declares Coarse Location and Other Diagnostic Data as linked, for Analytics and App Functionality, with tracking disabled. The Watch companion makes no independent public-feed request and declares no collected data.
- Required-reason API: UserDefaults, reason \`CA92.1\`, declared in the iOS and Watch \`PrivacyInfo.xcprivacy\` files.

If a future build sends profile, location, feedback, diagnostics, analytics, or submission data off-device, redo the App Privacy questionnaire before upload.

## Age Rating Notes

- Advertising and in-app purchases: No.
- Public chat, user-generated content, gambling, mature content, and unrestricted web access: No.
- External links: Provider registration/source links can open outside the app. Complete the current App Store Connect questionnaire against the submitted build.

## Made For Kids / Kids Category

- Select **No** for Made for Kids and do not submit release \`1.0 (12)\` to the Kids Category.
- This release is a general-audience education directory. External provider and map links are not behind a parental gate, and feed providers receive the limited request data disclosed in App Privacy.
- Do not use “For Kids” or “For Children” in the app name, subtitle, screenshots, or description. Reassess the product, parental gates, privacy, and network architecture before any future Kids Category submission.

## Platform Assets

Upload the following 13-file canonical package of visually reviewed JPEGs for the fixed \`iphone,ipad,watch,mac\` release scope. The package root is \`build/app-store-screenshots/final/\`:

- iPhone 6.9-inch: \`build/app-store-screenshots/final/iphone-6.9/01-home.jpg\` through \`04-profile.jpg\` at \`1320 x 2868\`.
- iPad 13-inch: \`build/app-store-screenshots/final/ipad-13/01-home.jpg\` through \`04-profile.jpg\` at \`2064 x 2752\`.
- Mac: \`build/app-store-screenshots/final/mac/01-home.jpg\` through \`04-profile.jpg\` at \`1440 x 900\`.
- Apple Watch Series 11: \`build/app-store-screenshots/final/watch-series-11/01-home.jpg\` at \`416 x 496\`.

The current files pass structural dimension/opacity checks and independent full-size visual QA. The reviewed set resolves the former data-state, iPad branding, Mac framing/sharpness, Watch truncation, and cross-tab query-state defects. Preserve these exact bytes, bind their hashes to the published source in the canonical manifest, and upload only that bound set. See \`docs/APP_STORE_SCREENSHOTS.md\`.

## TestFlight What To Test

\`\`\`text
Please test the discovery flow: keyword search; city, region, age, language, category, high-school, volunteer, co-op, mentorship, scholarship, equity, new-find, and distance filters; map/list switching; sorting; detail pages; saving; local profile creation/deletion; refresh; cache and offline fallback; language switching; Dynamic Type; dark mode; and VoiceOver. On a paired Watch, test the capped saved-opportunity set and archive status synced from the iPhone; the Watch app does not independently load the public feed. Report duplicate or stale results, broken links, permission problems, untranslated UI, visual overlap, or crashes through TestFlight feedback.
\`\`\`

## Portal Checklist

1. Confirm team \`FE33NM88XX\` remains active and that the Account Holder has accepted current agreements. The membership was verified active through June 10, 2027, so no additional Apple membership purchase is currently required.
2. Keep the recorded public platform selection at \`iphone,ipad,watch,mac\`. Create and verify the selected separate Mac App Store record for \`com.rupayonhaldar.gtafreestem.maccatalyst\`, including its Mac App ID and SKU. The Watch companion is included with the iOS upload. Do not switch the current Mac candidate to a universal record; that would require a bundle-ID change followed by a new archive, export, signature verification, screenshot set, and signoff.
3. Commit and publish the current source, rebuild all four bound artifacts, and replace the superseded commit, paths, hashes, test result, and verifier totals. Do not reuse the prior IPA or package.
4. Upload only the replacement deliverables after explicit authorization. Independently record the iOS and Mac delivery UUIDs, App Store Connect processing states, TestFlight states, and selected build 1.0 (12) only after Apple reports each product's values.
5. Enter the product page, App Privacy, age rating, availability, and export-compliance information above.
6. Add the release owner's chosen monitored public support email or telephone number, deploy the Support, Privacy, and Terms pages, confirm all three final HTTPS URLs in Safari, and verify that the public GitHub Issues route accepts a non-sensitive test ticket. Record the dated production truthfulness check in the signoff.
7. Set Made for Kids to No, complete the age-rating questionnaire, and enter the App Review Information contact name, email, and phone in App Store Connect. Keep those private values out of this repository; record only the verification date in the signoff.
8. Confirm the legal-rights holder and enter the exact Copyright value in App Store Connect.
9. Confirm the product-page primary language, select territories in Pricing and Availability, and complete the DSA trader-status self-assessment. Keep any private trader contact data out of this repository.
10. Recapture the canonical 13-file screenshot package from the clean published commit, generate and verify `CAPTURE_RECEIPT.json`, repeat the full-size review, bind the receipt hash and all 13 image hashes in \`FINAL_VISUAL_QA.md\`, record the manifest hash and pass, then upload the exact four iPhone, four iPad, four Mac, and one Watch images.
11. Add the release owner as an internal TestFlight tester, then record actual real-device evidence for iPhone, iPad, paired Apple Watch, and Mac in \`docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md\`.
12. Run \`IOS_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-1.0-12.xcarchive IOS_IPA_PATH=/absolute/path/to/GTAFreeSTEM-1.0-12.ipa MAC_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-Mac-1.0-12.xcarchive MAC_PKG_PATH=/absolute/path/to/GTAFreeSTEM.pkg PUBLIC_RELEASE_PLATFORMS=iphone,ipad,watch,mac bash docs/scripts/check-public-release-gates.sh\` only after TestFlight QA, Mac processing, screenshot QA/upload, and portal fields are complete.
13. Leave the custom-EULA field blank so Apple's Standard EULA applies, then submit for App Review only after explicit release confirmation.
