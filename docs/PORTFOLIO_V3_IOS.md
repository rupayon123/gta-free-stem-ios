# Approved portfolio v3 iOS implementation

Source-only preparation from delivered iOS source `4e81c27d043bb01a3573f79c3058886f951ce7ce`. Full Stack owns integration, version selection, signing and release. This branch has no native build, screenshots or device acceptance yet.

## Approved input

The design chat supplied `gta-theme-portfolio-v3/native-handoff/manifest.json`, 64 original PNG icon variants and the exact approved Nunito variable font. Nunito SHA-256: `bb55a5ca5c2042335b3991af27c4d0705d0ef41cac6164ac737fd8f2a1e85207`. The font's name table identifies PostScript face `Nunito-ExtraLight`, typographic family `Nunito`, and a variable font table. The source uses the registered face with semantic weights and relative text styles. Native QA must verify variable weight selection, Dynamic Type and script fallback; filename alone is not evidence of the rendered face. OFL is bundled. Patrick Hand is excluded.

Final handoff tokens are used, including light primary #2e7184 and dark background #14253a, surface #23364c, primary #a4d8e2. Earlier portfolio CSS layers are superseded by that manifest.

## Source changes

Central semantic content colours, outlined cards, control borders and 100 ms press feedback follow the handoff. Existing Reduce Motion removes decorative press scaling/animation. Original loader-specific colour constants, logo assets and loader implementation remain intact. Native TabView/NavigationStack and all five existing routes/deep links are preserved. Home/Explore use their matching compact illustrations; unmatched High School, Support and Profile roles retain existing native symbols pending authored role assets. Category illustrations are decorative beside existing readable labels. Dark and light PNGs are packaged as asset variants; unsupported SVG filters are not interpreted at runtime.

Typography changes cover content screens and common fields/buttons while native navigation chrome, map annotation typography and icon glyph sizing retain platform behaviour. No data, saved-filter association, catalogue, persistence, launch factory or refresh behaviour changes are intended.

## Required before integration/release

Build and inspect exact registered font/weights and all asset variants; verify ordinary and maximum Dynamic Type, Arabic/Urdu/Farsi and CJK glyph fallback, RTL in every modal, VoiceOver labels/focus, Show Borders, light/dark contrast, safe areas and no text/control collisions. Exercise each existing tab and deep link, back navigation, search/filter/query/reset, saved filter selection/modified/update semantics, save/unsave persistence, program details/provider/calendar, map 2D/3D/reset, empty and offline states, repeated/interruptible navigation, Reduce Motion, foreground/background and the unchanged loader. Use actual native screenshots and interactions; the portfolio is only a design reference.
