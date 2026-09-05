# Association Doctor for macOS
## Техническое задание, архитектура, roadmap и стартовый prompt для AI-агента

**Рабочее название:** Association Doctor  
**Платформа:** macOS  
**Технологии:** Swift 6.1+, SwiftUI, AppKit / NSWorkspace, UniformTypeIdentifiers, LaunchServices  
**Минимальная версия macOS:** macOS 15+  
**Базовый open-source проект:** https://github.com/jmarette/openwith  
**Рекомендуемый способ интеграции:** использовать `OpenWithCore` как зависимость / отдельный core-слой, не переписывая весь upstream UI.

---

# 1. Цель продукта

Создать нативное macOS-приложение, которое:

1. сканирует установленные приложения;
2. определяет, какие типы файлов / UTI / расширения они умеют открывать;
3. получает текущее приложение по умолчанию для каждого типа;
4. выявляет:
   - отсутствующие обработчики;
   - подозрительные ассоциации;
   - изменившиеся ассоциации;
   - устаревшие ассоциации;
   - конфликты / дубликаты;
5. рекомендует более подходящие установленные приложения;
6. позволяет исправлять ассоциации;
7. сохраняет пользовательский baseline / desired state;
8. позволяет восстанавливать выбранные ассоциации после обновлений macOS или приложений;
9. даёт понятную визуальную диагностику состояния системы.

Главная идея продукта:

> Не просто менять Open With, а диагностировать здоровье file associations и помогать пользователю поддерживать их в желаемом состоянии.

---

# 2. Главная пользовательская проблема

Пример:

```text
.rar → VLC
```

Пользователь ожидает:

```text
.rar → The Unarchiver
```

macOS при этом может:

- хранить неправильный default handler;
- показывать устаревшую иконку;
- иметь несколько зарегистрированных обработчиков;
- менять default handler после установки / обновления приложений;
- ссылаться на приложение, которое уже удалено.

Association Doctor должен показывать:

```text
.rar
Current: VLC
Status: Suspicious

Recommended:
The Unarchiver

Other available:
Keka
BetterZip

[Fix] [Choose another] [Ignore]
```

---

# 3. Что берём из OpenWith

Использовать возможности `OpenWithCore`, если они подходят без изменений.

Из upstream нужны:

- `Engine`
- `LaunchServicesProvider`
- `Discovery`
- `CuratedTargets`
- `Target`
- `ResolvedTarget`
- `AppInfo`
- текущие handlers API
- чтение current default
- изменение default handler
- проверка результата после изменения
- import/export config
- apply/dry-run
- базовая doctor-логика
- тестовая архитектура через provider abstraction

Не копировать существующий UI как основу нового продукта.

Новый продукт должен иметь собственный SwiftUI UI и собственную domain-логику диагностики.

---

# 4. Архитектура

Предлагаемая схема:

```text
AssociationDoctor.app
│
├── App
│   ├── AssociationDoctorApp.swift
│   └── AppState.swift
│
├── Features
│   ├── Dashboard
│   ├── Scan
│   ├── Problems
│   ├── Associations
│   ├── Profiles
│   ├── Settings
│   └── Onboarding
│
├── Domain
│   ├── AssociationRecord.swift
│   ├── AssociationStatus.swift
│   ├── Finding.swift
│   ├── Recommendation.swift
│   ├── HealthScore.swift
│   ├── Baseline.swift
│   └── RepairPlan.swift
│
├── Services
│   ├── AssociationScanner.swift
│   ├── RecommendationEngine.swift
│   ├── DiagnosticEngine.swift
│   ├── BaselineStore.swift
│   ├── RepairService.swift
│   ├── AppClassifier.swift
│   └── IconCacheService.swift
│
├── Persistence
│   ├── Codable models
│   ├── JSON baseline storage
│   └── SettingsStore
│
└── Dependencies
    └── OpenWithCore
```

---

# 5. Основные domain-модели

## 5.1 AssociationRecord

```swift
struct AssociationRecord: Identifiable, Hashable {
    let id: String

    let extensionName: String?
    let uti: String
    let localizedTypeName: String?

    let currentApp: AppInfo?
    let availableApps: [AppInfo]

    let category: FileCategory
    let status: AssociationStatus

    let recommendation: Recommendation?
}
```

