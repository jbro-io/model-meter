import Foundation
import XCTest
@testable import ModelMeter

final class UsageThresholdEngineTests: XCTestCase {
    func testInitialDeepBreachEmitsOnlyMostUrgentThreshold() throws {
        var engine = UsageThresholdEngine()

        let events = engine.evaluate(
            snapshot: snapshot(remainingPercent: 9),
            thresholds: [50, 25, 10, 10, 0, 100]
        )

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.thresholdPercent, 10)
        XCTAssertEqual(event.crossedThresholds, [50, 25, 10])
        XCTAssertEqual(event.remainingPercent, 9)
        XCTAssertTrue(
            engine.evaluate(snapshot: snapshot(remainingPercent: 8), thresholds: [50, 25, 10])
                .isEmpty
        )
    }

    func testGradualDeclineEmitsEveryConfiguredThreshold() throws {
        var engine = UsageThresholdEngine()
        XCTAssertTrue(
            engine.evaluate(snapshot: snapshot(remainingPercent: 60), thresholds: [50, 25, 10])
                .isEmpty
        )

        XCTAssertEqual(
            try XCTUnwrap(
                engine.evaluate(snapshot: snapshot(remainingPercent: 49), thresholds: [50, 25, 10])
                    .first
            ).thresholdPercent,
            50
        )
        XCTAssertEqual(
            try XCTUnwrap(
                engine.evaluate(snapshot: snapshot(remainingPercent: 24), thresholds: [50, 25, 10])
                    .first
            ).thresholdPercent,
            25
        )
        XCTAssertEqual(
            try XCTUnwrap(
                engine.evaluate(snapshot: snapshot(remainingPercent: 9), thresholds: [50, 25, 10])
                    .first
            ).thresholdPercent,
            10
        )
    }

    func testZeroThresholdFiresOnlyWhenUsageIsExhaustedAndRearms() throws {
        var engine = UsageThresholdEngine()

        XCTAssertTrue(
            engine.evaluate(snapshot: snapshot(remainingPercent: 0.01), thresholds: [0])
                .isEmpty
        )

        let exhausted = try XCTUnwrap(
            engine.evaluate(snapshot: snapshot(remainingPercent: 0), thresholds: [0]).first
        )
        XCTAssertEqual(exhausted.thresholdPercent, 0)
        XCTAssertEqual(exhausted.remainingPercent, 0)
        XCTAssertTrue(
            engine.evaluate(snapshot: snapshot(remainingPercent: 0), thresholds: [0]).isEmpty
        )

        _ = engine.evaluate(snapshot: snapshot(remainingPercent: 1), thresholds: [0])
        XCTAssertEqual(
            engine.evaluate(snapshot: snapshot(remainingPercent: 0), thresholds: [0]).first?
                .thresholdPercent,
            0
        )
    }

    func testRecoveryAndDeliveryFailureRearmThreshold() throws {
        var engine = UsageThresholdEngine()
        let first = try XCTUnwrap(
            engine.evaluate(snapshot: snapshot(remainingPercent: 19), thresholds: [20]).first
        )
        XCTAssertTrue(
            engine.evaluate(snapshot: snapshot(remainingPercent: 19), thresholds: [20]).isEmpty
        )

        engine.markDeliveryFailed(first)
        XCTAssertEqual(
            engine.evaluate(snapshot: snapshot(remainingPercent: 19), thresholds: [20]).first?
                .thresholdPercent,
            20
        )

        _ = engine.evaluate(snapshot: snapshot(remainingPercent: 21), thresholds: [20])
        XCTAssertEqual(
            engine.evaluate(snapshot: snapshot(remainingPercent: 19), thresholds: [20]).first?
                .thresholdPercent,
            20
        )
    }

    func testResetCycleRearmsWithoutObservedRecovery() throws {
        var engine = UsageThresholdEngine()
        let firstReset = Date(timeIntervalSince1970: 1_900_000_000)
        let secondReset = firstReset.addingTimeInterval(7 * 24 * 60 * 60)

        XCTAssertEqual(
            engine.evaluate(
                snapshot: snapshot(remainingPercent: 19, resetsAt: firstReset),
                thresholds: [20]
            ).first?.thresholdPercent,
            20
        )
        XCTAssertTrue(
            engine.evaluate(
                snapshot: snapshot(remainingPercent: 18, resetsAt: firstReset),
                thresholds: [20]
            ).isEmpty
        )
        XCTAssertEqual(
            engine.evaluate(
                snapshot: snapshot(remainingPercent: 18, resetsAt: secondReset),
                thresholds: [20]
            ).first?.thresholdPercent,
            20
        )
    }

    func testExactBoundaryAndProvidersAreIndependent() {
        var engine = UsageThresholdEngine()
        XCTAssertTrue(
            engine.evaluate(snapshot: snapshot(remainingPercent: 20.01), thresholds: [20])
                .isEmpty
        )
        XCTAssertEqual(
            engine.evaluate(snapshot: snapshot(remainingPercent: 20), thresholds: [20]).count,
            1
        )
        XCTAssertEqual(
            engine.evaluate(
                snapshot: snapshot(provider: .codex, remainingPercent: 20),
                thresholds: [20]
            ).count,
            1
        )
    }

    func testCodableStateSuppressesRelaunchDuplicate() throws {
        var engine = UsageThresholdEngine()
        XCTAssertEqual(
            engine.evaluate(snapshot: snapshot(remainingPercent: 15), thresholds: [20]).count,
            1
        )

        let data = try JSONEncoder().encode(engine)
        var restored = try JSONDecoder().decode(UsageThresholdEngine.self, from: data)
        XCTAssertTrue(
            restored.evaluate(snapshot: snapshot(remainingPercent: 14), thresholds: [20]).isEmpty
        )
    }

    private func snapshot(
        provider: ProviderID = .claude,
        remainingPercent: Double,
        resetsAt: Date? = Date(timeIntervalSince1970: 1_900_000_000)
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            fetchedAt: Date(),
            plan: "Test",
            limits: [
                UsageLimit(
                    id: "shared-window",
                    title: "Weekly",
                    usedFraction: 1 - remainingPercent / 100,
                    resetsAt: resetsAt,
                    windowMinutes: 10_080
                )
            ],
            activity: .empty,
            cliVersion: nil,
            source: "test",
            note: nil
        )
    }
}
