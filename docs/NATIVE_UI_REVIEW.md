# Native simulator layout review

The native unit-test lane separately exports two normal-runtime frames and twelve labelled layout-fixture frames as bounded JPEG blocks in ordinary job logs. No artifact/cache upload or external image service is used. Each frame includes its source commit, byte count and SHA-256; each exported raster is at most 180 KB and 1100 pixels on its longest edge.

Normal launches retain real network, source and content-rights behavior. Those frames may show a genuine unavailable/error state; they never substitute sample listings for a failed provider feed. A screenshot is not release or data acceptance.

`-frontend-layout-review` is Debug-only. It presents the actual ContentView/BrowseView/SavedView/SettingsView in a separate in-memory SwiftData container and unique defaults suite, with app-owned sample listings and a visible sample banner. It skips normal network launch preparation and Watch publishing. Release builds cannot enter this mode. Light, dark, accessibility3 text and Arabic RTL cases check layout independently of current publisher-feed readiness.

Capture can run after a reliability-test failure to retain independent UI evidence. It never converts a failed reliability job into a passing one; all 158 native unit tests, including the 31 exact frozen reliability contracts, must still pass with no skips. Screenshots still require human inspection, and simulator evidence does not establish physical-device or store-release acceptance.

The additional app-owned calendar frame waits until the real EventKitUI controller has a displayed window. Its visible event title begins with Sample, since the system modal may cover the fixture banner. It proves presentation only: no Calendar read/write permission is requested, no Save action is automated, and no persisted event is claimed.

Labelled layouts run before normal launches so a normal-startup/platform timeout cannot discard independent UI evidence. Normal frames still use a new process with real disk/source/rights behavior, after simulator/framework warmup; they do not establish first-install cold-start performance. Command and step deadlines remain bounded.