---

## 5.2 AssociationStatus

```swift
enum AssociationStatus {
    case healthy
    case suspicious
    case broken
    case changed
    case noDefault
    case ignored
}
```

---

## 5.3 Finding

```swift
struct Finding: Identifiable {
    let id: UUID

    let severity: Severity
    let type: FindingType
    let title: String
    let description: String

    let association: AssociationRecord?
    let recommendation: Recommendation?
}
```

---

## 5.4 Recommendation

```swift
struct Recommendation {
    let suggestedApp: AppInfo
    let score: Double
    let confidence: RecommendationConfidence
    let reasons: [RecommendationReason]
}
```

Важно:

Recommendation Engine не должен автоматически считать рекомендацию истиной.

Результат должен быть объяснимым:

```text
Recommended: The Unarchiver

Reasons:
- declares archive support
- ranked higher by macOS
- application category matches archive
- current VLC association looks category-inconsistent
```

---

# 6. Сканирование системы

## 6.1 Источники приложений

Сканировать минимум:

```text
/Applications
/Applications/Utilities
/System/Applications
/System/Applications/Utilities
~/Applications
```

При необходимости можно добавить дополнительные application directories позже.

---

## 6.2 Источники file types

Использовать:

- `Curated.targets`
- `Discovery.discoverTargets()`
- `CFBundleDocumentTypes`
- `LSItemContentTypes`
- `CFBundleTypeExtensions`
- `CFBundleURLTypes`
- `CFBundleURLSchemes`
- `UniformTypeIdentifiers`

Не пытаться обещать «абсолютно все существующие file types».

Приложение должно работать с теми типами, которые:

- известны curated list;
- объявлены установленными приложениями;
- были сохранены в baseline;
- были явно добавлены пользователем.

---

# 7. Association Scanner

`AssociationScanner` должен:

1. получить список известных targets;
2. нормализовать extension → UTI;
3. убрать дубликаты;
4. для каждого target получить:
   - current default;
   - compatible handlers;
   - localized description;
5. классифицировать file type;
6. передать данные Diagnostic Engine.

Псевдокод:

```swift
for target in allTargets {
    let resolved = try engine.resolve(target)

    let current = engine.currentDefault(for: resolved)
    let handlers = try engine.handlers(for: target)

    let record = AssociationRecord(...)
    records.append(record)
}
```

---

# 8. Категории файлов

Нужен enum:

```swift
enum FileCategory {
    case archive
    case image
    case video
    case audio
    case document
    case text
    case code
    case design
    case threeD
    case font
    case spreadsheet
    case presentation
    case ebook
    case diskImage
    case executable
    case web
    case unknown
}
```

Категория определяется по:

1. известным UTI;
2. `UTType.conforms(to:)`;
3. extension map;
4. curated mapping;
5. fallback `.unknown`.

---

# 9. Классификация приложений

Нужен `AppClassifier`.

Пример категорий:

```swift
enum AppCategory {
    case archiveUtility
    case mediaPlayer
    case imageViewer
    case imageEditor
    case videoEditor
    case textEditor
    case codeEditor
    case browser
    case designTool
    case officeApp
    case systemUtility
    case unknown
}
```

Классификация не должна зависеть только от имени приложения.

Использовать комбинацию:

- declared UTTypes;
- declared extensions;
- bundle metadata;
- количество типов конкретной категории;
- системный ranking;
- optional curated app signatures.

---

# 10. Diagnostic Engine

## 10.1 Broken

Пример:

```text
.psd → Photoshop 2025
```

но Photoshop 2025 больше не установлен.

Результат:

```text
Broken association
Default app is not available
```

Если установлен Photoshop 2026:

```text
Suggested replacement:
Adobe Photoshop 2026
```

---

## 10.2 No Default

```text
.foo → none
```

Если есть handlers:

```text
No default app

Available:
App A
App B
```

---

## 10.3 Changed

Только при наличии baseline.

```text
Expected:
.mkv → IINA

Current:
.mkv → QuickTime
```

Статус:

```text
Changed
```

---

## 10.4 Suspicious

