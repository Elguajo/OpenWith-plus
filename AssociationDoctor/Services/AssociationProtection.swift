import OpenWithCore
import UniformTypeIdentifiers

/// Why an association is off-limits to repair. Carried instead of a bare
/// `Bool` so the UI can say *what* it is protecting and the user can judge
/// the override for themselves, rather than meeting an unexplained
/// disabled button.
enum ProtectionReason: String, Sendable, Hashable, CaseIterable {
    /// Applications, executables, and loadable bundles — Finder launching
    /// an app is not an "association" a user should be able to redirect.
    case executable
    /// Installers and disk images: the Installer / DiskImageMounter path
    /// macOS uses to mount and install software.
    case installerOrDiskImage
    /// Preference panes, screen savers, Quick Look generators, Automator
    /// actions, aliases, smart folders — OS components a wrong handler
    /// makes unopenable.
    case systemComponent
    /// Apple's own URL schemes (`x-apple-*`, `prefs:`, `help:`, App Store
    /// and Books links) — how System Settings, Help and the App Store hand
    /// work to each other.
    case systemURLScheme

    var explanation: String {
        switch self {
        case .executable:
            return "Applications and executables are opened by macOS itself. Changing this can stop apps from launching."
        case .installerOrDiskImage:
            return "Installers and disk images are handled by macOS. Changing this can stop software from installing or mounting."
        case .systemComponent:
            return "This is a macOS component. Changing its handler can make System Settings, Finder or Quick Look stop working."
        case .systemURLScheme:
            return "This is one of Apple's internal URL schemes. Changing it can break System Settings, Help and the App Store."
        }
    }
}

/// Decides which associations the app refuses to rewrite (and which ones it
/// is perfectly safe to hand over to any app the user likes).
///
/// The line is *not* "the current handler is an Apple app": rerouting .png
/// away from Preview or .html away from Safari is the whole point of this
/// tool. It is "macOS itself depends on this handler" — launching apps,
/// installing software, mounting images, opening its own components and
/// internal URL schemes. Those are the changes a user cannot undo from a
/// broken system, so they need the deliberate opt-in in Settings (§22)
/// rather than a one-click Fix.
///
/// Deterministic and explainable, the same contract as
/// `RecommendationEngine`: every rule below is a named list or a UTType
/// conformance, never a guess about "system-looking" names.
enum AssociationProtection {
    /// Extensions macOS resolves to a `dyn.*` UTI (no real content type is
    /// registered for them), so conformance can't be asked and the
    /// extension itself is the only reliable key.
    private static let protectedExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "plugin", "xpc", "kext", "dext", "systemextension",
        "prefpane", "qlgenerator", "saver", "mdimporter", "service", "wdgt", "workflow", "action",
        "pkg", "mpkg", "dmg", "iso", "sparsebundle", "sparseimage",
        "command", "savedsearch", "terminal",
    ]

    private static let protectedUTIs: [String: ProtectionReason] = [
        "com.apple.application": .executable,
        "com.apple.application-file": .executable,
        "com.apple.application-bundle": .executable,
        "public.executable": .executable,
        "public.unix-executable": .executable,
        "com.apple.installer-package-archive": .installerOrDiskImage,
        "com.apple.systempreference.prefpane": .systemComponent,
        "com.apple.systempreference.screen-saver": .systemComponent,
        "com.apple.terminal.shell-script": .systemComponent,
        "com.apple.terminal.settings": .systemComponent,
        "com.apple.finder.smart-folder": .systemComponent,
        "com.apple.alias-file": .systemComponent,
        "com.apple.alias-record": .systemComponent,
        "com.apple.resolvable": .systemComponent,
    ]

    /// Apple's own schemes. Everything a user actually wants to reassign —
    /// `http`, `https`, `mailto`, `ftp`, `webcal`, `tel`, `sms`,
    /// `facetime`, `ssh`, `vnc` — is deliberately absent: picking a
    /// different browser or mail client is the point of the app.
    private static let protectedSchemes: Set<String> = [
        "help", "x-help-script", "prefs", "applefeedback", "apple-feedback", "x-radar",
        "macappstore", "macappstores", "itms", "itmss", "itms-apps", "itms-appss",
        "itms-books", "itms-bookss", "ibooks", "applenews", "applenewss", "findmy", "fmip1",
    ]

    private static let protectedSchemePrefixes = ["x-apple", "com.apple"]

    /// `nil` when the association is safe for the user to reassign.
    static func reason(for target: Target, uti: String?) -> ProtectionReason? {
        switch target {
        case .urlScheme(let scheme):
            let normalized = scheme.lowercased()
            if protectedSchemes.contains(normalized) { return .systemURLScheme }
            if protectedSchemePrefixes.contains(where: { normalized.hasPrefix($0) }) { return .systemURLScheme }
            return nil

        case .ext(let ext):
            if protectedExtensions.contains(ext.lowercased()) { return reasonForExtension(ext.lowercased()) }
            return reasonForUTI(uti)

        case .uti, .file:
            return reasonForUTI(uti)
        }
    }

    private static func reasonForExtension(_ ext: String) -> ProtectionReason {
        switch ext {
        case "app", "appex", "bundle", "framework", "plugin", "xpc", "kext", "dext", "systemextension":
            return .executable
        case "pkg", "mpkg", "dmg", "iso", "sparsebundle", "sparseimage":
            return .installerOrDiskImage
        default:
            return .systemComponent
        }
    }

    private static func reasonForUTI(_ uti: String?) -> ProtectionReason? {
        guard let uti else { return nil }
        if let known = protectedUTIs[uti] { return known }
        guard let type = UTType(uti) else { return nil }
        if type.conforms(to: .application) || type.conforms(to: .executable)
            || type.conforms(to: .unixExecutable)
        {
            return .executable
        }
        // Disk images conform to `public.archive` too, so this has to be
        // asked before anything archive-shaped is treated as an ordinary,
        // freely reassignable file (a .zip is; a .dmg is not).
        if type.conforms(to: .diskImage) { return .installerOrDiskImage }
        return nil
    }
}
