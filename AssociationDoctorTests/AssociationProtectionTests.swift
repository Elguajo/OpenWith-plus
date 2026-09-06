import OpenWithCore
import Testing

@testable import AssociationDoctor

/// The safety net has to hold in *both* directions: it must cover what
/// macOS depends on, and it must stay out of the way of the everyday
/// reassignments the app exists for (a different browser, editor, or image
/// viewer). A policy that over-protects is as broken as one that under-protects.
@Suite
struct AssociationProtectionTests {
    @Test("applications and loadable bundles are protected")
    func executablesAreProtected() {
        #expect(AssociationProtection.reason(for: .ext("app"), uti: "com.apple.application-file") == .executable)
        #expect(AssociationProtection.reason(for: .uti("public.executable"), uti: "public.executable") == .executable)
        #expect(AssociationProtection.reason(for: .ext("kext"), uti: nil) == .executable)
        #expect(AssociationProtection.reason(for: .ext("appex"), uti: nil) == .executable)
    }

    @Test("installers and disk images are protected")
    func installersAreProtected() {
        #expect(
            AssociationProtection.reason(for: .ext("pkg"), uti: "com.apple.installer-package-archive")
                == .installerOrDiskImage)
        #expect(AssociationProtection.reason(for: .ext("dmg"), uti: "com.apple.disk-image-udif") == .installerOrDiskImage)
        // Reached by conformance, not by name: an .iso target carries a
        // different UTI but the same consequence.
        #expect(AssociationProtection.reason(for: .uti("public.iso-image"), uti: "public.iso-image") == .installerOrDiskImage)
    }

    @Test("a disk image is not treated as an ordinary archive")
    func diskImageIsNotJustAnArchive() {
        // Both conform to public.archive; only one of them is safe to hand
        // to another app, so conformance order in the policy matters.
        #expect(AssociationProtection.reason(for: .uti("public.zip-archive"), uti: "public.zip-archive") == nil)
        #expect(AssociationProtection.reason(for: .ext("zip"), uti: "public.zip-archive") == nil)
    }

    @Test("macOS components are protected")
    func systemComponentsAreProtected() {
        #expect(AssociationProtection.reason(for: .ext("prefPane"), uti: nil) == .systemComponent)
        #expect(AssociationProtection.reason(for: .ext("qlgenerator"), uti: nil) == .systemComponent)
        #expect(AssociationProtection.reason(for: .ext("savedSearch"), uti: "com.apple.finder.smart-folder") == .systemComponent)
        #expect(AssociationProtection.reason(for: .uti("com.apple.alias-file"), uti: "com.apple.alias-file") == .systemComponent)
    }

    @Test("Apple's own URL schemes are protected")
    func systemSchemesAreProtected() {
        #expect(AssociationProtection.reason(for: .urlScheme("prefs"), uti: nil) == .systemURLScheme)
        #expect(AssociationProtection.reason(for: .urlScheme("help"), uti: nil) == .systemURLScheme)
        #expect(AssociationProtection.reason(for: .urlScheme("x-apple-helpbasic"), uti: nil) == .systemURLScheme)
        #expect(AssociationProtection.reason(for: .urlScheme("macappstore"), uti: nil) == .systemURLScheme)
    }

    @Test("the schemes people actually reassign stay open")
    func everydaySchemesAreNotProtected() {
        for scheme in ["http", "https", "mailto", "ftp", "webcal", "tel", "sms", "facetime", "ssh", "vnc"] {
            #expect(AssociationProtection.reason(for: .urlScheme(scheme), uti: nil) == nil)
        }
    }

    @Test("everyday documents and media stay open")
    func everydayTypesAreNotProtected() {
        #expect(AssociationProtection.reason(for: .ext("md"), uti: "net.daringfireball.markdown") == nil)
        #expect(AssociationProtection.reason(for: .uti("public.html"), uti: "public.html") == nil)
        #expect(AssociationProtection.reason(for: .uti("public.png"), uti: "public.png") == nil)
        #expect(AssociationProtection.reason(for: .ext("docx"), uti: "org.openxmlformats.wordprocessingml.document") == nil)
        #expect(AssociationProtection.reason(for: .uti("com.adobe.pdf"), uti: "com.adobe.pdf") == nil)
    }

    @Test("matching ignores extension and scheme case")
    func matchingIsCaseInsensitive() {
        #expect(AssociationProtection.reason(for: .ext("APP"), uti: nil) == .executable)
        #expect(AssociationProtection.reason(for: .urlScheme("PREFS"), uti: nil) == .systemURLScheme)
    }

    @Test("an unknown target with no UTI is not protected by guesswork")
    func unknownIsOpen() {
        #expect(AssociationProtection.reason(for: .ext("wibble"), uti: nil) == nil)
        #expect(AssociationProtection.reason(for: .uti("dyn.ah62d4rv4ge81g45fsvv0u"), uti: "dyn.ah62d4rv4ge81g45fsvv0u") == nil)
    }
}
