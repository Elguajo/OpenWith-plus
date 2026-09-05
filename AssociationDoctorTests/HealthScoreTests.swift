import Foundation
import Testing

@testable import AssociationDoctor

@Suite
struct HealthScoreTests {
    private func record(_ status: AssociationStatus) -> AssociationRecord {
        AssociationRecord(
            id: UUID().uuidString, target: .ext("x"), uti: nil, localizedTypeName: nil, category: .unknown,
            currentApp: nil, availableApps: [], status: status, recommendation: nil)
    }

    @Test("an empty scan scores 100 — nothing to penalize")
    func emptyScanIsPerfect() {
        let score = HealthScore(records: [])
        #expect(score.score == 100)
        #expect(score.scannedCount == 0)
    }

    @Test("an all-healthy scan scores 100")
    func allHealthyIsPerfect() {
        let score = HealthScore(records: [record(.healthy), record(.healthy)])
        #expect(score.score == 100)
    }

    @Test("penalties are weighted per §12 and normalized against the worst case")
    func weightedPenalty() {
        // 2 healthy + 1 suspicious (-2) + 1 broken (-5): penalty 7 of a
        // possible 4*5=20 → 100 - 35 = 65.
        let score = HealthScore(records: [record(.healthy), record(.healthy), record(.suspicious), record(.broken)])

        #expect(score.healthyCount == 2)
        #expect(score.suspiciousCount == 1)
        #expect(score.brokenCount == 1)
        #expect(score.score == 65)
    }

    @Test("every scored item broken bottoms out at 0, not negative")
    func allBrokenIsZero() {
        let score = HealthScore(records: [record(.broken), record(.broken)])
        #expect(score.score == 0)
    }

    @Test("ignored associations are excluded from both the counts and the denominator")
    func ignoredDoesNotDragScoreDown() {
        let score = HealthScore(records: [record(.healthy), record(.healthy), record(.ignored)])

        #expect(score.ignoredCount == 1)
        #expect(score.score == 100)
        #expect(score.scannedCount == 3)
    }
}
