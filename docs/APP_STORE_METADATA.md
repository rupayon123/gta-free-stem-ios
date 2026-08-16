# App Store Metadata Draft

Last updated: August 6, 2026

This is the source of truth for the GTA FREE STEM 1.0 (12) product page. Review it again if the app adds a server account, analytics, a feedback form, or any data collection.

## App Information

- App name: GTA FREE STEM
- Bundle ID: \`com.rupayonhaldar.gtafreestem\`
- Mac Catalyst bundle ID: \`com.rupayonhaldar.gtafreestem.maccatalyst\`
- Watch bundle ID: \`com.rupayonhaldar.gtafreestem.watchkitapp\`
- SKU suggestion: \`gta-free-stem-ios\`
- Copyright draft: \`2026 Rupayon Haldar\` (from \`LICENSE\`; confirm the legal-rights holder before saving this public field).
- Primary language: Pending owner confirmation in App Store Connect. It controls the product-page fallback language and is not automatically chosen from the app's 18 UI languages.
- Availability: Pending the owner's territory selection in Pricing and Availability.
- Digital Services Act (DSA) status: Pending App Store Connect trader-status self-assessment. Complete it even when the app is not distributed in the EU; do not commit any private trader contact details.
- Primary category: Education
- Subtitle suggestion: Youth programs near you
- Price: Free
- Content rights: The app displays source-backed public opportunity listings and links to the original provider for registration.
- Encryption: \`ITSAppUsesNonExemptEncryption\` is \`false\`; the app uses standard HTTPS/TLS only.

## Description Draft

GTA FREE STEM helps students, families, educators, and community groups find free STEM opportunities across the Greater Toronto Area.

Search by keyword, city, region, age, category, language, high-school pathway, distance, volunteer hours, co-op, mentorship, scholarships, and new finds. Browse in list or map view, open the original provider link, and save opportunities and a recent hunt on your device.

The app refreshes from a public, source-backed opportunity feed. If the network is unavailable, it opens with the latest on-device cache or bundled snapshot so discovery can continue. Nearby search uses location only on the device to sort or filter results.

No sign-in is required. A profile name and saved opportunities stay on the device and can be deleted in Settings.

## Keywords Draft

Toronto,robotics,coding,science,engineering,math,volunteer,coop,SHSM,mentorship,scholarships

## Metadata Limit Notes

- App name: 13/30 characters.
- Subtitle: 23/30 characters.
- Keywords: 92/100 bytes.
- Description: under the 4,000-character App Store Connect limit.

## Supported Platforms

- iPhone and iPad: native SwiftUI app distributed through the iOS upload.
- Mac: Mac Catalyst app distributed as the selected separate Mac App Store product \`com.rupayonhaldar.gtafreestem.maccatalyst\`, with its own Mac App ID, SKU, upload, processed build, and delivery UUID.
- Apple Watch: companion app embedded in the iOS upload. It shows a capped set of saved opportunities and archive status synced from the iPhone; it does not independently request or cache the public feed.

App Store Connect needs the matching platform enabled and its screenshots uploaded before public submission.

The build 1.0 (12) public-distribution set is \`iphone,ipad,watch,mac\`. The generic release gate still has no default and requires that exact current-release value to be supplied explicitly.

## Support, Privacy, Terms, And EULA URLs

- Marketing URL: \`https://gta-free-stem.vercel.app/\`
- Support URL: \`https://gta-free-stem.vercel.app/support/\`
- Privacy policy URL: \`https://gta-free-stem.vercel.app/privacy/\`
- Terms of Use URL: \`https://gta-free-stem.vercel.app/terms/\`
- Custom EULA field: Leave blank for this release. Apple's Standard EULA applies automatically: \`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/\`.

The no-cost Support route uses a public GitHub issue tracker for non-sensitive tickets. Apple also requires the Support URL to expose actual contact information. Before deployment, add a dedicated monitored public support email or telephone number chosen by the release owner; do not invent or publish a private value from source control. Keep Issues enabled, monitor both channels while the release is available, and preserve the warning not to post private or child information. Before the final gate, open the actual production Support, Privacy, and Terms URLs and verify that all three accurately describe the submitted build's local-only Profile, data flows, deletion controls, and lack of in-app submission collection. Record that dated, three-URL truthfulness check in \`Production legal/support truthfulness verified\` in the real-device signoff. See \`docs/APP_STORE_SUBMISSION_PACKET.md\` for the reviewer wording.

## App Privacy Answers

Use these answers only for build \`1.0 (12)\` as implemented.

- Tracking: No.
- Data linked to the user: Coarse Location and Other Diagnostic Data from retained feed-request records.
- Data used to track the user: None.
- Data collection: Yes. Conservatively disclose Coarse Location and Other Diagnostic Data for App Functionality and Analytics because GitHub and jsDelivr receive request IP addresses and technical request details and may retain them for delivery, security, diagnostics, service analytics, and improvement.
- Advertising, purchases, third-party analytics, and crash-reporting SDKs: No.
- Profile name, saved opportunities, hunt state, cached public listings, and seen-listing IDs: stored only on the device with SwiftData/UserDefaults.
- Precise device location: not collected. Nearby search uses a one-time device location locally and does not transmit it to the public feed. The separate Coarse Location disclosure covers general location that a feed provider may infer from the request IP address.
- Notifications: not collected. The user may opt into a local, on-device new-opportunity alert; no remote push token, service, or notification analytics is used.
- Privacy manifests: the iOS/iPadOS/Mac Catalyst manifest declares Coarse Location and Other Diagnostic Data, linked, for Analytics and App Functionality, with tracking disabled. The Watch companion has no independent public-feed request and declares no collected data.
- Required-reason API: UserDefaults, reason \`CA92.1\`, declared in both the iOS and Watch privacy manifests.

These answers treat on-device-only processing as not collected while conservatively disclosing retained network-provider request data. Immediately before submission, reconfirm every endpoint, provider practice, SDK, and privacy-manifest entry. If the build later sends profile, precise location, feedback, submission, diagnostic, or telemetry data off-device, redo the App Privacy questionnaire, policy, and manifests before upload.

## Age Rating Notes

The app is intended for families and students. It has no ads, purchases, gambling, public chat, public user-generated-content feed, unrestricted web browser, or mature-content feature. Listings can link to third-party provider pages; answer the App Store Connect external-link questions for the actual submitted build.

## Made For Kids / Kids Category

- Made for Kids: Select **No** for release \`1.0 (12)\`.
- Do not place this release in the Kids Category and do not use “For Kids” or “For Children” in App Store metadata.
- This is a general-audience education directory for students, parents, caregivers, educators, and community groups. It opens external provider and map links without a parental gate, and its feed providers receive the limited network request data disclosed above.
- A future Kids Category release requires a separate product and legal review, parental gates for external links, child-specific privacy analysis, and compatible network-provider practices before the setting is changed. Apple warns that an approved Kids Category selection creates continuing requirements for later updates.

## Dynamic Content And Reliability Notes

- Primary live feed: \`https://raw.githubusercontent.com/rupayon123/gta-free-stem-opportunities/main/public/opportunities.json\`.
- The release gate reports the current entry count and timestamp for both the live feed and bundled fallback. Run \`docs/scripts/sync-bundled-feed.sh\` and \`docs/scripts/check-release-readiness.sh\` immediately before upload; both feeds are rejected when older than 14 days.
- Every remote source, including the primary feed and jsDelivr CDN mirror, is rejected unless it declares data no more than 14 days old.
- The app opens from the latest valid local cache or bundled snapshot when available, refreshes the live feed on each cold launch, and revalidates active foreground content after 15 minutes. If neither local source is usable, the interactive app—not the branded loader—shows the live loading or error state so launch cannot become trapped behind a network timeout.
- Seen-listing records are pruned after 120 days and known-ID tracking is capped, avoiding unbounded local growth.

## Screenshot Notes

Apple accepts one to ten \`.jpeg\`, \`.jpg\`, or \`.png\` screenshots per required device display set, with no alpha channel. Generate release assets with:

\`\`\`bash
bash docs/scripts/capture-app-store-screenshots.sh
bash docs/scripts/capture-watch-app-store-screenshot.sh
\`\`\`

All 13 upload assets live under \`build/app-store-screenshots/final/\`: four iPhone, four iPad, four Retina-captured 16:10 Mac, and one Watch screenshot. The current local files passed structural checks and full-size visual inspection on August 6, 2026, but they are not release-signoff assets because they lack the clean-source capture receipt and one predates the final Watch edit. Recapture the entire set from the published source, generate `CAPTURE_RECEIPT.json`, repeat visual QA, and bind the receipt plus final image hashes in \`FINAL_VISUAL_QA.md\` before upload. Exact paths and review criteria are in \`docs/APP_STORE_SCREENSHOTS.md\`.

## App Review Information

- Reviewer contact: enter the release owner’s monitored name, email, and phone in App Store Connect. Do not commit those private details; record \`Verified in App Store Connect on YYYY-MM-DD\` in the real-device signoff.
- Demo account: not required. Core review requires no login.
- Mac record: the separate-record strategy is selected. Before upload, verify the real Mac App ID and SKU for \`com.rupayonhaldar.gtafreestem.maccatalyst\` in App Store Connect and record them in \`docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md\`.

## Before Submission

1. Upload and wait for TestFlight processing of build \`1.0 (12)\`.
2. Complete the App Privacy, age-rating, Made for Kids = No, availability, export-compliance, copyright, primary-language, DSA-status, and App Review contact forms using this file and the submission packet.
3. Create and verify the selected separate Mac App Store record, Mac App ID, and SKU for \`com.rupayonhaldar.gtafreestem.maccatalyst\`.
4. Recapture all 13 canonical JPEGs from the clean published commit, generate and verify `CAPTURE_RECEIPT.json`, repeat the full-size review, bind the receipt and image hashes in \`FINAL_VISUAL_QA.md\`, then upload those exact iPhone, iPad, Watch, and Mac files.
5. Record real-device QA on iPhone, iPad, paired Watch, and Mac plus the production Support/Privacy/Terms truthfulness check in \`docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md\`.
6. Submit only after \`IOS_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-1.0-12.xcarchive IOS_IPA_PATH=/absolute/path/to/GTAFreeSTEM-1.0-12.ipa MAC_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-Mac-1.0-12.xcarchive MAC_PKG_PATH=/absolute/path/to/GTAFreeSTEM.pkg PUBLIC_RELEASE_PLATFORMS=iphone,ipad,watch,mac bash docs/scripts/check-public-release-gates.sh\` passes for the verified iOS and Mac artifacts.