Пример:

```text
.rar → VLC
```

Не считать ошибкой автоматически.

Статус:

```text
Suspicious
```

только если Recommendation Engine имеет достаточную уверенность.

---

## 10.5 Duplicate / legacy app

Пример:

```text
Photoshop 2025
Photoshop 2026
Photoshop Beta
```

Нужно показывать это как информационный finding, если current default использует старую / удалённую версию.

---

# 11. Recommendation Engine

## 11.1 Принцип

Не строить «AI магию» в MVP.

Сначала deterministic scoring.

Пример:

```text
score = 0
```

Добавлять баллы:

```text
+30 category matches
+20 first in NSWorkspace ranking
+15 declares exact UTI
+10 declares exact extension
+10 app is already preferred for related formats
+10 baseline says this app
+5 system utility for system-compatible type
```

Снижать:

```text
-30 obvious category mismatch
-25 app missing
-15 handler only weakly matches
```

---

## 11.2 Confidence

```swift
enum RecommendationConfidence {
    case low
    case medium
    case high
}
```

Правило MVP:

- low → только показать варианты;
- medium → показать recommendation;
- high → разрешить One-click Fix.

---

# 12. Health Score

Пример:

```text
97 associations scanned

88 Healthy
6 Suspicious
2 Broken
1 Changed
```

Простая формула MVP:

```text
healthy = 0 penalty
changed = -1
suspicious = -2
noDefault = -3
broken = -5
```

Нормализовать к 0...100.

Не использовать Health Score как абсолютную техническую истину.

Это только визуальный индикатор.

---

# 13. Baseline / Desired State

Пользователь может сохранить текущее состояние:

```text
Save Current Defaults
```

Baseline:

```swift
struct Baseline {
    let id: UUID
    let name: String
    let createdAt: Date
    let associations: [BaselineAssociation]
}
```

Пример:

```json
{
  "schemaVersion": 1,
  "name": "My Mac",
  "associations": [
    {
      "uti": "public.zip-archive",
      "extension": "zip",
      "bundleID": "..."
    }
  ]
}
```

---

# 14. Profiles

MVP:

```text
My Mac
```

V2:

```text
Design
Development
Video Editing
Default Mac
```

Профили позволяют переключать expected handlers.

---

# 15. Repair Service

Repair Service получает:

```swift
RepairPlan
```

Пример:

```swift
struct RepairPlan {
    let changes: [RepairAction]
}
```

Каждый action:

```swift
struct RepairAction {
    let target: Target
    let currentApp: AppInfo?
    let desiredApp: AppInfo
}
```

Перед применением:

```text
Review Changes
```

Показывать:

```text
.rar
VLC → The Unarchiver
```

После изменения обязательно read-back validation.

Нельзя считать API success достаточным.

---

# 16. Важное ограничение macOS

Upstream OpenWith указывает, что современные версии macOS могут показывать системное подтверждение для изменения default file handler.

Поэтому нельзя проектировать UX с предположением:

```text
Fix 100 associations
→ без единого подтверждения
```

Правильный UX:

```text
Fix 8 Issues
```

затем показывать прогресс:

```text
1/8 Applied
2/8 Waiting for macOS confirmation
3/8 User declined
...
```

После каждого изменения делать read-back.

---

# 17. UI / UX

## 17.1 Sidebar

```text
Dashboard
Problems
All Associations
Profiles
Settings
```

---

# 18. Dashboard

Экран:

```text
Association Health

91%

97 file types scanned

✓ Healthy        88
⚠ Suspicious      6
✕ Broken          2
↻ Changed         1

[Review Problems]

Last scan: 2 min ago
```

---

# 19. Problems

Фильтры:

```text
All
Broken
Suspicious
Changed
No Default
```

Карточка:

```text
.rar

Current
VLC

Recommended
The Unarchiver

Reason
Archive handler better matches this file type

[Fix]
[Choose another]
[Ignore]
```

---

# 20. All Associations

Табличный / list UI:

```text
Search...

Archives
.rar     VLC                 Suspicious
.zip     The Unarchiver      Healthy
.7z      Keka                Healthy

Video
.mp4     IINA                Healthy
.mov     QuickTime Player    Healthy
.mkv     IINA                Healthy
```

