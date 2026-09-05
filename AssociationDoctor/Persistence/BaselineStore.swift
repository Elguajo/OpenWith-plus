import Foundation

/// JSON persistence for the saved baseline (§13/§24) in Application
/// Support — never `UserDefaults`, never Core Data/SwiftData. MVP holds a
/// single baseline file ("My Mac" per §14's MVP scope); multiple named
/// profiles is V2.
struct BaselineStore {
    private let fileURL: URL
    private let fileManager: FileManager

    /// - Parameters:
    ///   - directory: where `baseline.json` lives. Defaults to this app's
    ///     real `~/Library/Application Support/AssociationDoctor`; tests
    ///     inject a temp directory so nothing here ever touches real user
    ///     state (same spirit as `SettingsStore`'s injectable `UserDefaults`).
    init(directory: URL = BaselineStore.defaultDirectory, fileManager: FileManager = .default) {
        self.fileURL = directory.appendingPathComponent("baseline.json")
        self.fileManager = fileManager
    }

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("AssociationDoctor", isDirectory: true)
    }

    /// `nil` when nothing has been saved yet, or the file can't be read —
    /// a missing/corrupt baseline is the same "no baseline" state to every
    /// caller, not an error worth surfacing.
    func load() -> Baseline? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(Baseline.self, from: data)
    }

    func save(_ baseline: Baseline) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(baseline)
        try data.write(to: fileURL, options: .atomic)
    }

    // `.iso8601` and `.secondsSince1970` both round-trip `Date` lossily —
    // JSON's `Double` formatting only keeps ~8 significant digits, which
    // silently drifts a Unix-epoch timestamp's fractional seconds. Integer
    // milliseconds-since-1970 round-trips exactly and is far more precision
    // than `createdAt` (shown to the user as a bare day, §21) ever needs.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64((date.timeIntervalSince1970 * 1000).rounded()))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let milliseconds = try container.decode(Int64.self)
            return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        }
        return decoder
    }()
}
