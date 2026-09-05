import OpenWithCore
import Testing

@testable import AssociationDoctor

@Suite
struct FileCategoryClassifierTests {
    @Test("classifies a known archive UTI as archive")
    func archiveUTI() {
        let category = FileCategoryClassifier.classify(
            target: .uti("public.zip-archive"), uti: "public.zip-archive", curatedCategory: .archives)
        #expect(category == .archive)
    }

    @Test("classifies a known image UTI as image even without curated data")
    func imageUTIWithoutCuratedData() {
        let category = FileCategoryClassifier.classify(
            target: .ext("heic"), uti: "public.heic", curatedCategory: nil)
        #expect(category == .image)
    }

    @Test("falls back to the curated category when the UTI has no umbrella conformance")
    func fallsBackToCuratedCategory() {
        // A vendor-specific document UTI (no `UTType.conforms(to:)` umbrella
        // covers arbitrary office formats), so classification must fall
        // back to what the curated list already knows.
        let category = FileCategoryClassifier.classify(
            target: .ext("docx"),
            uti: "org.openxmlformats.wordprocessingml.document",
            curatedCategory: .documents)
        #expect(category == .document)
    }

    @Test("recognizes spreadsheet extensions the curated list only tags as documents")
    func spreadsheetExtensionOverridesGenericDocumentCategory() {
        let category = FileCategoryClassifier.classify(
            target: .ext("xlsx"), uti: "org.openxmlformats.spreadsheetml.sheet", curatedCategory: .documents)
        #expect(category == .spreadsheet)
    }

    @Test("classifies a URL scheme as web")
    func urlSchemeIsWeb() {
        let category = FileCategoryClassifier.classify(target: .urlScheme("mailto"), uti: nil, curatedCategory: .urlSchemes)
        #expect(category == .web)
    }

    @Test("falls back to unknown when nothing is known about the target")
    func unknownWhenNoSignal() {
        let category = FileCategoryClassifier.classify(target: .ext("xyz123"), uti: nil, curatedCategory: nil)
        #expect(category == .unknown)
    }
}
