import Foundation
import XCTest
@testable import ModelMeter

final class AutoContinueControllerTests: XCTestCase {
    @MainActor
    func testFailedScanDoesNotPruneEnrollment() async throws {
        let suiteName = "AutoContinueControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.autoContinueTerminal = .iterm
        let target = itermTarget(id: "keep-me")
        settings.setTerminalSession(target, enabled: true)
        let store = UsageStore(settings: settings)
        let controller = AutoContinueController(
            settings: settings,
            store: store,
            clients: [
                StubTerminalAutomationClient(
                    terminal: .iterm,
                    scanResult: .failure(.unauthorized(.iterm))
                )
            ],
            defaults: defaults
        )

        controller.scanTargets(for: .claude)
        await waitForScan(controller, provider: .claude)

        XCTAssertEqual(
            settings.selectedSessionTargets(for: .iterm, provider: .claude),
            [target]
        )
        XCTAssertTrue(controller.status(for: .claude).isFailure)
    }

    @MainActor
    func testCompleteEmptyScanPrunesClosedEnrollment() async throws {
        let suiteName = "AutoContinueControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.autoContinueTerminal = .iterm
        settings.setTerminalSession(itermTarget(id: "closed"), enabled: true)
        let store = UsageStore(settings: settings)
        let controller = AutoContinueController(
            settings: settings,
            store: store,
            clients: [
                StubTerminalAutomationClient(
                    terminal: .iterm,
                    scanResult: .complete(TerminalTargetSummary(targets: []))
                )
            ],
            defaults: defaults
        )

        controller.scanTargets(for: .claude)
        await waitForScan(controller, provider: .claude)

        XCTAssertTrue(
            settings.selectedSessionTargets(for: .iterm, provider: .claude).isEmpty
        )
        XCTAssertEqual(
            controller.status(for: .claude),
            .ready(TerminalTargetSummary(targets: []))
        )
    }

    @MainActor
    func testActivationMigratesLegacyKittyEnrollmentWithLiveScan() async throws {
        let suiteName = "AutoContinueControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.autoContinueEnabled = true
        settings.setKittySession(17, enabled: true, for: .claude)
        let live = TerminalSessionTarget(
            terminal: .kitty,
            provider: .claude,
            id: "17",
            displayTitle: "Model Meter",
            currentDirectory: "/Users/test/model-meter",
            processName: "claude",
            auxiliaryIdentifier: nil
        )
        let store = UsageStore(settings: settings)
        let controller = AutoContinueController(
            settings: settings,
            store: store,
            clients: [
                StubTerminalAutomationClient(
                    terminal: .kitty,
                    scanResult: .complete(
                        TerminalTargetSummary(targets: [live])
                    )
                )
            ],
            defaults: defaults
        )

        controller.activate()
        await waitForScan(controller, provider: .claude)
        controller.deactivate()

        XCTAssertFalse(
            settings.hasIncompleteSessionIdentity(
                for: .kitty,
                provider: .claude
            )
        )
        XCTAssertEqual(
            settings.selectedSessionTargets(for: .kitty, provider: .claude),
            [live]
        )
    }

    @MainActor
    func testRouteChangeIsRejectedImmediatelyBeforeDelivery() async throws {
        let suiteName = "AutoContinueControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.autoContinueEnabled = true
        settings.autoContinueTerminal = .iterm
        settings.setTerminalSession(itermTarget(id: "selected"), enabled: true)
        let store = UsageStore(settings: settings)
        let controller = AutoContinueController(
            settings: settings,
            store: store,
            clients: [
                RouteChangingTerminalAutomationClient(
                    changeRoute: {
                        settings.autoContinueTerminal = .ghostty
                    }
                )
            ],
            defaults: defaults
        )

        controller.sendNow(to: .claude)
        await waitForDelivery(controller, provider: .claude)

        XCTAssertTrue(controller.status(for: .claude).isFailure)
    }

    @MainActor
    func testLegacyKittyIdentityDoesNotBlockAllMatchingRecovery() throws {
        let suiteName = "AutoContinueControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.autoContinueEnabled = true
        settings.setKittySession(17, enabled: true, for: .claude)
        settings.kittyClaudeAllSessions = true
        let store = UsageStore(settings: settings)
        let controller = AutoContinueController(
            settings: settings,
            store: store,
            clients: [
                StubTerminalAutomationClient(
                    terminal: .kitty,
                    scanResult: .complete(
                        TerminalTargetSummary(targets: [])
                    )
                )
            ],
            defaults: defaults
        )

        controller.processSuccessfulSnapshot(
            usageSnapshot(usedFraction: 1)
        )

        XCTAssertTrue(controller.isArmed(for: .claude))
    }

