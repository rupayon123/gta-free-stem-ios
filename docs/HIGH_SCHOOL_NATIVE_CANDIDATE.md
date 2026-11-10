# High School native candidate — 2026-10-30

Source-only integration on reviewed model c622769e5fe365721efb01fd843443c6925f2b24 (shipped-19 lineage). This document is not a build, native test, physical-device or release receipt.

## Implemented scope

The School tab opens a separate four-pathway reviewed guide and actual-completed-hours notebook. Existing activity browsing/saved presets remain explicitly accessible; Home pathway/preset actions open that activity browser. Plain School links open the guide; /activities or view=activities opens existing browsing. Existing footer, original logo/loader/Nunito, old SearchMode values, window factory and Watch stay unchanged.

Independent optional age/grade/region/delivery choices use the curated evaluator without the older event age gate. Unknown location/delivery stay disclosed. Current reviewed no-fee programme intakes are separated from upcoming/ask-about programmes, and cards expose costs beside status. Directories/resources/funding are not roles, placements, awards or promises of school hours.

The nine reviewed JSON records are copied unchanged (SHA256 2c86090f12b5e413810e07ac06258441182f0d6e46ec009922da695203d46d97). Zero individual roles, two directories; programme intake is not guaranteed placement. No endpoint, feed, network or publishing activation.

## Notebook and privacy

The file actor uses bounded UTF8 reads, byte-exact CAS, stable advisory locking across cooperating app/Catalyst processes, atomic private-file replacement and synchronization. Repository algorithms use captured leases checked against a non-personal durable UUID epoch sidecar under the same file lock. Delete All rotates the epoch, removes personal notebook JSON and synchronizes before success; old missing/empty-file leases cannot recreate entries. Only lock/epoch metadata remains. Pure backend model algorithms are unchanged.

The shared UI store rotates its generation and clears its archive before awaiting Delete All. Pending completions and later queued actions require the captured generation. Editor/draft/delete/export state clears on reset. Settings' explicit Delete All calls this first; ordinary recent-history behavior stays independent. Existing exported copies outside the app are not revoked. Read-only storage recovery blocks mutations/deletion. Durability failures stay visible and preserve the editor's stable ID/draft; no unconfirmed save is presented as success. CSV rereads validated latest storage; no automatic time, school approval or calendar event.

## Source checks and test plan

Project plist parses; explicit app/test resource and source membership inspected, fixture folder is test-only, Watch receives no High School files, whitespace check passes, native source hash manifest refreshed. These are static checks only.

Thirteen new focused tests are written for real-file revisions/latest CSV; same/separate-adapter concurrent CAS; byte-exact Unicode comparison; failed replacement/unknown-version preservation; reset nil/empty ABA/stale CSV/delete/new write; paused read; paused CAS/cache/late generation; read-only save/reset; School link intent; Grade12/age18/York online+in-person hybrid inclusion and incompatible age/grade/delivery exclusion; exact bundle coverage. Existing eight portable/core tests and original fixtures remain unchanged and registered in the native test target.

Pending: one-worker native compile and focused tests on the existing simulator after explicit shared slot grant. Native UI, reduced motion, dark/light, largest text, keyboard/RTL/accessibility, main-flow/network and actual phone behavior need separate fresh receipts. No archive, upload or physical-phone verification is claimed here.

## First native focused receipt

Exact source 8b433c81c556b5710fe99111de80c4120053cad7 compiled and executed 21 unique focused tests (8 original +13 new), zero failures/unexpected failures. xcodebuild exit0, suite wall0.381 seconds; full one-worker batch70.7seconds on existing iOS27 GTA Owner17 QA simulator. Memory floor34%; simulator shut down and original preferences restored bytewise verified. Evidence: /tmp/gta-high-school-native-20261030-retry2/{receipt.json,xcodebuild.log,focused.xcresult}.

Two earlier compile failures remain preserved separately: initial0e8a193 used ambiguous Darwin.flock; replaced with documented O_EXLOCK open/close locking (no ABI shim). Retry1a182004 compiled the app but found a Swift6 test closure capturing XCTest self; fixed with explicit immutable actor/value captures. No tests executed in either failed batch. Raw artifacts remain /tmp/gta-high-school-native-20261030 and /tmp/gta-high-school-native-20261030-retry1.

## Next native UI candidate (unrun)

