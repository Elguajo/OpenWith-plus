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
├── Domain/         AssociationRecord, FileCategory, AssociationStatus,
│                   Finding, Recommendation, Baseline, RepairPlan
├── Services/       AssociationScanner (curated + discovered targets →
│                   deduped, categorized records), FileCategoryClassifier
└── Features/Scan/  ScanDebugView — temporary PoC UI (until Phase 6's
                    real Dashboard/Problems/All Associations screens)

AssociationDoctorTests/
├── FakeLaunchServicesProvider.swift    — in-memory LaunchServicesProviding
├── AssociationScannerTests.swift       — dedup, categorization, no-default;
│                                         never touches real machine defaults
└── FileCategoryClassifierTests.swift
```

`AssociationRecord` intentionally has no `status` or `recommendation` field
yet: those are computed by the Diagnostic Engine (Phase 4) and
Recommendation Engine (Phase 5), which don't exist yet — adding the fields
now would mean guessing their values in the scanner and redoing it later.
`AppState` and the real Dashboard/Problems/Profiles UI land with Phases 6–8.

## Build & test

```console
xcodebuild -project AssociationDoctor.xcodeproj -scheme AssociationDoctor -destination 'platform=macOS' build
xcodebuild -project AssociationDoctor.xcodeproj -scheme AssociationDoctor -destination 'platform=macOS' test
```
