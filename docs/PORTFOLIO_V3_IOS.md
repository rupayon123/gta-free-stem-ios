# Approved portfolio v3 iOS implementation

Source-only preparation from delivered iOS source `4e81c27d043bb01a3573f79c3058886f951ce7ce`. Full Stack owns integration, version selection, signing and release. The initial Debug simulator build and focused font/visual smoke checks passed on iOS 27.0, iPhone 17 Pro Max. Physical-device and full-flow acceptance remain pending.

## Approved input

The design chat supplied `gta-theme-portfolio-v3/native-handoff/manifest.json`, 64 original PNG icon variants and the exact approved Nunito variable font. Nunito SHA-256: `bb55a5ca5c2042335b3991af27c4d0705d0ef41cac6164ac737fd8f2a1e85207`. The font's name table identifies PostScript face `Nunito-ExtraLight`, typographic family `Nunito`, and a variable font table. The source uses the registered face with semantic weights and relative text styles. The initial native diagnostic registered eight Nunito faces and visibly distinguished default 200, requested regular 400 and semibold 600. Maximum Dynamic Type and a multilingual fallback sample rendered successfully on the tested simulator. Other devices and exhaustive script coverage remain pending; filename alone is not evidence of the rendered face. OFL is bundled. Patrick Hand is excluded.

Final handoff tokens are used, including light primary #2e7184 and dark background #14253a, surface #23364c, primary #a4d8e2. Earlier portfolio CSS layers are superseded by that manifest.

## Source changes

Central semantic content colours, outlined cards, control borders and 100 ms press feedback follow the handoff. Existing Reduce Motion removes decorative press scaling/animation. Original loader-specific colour constants, logo assets and loader implementation remain intact. Native TabView/NavigationStack and all five existing routes/deep links are preserved. All five routes now use their matching approved compact illustrations, including the subsequently authored School, Support and Profile roles. The native symbol remains only an asset-load failure fallback. Category illustrations are decorative beside existing readable labels. Dark and light PNGs are packaged as asset variants; unsupported SVG filters are not interpreted at runtime.

Typography changes cover content screens and common fields/buttons while native navigation chrome, map annotation typography and icon glyph sizing retain platform behaviour. No data, saved-filter association, catalogue, persistence, launch factory or refresh behaviour changes are intended.

## Additional route artwork source checkpoint

The design owner authored School (cap/book), Support (contact headset) and Profile (portrait card); Full Stack visually approved their contact sheet. Exact 12 PNG hashes were verified before packaging six new light/dark image sets. Existing five labels, route cases, deep links and 26-point bitmap sizing remain unchanged. Tab and sidebar navigation share the same artwork mapping. This source-only follow-up has not yet been built or rendered; the earlier nine-frame smoke receipt predates these three route images.

## Required before integration/release

Build and inspect exact registered font/weights and all asset variants; verify ordinary and maximum Dynamic Type, Arabic/Urdu/Farsi and CJK glyph fallback, RTL in every modal, VoiceOver labels/focus, Show Borders, light/dark contrast, safe areas and no text/control collisions. Exercise each existing tab and deep link, back navigation, search/filter/query/reset, saved filter selection/modified/update semantics, save/unsave persistence, program details/provider/calendar, map 2D/3D/reset, empty and offline states, repeated/interruptible navigation, Reduce Motion, foreground/background and the unchanged loader. Use actual native screenshots and interactions; the portfolio is only a design reference.

## Final QA checkpoint: functional pass, visual gate open

Frozen source `aba689ab65a030f271d7502fa1f52ef358b90599` passed all 193 tests with zero failures/skips on the owned iOS 27.0 iPhone 17 Pro Max simulator. The original two test failures and original result bundle remain retained; the existing spring helper was restored and the completed DEBUG font probe removed, with no test exemptions. The full run does not establish visual acceptance.

Actual five-tab light/dark screenshots and maximum Dynamic Type frames revealed a visual failure: native translucent tab chrome allows scrolling words and the enlarged Profile destructive control to mix with navigation labels. Normal light Home also shows CTA content through the bar. Maximum-text High School search shows an oversized system magnifier inside a constrained native field. Neither is accepted. A minimal opaque tab background candidate is being reviewed and has not been compiled or visually verified.

Actual interactions verified saved-filter select/edit/explicit update, normal relaunch preservation of preset identity and criteria, Reset retaining the saved archive, saved-event library presence, detail back navigation, the matching TPL provider event page, and responsive repeated tab changes. The preset loss observed after XCTest was traced to a pre-existing cleanup test using standard defaults; separate commit `7277102` isolates that test's defaults suite without changing production behaviour or existing assertions. That later test-only patch has not yet been rerun.

Source-bound screenshots, preset snapshots, both test bundles and `receipt.json` are in `outputs/ios-portfolio-v3-final-20261029/` in this chat workspace. English/Light/large were restored; Reduce Motion was untouched; the owned simulator was shut down and the heavy slot released. Actual offline and Reduce Motion interactions, remaining release gates and physical-device verification remain pending. No signing, upload or release is claimed.

