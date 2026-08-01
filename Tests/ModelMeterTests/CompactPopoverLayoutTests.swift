import AppKit
import SwiftUI
import XCTest
@testable import ModelMeter

final class CompactPopoverLayoutTests: XCTestCase {
    @MainActor
    func testCodexActivityUsesTwoRowsOfThreeMetrics() {
        let card = ProviderUsageCard(
            provider: .codex,
            state: .idle,
            displayMode: .used
        )
        let metrics = card.activityMetrics(
            UsageActivity(
                todayTokens: 87_650,
                lifetimeTokens: 9_876_543,
                peakDailyTokens: 456_789,
                currentStreakDays: 9,
                longestStreakDays: 42,
                longestRunningTurnSeconds: 7_425
            )
        )

        XCTAssertEqual(
            metrics.map(\.id),
            [
                "todayTokens",
                "lifetimeTokens",
                "peakDailyTokens",
                "streak",
                "longestStreak",
                "longestRunningTurn",
            ]
        )
        XCTAssertEqual(metrics.last?.value, "2h 3m")
    }

    @MainActor
    func testRepresentativeCompactCardsStayWithinHeightBudget() {
        _ = NSApplication.shared
        let now = Date()
        let reset = now.addingTimeInterval(3 * 60 * 60)

        let claude = ProviderUsageSnapshot(
            provider: .claude,
            fetchedAt: now,
            plan: "Subscription",
            limits: [
                limit("claude-session", "5-hour", 0.37, reset),
                limit("claude-week", "Weekly · All models", 0.63, reset),
                limit("claude-sonnet", "Weekly · Sonnet", 0.14, reset),
                limit("claude-opus", "Weekly · Opus", 0.10, reset)
            ],
            activity: UsageActivity(
                todayTokens: 128_450,
                lifetimeTokens: 12_345_678,
                sessionCostUSD: 12.34,
                activeSessions: 3,
                currentStreakDays: 21,
                totalSessions: 1_248,
                totalMessages: 48_392,
                dailyTokens: history(endingAt: now, scale: 8_000),
                scope: .claudeLocalProfile
            ),
            cliVersion: "2.1.0",
            source: "Claude CLI /usage",
            note: nil
        )

        let codex = ProviderUsageSnapshot(
            provider: .codex,
            fetchedAt: now,
            plan: "Plus",
            limits: [
                limit("codex-primary", "Codex · 5-hour", 0.42, reset),
                limit("codex-secondary", "Codex · Weekly", 0.71, reset),
                limit("codex-spend", "Codex · Spend limit", 0.25, reset),
                limit("codex-mini", "Codex Mini · 5-hour", 0.18, reset)
            ],
            resetCredits: UsageResetCredits(
                availableCount: 1,
                credits: [
                    UsageResetCredit(
                        id: "reset-credit",
                        title: "Full reset",
                        expiresAt: reset
                    )
                ]
            ),
            activity: UsageActivity(
                todayTokens: 87_650,
                lifetimeTokens: 9_876_543,
                peakDailyTokens: 456_789,
                currentStreakDays: 9,
                longestStreakDays: 42,
                longestRunningTurnSeconds: 7_425,
                dailyTokens: history(endingAt: now, scale: 5_000),
                scope: .codexAccount
            ),
            cliVersion: "1.2.3",
            source: "Codex app-server",
            note: nil
        )

        let claudeHeight = fittingHeight(for: claude)
        let codexHeight = fittingHeight(for: codex)
        let stackHeight = claudeHeight
            + codexHeight
            + ResponsiveProviderCards.compactSpacing
            + (UsagePopover.DashboardLayout.providerPadding * 2)

        XCTAssertGreaterThan(claudeHeight, 0)
        XCTAssertGreaterThan(codexHeight, 0)
        XCTAssertLessThanOrEqual(
            stackHeight,
            UsagePopover.DashboardLayout.providerViewportHeight,
            "Compact loaded cards require \(stackHeight) points"
        )
    }

    private func limit(
        _ id: String,
        _ title: String,
        _ usedFraction: Double,
        _ resetsAt: Date
    ) -> UsageLimit {
        UsageLimit(
            id: id,
            title: title,
            usedFraction: usedFraction,
            resetsAt: resetsAt,
            windowMinutes: 300
        )
    }

    private func history(endingAt date: Date, scale: Int64) -> [UsageActivityDay] {
        (0..<30).compactMap { index in
            guard let day = Calendar.current.date(
                byAdding: .day,
                value: index - 29,
                to: date
            ) else {
                return nil
            }
            let signal = Int64(((index * 7) % 13) + 2)
            return UsageActivityDay(date: day, tokens: signal * scale)
        }
    }

    @MainActor
    private func fittingHeight(for snapshot: ProviderUsageSnapshot) -> CGFloat {
        let width = UsagePopover.DashboardLayout.compactCardWidth
        let view = ProviderUsageCard(
            provider: snapshot.provider,
            state: .loaded(snapshot),
            displayMode: .used,
            activityStyle: .compact,
            openWindow: {}
        )
        .frame(width: width)

        let hostingController = NSHostingController(rootView: view)
        return hostingController.sizeThatFits(
            in: NSSize(width: width, height: .greatestFiniteMagnitude)
        ).height
    }
}
