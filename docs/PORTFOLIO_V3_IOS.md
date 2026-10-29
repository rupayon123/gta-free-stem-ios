# Approved portfolio v3 iOS implementation

Source-only preparation from delivered iOS source `4e81c27d043bb01a3573f79c3058886f951ce7ce`. Full Stack owns integration, version selection, signing and release. The initial Debug simulator build and focused font/visual smoke checks passed on iOS 27.0, iPhone 17 Pro Max. Physical-device and full-flow acceptance remain pending.

## Approved input

The design chat supplied `gta-theme-portfolio-v3/native-handoff/manifest.json`, 64 original PNG icon variants and the exact approved Nunito variable font. Nunito SHA-256: `bb55a5ca5c2042335b3991af27c4d0705d0ef41cac6164ac737fd8f2a1e85207`. The font's name table identifies PostScript face `Nunito-ExtraLight`, typographic family `Nunito`, and a variable font table. The source uses the registered face with semantic weights and relative text styles. The initial native diagnostic registered eight Nunito faces and visibly distinguished default 200, requested regular 400 and semibold 600. Maximum Dynamic Type and a multilingual fallback sample rendered successfully on the tested simulator. Other devices and exhaustive script coverage remain pending; filename alone is not evidence of the rendered face. OFL is bundled. Patrick Hand is excluded.

Final handoff tokens are used, including light primary #2e7184 and dark background #14253a, surface #23364c, primary #a4d8e2. Earlier portfolio CSS layers are superseded by that manifest.

## Source changes

Central semantic content colours, outlined cards, control borders and 100 ms press feedback follow the handoff. Existing Reduce Motion removes decorative press scaling/animation. Original loader-specific colour constants, logo assets and loader implementation remain intact. Native TabView/NavigationStack and all five existing routes/deep links are preserved. Home/Explore use their matching compact illustrations; unmatched High School, Support and Profile roles retain existing native symbols pending authored role assets. Category illustrations are decorative beside existing readable labels. Dark and light PNGs are packaged as asset variants; unsupported SVG filters are not interpreted at runtime.

Typography changes cover content screens and common fields/buttons while native navigation chrome, map annotation typography and icon glyph sizing retain platform behaviour. No data, saved-filter association, catalogue, persistence, launch factory or refresh behaviour changes are intended.

## Required before integration/release

Build and inspect exact registered font/weights and all asset variants; verify ordinary and maximum Dynamic Type, Arabic/Urdu/Farsi and CJK glyph fallback, RTL in every modal, VoiceOver labels/focus, Show Borders, light/dark contrast, safe areas and no text/control collisions. Exercise each existing tab and deep link, back navigation, search/filter/query/reset, saved filter selection/modified/update semantics, save/unsave persistence, program details/provider/calendar, map 2D/3D/reset, empty and offline states, repeated/interruptible navigation, Reduce Motion, foreground/background and the unchanged loader. Use actual native screenshots and interactions; the portfolio is only a design reference.

## Initial native smoke evidence

Actual tested Swift source checkpoint: `f9339c98472d8bedb0bacc0202a081bd8fdbb518` (includes a DEBUG-only typography diagnostic inside the existing isolated FrontendLayoutReview). The diagnostic is excluded from Release by the existing `#if DEBUG` boundary and does not replace personal defaults or model storage. The build inputs stayed frozen while compiling; only the source-pin manifest was refreshed afterward before committing that checkpoint.

A single `-jobs 1` Debug simulator build succeeded. All 83 installed application files matched its output bytes. Native screenshots were personally inspected for Home, Browse and Filters in light/dark appearance, maximum accessibility text in Filters, and actual Arabic RTL Filters. Exact font registration and an identical-string raster comparison showed different 200/400/600 weights; Arabic, Urdu, Bengali, Chinese and Japanese sample glyphs had no missing-glyph boxes. The preserved Age four preset still opened 131 results and appeared selected with Update filter in the panel. No control/text collision was observed in these states.

The evidence receipt and nine source-bound PNGs are retained in this task's `outputs/ios-portfolio-v3-smoke-20261029/` folder. The simulator was restored to English, Light and standard large text, then shut down. No full 193-test run, signing, upload, physical-device validation or full navigation/VoiceOver/offline/map/motion matrix is claimed. The simulator logged a duplicate system WebKit accessibility-class warning; no application crash was observed in this batch.