### A/B follow-up and next source candidate

Source A `53a28d6` built successfully after correcting an explicit SDK argument that wrongly applied the iPhone SDK to Watch assets; both the failed and corrected logs are retained. All 81 installed app files matched the successful output. Actual normal/max-text Home/Profile scrolling still showed CTA words and destructive red colour through the native tab bar, so the declarative SwiftUI background candidate failed visual acceptance.

Diagnostic B `380c964` removed only the shell-level font modifier and updated its source hash. It built and matched all 81 installed files. At maximum text, the native search's idle placeholder/icon disappeared and focused controls remained oversized. Focus, typing, Return refresh, clear, typing again, clearing, Return and closing were exercised. This diagnostic is rejected as a production treatment; the normal Nunito setup is retained. No full 193 run was repeated for either candidate. The owned simulator was restored and shut down; both failures are preserved in `outputs/ios-v3-visual-ab-20261029/receipt.json`.

The next source prototype uses app-scoped public UIKit containment to request opaque standard/scroll-edge tab appearances and `isTranslucent = false`. It replaces the failed declarative background settings. Apple's public APIs support appearance configuration, but this is not proof that floating Liquid Glass will render opaque; an actual iOS 27 check must decide. It uses neither a global appearance proxy nor private view inspection nor an OS compatibility flag.

Search falls back to a native SwiftUI TextField in existing scroll content: the decorative magnifier is 20 points inside a 24-point frame, the field has a 48-point minimum and its clear control a 44-point target. User text retains full Nunito Dynamic Type. Existing query binding and submit-triggered refresh remain; no request is added per keystroke. Clear retains focus, Return dismisses it, scrolling dismisses interactively and leaving the tab clears focus. Clear's accessible label is present in all 18 supported languages. No production data or saved-filter association changes are made.

Before accepting this prototype: build the frozen source, verify installed bytes, inspect all five tabs in light/dark at normal and maximum text while scrolling Home CTA and Profile red controls; verify readable tab labels without underlying words/colour; exercise search focus/type/clear/refocus/Return/dismiss on Browse and High School with hardware and on-screen keyboards, RTL and CJK; verify saved-filter selection/edit/Reset/update/relaunch semantics; and run the full suite only after the production UI treatment is settled. Original offline/Reduce Motion/device gates remain open.

### Prototype runtime result: visual approval still withheld

Frozen `fb6d4b6807b70cc26c73a6fceb05294f2c9c1d7a` built successfully with one job and matched all 81 installed app files and the full embedded source SHA. The app-owned query field rendered correctly at normal/max text, including RTL icon/clear ordering, focus/clear/type/Return and tab changes. The same named preset identity and Robot/age-four criteria remained present. These are simulator observations, not physical-device acceptance.

The public tab appearance treatment stopped content bleed but produced an oversized default white/black backing above the floating pill, reducing the content viewport and missing the semantic dark surface. That geometry is a visual failure. Arabic maximum text also exposed a separate Hunt label breaking inside a word because the horizontal `ViewThatFits` row permits text wrapping. Neither is accepted. Full on-screen keyboard layout, the full five-role/theme matrix, the 193-test repeat on final production source and the original offline/motion/device gates remain pending.

The nine source-bound screenshots, successful build log, installed-byte binding and failed visual receipt are preserved in `outputs/ios-v3-prototype-20261029/`. English/Light/large were restored, keyboard capture and Reduce Motion left unchanged, the owned simulator shut down, and the runtime slot released. The next proposed diagnosis measures public tab/container geometry and compares only `isTranslucent` in a DEBUG-controlled launch; the proposed Arabic treatment stacks the two actions at accessibility sizes without shrinking text. No further prototype build is implied by these proposals.

### Historical initial smoke

Actual tested Swift source checkpoint: `f9339c98472d8bedb0bacc0202a081bd8fdbb518` (includes a DEBUG-only typography diagnostic inside the existing isolated FrontendLayoutReview). The diagnostic is excluded from Release by the existing `#if DEBUG` boundary and does not replace personal defaults or model storage. The build inputs stayed frozen while compiling; only the source-pin manifest was refreshed afterward before committing that checkpoint.

A single `-jobs 1` Debug simulator build succeeded. All 83 installed application files matched its output bytes. Native screenshots were personally inspected for Home, Browse and Filters in light/dark appearance, maximum accessibility text in Filters, and actual Arabic RTL Filters. Exact font registration and an identical-string raster comparison showed different 200/400/600 weights; Arabic, Urdu, Bengali, Chinese and Japanese sample glyphs had no missing-glyph boxes. The preserved Age four preset still opened 131 results and appeared selected with Update filter in the panel. No control/text collision was observed in these states.

The evidence receipt and nine source-bound PNGs are retained in this task's `outputs/ios-portfolio-v3-smoke-20261029/` folder. The simulator was restored to English, Light and standard large text, then shut down. No full 193-test run, signing, upload, physical-device validation or full navigation/VoiceOver/offline/map/motion matrix is claimed. The simulator logged a duplicate system WebKit accessibility-class warning; no application crash was observed in this batch.
