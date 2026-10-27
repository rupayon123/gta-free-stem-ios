# Current internal release handoff

Recorded October 27, 2026. This is the current **1.0 (15)** internal iPhone candidate. Public App Store release is **not complete**.

## Source and delivery status

- Verified app source: `08c172d20060ec0748fccae2677c7554c3fe8145`.
- Original `GTAFreeSTEMApp.swift` SHA-256: `b43447d78fb72d4bc068d175808d125f4e804fbe317c3531a416cb6df2e1e7b9`. The original launch implementation is preserved.
- The documentation follow-up also retains PR 11's `7509f1b` and `8b64eaa` release-script fixes. Its app, Watch, tests, project and bundled-resource bytes remain identical to the verified source above; a newer documentation commit is not a new signed app build.
- Xcode confirmed **GTAFreeSTEM 1.0 (15) uploaded** on October 27. This record does **not** establish App Store Connect processing, tester-group availability, installation on the phone, or physical-device acceptance. Record those outcomes after confirmation.
- No App Review submission or public App Store availability is claimed. This handoff does not authorize or certify a separate Mac release.

## Recorded checks and artifact binding

The [source-bound CI run](https://github.com/rupayon123/gta-free-stem-ios/actions/runs/40521124677) succeeded with **178/178** tests, zero failures or skips, and three additional successful repeats of the cancellation/completion race regression. It produced 19 authentic native simulator captures. The release owner recorded manual inspection of all 19: normal Home/Browse, labelled layout fixtures, large text, dark mode, Arabic, calendar presentation and native maps.

The release owner's October 27 archive/export receipt records:

| Item | Recorded result |
| --- | --- |
| Archive | `GTAFreeSTEM-1.0-build15-08c172d.xcarchive`; **52/52** strict checks passed |
| Export | Existing Xcode GUI, cloud-managed Apple distribution; **62/62** strict IPA checks passed |
| Preflight IPA | `ios-build15-08c172d-gui/GTAFreeSTEM.ipa`, 7,353,397 bytes |
| Preflight IPA SHA-256 | `c504a74575e7af9d39282e1d49ab9e0ad55fbc09228dccad845b26df6fc7a749` |
| Embedded source | `08c172d20060ec0748fccae2677c7554c3fe8145` |
| Export options | Internal TestFlight only; preserve version/build (`manageVersionBuild=false`) |

Xcode subsequently confirmed upload from the same source-bound archive. The package retained with **Export** on the successful upload sheet is `ios-build15-08c172d-upload-export/GTAFreeSTEM.ipa`, 7353403 bytes, SHA-256 `83b24dda980ce3bc8d658fd6bd8e76fe6941ad675deda4e17ee908eb444d4125`. That retained delivery package passed all 62 strict IPA checks after upload, including exact source, distribution profiles and the same main/Watch Mach-O UUIDs as the verified archive. The earlier `c504...` preflight export is preserved separately and is not represented as the uploaded file hash. Apple processing and tester-group availability remain unverified.

## Current repository previews

The README displays two unmodified JPEG exports from the CI run: [normal Home](showcase/2026-10-27/normal-home.jpg) and [native map overview](showcase/2026-10-27/ios-map-overview-light.jpg). The [capture receipt](showcase/2026-10-27/capture-receipt.json) preserves the source, run URL, JPEG hashes, original native PNG hashes and capture-mode limitations.

- Normal Home/Browse showed 1,877 available results at capture time. The underlying published bundle has 1,878 records; the visible current result count is time-sensitive.
- The native map overview showed 94 physical venues containing 1,832 opportunities. Virtual opportunities remain in the list and are not fabricated as physical pins.
- The map overview uses real source-backed records. Selected/detail capture states elsewhere in the full CI set are entered by debug flags and do not prove an automated touch journey.
- Sample layout captures remain labelled fixtures. They are not used as production-data previews here. The system-calendar presentation does not prove an event was saved.
- These simulator JPEGs are repository previews, not physical-device, performance or data acceptance, and not the canonical App Store screenshot package. The signed internal distribution and the simulator capture are distinct artifacts bound to the same app source.

## Website and bundled feed

The current free website is [gta-free-stem.pages.dev](https://gta-free-stem.pages.dev/), with [rupayon123.github.io](https://rupayon123.github.io/) as its backup. The [verified website publication](https://github.com/rupayon123/rupayon123.github.io/actions/runs/40521322266) serves source `f03b4eb6187499cf5f1fc03c4d1a23cf7c7cd257` on both hosts, including the current [Privacy Policy](https://gta-free-stem.pages.dev/privacy/), [Terms of Use](https://gta-free-stem.pages.dev/terms/) and [Support](https://gta-free-stem.pages.dev/support/) routes. Website publication does not update native app code installed on a phone.

The frozen native feed comes from producer `7ca94cff12c9667f93bd9d4febb774ee6e6f0e37`: **1,878 records**, **4,185,293 bytes**, SHA-256 `c61ed81737815ad1543df966f382c8e2672fe2cb28b7d8f6f68cfc3ef39fd391`. The bundled feed and actual feed bytes on both website hosts were verified against that digest. This does not assert that all provider descriptions have complete translations; interface translations and source descriptions are separate checks.

## Remaining release boundaries

1. Upload is confirmed; confirm processing and tester-group availability before saying build 15 can be installed. Then verify the version/source on the actual phone and preserve its existing local data.
2. Record fresh iPhone and iPad journeys, paired-Watch behavior and Mac behavior independently. The current simulator and embedded-Watch archive checks do not establish these device/platform results.
3. Keep the privacy declarations, exact signed-artifact provenance, monitored direct-support requirement, canonical screenshot receipt/full-size visual review and public platform gates enabled. The 19 CI captures do not replace `build/app-store-screenshots/final/` or its release-owner signoff.
4. The older build 12 public-release packet, runbook and signoff templates remain historical. Build 13 and 14 delivery records likewise retain their original dates and bindings. None is rewritten as build-15 acceptance by this documentation update.
5. Complete and rebind the actual public-release packet and platform evidence, then intentionally decide whether to submit to App Review. Internal TestFlight progress alone does not satisfy that gate.