    @MainActor
    func testPartialDeliveryRetriesOnlyUnsentSessions() async throws {
        let suiteName = "AutoContinueControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.autoContinueTerminal = .iterm
        settings.setTerminalSession(itermTarget(id: "first"), enabled: true)
        settings.setTerminalSession(itermTarget(id: "second"), enabled: true)
        settings.autoContinueEnabled = true
        let store = UsageStore(settings: settings)
        let client = PartialThenSuccessfulTerminalAutomationClient()
        let controller = AutoContinueController(
            settings: settings,
            store: store,
            clients: [client],
            defaults: defaults
        )

        controller.processSuccessfulSnapshot(
            usageSnapshot(usedFraction: 1)
        )
        controller.processSuccessfulSnapshot(
            usageSnapshot(usedFraction: 0)
        )
        await waitForDelivery(controller, provider: .claude)

        XCTAssertTrue(controller.isArmed(for: .claude))
        XCTAssertEqual(client.targetIDsByAttempt, [["first", "second"]])

        controller.processSuccessfulSnapshot(
            usageSnapshot(usedFraction: 0.1)
        )
        await waitForDelivery(controller, provider: .claude)

        XCTAssertFalse(controller.isArmed(for: .claude))
        XCTAssertEqual(
            client.targetIDsByAttempt,
            [["first", "second"], ["second"]]
        )
    }

    @MainActor
    private func waitForScan(
        _ controller: AutoContinueController,
        provider: ProviderID
    ) async {
        for _ in 0..<100 where controller.status(for: provider) == .scanning {
            await Task.yield()
        }
    }

    @MainActor
    private func waitForDelivery(
        _ controller: AutoContinueController,
        provider: ProviderID
    ) async {
        for _ in 0..<100 where controller.status(for: provider) == .sending {
            await Task.yield()
        }
    }

    private func itermTarget(id: String) -> TerminalSessionTarget {
        TerminalSessionTarget(
            terminal: .iterm,
            provider: .claude,
            id: id,
            displayTitle: "Model Meter",
            currentDirectory: "/Users/test/model-meter",
            processName: "claude",
            auxiliaryIdentifier: "/dev/ttys001"
        )
    }

    private func usageSnapshot(
        usedFraction: Double
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: .claude,
            fetchedAt: Date(),
            plan: nil,
            limits: [
                UsageLimit(
                    id: "five-hour",
                    title: "5-hour",
                    usedFraction: usedFraction,
                    windowMinutes: 300
                )
            ],
            activity: .empty,
            cliVersion: nil,
            source: "test",
            note: nil
        )
    }
}

@MainActor
private struct RouteChangingTerminalAutomationClient: TerminalAutomationClient {
    let terminal = AutoContinueTerminal.iterm
    let changeRoute: @MainActor @Sendable () -> Void

    func preflight(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalPreflightResult {
        .ready
    }

    func scan(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalScanResult {
        .complete(TerminalTargetSummary(targets: configuration.enrolledTargets))
    }

    func sendContinue(
        configuration: TerminalAutomationConfiguration,
        authorization: @escaping @MainActor @Sendable () -> Bool
    ) async -> TerminalSendResult {
        changeRoute()
        return authorization()
            ? .sent(TerminalTargetSummary(targets: configuration.enrolledTargets))
            : .failure(.routeChanged(terminal))
    }
}

@MainActor
private struct StubTerminalAutomationClient: TerminalAutomationClient {
    let terminal: AutoContinueTerminal
    let scanResult: TerminalScanResult

    func preflight(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalPreflightResult {
        .ready
    }

    func scan(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalScanResult {
        scanResult
    }

    func sendContinue(
        configuration: TerminalAutomationConfiguration,
        authorization: @escaping @MainActor @Sendable () -> Bool
    ) async -> TerminalSendResult {
        .failure(.partial(terminal: terminal, detail: "not used"))
    }
}

@MainActor
private final class PartialThenSuccessfulTerminalAutomationClient:
    TerminalAutomationClient {
    let terminal = AutoContinueTerminal.iterm
    private(set) var targetIDsByAttempt: [[String]] = []

    func preflight(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalPreflightResult {
        .ready
    }

    func scan(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalScanResult {
        .complete(TerminalTargetSummary(targets: configuration.enrolledTargets))
    }

    func sendContinue(
        configuration: TerminalAutomationConfiguration,
        authorization: @escaping @MainActor @Sendable () -> Bool
    ) async -> TerminalSendResult {
        guard authorization() else {
            return .failure(.routeChanged(terminal))
        }
        targetIDsByAttempt.append(configuration.enrolledTargets.map(\.id))
        if targetIDsByAttempt.count == 1,
           let sent = configuration.enrolledTargets.first {
            return .partial(
                sent: TerminalTargetSummary(targets: [sent]),
                issue: .partial(
                    terminal: terminal,
                    detail: "1 selected session failed during delivery"
                )
            )
        }
        return .sent(
            TerminalTargetSummary(targets: configuration.enrolledTargets)
        )
    }
}
