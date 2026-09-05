import CoreServices

/// OpenWithCore's `LaunchServicesProviding.defaultApp` always resolves a
/// registered bundle ID to an installed `AppInfo` first, so an app that was
/// deleted after being set as default reads back as `nil` — identical to
/// "never set". `DiagnosticEngine` needs to tell those two apart to report
/// `broken` (§10.1) instead of `noDefault`, and no public OpenWithCore API
/// exposes the raw registration. This is a small local adapter around the
/// same LaunchServices C API `LaunchServicesProvider` itself uses
/// internally (§44: "implement a local adapter" before considering a
/// fork) — not a private API, just one OpenWithCore doesn't surface.
protocol RawDefaultHandlerProviding: Sendable {
    func rawDefaultBundleID(forContentType uti: String) -> String?
    func rawDefaultBundleID(forScheme scheme: String) -> String?
}

struct LiveRawDefaultHandlerProvider: RawDefaultHandlerProviding {
    func rawDefaultBundleID(forContentType uti: String) -> String? {
        LSCopyDefaultRoleHandlerForContentType(uti as CFString, .all)?
            .takeRetainedValue() as String?
    }

    func rawDefaultBundleID(forScheme scheme: String) -> String? {
        // `LSCopyDefaultHandlerForURLScheme` is deprecated in favor of
        // `NSWorkspace.urlForApplication(toOpen:)` — but that replacement
        // has the exact install-required resolution this type exists to
        // bypass, so the deprecated call is deliberate here.
        LSCopyDefaultHandlerForURLScheme(scheme as CFString)?
            .takeRetainedValue() as String?
    }
}