Separate GTAHighSchoolUIQA scheme and dedicated GTAFreeSTEMUITests target contain three actual-app journeys: all four guide pathways plus independent filters/legacy saved preset return; notebook create/edit/relaunch/real CSV chooser cancel/explicit DeleteAll/relaunch; dark largest text and real system Reduce Motion with keyboard/save checks. Ordinary unit-test scheme stays unchanged. Test identifiers add no UI flow or fixture mode. App starts normally with real reviewed bundle and normal disk store; no demo, fake success, model override, feed substitute, or hidden preview flag.

Run only on newly created disposable GTAHighSchoolUIQA20261030 iOS27 iPhone17ProMax simulator after explicit shared heavy grant, at most one booted device. Build-for-testing one worker, then normal journeys1/2; after stopping that test process apply real simulator dark/max text and execute journey3 without rebuilding. The UI journey enables and asserts the actual Settings Reduce Motion switch. Preserve xcresults/screenshots and halt on failure/pressure; stop/shutdown/release at the end. Existing owner QA and phone data remain untouched. UI assertions, screenshots and physical-phone checks are still pending.

## Broader frozen-source receipt and UI failures

Frozen 8e1635d7a1c8ca275989518d20dfd0c2b4b44e45: complete ordinary suite214 unique tests, zero failures/unexpected failures, test time162.951seconds/wall163.061seconds; full unit stage260.4seconds on NEW disposable GTAHighSchoolUIQA20261030 D25D2471-7C55-48BF-ACC6-B02F4C071420. Dedicated UI build-for-testing passed10seconds. Complete unit xcresult/log: /tmp/gta-high-school-ui-20261030/01-full-units.xcresult and01-full-units.log.

Two UI journeys ran and failed (222.8seconds of tests). Journey01 traversed all four pathways and the age18/grade12/York/online programme conditions, then failed the browse-query existence assertion after opening activities; the returned app AX query tree was empty. Navigation defect versus foreground/scroll/automation state is not established; the next harness captures immediately after transition and requires foreground plus bounded scrolling before asserting. No product navigation fix is claimed.

Journey02 created30minutes, edited/explicitly asserted45, relaunched and read45 successfully, then failed looking for Cancel on the system exporter. Actual remote AX hierarchy confirms Files picker FullDocumentManagerViewControllerNavigationBar, DOCPicker.filenameTextField gta-hours-notebook, DOCPicker.actionButton Save; no Cancel. Updated unrun harness verifies actual picker then uses native pull-down dismissal when Cancel is absent, verifies picker gone and45minutes unchanged, and continues explicit DeleteAll/relaunch assertions. No file was saved by the failed test. Generic tap now performs bounded observed-frame scrolling before final existence/hittability assertions, retaining strict positive assertions.

After both test failures, xcodebuild result finalization stalled for several minutes. A targeted SIGTERM ended only the matching UI process group, then the supervisor shut down the owned disposable simulator; UI stage exit-15, batch761.7seconds, sampled memory floor22%. The UI xcresult remains unfinalized (missing Info.plist), so normal xcresulttool export is unavailable; original Staging/Data and detailed Session AX log remain preserved. Nine unchanged raw PNG objects recovered with original-object mapping under /tmp/gta-high-school-ui-20261030/recovered-native-attachments. These do not substitute for completed failure attachments or a passing journey. Dark/maxtext/Reduce Motion journey03 did not run.

Postbatch inventory found two separately booted unowned iOS26.5 devices (23C5F1F5-8637-45FE-988C-351466D3B0C7 and9CC57172-6632-47CC-8C9A-2BCD55D7708C); earlier in-batch inventory had only the owned QA device booted. Coordinator was alerted; no ownership or cause of the finalization stall is inferred, and no unowned process/device was stopped here. Native runs are held pending explicit shared grant after web work.

## Near-limit stress plan (not executed)

The test-only generator docs/scripts/make-hours-stress-fixture.py writes an explicitly requested new file without overwrite, simulator access or app-bundle registration. Generated fixture:2,000 fictional completed entries,1minute each,20perday,632031bytes, total2,000minutes; SHA256 a659b283fbd5e805eb7a7fc2f03ee0c0b7100f7ee618f0e587bf7928f591220e for2026-10-30 generation. Native model validation, staging and device execution remain pending and are false in its receipt.

Before a separately granted stress run, validate through the actual native Notebook decoder and stage only into the stopped disposable QA app's normal hours file. Test04 independently opens the notebook twice, requires the33h20min total, records observed open-to-visible latency including automation, scrolls and checks footer navigation. No eager-list optimization is claimed or made before measurement. UI04 must be explicitly selected after staging; it is absent from the prior three-journey invocation. No owner QA or phone data may be used. User's new accessibility/support filter, hub card/copy changes and active real-opportunity data gates remain additional release requirements; this source is not iOS20 release approval.
