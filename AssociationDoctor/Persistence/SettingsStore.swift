import Foundation

/// User-facing preferences (§22), backed by `UserDefaults` per §24 (no
/// Core Data / SwiftData for simple flags like these).
@MainActor
final class SettingsStore: ObservableObject {
    @Published var scanOnLaunch: Bool { didSet { defaults.set(scanOnLaunch, forKey: Keys.scanOnLaunch) } }
    @Published var showLowConfidenceRecommendations: Bool {
        didSet { defaults.set(showLowConfidenceRecommendations, forKey: Keys.showLowConfidence) }
    }
    @Published var includeURLSchemes: Bool { didSet { defaults.set(includeURLSchemes, forKey: Keys.includeURLSchemes) } }
    @Published var includeSystemFileTypes: Bool {
        didSet { defaults.set(includeSystemFileTypes, forKey: Keys.includeSystemFileTypes) }
    }
    @Published var showAdvancedUTIIdentifiers: Bool {
        didSet { defaults.set(showAdvancedUTIIdentifiers, forKey: Keys.showAdvancedUTI) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let scanOnLaunch = "settings.scanOnLaunch"
        static let showLowConfidence = "settings.showLowConfidenceRecommendations"
        static let includeURLSchemes = "settings.includeURLSchemes"
        static let includeSystemFileTypes = "settings.includeSystemFileTypes"
        static let showAdvancedUTI = "settings.showAdvancedUTIIdentifiers"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        scanOnLaunch = defaults.object(forKey: Keys.scanOnLaunch) as? Bool ?? true
        showLowConfidenceRecommendations = defaults.bool(forKey: Keys.showLowConfidence)
        includeURLSchemes = defaults.object(forKey: Keys.includeURLSchemes) as? Bool ?? true
        includeSystemFileTypes = defaults.object(forKey: Keys.includeSystemFileTypes) as? Bool ?? true
        showAdvancedUTIIdentifiers = defaults.bool(forKey: Keys.showAdvancedUTI)
    }
}
