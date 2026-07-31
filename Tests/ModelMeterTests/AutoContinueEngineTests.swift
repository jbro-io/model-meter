import Foundation
import XCTest
@testable import ModelMeter

final class AutoContinueEngineTests: XCTestCase {
    func testRecoveryDoesNotFireUnlessExhaustionWasObserved() {
        var engine = AutoContinueEngine()

        XCTAssertNil(engine.evaluate(snapshot: snapshot(usedFraction: 0.2), enabled: true))
        XCTAssertFalse(engine.isAwaitingRecovery(for: .claude))
    }

    func testObservedExhaustionArmsAndRecoveryWaitsForDeliveryAcknowledgement() throws {
        var engine = AutoContinueEngine()
        let reset = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertNil(
            engine.evaluate(
                snapshot: snapshot(usedFraction: 1, resetsAt: reset),
                enabled: true
            )
        )
        XCTAssertTrue(engine.isAwaitingRecovery(for: .claude))
        XCTAssertEqual(engine.pendingResetDate(for: .claude), reset)

        let event = try XCTUnwrap(
            engine.evaluate(snapshot: snapshot(usedFraction: 0), enabled: true)
        )
        XCTAssertEqual(event.provider, .claude)
        XCTAssertEqual(event.recoveredLimitIDs, ["five-hour"])
        XCTAssertNotNil(
            engine.evaluate(snapshot: snapshot(usedFraction: 0.1), enabled: true),
            "A failed terminal delivery must remain armed for a later retry."
        )

        engine.markDeliverySucceeded(for: .claude)
        XCTAssertFalse(engine.isAwaitingRecovery(for: .claude))
        XCTAssertNil(engine.evaluate(snapshot: snapshot(usedFraction: 0.2), enabled: true))
    }

    func testWeeklyExhaustionIsIgnored() {
        var engine = AutoContinueEngine()
        let weekly = ProviderUsageSnapshot(
            provider: .codex,
            fetchedAt: Date(),
            plan: nil,
            limits: [
                UsageLimit(
                    id: "weekly",
                    title: "Weekly",
                    usedFraction: 1,
                    windowMinutes: 10_080
                )
            ],
            activity: .empty,
            cliVersion: nil,
            source: "test",
            note: nil
        )

        XCTAssertNil(engine.evaluate(snapshot: weekly, enabled: true))
        XCTAssertFalse(engine.isAwaitingRecovery(for: .codex))
    }

    func testProviderRemainsArmedUntilEveryFiveHourBucketRecovers() {
        var engine = AutoContinueEngine()
        let exhausted = snapshot(
            provider: .codex,
            limits: [
                limit(id: "general", usedFraction: 1),
                limit(id: "special", usedFraction: 0.5)
            ]
        )
        XCTAssertNil(engine.evaluate(snapshot: exhausted, enabled: true))

        let stillExhausted = snapshot(
            provider: .codex,
            limits: [
                limit(id: "general", usedFraction: 0),
                limit(id: "special", usedFraction: 1)
            ]
        )
        XCTAssertNil(engine.evaluate(snapshot: stillExhausted, enabled: true))

        let recovered = snapshot(
            provider: .codex,
            limits: [
                limit(id: "general", usedFraction: 0),
                limit(id: "special", usedFraction: 0.2)
            ]
        )
        XCTAssertNotNil(engine.evaluate(snapshot: recovered, enabled: true))
    }

    func testDisabledProviderClearsPersistedPendingState() throws {
        var engine = AutoContinueEngine()
        _ = engine.evaluate(snapshot: snapshot(usedFraction: 1), enabled: true)
        XCTAssertTrue(engine.isAwaitingRecovery(for: .claude))

        XCTAssertNil(engine.evaluate(snapshot: snapshot(usedFraction: 1), enabled: false))
        XCTAssertFalse(engine.isAwaitingRecovery(for: .claude))

        let data = try JSONEncoder().encode(engine)
        let restored = try JSONDecoder().decode(AutoContinueEngine.self, from: data)
        XCTAssertEqual(restored, engine)
    }

    func testRecoveryEventKeepsTheRouteRevisionThatWasArmed() throws {
        var engine = AutoContinueEngine()

        XCTAssertNil(
            engine.evaluate(
                snapshot: snapshot(usedFraction: 1),
                enabled: true,
                routeRevision: 7
            )
        )
        XCTAssertEqual(engine.pendingRouteRevision(for: .claude), 7)

        let event = try XCTUnwrap(
            engine.evaluate(
                snapshot: snapshot(usedFraction: 0),
                enabled: true,
                routeRevision: 9
            )
        )
        XCTAssertEqual(event.routeRevision, 7)
    }

    func testPartialDeliveryProgressPersistsUntilRecoveryCompletes() throws {
        var engine = AutoContinueEngine()
        _ = engine.evaluate(
            snapshot: snapshot(usedFraction: 1),
            enabled: true,
            routeRevision: 7
        )

        engine.markDeliveryProgress(
            for: .claude,
            routeRevision: 7,
            targetIDs: ["already-sent"]
        )

        let data = try JSONEncoder().encode(engine)
        var restored = try JSONDecoder().decode(
            AutoContinueEngine.self,
            from: data
        )
        XCTAssertEqual(
            restored.deliveredTargetIDs(for: .claude),
            ["already-sent"]
        )

        restored.markDeliverySucceeded(for: .claude, routeRevision: 6)
        XCTAssertTrue(restored.isAwaitingRecovery(for: .claude))
        restored.markDeliverySucceeded(for: .claude, routeRevision: 7)
        XCTAssertFalse(restored.isAwaitingRecovery(for: .claude))
    }

    private func snapshot(
        provider: ProviderID = .claude,
        usedFraction: Double,
        resetsAt: Date? = nil
    ) -> ProviderUsageSnapshot {
        snapshot(
            provider: provider,
            limits: [
                UsageLimit(
                    id: "five-hour",
                    title: "5-hour",
                    usedFraction: usedFraction,
                    resetsAt: resetsAt,
                    windowMinutes: 300
                )
            ]
        )
    }

    private func snapshot(
        provider: ProviderID,
        limits: [UsageLimit]
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            fetchedAt: Date(),
            plan: nil,
            limits: limits,
            activity: .empty,
            cliVersion: nil,
            source: "test",
            note: nil
        )
    }

    private func limit(id: String, usedFraction: Double) -> UsageLimit {
        UsageLimit(
            id: id,
            title: "5-hour",
            usedFraction: usedFraction,
            windowMinutes: 300
        )
    }
}
