# 1.0 (17) crash and saved-filter update — verification in progress

The owner reported a crash in delivered build 16. Its symbolicated report matches the uploaded executable and identifies a main-actor assertion in the scene's deferred window builder during SwiftUI background rendering. Build 17 moves that builder to a stateless, nonisolated factory and keeps UI state in the main-actor view. The shared stores, original GTA logo and loading-animation implementation are preserved. No runtime safety checks are disabled.

Browse now opens **Saved filters** from its toolbar. The Filters sheet provides **Save filter** or **Update filter**, a named-filter form and a saved confirmation. Existing stored filters and their update history retain their data format. Interface copy is updated across the 18 existing locales. Standard Apple toolbar controls remain accessible; system border/underline preferences are not overridden.

The integrated source `02c6b4d57823f46ced770927bb575564add6381e` passed **190/190 tests, zero failures or skips** locally on an iPhone 17 Pro Max simulator running iOS 27.0. The new tests exercise off-main window-factory construction and main-actor root construction. The subsequent CI-only commit corrects integrity digests without changing tested app bytes. This is simulator evidence, not proof of physical-device acceptance on the reported iOS 27.0.1 version.

Actual rendered flows, lifecycle checks, signed archive/export and TestFlight delivery are still pending for build 17. **Build 17 has not been uploaded.** External tester sharing and public App Store release remain on hold. The build 16 record below documents delivery, not crash-free acceptance.

---

# Owner-only development update: 1.0 (16)

Uploaded October 29, 2026 through **TestFlight Internal Only**, from source `1338441b5daa7d7281d0d22d6d5e7da552a88f54`. App Store Connect now shows **Internal Testing** in the sole-owner Zenin group and reports the owner **Installed 1.0 (16)** on October 29. This Apple status confirms delivery availability and reported installation, not a directly observed physical-device launch or core-use journey. External sharing remains on hold pending the owner's visual review.

Home is a bright topic-led landing page with independently named saved searches and per-search new-event updates. Browse contains the search/filter tools. The original GTA logo and loading animation remain intact. This update also retains the responsiveness, unknown-age, full original provider text, virtual-location and legacy event-language fixes. The experimental complete-library adapter and full-description translation trial are excluded.

## Evidence and limits

- All 187 test stages passed on the delivered app source in [run 40810554175](https://github.com/rupayon123/gta-free-stem-ios/actions/runs/40810554175). The overall job failed during simulator screenshot capture, so it is not a green end-to-end CI run.
- 31 actual local native frames were reviewed across Home, Browse, saved-search forms, dark/System appearance, large text and relevant CJK/RTL layouts. Their effective UI source matches the delivered app. Debug-selected screen states do not establish physical-device or complete touch-journey acceptance.
- Release archive: 52/52 strict checks passed. Xcode confirms upload of 1.0(16). The package retained with Export on that successful-upload screen passed 62/62 strict IPA checks, including exact source, distribution signatures/profiles and main/Watch executable UUID agreement.
- Uploaded IPA: 7397696 bytes; SHA-256 `497b6cb3c6d242a94b5a1968a39feba03c232dc72686ef2b20952b62c4a5d4e3`.
- Xcode's Internal Only preset used `testFlightInternalTestingOnly=true` and `manageAppVersionAndBuildNumber=true`; the actual archive, retained IPA and Apple upload were independently verified as 1.0(16). No pre-upload IPA-export claim is made.

The sole existing internal tester is the owner. This private development update is not public App Store signoff. Full catalogue adoption, qualified full-description translation coverage, final screenshot automation, physical devices and the existing public-release gates remain unfinished. Prior build 15 is now verified available and installed by the owner; its dated archive/upload history remains in [the previous handoff](CURRENT_RELEASE_HANDOFF.md).
