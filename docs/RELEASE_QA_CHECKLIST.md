# Release QA Checklist

Use this checklist for every GTA FREE STEM TestFlight upload. Record the actual real-device pass in \`docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md\` before App Review.

## Build Readiness

- Use the tracked \`GTAFreeSTEM.xcodeproj\` as the release input. If \`project.yml\` is intentionally regenerated with a separately installed XcodeGen, review the resulting project diff before release verification.
- Increment \`CURRENT_PROJECT_VERSION\` once, then confirm the iOS and Watch bundles agree.
- Run \`CHECK_APP_STORE_SCREENSHOTS=0 STRICT_TRANSLATION_CHECK=1 bash docs/scripts/check-release-readiness.sh\`.
- Build and test the iPhone Release configuration.
- Build the iPad, Mac Catalyst, and Watch configurations.
- Confirm both privacy manifests declare app-local UserDefaults access with reason \`CA92.1\`; confirm iOS/iPadOS/Mac Catalyst also declares feed-provider Coarse Location and Other Diagnostic Data while Watch declares no independent collection.
- Confirm iOS and Watch icon assets compile into the Release products.
- Confirm no archive, IPA, provisioning profile, certificate, secret, or generated screenshot is staged for commit.

## Core Discovery And Storage

- Public browsing works without sign-in.
- Keyword and translated-field searches work, with English fallback.
- City, region, age, category, language, high-school, volunteer, co-op, mentorship, scholarship, equity, new-find, distance, and sort controls apply and reset.
- List and map show consistent filtered results.
- Details show source/provider links, maps/directions when available, and readable fact cards.
- Local saving works from a detail view without an account.
- Local Profile creation, sign-out, and deletion work; deletion clears saved opportunities and personal hunt history.
- Manual refresh, foreground revalidation, cache restore, and bundled fallback avoid a blank or failed experience.
- Repeated refreshes do not duplicate results or spam new-match notices.

## Permission, Accessibility, And Localization

- Location is requested only after nearby search; denial has a clear fallback.
- Notification permission does not block browsing.
- Large Dynamic Type, VoiceOver, light/dark appearance, and contrast are usable.
- Arabic, Farsi/Persian, and Urdu remain usable in right-to-left layout.
- Spot-check each supported language for untranslated UI and translated opportunity payloads.
- The loading sequence remains warm, branded, and free of a blank-white stall.

## Platform Coverage

First record the deliberate final public selection in \`docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md\` using \`iphone\`, \`ipad\`, \`watch\`, and/or \`mac\`. Test and retain evidence only for the selected values; the release gate has no implied platform default.

- iPhone (when \`iphone\` is selected): TestFlight fresh install, online and offline flow.
- iPad (when \`ipad\` is selected): sidebar/navigation and filter layout.
- Apple Watch (when \`watch\` is selected): launch, compact live/cache data, and readability on paired hardware.
- Mac Catalyst (when \`mac\` is selected): launch, sidebar navigation, links, and window-scale appearance.

## App Store Gate

- Product page, support URL, privacy URL, App Privacy, age rating, availability, export compliance, and review notes match \`docs/APP_STORE_SUBMISSION_PACKET.md\`.
- The live support route has a real, user-owned contact method and does not promise unsupported web accounts, submissions, or feedback.
- The production Support and Privacy URLs were opened and verified against the submitted build, then recorded in the signoff without private contact details.
- Current screenshots are opaque, current, and visually reviewed for every selected platform.
- The selected App Store Connect build has processed successfully.
- \`docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md\` contains actual TestFlight evidence.
- \`IOS_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-1.0-12.xcarchive IOS_IPA_PATH=/absolute/path/to/GTAFreeSTEM-1.0-12.ipa PUBLIC_RELEASE_PLATFORMS=iphone,ipad,watch bash docs/scripts/check-public-release-gates.sh\` passes for the current archive and its verified distribution-signed IPA; if the separate Mac product is included, also set \`MAC_ARCHIVE_PATH=/absolute/path/to/GTAFreeSTEM-Mac-1.0-12.xcarchive MAC_PKG_PATH=/absolute/path/to/GTAFreeSTEM.pkg\` and add \`,mac\`.