Нужны:

- search;
- filter;
- sort;
- category grouping;
- app icon;
- file extension;
- current app;
- status.

---

# 21. Profiles

```text
My Mac

154 saved associations

Created:
Sep 5, 2026

[Compare]
[Restore]
[Update Baseline]
[Export]
```

---

# 22. Settings

MVP:

```text
Scan on launch
Show low-confidence recommendations
Include URL schemes
Include system file types
Show advanced UTI identifiers
```

Опционально:

```text
Automatically rescan when Applications folder changes
```

Не включать automatic repair без явного пользовательского согласия.

---

# 23. Ignore system

Пользователь должен иметь:

```text
Ignore this recommendation
```

Хранить:

```swift
IgnoredFinding {
    target
    currentBundleID
    reason
}
```

Если current app поменялся — старый ignore можно считать неактуальным.

---

# 24. Persistence

Использовать простое локальное хранение.

MVP:

- JSON files;
- UserDefaults для settings;
- Application Support directory для baselines.

Не вводить Core Data / SwiftData без реальной необходимости.

---

# 25. Logging

Нужен structured logger.

Категории:

```text
scan
diagnostic
recommendation
repair
baseline
launchservices
```

Не логировать содержимое пользовательских файлов.

---

# 26. Privacy

MVP должен работать полностью локально.

Не отправлять:

- список установленных приложений;
- file associations;
- имена файлов;
- пользовательские paths

на сервер.

Если когда-либо появится cloud/AI recommendation service — только opt-in.

---

# 27. Работа с иконками

Показывать иконку приложения через AppKit.

Например:

```swift
NSWorkspace.shared.icon(forFile: app.path)
```

Не хранить дубликаты app icons без необходимости.

---

# 28. Icon Cache Doctor

Это отдельная optional feature.

Проблема:

```text
default app уже поменялся,
но Finder всё ещё показывает старую icon association
```

MVP:

только диагностика / подсказка.

V2:

можно добавить безопасную кнопку:

```text
Refresh Finder / icon cache
```

Но не внедрять разрушительные shell-команды без проверки.

---

# 29. LaunchServices Doctor

MVP:

```text
LaunchServices reachable
Default browser resolvable
Known curated UTIs resolvable
```

V2:

диагностика inconsistent LaunchServices state.

Не выполнять destructive rebuild автоматически.

---

# 30. Onboarding

Первый запуск:

```text
Welcome to Association Doctor

We'll scan the file types known on this Mac
and show which apps currently open them.

Nothing will be changed without your approval.

[Scan My Mac]
```

После scan:

```text
97 file types scanned

6 recommendations found
2 broken associations found

[Review]
```

---

# 31. MVP scope

Обязательно реализовать:

- OpenWithCore integration
- Scan installed apps
- Scan file associations
- Current default app
- Available handlers
- File categories
- Basic AppClassifier
- Diagnostic Engine
- Broken detection
- No default detection
- Suspicious detection
- Baseline
- Changed detection
- Recommendation Engine
- Manual Fix
- Read-back verification
- Dashboard
- Problems
- All Associations
- Profiles
- Settings
- Unit tests

Не делать в MVP:

- cloud;
- ML;
- login;
- subscription;
- telemetry;
- background daemon;
- automatic silent repair;
- App Store-specific purchase flow;
- huge curated database.

---

# 32. V1.1

После MVP:

- export/import profiles;
- better category heuristics;
- better app classification;
- URL schemes;
- bulk review;
- scan diff history;
- Finder icon refresh helper;
- app uninstall detection;
- live Applications folder monitoring.

---

# 33. V2

Возможные функции:

- multiple profiles;
- menu bar status;
- scheduled health scan;
- notifications when associations changed;
- device migration;
- shareable profiles;
- recommended presets:
  - Designer
  - Developer
  - Video Editor
  - Photographer

Важно: presets должны быть suggestions, не silently applied.

---

# 34. Tests

## Unit tests

Обязательные тесты:

```text
extension → UTI resolution
current default mapping
handler ranking
broken association
no default
changed from baseline
suspicious category mismatch
recommendation scoring
ignore behavior
repair plan
read-back validation
baseline serialization
```

