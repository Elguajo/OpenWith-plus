import OpenWithCore

/// The real outcome of one repair attempt (§15/§16) — never assumed from
/// the API call succeeding. `notConfirmed` means the write went through
/// but the read-back doesn't show the desired app: on current macOS that
/// almost always means the user declined (or hasn't yet answered) the
/// system confirmation dialog.
enum RepairOutcome: Sendable, Equatable {
    case applied(AppInfo)
    case alreadySet(AppInfo)
    case notConfirmed(desired: AppInfo)
    case failed(String)
}

/// Applies a single default-app change and reads the result back.
///
/// Scoped to one association at a time on purpose — a batch "Repair Plan"
/// review/progress/confirmation-queue flow (§15/§16, for e.g. Dashboard's
/// "Fix N Issues" or Profile Restore) is Phase 7's job. A single click on
/// one Problem card doesn't need that machinery: `Engine.setDefault`
/// already does the one thing this needs (write, then verify).
struct RepairService {
    var engine: Engine

    init(engine: Engine) {
        self.engine = engine
    }

    func apply(app: AppInfo, to target: Target) async -> RepairOutcome {
        do {
            let resolved = try engine.resolve(target)
            switch try await engine.setDefault(app: app, for: resolved) {
            case .applied(let applied): return .applied(applied)
            case .alreadySet(let already): return .alreadySet(already)
            case .notConfirmed(let desired, _): return .notConfirmed(desired: desired)
            }
        } catch {
            return .failed((error as? OpenWithError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
