import XCTest
@testable import ModelMeter

final class StatusItemPresentationTests: XCTestCase {
    func testRowsUseMostConstrainedLimitForEachProviderInStableOrder() throws {
        let states: [ProviderID: ProviderLoadState] = [
            .claude: .loaded(
                snapshot(
                    provider: .claude,
                    limits: [
                        limit(id: "claude-5h", title: "5-hour", usedFraction: 0.24),
                        limit(id: "claude-week", title: "Weekly", usedFraction: 0.72)
                    ]
                )
            ),
            .codex: .loaded(
                snapshot(
                    provider: .codex,
                    limits: [
                        limit(id: "codex-month", title: "Monthly", usedFraction: 0.55),
                        limit(id: "codex-5h", title: "5-hour", usedFraction: 0.31)
                    ]
                )
            )
        ]

        let rows = StatusItemPresentation.rows(states: states, displayMode: .used)

        XCTAssertEqual(rows.map(\.provider), [.claude, .codex])
        XCTAssertEqual(rows[0].windowLabel, "Claude Wk")
        XCTAssertEqual(rows[0].displayedPercent, 72)
        XCTAssertEqual(
            try XCTUnwrap(rows[0].displayedFraction),
            0.72,
            accuracy: 0.000_1
        )
        XCTAssertEqual(rows[1].windowLabel, "Codex Mo")
        XCTAssertEqual(rows[1].displayedPercent, 55)
        XCTAssertEqual(
            try XCTUnwrap(rows[1].displayedFraction),
            0.55,
            accuracy: 0.000_1
        )
    }

    func testRowsTransformUsedFractionForRemainingMode() throws {
        let states: [ProviderID: ProviderLoadState] = [
            .claude: .loaded(
                snapshot(
                    provider: .claude,
                    limits: [limit(id: "claude-5h", title: "5-hour", usedFraction: 0.38)]
                )
            )
        ]

        let used = try XCTUnwrap(
            StatusItemPresentation.rows(states: states, displayMode: .used)
                .first { $0.provider == .claude }
        )
        let remaining = try XCTUnwrap(
            StatusItemPresentation.rows(states: states, displayMode: .remaining)
                .first { $0.provider == .claude }
        )

        XCTAssertEqual(try XCTUnwrap(used.displayedFraction), 0.38, accuracy: 0.000_1)
        XCTAssertEqual(used.displayedPercent, 38)
        XCTAssertEqual(
            try XCTUnwrap(remaining.displayedFraction),
            0.62,
            accuracy: 0.000_1
        )
        XCTAssertEqual(remaining.displayedPercent, 62)
    }

    func testRemainingModeSkipsZeroAndUsesNextLowestPositiveWindow() throws {
        let states: [ProviderID: ProviderLoadState] = [
            .codex: .loaded(
                snapshot(
                    provider: .codex,
                    limits: [
                        limit(id: "empty", title: "5-hour", usedFraction: 1),
                        limit(id: "nearly-empty", title: "Daily", usedFraction: 0.996),
                        limit(id: "weekly", title: "Weekly", usedFraction: 0.78),
                        limit(id: "monthly", title: "Monthly", usedFraction: 0.45)
                    ]
                )
            )
        ]

        let row = try XCTUnwrap(
            StatusItemPresentation.rows(states: states, displayMode: .remaining)
                .first { $0.provider == .codex }
        )

        XCTAssertEqual(row.windowLabel, "Codex Wk")
        XCTAssertEqual(row.displayedPercent, 22)
        XCTAssertEqual(try XCTUnwrap(row.displayedFraction), 0.22, accuracy: 0.000_1)
    }

    func testAllZeroDisplayedWindowsProducePlaceholder() throws {
        let states: [ProviderID: ProviderLoadState] = [
            .claude: .loaded(
                snapshot(
                    provider: .claude,
                    limits: [
                        limit(id: "empty", title: "5-hour", usedFraction: 1),
                        limit(id: "rounds-to-zero", title: "Weekly", usedFraction: 0.999)
                    ]
                )
            )
        ]

        let row = try XCTUnwrap(
            StatusItemPresentation.rows(states: states, displayMode: .remaining)
                .first { $0.provider == .claude }
        )

        XCTAssertEqual(row.windowLabel, "--")
        XCTAssertNil(row.displayedPercent)
        XCTAssertNil(row.displayedFraction)
    }

    func testCompactWindowLabelsCoverStandardAndScopedTitles() {
        XCTAssertEqual(compactLabel(for: "5-hour"), "5h")
        XCTAssertEqual(compactLabel(for: "Weekly"), "Wk")
        XCTAssertEqual(compactLabel(for: "Monthly"), "Mo")
        XCTAssertEqual(compactLabel(for: "Weekly · Opus"), "Opus Wk")
        XCTAssertEqual(
            compactLabel(for: "Weekly · Claude Sonnet 4.5"),
            "Claude Sonnet 4.5 Wk"
        )
    }

    func testMissingProvidersProducePlaceholderRows() {
        let rows = StatusItemPresentation.rows(states: [:], displayMode: .used)

        XCTAssertEqual(rows.map(\.provider), [.claude, .codex])
        XCTAssertEqual(rows.map(\.windowLabel), ["--", "--"])
        XCTAssertTrue(rows.allSatisfy { $0.displayedFraction == nil })
        XCTAssertTrue(rows.allSatisfy { $0.displayedPercent == nil })
        XCTAssertTrue(rows.allSatisfy { !$0.isLoading })
        XCTAssertTrue(rows.allSatisfy { !$0.hasError })
    }

    private func compactLabel(for title: String) -> String {
        StatusItemPresentation.compactWindowTitle(
            limit(id: title, title: title, usedFraction: 0)
        )
    }

    private func limit(id: String, title: String, usedFraction: Double) -> UsageLimit {
        UsageLimit(
            id: id,
            title: title,
            usedFraction: usedFraction
        )
    }

    private func snapshot(
        provider: ProviderID,
        limits: [UsageLimit]
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            fetchedAt: Date(timeIntervalSince1970: 0),
            plan: nil,
            limits: limits,
            activity: .empty,
            cliVersion: nil,
            source: "test",
            note: nil
        )
    }
}
