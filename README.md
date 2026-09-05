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
├── App/                 AssociationDoctorApp (@main) → RootView (sidebar +
│                        detail); AppState (scan/diagnose pipeline, session
│                        ignore list, navigation, settings)
├── Domain/              ScannedAssociation → AssociationRecord (status +
│                        recommendation); FileCategory, AssociationStatus,
│                        Finding, Recommendation, Baseline, RepairPlan,
│                        HealthScore (§12)
├── Services/            AssociationScanner, FileCategoryClassifier,
│                        DiagnosticEngine, RecommendationEngine,
│                        RepairService (single-item apply + read-back),
│                        RawDefaultHandlerProviding / AppDeclaredTypesReading
│                        (the two local adapters below)
├── Persistence/         SettingsStore (UserDefaults-backed §22 toggles);
│                        BaselineStore (Phase 8 — JSON baseline in
│                        Application Support, injectable directory for tests)
└── Features/
    ├── Dashboard/       Health score, status breakdown (§18)
    ├── Problems/        Filterable list; Fix / Choose Another / Ignore (§19)
    ├── Associations/    Searchable, category-grouped list (§20); defaults to
    │                    Common (curated) scope, "All" reveals the long tail
    ├── Applications/    Browse by program instead of by file type: pick an
    │                    app, see everything it can open, "Make Default" for
    │                    anything it isn't already (not in the original spec
    │                    — added on request; the reverse of All Associations
    │                    over the same scan data, no new scanning needed)
    ├── Profiles/        Save/Compare/Restore/Update Baseline (§13/§14/§21,
    │                    Phase 8) — single "My Mac" baseline (MVP scope);
    │                    Restore reuses Shared/RepairPlanSheet, no second flow
    ├── Settings/         (§22)
    └── Shared/          AppIconView, StatusBadge, AppPickerSheet (shared by
                         "Choose Another" / "Change..." / "Make Default"),
                         RepairOutcomeMessage (shared §15/§16 result wording),
                         recommendation display text

AssociationDoctorTests/
├── FakeLaunchServicesProvider.swift          — read-only LaunchServicesProviding
├── FakeWritableLaunchServicesProvider.swift  — same, but setDefault actually
│                                               sticks (needed to test apply)
├── FakeRawDefaultHandlerProvider.swift       — in-memory RawDefaultHandlerProviding
├── FakeAppDeclaredTypesReader.swift          — in-memory AppDeclaredTypesReading
├── AssociationScannerTests.swift             — dedup, categorization, no-default
├── DiagnosticEngineTests.swift               — healthy/broken/noDefault/changed/
│                                                suspicious, and baseline priority
├── RecommendationEngineTests.swift           — each scoring signal + confidence
├── RepairServiceTests.swift                  — applied/alreadySet/notConfirmed/failed
├── HealthScoreTests.swift
├── FileCategoryClassifierTests.swift
└── BaselineStoreTests.swift                  — save/load round-trip against a temp
                                                 directory; Baseline.capturing conversion

All tests run against fakes; none touches real machine defaults.
```

**Phase 6 scope decision — single-item repair, not the batch Repair Plan.**
Problems' Fix/Choose Another call `RepairService.apply` directly
(`Engine.setDefault` + read-back, exactly §15/§16's per-change contract).
The `RepairPlan`/`RepairAction` batch types (Phase 7: Dashboard's "Fix N
Issues", Profile Restore, with a progress/confirmation queue) stay unused
for now — a single click on one card never needed that machinery.

**Ignore (§23) is session-only.** `AppState` keeps an in-memory
`[record.id: bundleID-at-ignore-time]` map and auto-invalidates an entry
once the current app no longer matches it — matching §23's staleness rule
— but nothing is persisted to disk yet. Persisting `IgnoredFinding` can
follow `BaselineStore`'s pattern (below) if that becomes worth doing.

**Phase 8 — Baseline is wired end to end.** `BaselineStore` persists the
single "My Mac" baseline (§14 MVP scope — multiple named profiles is V2)
as JSON in Application Support, with an injectable directory so tests never
touch the real one. `AppState` loads it once at launch and threads it
through every `scan()` call, so `DiagnosticEngine`'s `.changed` status and
`RecommendationEngine`'s `matchesBaseline` scoring — both implemented and
tested since Phase 2/5 — are live for the first time. Profiles' Compare
reads the resulting `.changed` records directly rather than inventing a
second diff model; Restore builds a `RepairPlan` from them (baseline's
bundle ID as `desiredApp`, skipping any baseline app no longer installed)
and hands it to the same `RepairPlanSheet` Phase 7 built — no second
review/apply/result flow. Export (§21's wireframe) is V1.1 per the spec's
own roadmap (§32) and was left out.

**Common vs. All in All Associations.** A real scan turns up 1000+ types —
most of them obscure things some installed app happens to declare, not
anything a person is looking for. `AssociationRecord.isCurated` (true for
OpenWithCore's hand-picked `Curated.targets` — .rar/.zip/.mp4/.mp3 and the
rest) lets the screen default to that short, recognizable list instead of
burying it; "All" reveals the long tail on request. Every row — not just
Problems — can reassign its default via the same `AppPickerSheet` +
`RepairService` path, since fixing a *problem* isn't the only reason
someone wants to pick a different app.

**Applications screen (user-requested, not in the original spec).** Every
other screen answers "what opens this file type"; this one answers "what
can this program open, and can I just make it the default for that" —
picked an app first, not a type first. It needed zero new scanning:
`AssociationRecord.availableApps` (NSWorkspace's own, real handler list for
a type — already computed by `AssociationScanner`) is exactly "which apps
can open this," so `AppState.installedApps` / `records(for:)` just
re-slices the existing scan by app instead of by type. "Make Default"
reuses the same `RepairService` path as Problems/All Associations.

## Build & test

```console
xcodebuild -project AssociationDoctor.xcodeproj -scheme AssociationDoctor -destination 'platform=macOS' build
xcodebuild -project AssociationDoctor.xcodeproj -scheme AssociationDoctor -destination 'platform=macOS' test
```
