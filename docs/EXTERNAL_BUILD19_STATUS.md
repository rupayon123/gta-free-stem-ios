# External beta build 19

**Build 19 is available for external TestFlight testing.** Apple shows version 1.0 (19) as Testing in the external group, with exactly three owner-authorized testers showing Invited on October 29, 2026. The group contains one build (19), no older build, and no public invitation link.

The owner explicitly requested external-testing setup. Build 18 used TestFlight Internal Only, which Apple does not allow in external groups, so build 19 uses the normal App Store Connect upload route. This does not itself publish an App Store release.

Release source: `ee6edf3b9852db149390c38a18c48023f5a3f509`. App/Watch/test files exactly match the final 193-pass diagnostic source `4a5710157dad193f621ef030f08bbcbdd909b7b8`; the rendered UI source remains `a96d2f4246e574c65a1200503393c54291a824bd`. Build-number metadata is 19. The new archive passed 52 strict checks, and the exact uploaded IPA passed 62 strict distribution/provenance checks. ExportOptions confirms the internal-only flag is absent/false. The beta-review submission completed; final Apple status is external Testing.

The review group is limited to exactly three recipients explicitly authorized by the owner. It must contain no older build and no other testers. The owner explicitly requested automatic invitations after approval. Apple’s native Automatically notify testers option was enabled at submission for those three. Their Invited status is verified; actual email delivery, acceptance and installation are not. Creating tester records does not establish that invitation emails were sent or that Apple has approved the beta. Other recipients and public links remain on hold. Recipient addresses are kept out of public repository records. Apple beta-review approval is distinct from review preparation or submission.

The original earlier test timeout is retained in the build 18 evidence and is not claimed causally fixed. Physical-phone core-flow acceptance, full software-keyboard occlusion, catalogue expansion and qualified full-description translations remain open; this packaging-only build does not claim to complete them.

## Final evidence

Release coordinator inspected the post-submission group/build view (1.0 (19), Testing, three testers, one build) and all three Invited rows. The temporary processing follow-up was removed after successful setup. No continuing monitor, additional recipients, public link or older-build invitation was created. Private Apple screenshots and recipient addresses are retained outside the public repository.
