# Association Doctor

Native macOS app that diagnoses and repairs file-type / URL-scheme default
app associations. See
[Association_Doctor_TZ_and_AI_Agent_Prompt.md](Association_Doctor_TZ_and_AI_Agent_Prompt.md)
for the full spec and roadmap.

## Dependency decision

`OpenWithCore` from [jmarette/openwith](https://github.com/jmarette/openwith)
is consumed as a remote Swift Package (`.package(url: ..., from: "0.1.0")`,
see `project.yml`), not vendored or forked:

- Its `OpenWithCore` library product is public API only (`Engine`,
  `LaunchServicesProvider`/`LaunchServicesProviding`, `Discovery`,
  `Curated.targets`, `Target`, `ResolvedTarget`, `AppInfo`, read-back
  `SetOutcome`) — everything Phase 0/1 (and the diagnostics/repair phases
  after it) need is already exposed; no fork or patch required.
- `Apps/` (the upstream GUI + PrefPane) is a separate Xcode project outside
  SPM, so depending on the `OpenWithCore` product pulls in none of it.
- Dual-licensed MIT / Apache-2.0 (permissive); no attribution beyond
  keeping the upstream license files applies.
- Pinned to the `v0.1.0` tag (current `master`), matching this project's
  `swift-tools-version: 6.1` / macOS 15 baseline exactly.

**Gap found in Phase 4:** no public OpenWithCore API can tell "no default
was ever set" apart from "the default was set, but that app is now
uninstalled" (`broken`, §10.1) — `LaunchServicesProviding.defaultApp`
always resolves the registered bundle ID to an installed `AppInfo` first,
collapsing both cases to `nil`. Per §44 ("implement a local adapter before
forking"), `Services/RawDefaultHandlerProviding.swift` calls the same
public LaunchServices C API `LaunchServicesProvider` already uses
internally (`LSCopyDefaultRoleHandlerForContentType` /
`LSCopyDefaultHandlerForURLScheme`) to read the raw registration, behind
its own small protocol so tests still never touch real LaunchServices.

**Gap found in Phase 5:** the "category matches" signal (§11.1, +30 —
the heaviest weight in the scoring table) needs to know what *kinds* of
files a candidate app generally handles, not just this one target.
OpenWithCore's `Discovery` only exposes a directory-wide *merged* target
list built for the curated table; it has no per-app query.
`Services/AppDeclaredTypesReading.swift` reads one app's own
`CFBundleDocumentTypes` (the same Info.plist keys `Discovery` reads
internally, scoped to a single app) so `RecommendationEngine` can tally its
declared UTIs/extensions into a dominant `FileCategory` — again a local
adapter, not a fork, behind its own fake-able protocol.

## Project structure

Generated via [XcodeGen](https://github.com/yonaskolb/XcodeGen) from
`project.yml` (same convention upstream uses for its own `Apps/`):
`AssociationDoctor.xcodeproj` is committed so CI/other machines don't need
xcodegen installed. Regenerate after editing `project.yml`:

```console
xcodegen generate
```

```text
AssociationDoctor/
├── App/            AssociationDoctorApp.swift — @main entry point
├── Domain/         ScannedAssociation (raw scan output) → AssociationRecord
│                   (diagnosed, with status); FileCategory, AssociationStatus,
│                   Finding, Recommendation, Baseline, RepairPlan
├── Services/       AssociationScanner (curated + discovered targets →
│                   deduped, categorized ScannedAssociations),
│                   FileCategoryClassifier, DiagnosticEngine (→ status),
│                   RawDefaultHandlerProviding (broken-detection adapter),
│                   RecommendationEngine (deterministic scoring, §11),
│                   AppDeclaredTypesReading (per-app category adapter)
└── Features/Scan/  ScanDebugView — temporary PoC UI (until Phase 6's
                    real Dashboard/Problems/All Associations screens)

AssociationDoctorTests/
├── FakeLaunchServicesProvider.swift     — in-memory LaunchServicesProviding
├── FakeRawDefaultHandlerProvider.swift  — in-memory RawDefaultHandlerProviding
├── FakeAppDeclaredTypesReader.swift     — in-memory AppDeclaredTypesReading
├── AssociationScannerTests.swift        — dedup, categorization, no-default
├── DiagnosticEngineTests.swift          — healthy/broken/noDefault/changed/
│                                         suspicious, and baseline priority
├── RecommendationEngineTests.swift      — each scoring signal + confidence
└── FileCategoryClassifierTests.swift

All tests run against fakes; none touches real machine defaults.
```

`AssociationStatus.ignored` stays unreachable until the Ignore feature
(§23) exists — `DiagnosticEngine` never guesses at it. `AppState` and the
real Dashboard/Problems/Profiles UI land with Phases 6–8.

## Build & test

```console
xcodebuild -project AssociationDoctor.xcodeproj -scheme AssociationDoctor -destination 'platform=macOS' build
xcodebuild -project AssociationDoctor.xcodeproj -scheme AssociationDoctor -destination 'platform=macOS' test
```
