# Contributing to GTA FREE STEM for Apple platforms

Thank you for helping make free STEM opportunities easier to find. Code,
accessibility testing, documentation, design feedback, and human-reviewed
translations are all welcome.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
Unless a contribution says otherwise, it is submitted under the repository's
[MIT License](LICENSE).

## Before you start

- Search existing issues before opening a new one.
- Use the translation issue form for language help that does not require code.
- Discuss large features or architecture changes in an issue before investing
  significant work.
- Never include passwords, certificates, provisioning profiles, precise personal
  locations, children's information, or other sensitive data in an issue, pull
  request, screenshot, fixture, or log.
- Report vulnerabilities through the private process in [SECURITY.md](SECURITY.md),
  not in a public issue.

Opportunity listings and their translated titles or summaries come from the
[public opportunity-data repository](https://github.com/rupayon123/gta-free-stem-opportunities).
This repository is for the iPhone, iPad, Mac Catalyst, and Apple Watch apps.

## Set up the project

You need macOS, Git, and an Xcode version that supports the project's iOS 17,
macOS 14, and watchOS 10 deployment targets.

The tracked `GTAFreeSTEM.xcodeproj` is the build and release input. XcodeGen is
optional; if you use `project.yml` to regenerate the project, review every
project-file change before submitting it.

1. Fork and clone the repository.
2. Open `GTAFreeSTEM.xcodeproj` in Xcode.
3. List the simulator destinations installed on your Mac:

   ```bash
   xcodebuild -project GTAFreeSTEM.xcodeproj -scheme GTAFreeSTEM -showdestinations
   ```

4. Build and test with an installed simulator, substituting its name below:

   ```bash
   xcodebuild build \
     -project GTAFreeSTEM.xcodeproj \
     -scheme GTAFreeSTEM \
     -destination 'platform=iOS Simulator,name=iPhone 17'

   xcodebuild test \
     -project GTAFreeSTEM.xcodeproj \
     -scheme GTAFreeSTEM \
     -destination 'platform=iOS Simulator,name=iPhone 17'
   ```

Signing, App Store Connect access, and a paid Apple Developer account are not
required for normal simulator contributions. Do not change the development team
or signing setup just to make a pull request.

## Choose a focused change

- **Translations:** follow [the localization guide](docs/LOCALIZATION.md).
- **Accessibility:** test VoiceOver, Dynamic Type, keyboard focus where
  applicable, Reduce Motion, contrast, and light/dark themes.
- **Cross-platform UI:** check iPhone and iPad; also check Mac Catalyst or Watch
  when the affected code is shared with those targets.
- **App behaviour:** add or update focused XCTest coverage.
- **Documentation:** keep commands and release claims tied to behaviour you
  verified.

Keep pull requests small enough to review. Avoid unrelated formatting,
generated-project, dependency, or release-document changes.

## Pull request checklist

- Explain the user-facing problem and the chosen solution.
- Link the relevant issue when one exists.
- Include screenshots or a short recording for visible changes, with personal
  information removed.
- State the devices, simulators, OS versions, accessibility settings, and exact
  commands you tested.
- Add or update tests in proportion to the change.
- Confirm that no credentials, signing material, generated build output, or
  personal data were added.
- For translations, name the language reviewer and complete the localization
  checklist.

A maintainer may ask for a narrower change or additional evidence before
merging. Submission does not guarantee inclusion in a release.
