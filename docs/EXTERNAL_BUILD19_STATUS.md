# External beta build 19

Build 19 uploaded successfully through App Store Connect for external TestFlight eligibility. It is not approved for external testing yet. Build 18 remains the available internal owner update.

The owner explicitly requested external-testing setup. Build 18 used TestFlight Internal Only, which Apple does not allow in external groups, so build 19 uses the normal App Store Connect upload route. This does not itself publish an App Store release.

Release source: `ee6edf3b9852db149390c38a18c48023f5a3f509`. App/Watch/test files exactly match the final 193-pass diagnostic source `4a5710157dad193f621ef030f08bbcbdd909b7b8`; the rendered UI source remains `a96d2f4246e574c65a1200503393c54291a824bd`. Build-number metadata is 19. The new archive passed 52 strict checks, and the exact uploaded IPA passed 62 strict distribution/provenance checks. ExportOptions confirms the internal-only flag is absent/false. Apple processing and beta-review approval remain separate steps.

External review will use an existing empty group only after rechecking that it has zero testers. Automatic tester notification stays off. A later direct owner request authorizes invitations to exactly three named recipients after build 19 is approved and available. Other recipients, populated-group assignment before approval and public links remain on hold. Recipient addresses are kept out of public repository records. Apple beta-review approval is distinct from completed review preparation or submission.

The original earlier test timeout is retained in the build 18 evidence and is not claimed causally fixed. Physical-phone core-flow acceptance, full software-keyboard occlusion, catalogue expansion and qualified full-description translations remain open; this packaging-only build does not claim to complete them.
