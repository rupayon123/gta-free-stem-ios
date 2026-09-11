# Product screenshot capture notes

Captured on September 11, 2026 on the project owner's Mac. These are unaltered runtime captures, not generated mockups or app-store release screenshots.

| Asset | Capture source | Observed state |
| --- | --- | --- |
| ios-home.png | iOS 26.5 Simulator, installed GTA FREE STEM 1.0 (12) | Home and search; the screen explicitly reports an offline backup dated August 20, 2026. |
| ios-detail.png | Same iOS app and simulator | Opened Mini-Makers details with a rendered Apple Maps preview. |
| android-home.png | Android API 36 emulator, GTA FREE STEM 1.1.0 (3), existing local debug APK | Home with a loaded Mini-Makers listing. |
| web-home.png | https://gta-free-stem.vercel.app/ in the Mac's Codex browser | Live landing page. |
| web-browse.png | Same live website | Opportunity browser with listing and provider details. |

The Android APK SHA-256 was 1b3cd8345d2ca05efac72ed7d104149b409a2041c23202379529f9f1a8dd25d7. The installed iOS app and Android APK were existing local builds; their exact source commits were not established. These images document the observed interfaces, not a rebuild of the latest source or full functional verification. Listing counts and content can differ between cached native data and the live website.

The Android emulator's first boot displayed a System UI startup warning. After an emulator restart, the app opened and loaded the listing shown in the published capture. The warning and loading-state captures were not published.

Screenshots contain only the app or webpage, without the Mac desktop, unrelated windows, or account details. Original pixels and platform status bars are retained. No sample data was inserted or UI labels retouched. Provider content and map attribution remain owned by their respective sources.

This documentation update does not assert App Store or Google Play availability, physical-device signoff, or completion of release gates. See each repository's existing release documentation for distribution status.

## Original image checksums

```text
d93d35848e1978f7e3f6097252ed2c970287032eef7b11dda0e877577d6b4178  web-home.png
ea29e08eb847ba0e50630dcd224fe591be88a138772396d1b6234f4f0378c3d8  web-browse.png
b3a93ba00e1ff575c31df10fb2c9820576ec942c3aea06ee48672134693754db  ios-home.png
a0be035c4e24349579624ac7691ff727f1327044a3279a01b32c5f04b9ca2be5  ios-detail.png
2c7e7b8d483c1786eb43b50f3c1a9ed1e1fb0cc5b836bf3b053e88368b07f344  android-home.png
```
