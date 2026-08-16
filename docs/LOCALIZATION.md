# Apple-platform localization guide

GTA FREE STEM welcomes human-reviewed translations that use clear, respectful
language for students, families, educators, and community organizations.

## Where interface translations live

The iPhone, iPad, and Mac Catalyst interface catalog is
`GTAFreeSTEM/Resources/app_strings.json`. Its `en` object is the source set, and
each other language object must contain every English key with a non-empty value.
`languageMeta` stores the English label, native label, and text direction.

The app currently includes these 18 language identifiers:

`en`, `fr`, `zh`, `yue`, `pa`, `ur`, `ta`, `tl`, `es`, `ar`, `fa`, `hi`, `pt`,
`gu`, `bn`, `ja`, `ko`, and `hu`.

The location permission sentence is localized separately in
`GTAFreeSTEM/Resources/<locale>.lproj/InfoPlist.strings`. Some folder names use
Apple locale identifiers rather than the catalog key: `zh-Hans` for `zh`,
`yue-Hant` for `yue`, and `fil` for `tl`.

`GTAFreeSTEM/Localization.swift` defines the launch-language list, locale
mapping, system-language matching, and right-to-left direction. Arabic, Farsi,
and Urdu use right-to-left layout.

## Improve an existing language

1. Edit only the target language object in `app_strings.json`, plus its
   `InfoPlist.strings` file when the location-permission wording needs a change.
2. Preserve every key and these replacement tokens exactly where they appear:
   `{summary}`, `{km}`, `{count}`, and `{city}`.
3. Keep JSON valid. Do not add comments, trailing commas, or duplicate keys.
4. Keep `GTA FREE STEM` as the project name unless the maintainer explicitly
   approves a localized brand treatment.
5. Prefer plain, natural language over literal word-for-word translation. Avoid
   gender, age, ability, or newcomer-status assumptions.
6. Ask a fluent human reviewer to check the result in context. Machine
   translation may help draft text but is not sufficient review by itself.

Privacy, permission, safety, deletion, and legal strings need especially careful
meaning review. Do not weaken what data is used, deleted, or kept on-device.

## Add a new language

Open a translation issue before coding so the language tag, script, regional
variant, reviewer, and scope can be agreed on. A complete new language requires:

1. A new `AppLanguage` case and any required locale matching or layout direction
   in `GTAFreeSTEM/Localization.swift`.
2. A `languageMeta` entry and a non-empty translation for every English key in
   `app_strings.json`.
3. A localized `InfoPlist.strings` file with the location permission purpose.
4. The localization added to the tracked Xcode project. `project.yml` is an
   optional maintenance definition; if XcodeGen is used, review the generated
   `GTAFreeSTEM.xcodeproj` diff because the tracked project remains the build and
   release input.
5. Tests and screenshots covering the new language.

## Verify the contribution

First validate JSON structure and key parity:

```bash
python3 - <<'PY'
import json
from pathlib import Path

catalog = json.loads(Path("GTAFreeSTEM/Resources/app_strings.json").read_text())
source = catalog["en"]
for code, strings in catalog.items():
    if code == "languageMeta":
        continue
    missing = [key for key in source if not str(strings.get(key, "")).strip()]
    extra = [key for key in strings if key not in source]
    if missing or extra:
        raise SystemExit(f"{code}: missing={missing}, extra={extra}")
print("Localization key parity passed.")
PY
```

Then run the XCTest suite with an installed simulator, substituting its name:

```bash
xcodebuild test \
  -project GTAFreeSTEM.xcodeproj \
  -scheme GTAFreeSTEM \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

In the app, switch to the contributed language and inspect:

- every tab, sheet, alert, empty/loading/error state, and opportunity detail
- VoiceOver labels and reading order
- replacement tokens with more than one value
- Dynamic Type without clipping on iPhone and iPad
- light and dark themes
- right-to-left mirroring for Arabic, Farsi, and Urdu
- the system location prompt on a fresh install or reset simulator

Include privacy-safe screenshots, the tested device or simulator, OS version,
locale, and human reviewer in the pull request.

## Opportunity content is separate

App-interface strings belong here. Translated opportunity titles, summaries,
and descriptions belong in the
[GTA FREE STEM opportunity-data repository](https://github.com/rupayon123/gta-free-stem-opportunities).
Do not hand-edit the bundled `GTAFreeSTEM/Resources/opportunities.json` snapshot
as a substitute for updating its source data.
