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

    @Test("falls back to the curated category when nothing else identifies the type")
    func fallsBackToCuratedCategory() {
        let category = FileCategoryClassifier.classify(
            target: .ext("xyz123"), uti: nil, curatedCategory: .documents)
        #expect(category == .document)
    }

    @Test("office and iWork documents classify without any curated help")
    func documentUTIsClassifyOnTheirOwn() {
        // The path `RecommendationEngine.dominantCategory` takes: it reads
        // an app's declared types and has no curated category to fall back
        // on. While these landed on `.unknown`, Word and Pages had no
        // document signal and were scored as a category *mismatch* on the
        // very formats they own.
        for uti in [
            "org.openxmlformats.wordprocessingml.document",
            "com.microsoft.word.doc",
            "com.apple.iwork.pages.sffpages",
            "org.oasis-open.opendocument.text",
        ] {
            #expect(FileCategoryClassifier.classify(target: .uti(uti), uti: uti, curatedCategory: nil) == .document)
        }
    }

    @Test("spreadsheets and presentations classify by conformance, not just by extension")
    func officeUTIsClassifyByConformance() {
        #expect(
            FileCategoryClassifier.classify(
                target: .uti("org.openxmlformats.spreadsheetml.sheet"),
                uti: "org.openxmlformats.spreadsheetml.sheet", curatedCategory: nil) == .spreadsheet)
        #expect(
            FileCategoryClassifier.classify(
                target: .uti("com.apple.iwork.keynote.sffkey"),
                uti: "com.apple.iwork.keynote.sffkey", curatedCategory: nil) == .presentation)
    }

    @Test("a disk image is a disk image, not an archive")
    func diskImageBeatsArchive() {
        // Both conform to `public.archive`; asking about the archive first
        // made `.diskImage` unreachable for every real .dmg.
        #expect(
            FileCategoryClassifier.classify(
                target: .ext("dmg"), uti: "com.apple.disk-image-udif", curatedCategory: nil) == .diskImage)
    }

    @Test("an e-book container is an e-book, not a generic document")
    func ebookUTIBeatsCompositeContent() {
        #expect(
            FileCategoryClassifier.classify(
                target: .uti("org.idpf.epub-container"), uti: "org.idpf.epub-container", curatedCategory: nil) == .ebook)
    }

    @Test("an application bundle classifies as executable")
    func applicationIsExecutable() {
        #expect(
            FileCategoryClassifier.classify(
                target: .ext("app"), uti: "com.apple.application-file", curatedCategory: nil) == .executable)
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
