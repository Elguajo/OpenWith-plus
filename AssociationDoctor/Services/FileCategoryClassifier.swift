import OpenWithCore
import UniformTypeIdentifiers

/// Classifies a resolved target into a `FileCategory` (§8), preferring the
/// most specific signal available: a few extensions macOS has no umbrella
/// UTI for, then `UTType.conforms(to:)`, then the curated list's own
/// (coarser) category, else `.unknown`.
///
/// Getting the *document* formats right matters well beyond grouping:
/// `RecommendationEngine.dominantCategory` classifies an app's declared
/// types with no curated category to fall back on, so every UTI that lands
/// on `.unknown` here is a type that counts for nothing when deciding what
/// an app specializes in. While Office/iWork/OpenDocument formats fell
/// through (none of them conform to any of the coarse umbrellas), Word and
/// Pages had no document signal at all and collected a −30 category
/// mismatch on .docx, handing the +30 to whatever unrelated app did match.
enum FileCategoryClassifier {
    private static let spreadsheetExtensions: Set<String> = ["xls", "xlsx", "numbers"]
    private static let presentationExtensions: Set<String> = ["ppt", "pptx", "key"]
    private static let ebookExtensions: Set<String> = ["epub", "mobi", "azw", "azw3"]

    /// Book containers, checked before the generic document rule below —
    /// an .epub conforms to `public.composite-content` like any other
    /// document package, and would otherwise be filed as a document.
    private static let ebookUTIs: Set<String> = [
        "org.idpf.epub-container", "org.idpf.epub-folder",
        "com.amazon.ebook", "com.amazon.mobi-ebook", "com.amazon.mobi8-ebook",
    ]

    /// Word-processing formats that conform to nothing coarser than
    /// `public.data`, so neither an umbrella conformance nor a curated
    /// category can classify them (`.odt` doesn't even reach
    /// `public.composite-content`).
    private static let documentUTIs: Set<String> = [
        "com.microsoft.word.doc", "com.microsoft.word.wordml",
        "org.openxmlformats.wordprocessingml.document",
        "org.openxmlformats.wordprocessingml.document.macroenabled",
        "com.apple.iwork.pages.pages", "com.apple.iwork.pages.sffpages",
        "org.oasis-open.opendocument.text", "org.oasis-open.opendocument.text-template",
    ]

    static func classify(target: Target, uti: String?, curatedCategory: CuratedTarget.Category?) -> FileCategory {
        if case .ext(let ext) = target {
            let normalized = ext.lowercased()
            if spreadsheetExtensions.contains(normalized) { return .spreadsheet }
            if presentationExtensions.contains(normalized) { return .presentation }
            if ebookExtensions.contains(normalized) { return .ebook }
        }

        if let uti, let type = UTType(uti) {
            // Disk images conform to `public.archive` as well, so they have
            // to be asked about first or `.diskImage` is unreachable and a
            // .dmg files itself under "Archive".
            if type.conforms(to: .diskImage) { return .diskImage }
            if type.conforms(to: .archive) { return .archive }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .pdf) { return .document }
            if type.conforms(to: .sourceCode) { return .code }
            if type.conforms(to: .html) { return .web }
            if type.conforms(to: .font) { return .font }
            if type.conforms(to: .executable) { return .executable }
            if type.conforms(to: .spreadsheet) { return .spreadsheet }
            if type.conforms(to: .presentation) { return .presentation }
            if ebookUTIs.contains(uti) { return .ebook }
            if documentUTIs.contains(uti) { return .document }
            if type.conforms(to: .text) { return .text }
            // Anything left that is a document package (.docx, .pages, and
            // the long tail of app-declared formats) rather than raw data.
            if type.conforms(to: .compositeContent) { return .document }
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