Использовать fake provider.

Тесты не должны менять реальные defaults машины.

---

# 35. Integration tests

Отдельные opt-in tests:

- read real LaunchServices;
- scan installed apps;
- verify known harmless types;
- test manual change only на тестовом UTI / mock where possible.

Никогда не менять реальные пользовательские defaults в обычном CI.

---

# 36. Definition of Done для MVP

MVP считается готовым, если:

1. приложение запускается на macOS 15+;
2. список известных file types успешно сканируется;
3. для каждого отображается current default;
4. отображаются доступные handlers;
5. broken / no default / changed / suspicious работают;
6. recommendation имеет объяснение;
7. пользователь может изменить handler;
8. результат проверяется read-back;
9. baseline сохраняется;
10. после повторного scan changed associations определяются;
11. unit tests проходят;
12. приложение не отправляет пользовательские данные наружу;
13. UI не зависает при scan;
14. ошибки LaunchServices отображаются пользователю понятно.

---

# 37. Рекомендуемый порядок разработки

## Phase 0 — Repository setup

- создать новый repo;
- подключить OpenWith;
- проверить license;
- собрать minimal macOS app;
- добавить CI;
- добавить SwiftFormat / lint.

---

## Phase 1 — OpenWithCore integration

Результат:

```text
button Scan
→ получить curated/discovered types
→ вывести current apps в debug list
```

---

## Phase 2 — Domain layer

Реализовать:

```text
AssociationRecord
Finding
Recommendation
Baseline
RepairPlan
```

---

## Phase 3 — Scanner

Собрать:

```text
target
uti
extension
currentApp
handlers
category
```

---

## Phase 4 — Diagnostic Engine

Сначала:

```text
Healthy
Broken
No Default
Changed
```

Suspicious добавить после устойчивой базы.

---

## Phase 5 — Recommendation Engine

Deterministic scoring.

Без AI/LLM.

---

## Phase 6 — UI

Экран за экраном:

```text
Dashboard
Problems
All Associations
Profiles
Settings
```

---

## Phase 7 — Repair

Добавить:

```text
Review
Apply
Confirmation state
Read-back
Result
```

---

## Phase 8 — Baseline

Добавить:

```text
Create
Compare
Update
Restore
Export
```

---

## Phase 9 — QA

Проверить:

- VLC;
- IINA;
- The Unarchiver;
- Keka;
- Preview;
- Photoshop;
- VS Code;
- Safari / Chrome.

Не хардкодить наличие этих приложений.

---

# 38. Git strategy

Рекомендуемая структура веток:

```text
main
develop

feature/core-integration
feature/scanner
feature/diagnostics
feature/recommendations
feature/baseline
feature/dashboard
feature/repair
```

Каждый PR:

- небольшой;
- с тестами;
- без unrelated refactor.

---

# 39. Coding rules

AI-агент должен:

1. не переписывать OpenWithCore без необходимости;
2. сначала расширять через adapter / wrapper;
3. сохранять dependency inversion;
4. писать unit tests для domain logic;
5. не выполнять destructive shell commands;
6. не использовать private macOS API;
7. не добавлять network dependency без причины;
8. не добавлять Electron;
9. не добавлять third-party frameworks без необходимости;
10. использовать native SwiftUI/AppKit.

---

# 40. Риски

## Risk 1 — macOS confirmation dialogs

Bulk changes могут требовать подтверждений.

Решение:

- очередь изменений;
- прогресс;
- read-back;
- корректно обрабатывать decline.

---

## Risk 2 — false positive recommendation

Пример:

```text
.jpg → Photoshop
```

может быть осознанным выбором пользователя.

Решение:

- Suspicious != Broken;
- показывать confidence;
- Ignore;
- baseline имеет приоритет над heuristic.

---

## Risk 3 — неполный список file types

Нет универсального API для всех типов.

Решение:

- curated targets;
- installed apps discovery;
- baseline;
- user-added types.

---

## Risk 4 — upstream changes

OpenWith может обновиться.

Решение:

- wrapper layer;
- pin package version;
- не менять upstream core напрямую без причины.

