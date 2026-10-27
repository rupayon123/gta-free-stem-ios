# Screenshot provenance

`ios-home-simulator-2026-10-25.jpg` is an unretouched normal-runtime iPhone simulator capture from October 25, 2026 at commit `a6b1a54deeefe1dfbb0aa28cda444e45dd605153`. Its capture receipt recorded 1,882 visible opportunities from the public live feed, last checked October 25. This is simulator evidence, not a physical-device or build 14 capture.

`ios-browse-simulator-2026-10-27.jpg` is an unretouched normal-runtime iPhone 17 Pro simulator capture on iOS 26.5, using the same app source. The 20-second frame showed 1,856 public-feed listings, a Toronto Public Library activity, search, filters, and list/map controls. The [QA run](https://github.com/rupayon123/gta-free-stem-ios/actions/runs/40457611817) and local capture receipt also record matching interactive frames at 40 and 60 seconds. This does not establish physical-device or build 14 performance.

An earlier eight-second normal Browse attempt at this commit was **not accepted**: it still showed the “preparing opportunities” loader at 38%. It is intentionally absent from the gallery. The later accepted 20-second frame does not by itself resolve the startup latency question.

The older `home.png`, `search.png`, `hs-search.png`, and `profile.png` are archived September 11, 2026 captures from an installed iOS 1.0 (12) simulator build on iOS 26.5. They used an August 20 offline backup; the installed build's source revision was not established. High School search had no matches, and Profile showed local guest settings. These are not current release evidence.
