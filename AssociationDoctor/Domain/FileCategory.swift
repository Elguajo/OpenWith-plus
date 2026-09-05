/// Broad kind of file a target represents (§8 of the spec). Used for
/// grouping in the UI and as a signal in the Recommendation Engine
/// (category match / mismatch).
enum FileCategory: String, Sendable, Hashable, CaseIterable {
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

    var displayName: String {
        switch self {
        case .archive: return "Archive"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .document: return "Document"
        case .text: return "Text"
        case .code: return "Code"
        case .design: return "Design"
        case .threeD: return "3D"
        case .font: return "Font"
        case .spreadsheet: return "Spreadsheet"
        case .presentation: return "Presentation"
        case .ebook: return "E-book"
        case .diskImage: return "Disk Image"
        case .executable: return "Executable"
        case .web: return "Web"
        case .unknown: return "Unknown"
        }
    }
}