---

# 41. Лицензирование

OpenWith опубликован под permissive license (MIT / Apache 2.0).

Перед релизом:

- сохранить copyright notices;
- добавить Third-Party Licenses;
- зафиксировать конкретную upstream commit/tag;
- проверить соответствие выбранной лицензии дистрибуции приложения.

---

# 42. Первая версия интерфейса

Главная цель UI:

> За 5 секунд пользователь должен понять, есть ли проблемы и что именно будет изменено.

Не перегружать UI UTI-терминами по умолчанию.

Показывать:

```text
RAR Archive (.rar)
```

а не:

```text
com.rarlab.rar-archive
```

UTI показывать в Advanced mode.

---

# 43. Ключевой продуктовый принцип

Разделять:

```text
Broken
```

и

```text
Suspicious
```

Broken — технически некорректно.

Suspicious — эвристика.

Это критически важно для доверия пользователя.

---

# 44. Стартовый prompt для AI coding agent

Скопировать весь prompt ниже и передать агенту.

---

## AI Agent Prompt

```text
You are the lead macOS engineer for a new native macOS app called “Association Doctor”.

Your task is to build the project incrementally, safely, and test-first where practical.

PRODUCT GOAL

Association Doctor scans macOS file associations, detects broken, suspicious, missing, or changed default handlers, recommends better installed applications, allows the user to repair associations, and can save/restore a user-defined baseline.

The app must be native Swift + SwiftUI.

TECH STACK

- Swift 6.1+
- SwiftUI
- AppKit / NSWorkspace
- UniformTypeIdentifiers
- LaunchServices only where required
- macOS 15+
- Swift Package Manager
- XCTest / Swift Testing where appropriate

UPSTREAM FOUNDATION

Use this project as the low-level file-association engine:

https://github.com/jmarette/openwith

Prefer consuming/reusing OpenWithCore instead of rewriting LaunchServices logic.

Important upstream concepts to reuse:

- Engine
- LaunchServicesProvider
- Discovery
- CuratedTargets
- Target
- ResolvedTarget
- AppInfo
- currentDefault
- handlers
- setDefault
- read-back verification
- import/export config where useful
- provider abstraction for tests

Do NOT copy the existing OpenWith GUI as the product UI.

Build a new application layer and new SwiftUI UI.

ARCHITECTURE

Create clear modules/layers:

App
Features
Domain
Services
Persistence
Dependencies

Suggested services:

AssociationScanner
DiagnosticEngine
RecommendationEngine
AppClassifier
BaselineStore
RepairService

Suggested domain models:

AssociationRecord
AssociationStatus
Finding
Recommendation
HealthScore
Baseline
RepairPlan

FUNCTIONAL REQUIREMENTS

1. Scan installed apps.
2. Discover file types from curated targets and installed app declarations.
3. Resolve extension -> UTI.
4. Get the current default handler.
5. Get all compatible handlers.
6. Categorize file types.
7. Detect:
   - healthy
   - broken
   - no default
   - changed from baseline
   - suspicious
8. Build deterministic recommendations.
9. Explain recommendation reasons.
10. Save a baseline.
11. Compare current state against baseline.
12. Repair a selected association.
13. Verify every write by reading the current default back.
14. Never silently assume a write succeeded.
15. Support Ignore for suspicious recommendations.
16. Show a health score.
17. Keep all user data local.

IMPORTANT PRODUCT RULES

Broken and Suspicious are not the same.

Broken means technically invalid or unavailable.

Suspicious means heuristic only.

Never automatically “repair” suspicious entries without user approval.

A user may intentionally use Photoshop for JPG or Chrome for SVG.

Therefore:
- show confidence
- show recommendation reasons
- provide Ignore
- baseline should override heuristics

RECOMMENDATION ENGINE

Start deterministic.

Do NOT use AI/LLM in MVP.

Signals can include:

+ exact UTI declaration
+ exact extension declaration
+ macOS NSWorkspace handler ranking
+ app category matches file category
+ same app preferred for related formats
+ saved baseline preference

Penalties:

- category mismatch
- missing app
- weak generic handler

Produce:

suggestedApp
score
confidence
reasons[]

PERSISTENCE

MVP:
- UserDefaults for settings
- JSON/Codable files in Application Support for baselines and ignores

Avoid Core Data / SwiftData unless necessary.

PRIVACY

No network calls.

Do not upload:
- installed app list
- file associations
- file names
- paths
- baseline information

No telemetry in MVP.

UI

Sidebar:

Dashboard
Problems
All Associations
Profiles
Settings

Dashboard should show:

Health score
number of scanned types
Healthy
Suspicious
Broken
Changed
Review Problems button
last scan time

Problems should support filters:

All
Broken
Suspicious
Changed
No Default

All Associations:

search
category grouping
extension/type
current app
status
app icon

Profiles:

Create baseline
Compare
Update baseline
Restore
Export

REPAIR FLOW

User selects Fix.

Show:

Current App -> Desired App

Then call OpenWithCore / provider.

macOS may show a confirmation dialog.

After the call:
READ THE VALUE BACK.

Possible outcomes:

alreadySet
applied
notConfirmed
failed

Display the real outcome.

Do not fake success.

TESTING

Use fake providers for tests.

Unit tests must never modify the developer’s real macOS file associations.

Write tests for:

extension -> UTI resolution
handler mapping
broken detection
no-default detection
changed-from-baseline
suspicious mismatch
recommendation scoring
ignore behavior
repair plan
baseline serialization
read-back validation

REPOSITORY RULES

Do not perform a huge rewrite.

Do not add Electron.

Do not use private macOS APIs.

Do not add unnecessary dependencies.

Prefer small commits.

Every implementation phase should remain buildable.

FIRST TASK

Do not start by implementing the entire product.

Start with Phase 0 and Phase 1 only.

PHASE 0

1. Inspect the upstream OpenWith repository.
2. Confirm how OpenWithCore can be consumed.
3. Create the new macOS project structure.
4. Add OpenWithCore.
5. Make the project build successfully.
6. Add a minimal test target.
7. Document the dependency and architecture decision.

PHASE 1

Build a proof-of-concept scanner.

Create:

AssociationRecord
AssociationScanner

The scanner must:

1. load curated targets
2. augment them using Discovery
3. de-duplicate targets
4. resolve each target
5. retrieve the current default app
6. retrieve compatible handlers
7. return AssociationRecord objects

Build a temporary SwiftUI debug view showing:

File type / extension
Current app
Number of handlers

Example:

RAR Archive (.rar)
Current: VLC
Handlers: 4

ZIP Archive (.zip)
Current: The Unarchiver
Handlers: 3

DO NOT implement recommendations yet.

DO NOT implement repair yet.

DO NOT implement the final dashboard yet.

After Phase 1:

- run the tests
- run the app
- report the project structure
- report which OpenWithCore APIs are used
- report any upstream limitations discovered
- propose the next exact implementation step

If the existing OpenWithCore API is insufficient, do not immediately fork it.

First:
1. explain the missing capability
2. implement a local adapter if possible
3. only propose a fork if there is no clean alternative

Keep the implementation maintainable and compatible with future upstream updates.
```

---

# 45. Что дать агенту вместе с prompt

Передать:

1. этот документ;
2. URL:
   `https://github.com/jmarette/openwith`;
3. новый пустой git repository;
4. доступ к Xcode / Swift toolchain;
5. правило:
   не реализовывать весь roadmap сразу.

Рекомендуемый первый результат от агента:

```text
AssociationDoctor.app запускается

Scan
↓
видны расширения / UTI
↓
виден current app
↓
видно количество available handlers
```

Только после этого переходить к Diagnostic Engine.

---

# 46. Краткий MVP milestone

```text
M0 Repository
↓
M1 Scanner
↓
M2 Diagnostics
↓
M3 Recommendations
↓
M4 UI
↓
M5 Repair
↓
M6 Baseline
↓
M7 QA
↓
MVP
```

Не смешивать все milestones в один большой PR.

---

# 47. Финальная продуктовая формула

```text
OpenWithCore
+
Association Scanner
+
Diagnostic Engine
+
Recommendation Engine
+
Baseline / Desired State
+
Repair Workflow
+
Native macOS UX
=
Association Doctor
```
