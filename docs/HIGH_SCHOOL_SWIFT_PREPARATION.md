# Swift High School model preparation — not activated

Base: `edc0453`, in the shipped build-19 lineage (`ee6edf3`), with app source
`a96d2f4`. These new files are deliberately not registered in the Xcode project,
referenced by app UI, or connected to existing feed/cache/SwiftData models. There
is no new service, account, background work, network request or telemetry.

The source reference is accepted web core
`f4d87bfad2f33ac2acc95c8b292a8e84fac8118a`. No isolated native catalogue or
translation adapter is imported. No curated provider records are copied here:
the three JSON files are synthetic policy/reference fixtures only.

## API and ownership

- `GTAFreeSTEM/HighSchool/YouthListing.swift`: `YouthHub.Listing` and nested
  Codable/Sendable fields; `decodeCatalogue(Data)`, `validate(Listing)`,
  `evaluate(Listing, context: EvaluationContext)` and `Evaluation.jsonData()`.
  The context supplies the clock, selected age/grade and evidence freshness.
  Unknown ages/grades remain nil. Portable output explicitly emits null. Grade-12
  eligibility admits an 18-year-old subject to provider conditions; ordinary
  adult/child-parent keywords do not create eligibility. Directory status,
  required costs, conflicting/held/stale sources, Toronto season days and
  application instants follow the shared policy. No automatic school credit.
- `GTAFreeSTEM/HighSchool/YouthHoursNotebook.swift`: independent
  `YouthHub.HoursEntry`, `HoursArchive`, `NotebookFailure` and `Notebook`.
  Entry fields preserve the shared JSON names and integer revision. APIs are
  `load(storage,today:)`, `save(storage,entry:today:expectedRevision:)`,
  `delete(storage,id:today:expectedRevision:)`, `recordedMinutes`, `formatMinutes`
  and `csv`. Results are explicit `Result<HoursArchive, NotebookFailure>` values.
  Errors use the shared read-failed/invalid-archive/invalid-entry/write-failed/
  conflict/not-found strings. Every user text CSV cell is apostrophe-prefixed;
  quotes, commas and line breaks are escaped; original stored text is retained.
- `YouthHoursAtomicStorage: Sendable` is injected and unimplemented. Its async
  `read(key:)` and `compareAndSwap(key:expected:replacement:)` must serialize all
  writers and acknowledge only completed durable commits. UserDefaults get/set
  is not such an adapter. Per-entry revisions independently reject stale edits
  and deletes even when update timestamps are equal. No automatic retries.
- `GTAFreeSTEMTests/YouthHighSchoolTests.swift` consumes all 14 full-output
  goldens and independently asserts every field in the original policy packet.
  Additional source tests cover actual minutes, calendar/DST dates, equal-time
  revision races, storage errors, corrupt bytes, CSV formulas and held/stale
  sources. Its actor storage double is not a real persistence adapter.
- `GTAFreeSTEMTests/HighSchoolFixtures/`: exact web copies of `eligibility.json`,
  `eligibility-goldens.json`, `notebook-golden.json`. The test loader first looks
  for a bundled `HighSchoolFixtures` subdirectory, then the source directory.
  Root must explicitly register source and fixtures before execution.

## Swift semantics requiring review and execution

1. **Host model checked; iOS integration untested.** One bounded temporary Swift
   package compiled the exact source and ran all eight XCTest methods, including
   all 14 full-output/reference policy cases: exit 0, zero failures, Swift 6,
   complete concurrency checking, production-source warnings as errors. Project
   settings specify Swift 6.0 and no default actor-isolation override; the harness
   uses that nonisolated default. No project membership changed and no Xcode app
   build, simulator, archive or signing ran. Actual storage, UI, native lifecycle,
   accessibility/offline tests and release identity checks remain mandatory.
   Receipt/log/harness: `outputs/high-school-swift-host-20261030` in the parent
   workspace. Batch elapsed 31.02 seconds, peak aggregate RSS 767,508,480 bytes;
   tests took 0.196 seconds. This patch is preparation, not delivery.
2. String bounds use UTF-16 length to match JavaScript rather than Swift grapheme
   count. Trimming uses the exact ECMAScript whitespace/line-terminator set, including BOM and excluding U+0085/U+200B; the boundary set is tested. JSON uses safe-integer bounds where
   the TS contract does; activity dates remain strings without UTC conversion.
3. ISO date parsing uses local ISO8601 formatters, and Toronto display/season days
   use a Gregorian calendar and explicit timezone. They share no mutable static
   formatter. Fraction precision is 0–3 digits. Cross-platform parsing of unusual
   valid offsets still needs fixture execution; do not loosen invalid dates.
4. Foundation URL parsing is not WHATWG URL parsing. The port rejects local/IP
   destinations, including numeric/hex IPv4 components, and strips a trailing
   domain dot for the local-suffix check. This is intentionally stricter for a
   local trailing-dot host than the current TS guard. HTTPS port 443 is accepted
   to match WHATWG's removal of a default port; custom ports reject. There is no
   DNS resolution or fetch. Review before exposing externally supplied links.
5. On listing JSON input, explicit null is rejected for known optional fields
   to match TS absence-only validation; typed optional nil is allowed. Unknown
   listing metadata is ignored, including nested null, matching TS. Required
   fields still require their declared type. Notebook unknown keys and explicit
   null still reject. No approval field can override computed zero credit.
6. Swift task cancellation before a notebook commit returns write-failed and
   starts no write. Once an adapter confirms a commit, the service returns the
   actual committed state. A caller must suppress stale UI publication itself.
   An adapter error after a possible commit is unconfirmed, requiring reload
   before retry. No future UI may report success from a draft or request-start.
7. JSONEncoder's key order is not a digest contract. Archive CAS compares the
   exact string last read. Fixtures compare parsed JSON values and exact CSV;
   they do not require Swift to reproduce JavaScript object byte order.

The web content's nine reviewed programmes/resources are separately root-owned.
Strides remains held; CVC 2026 season text does not imply a new intake. Current
open-role coverage stays incomplete. A later native UI must use verified free
role/program decisions rather than audience relevance alone, retain exact source
restrictions, and clearly distinguish recorded time from school approval.
