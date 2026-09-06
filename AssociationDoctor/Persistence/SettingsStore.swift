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
    /// Unlocks the associations macOS itself depends on — apps, installers,
    /// disk images, OS components, Apple's internal URL schemes (see
    /// `AssociationProtection`). Off by default and never flipped by the
    /// app: a wrong handler here can leave a Mac unable to install
    /// software or open System Settings, which is not something a
    /// one-click Fix should be able to do behind the user's back.
    @Published var allowProtectedAssociationChanges: Bool {
        didSet { defaults.set(allowProtectedAssociationChanges, forKey: Keys.allowProtectedChanges) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let scanOnLaunch = "settings.scanOnLaunch"
        static let showLowConfidence = "settings.showLowConfidenceRecommendations"
        static let includeURLSchemes = "settings.includeURLSchemes"
        static let includeSystemFileTypes = "settings.includeSystemFileTypes"
        static let showAdvancedUTI = "settings.showAdvancedUTIIdentifiers"
        static let allowProtectedChanges = "settings.allowProtectedAssociationChanges"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        scanOnLaunch = defaults.object(forKey: Keys.scanOnLaunch) as? Bool ?? true
        showLowConfidenceRecommendations = defaults.bool(forKey: Keys.showLowConfidence)
        includeURLSchemes = defaults.object(forKey: Keys.includeURLSchemes) as? Bool ?? true
        includeSystemFileTypes = defaults.object(forKey: Keys.includeSystemFileTypes) as? Bool ?? true
        showAdvancedUTIIdentifiers = defaults.bool(forKey: Keys.showAdvancedUTI)
        allowProtectedAssociationChanges = defaults.bool(forKey: Keys.allowProtectedChanges)
    }
}
