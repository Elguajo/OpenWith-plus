/// Dashboard summary of a diagnosed scan (§12). A visual indicator only —
/// never treated as an absolute technical truth (the spec is explicit
/// about this), so any reasonable monotonic formula is acceptable.
///
/// `ignored` associations are excluded from both the counts used for the
/// score and its denominator: the user already dismissed them, so they
/// shouldn't keep dragging health down.
struct HealthScore {
    let scannedCount: Int
    let healthyCount: Int
    let suspiciousCount: Int
    let brokenCount: Int
    let changedCount: Int
    let noDefaultCount: Int
    let ignoredCount: Int
    /// 0...100, 100 = perfectly healthy (or nothing scored yet).
    let score: Int

    init(records: [AssociationRecord]) {
        var counts: [AssociationStatus: Int] = [:]
        for record in records { counts[record.status, default: 0] += 1 }

        scannedCount = records.count
        healthyCount = counts[.healthy] ?? 0
        suspiciousCount = counts[.suspicious] ?? 0
        brokenCount = counts[.broken] ?? 0
        changedCount = counts[.changed] ?? 0
        noDefaultCount = counts[.noDefault] ?? 0
        ignoredCount = counts[.ignored] ?? 0

        let scored = healthyCount + suspiciousCount + brokenCount + changedCount + noDefaultCount
        guard scored > 0 else {
            score = 100
            return
        }

        // §12's penalty weights, normalized against the worst case (every
        // scored item broken) so the result always lands in 0...100.
        let penalty = changedCount * 1 + suspiciousCount * 2 + noDefaultCount * 3 + brokenCount * 5
        let maxPenalty = scored * 5
        score = max(0, min(100, 100 - Int((Double(penalty) / Double(maxPenalty)) * 100)))
    }
}
