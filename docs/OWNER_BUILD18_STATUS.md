# Owner build 18

Build 18 passed 52 strict archive checks and Xcode is uploading it for owner-only TestFlight testing. Apple availability has not been confirmed yet. Owner build 17 remains the available update. Public App Store distribution and external tester sharing are not approved by this record.

## What changed

- Restored approved Nunito typography and original illustrated light/dark artwork, keeping the existing logo and animated launch experience.
- Replaced the tiny Reset/Done outlines with padded rounded controls, checked with Show Borders enabled at normal and maximum text sizes.
- Put a named Saved filters dropdown inside Filters. Selection applies query and criteria immediately and updates the live count. Save/Update remains explicit; Reset starts a new selection; Done returns to Browse.
- Removed the duplicate toolbar Filters control. Browse retains one prominent labeled Filters action and a distinct accessible Refresh button.
- Reserved opaque space for five navigation destinations so scrolling content cannot obscure their labels. Full Dynamic Type, RTL and selected-state accessibility are retained.

## Verification and source lineage

The rendered app source is `a96d2f4246e574c65a1200503393c54291a824bd`. Actual simulator captures cover Home/Browse, all five routes, normal/maximum text, dark mode, Arabic and the final named-filter panel. The 81 installed files and embedded source revision matched the build products. [Screenshots and provenance](showcase/2026-10-29/capture-receipt.json).

The final instrumented suite passed **193 tests, 0 failures, 0 skips**, exit 0, on test source `4a5710157dad193f621ef030f08bbcbdd909b7b8`. Production app/Watch sources are identical to the rendered candidate. The upload source `e8cbd54756bdd48bc5873fd521ee6bf16e911b89` contains the same app/Watch/test files, with build-number-only metadata changed to 18 and matching source pins.

An earlier full run passed 192 tests and timed out waiting for one saved-filter reconciliation gate. The same test then passed unchanged in isolation. Test-only diagnostics added an idle precondition and request/gate/completion timeline while retaining the original ten-second expectation and all persistence assertions; the full run passed. The original timeout and partial result are retained, and its cause is **not established or claimed fixed**. The delayed result finalization was a separate Xcode on-failure diagnostic collection.

The isolated simulator's QA archive and preferences were backed up and restored after the tests. Some pre-existing tests construct stores with standard defaults and can change the test-host archive; this is recorded as test-isolation debt, not evidence of physical-phone data loss.

Physical iPhone installation/core journey and full software-keyboard occlusion remain unverified. Simulator checks do not substitute for those gates. Catalogue expansion and full-description translations are excluded from this style update.
