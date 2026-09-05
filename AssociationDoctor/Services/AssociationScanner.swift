import OpenWithCore

/// Builds `ScannedAssociation`s from OpenWithCore's curated + discovered
/// targets — the raw material `DiagnosticEngine` turns into diagnosed
/// `AssociationRecord`s. Takes an `Engine` rather than constructing
/// `.live()` itself so tests can inject a fake `LaunchServicesProviding`
/// and never touch the machine's real defaults.
struct AssociationScanner {
    var engine: Engine
    var discoveryDirectories: [String]

    init(engine: Engine = .live(), discoveryDirectories: [String] = Discovery.defaultDirectories) {
        self.engine = engine
        self.discoveryDirectories = discoveryDirectories
    }

    func scan() -> [ScannedAssociation] {
        let curated = Curated.targets
        let discovered = Discovery.discoverTargets(directories: discoveryDirectories, existing: curated)
        let allEntries = curated + discovered

        var categoryByTarget: [Target: CuratedTarget.Category] = [:]
        var labelByTarget: [Target: String] = [:]
        for entry in allEntries {
            categoryByTarget[entry.target] = entry.category
            labelByTarget[entry.target] = entry.label
        }

        // Different `Target`s (an extension and a UTI, say) can resolve to
        // the same LaunchServices key; dedupe on that, not on the raw
        // `Target`, or the same file type shows up twice (§7).
        var seenResolved = Set<ResolvedTarget>()
        var records: [ScannedAssociation] = []

        for entry in allEntries {
            let target = entry.target
            guard let resolved = try? engine.resolve(target) else { continue }
            guard seenResolved.insert(resolved).inserted else { continue }

            let uti: String?
            switch resolved {
            case .contentType(let value): uti = value
            case .scheme: uti = nil
            }

            let localizedTypeName = uti.flatMap { engine.provider.localizedDescription(forContentType: $0) }
                ?? labelByTarget[target]

            records.append(
                ScannedAssociation(
                    id: target.description,
                    target: target,
                    uti: uti,
                    localizedTypeName: localizedTypeName,
                    category: FileCategoryClassifier.classify(
                        target: target, uti: uti, curatedCategory: categoryByTarget[target]),
                    currentApp: engine.currentDefault(for: resolved),
                    availableApps: (try? engine.handlers(for: target)) ?? []
                )
            )
        }

        return records.sorted {
            ($0.localizedTypeName ?? $0.target.value)
                .localizedCaseInsensitiveCompare($1.localizedTypeName ?? $1.target.value) == .orderedAscending
        }
    }
}
