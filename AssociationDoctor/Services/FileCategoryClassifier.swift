import OpenWithCore
import UniformTypeIdentifiers

/// Classifies a resolved target into a `FileCategory` (§8), preferring the
/// most specific signal available: a few extensions macOS has no umbrella
/// UTI for, then `UTType.conforms(to:)`, then the curated list's own
/// (coarser) category, else `.unknown`.
enum FileCategoryClassifier {
    private static let spreadsheetExtensions: Set<String> = ["xls", "xlsx", "numbers"]
    private static let presentationExtensions: Set<String> = ["ppt", "pptx", "key"]
    private static let ebookExtensions: Set<String> = ["epub", "mobi", "azw", "azw3"]

    static func classify(target: Target, uti: String?, curatedCategory: CuratedTarget.Category?) -> FileCategory {
        if case .ext(let ext) = target {
            let normalized = ext.lowercased()
            if spreadsheetExtensions.contains(normalized) { return .spreadsheet }
            if presentationExtensions.contains(normalized) { return .presentation }
            if ebookExtensions.contains(normalized) { return .ebook }
        }

        if let uti, let type = UTType(uti) {
            if type.conforms(to: .archive) { return .archive }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .pdf) { return .document }
            if type.conforms(to: .sourceCode) { return .code }
            if type.conforms(to: .html) { return .web }
            if type.conforms(to: .font) { return .font }
            if type.conforms(to: .diskImage) { return .diskImage }
            if type.conforms(to: .executable) { return .executable }
            if type.conforms(to: .text) { return .text }
        }

        if case .urlScheme = target { return .web }

        switch curatedCategory {
        case .text: return .text
        case .web: return .web
        case .developer: return .code
        case .documents: return .document
        case .images: return .image
        case .audio: return .audio
        case .video: return .video
        case .archives: return .archive
        case .urlSchemes: return .web
        case .discovered, nil: return .unknown
        }
    }
}
