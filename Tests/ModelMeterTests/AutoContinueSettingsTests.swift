import Foundation
import XCTest
@testable import ModelMeter

final class AutoContinueSettingsTests: XCTestCase {
    @MainActor
    func testSessionTargetingIsDefaultAndSelectionsPersistPerProvider() throws {
        let suiteName = "AutoContinueSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.autoContinueEnabled)
        XCTAssertFalse(settings.kittyAllSessions(for: .claude))
        XCTAssertFalse(settings.kittyAllSessions(for: .codex))
        XCTAssertTrue(settings.kittySessionIDs(for: .claude).isEmpty)
        XCTAssertEqual(settings.kittyMatch(for: .claude), "smart:claude")
        XCTAssertEqual(settings.kittyMatch(for: .codex), "smart:codex")

        settings.autoContinueEnabled = true
        settings.setKittySession(17, enabled: true, for: .claude)
        settings.setKittySession(22, enabled: true, for: .codex)
        settings.kittyCodexAllSessions = true

        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.autoContinueEnabled)
        XCTAssertEqual(restored.kittySessionIDs(for: .claude), [17])
        XCTAssertEqual(restored.kittySessionIDs(for: .codex), [22])
        XCTAssertFalse(restored.kittyAllSessions(for: .claude))
        XCTAssertTrue(restored.kittyAllSessions(for: .codex))
    }

    @MainActor
    func testSuccessfulScanCanForgetClosedSessionsWithoutTouchingOtherProvider() throws {
        let suiteName = "AutoContinueSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.setKittySession(17, enabled: true, for: .claude)
        settings.setKittySession(18, enabled: true, for: .claude)
        settings.setKittySession(22, enabled: true, for: .codex)

        settings.retainKittySessions(withIDs: [18, 99], for: .claude)

        XCTAssertEqual(settings.kittySessionIDs(for: .claude), [18])
        XCTAssertEqual(settings.kittySessionIDs(for: .codex), [22])

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.kittySessionIDs(for: .claude), [18])
        XCTAssertEqual(restored.kittySessionIDs(for: .codex), [22])
    }

    @MainActor
    func testSelectionsPersistSeparatelyForEveryTerminalAndProvider() throws {
        let suiteName = "AutoContinueSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let itermClaude = terminalTarget(
            terminal: .iterm,
            provider: .claude,
            id: "iterm-claude"
        )
        let ghosttyCodex = terminalTarget(
            terminal: .ghostty,
            provider: .codex,
            id: "ghostty-codex"
        )

        settings.setTerminalSession(itermClaude, enabled: true)
        settings.setTerminalSession(ghosttyCodex, enabled: true)
        settings.autoContinueTerminal = .ghostty

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.autoContinueTerminal, .ghostty)
        XCTAssertEqual(
            restored.selectedSessionTargets(for: .iterm, provider: .claude),
            [itermClaude]
        )
        XCTAssertEqual(
            restored.selectedSessionTargets(for: .ghostty, provider: .codex),
            [ghosttyCodex]
        )
        XCTAssertTrue(
            restored.selectedSessionTargets(for: .iterm, provider: .codex).isEmpty
        )
    }

    @MainActor
    func testCompleteScanRefreshesIdentityAndPrunesOnlyItsRoute() throws {
        let suiteName = "AutoContinueSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let stale = terminalTarget(
            terminal: .iterm,
            provider: .claude,
            id: "closed"
        )
        let refreshed = terminalTarget(
            terminal: .iterm,
            provider: .claude,
            id: "live",
            title: "Old title"
        )
        let otherProvider = terminalTarget(
            terminal: .iterm,
            provider: .codex,
            id: "codex-live"
        )
        settings.setTerminalSession(stale, enabled: true)
        settings.setTerminalSession(refreshed, enabled: true)
        settings.setTerminalSession(otherProvider, enabled: true)

        let liveSnapshot = terminalTarget(
            terminal: .iterm,
            provider: .claude,
            id: "live",
            title: "Current title"
        )
        settings.synchronizeEnrolledSessions(
            with: [liveSnapshot],
            terminal: .iterm,
            provider: .claude
        )

        XCTAssertEqual(
            settings.selectedSessionTargets(for: .iterm, provider: .claude),
            [liveSnapshot]
        )
        XCTAssertEqual(
            settings.selectedSessionTargets(for: .iterm, provider: .codex),
            [otherProvider]
        )
    }

    @MainActor
    func testRouteRevisionsChangeOnlyForAffectedProviders() throws {
        let suiteName = "AutoContinueSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let initialClaude = settings.autoContinueRouteRevision(for: .claude)
        let initialCodex = settings.autoContinueRouteRevision(for: .codex)
        settings.autoContinueTerminal = .iterm
        XCTAssertGreaterThan(
            settings.autoContinueRouteRevision(for: .claude),
            initialClaude
        )
        XCTAssertGreaterThan(
            settings.autoContinueRouteRevision(for: .codex),
            initialCodex
        )

        let claudeAfterTerminal = settings.autoContinueRouteRevision(for: .claude)
        let codexAfterTerminal = settings.autoContinueRouteRevision(for: .codex)
        settings.setTerminalSession(
            terminalTarget(
                terminal: .iterm,
                provider: .claude,
                id: "session"
            ),
            enabled: true
        )
        XCTAssertGreaterThan(
            settings.autoContinueRouteRevision(for: .claude),
            claudeAfterTerminal
        )
        XCTAssertEqual(
            settings.autoContinueRouteRevision(for: .codex),
            codexAfterTerminal
        )
    }

    @MainActor
    func testDisplayOnlyRefreshDoesNotReviseTheRoute() throws {
        let suiteName = "AutoContinueSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.autoContinueTerminal = .iterm
        let enrolled = terminalTarget(
            terminal: .iterm,
            provider: .claude,
            id: "live",
            title: "Old title"
        )
        settings.setTerminalSession(enrolled, enabled: true)
        let revision = settings.autoContinueRouteRevision(for: .claude)
        let refreshed = terminalTarget(
            terminal: .iterm,
            provider: .claude,
            id: "live",
            title: "Current title"
        )

        settings.synchronizeEnrolledSessions(
            with: [refreshed],
            terminal: .iterm,
            provider: .claude
        )

        XCTAssertEqual(
            settings.autoContinueRouteRevision(for: .claude),
            revision
        )
        XCTAssertEqual(
            settings.selectedSessionTargets(for: .iterm, provider: .claude),
            [refreshed]
        )
    }

    @MainActor
    func testReusedSessionIdentityIsUnenrolled() throws {
        let suiteName = "AutoContinueSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.autoContinueTerminal = .iterm
        settings.setTerminalSession(
            terminalTarget(
                terminal: .iterm,
                provider: .claude,
                id: "reused",
                tty: "/dev/ttys001"
            ),
            enabled: true
        )
        let revision = settings.autoContinueRouteRevision(for: .claude)

        settings.synchronizeEnrolledSessions(
            with: [
                terminalTarget(
                    terminal: .iterm,
                    provider: .claude,
                    id: "reused",
                    tty: "/dev/ttys009"
                )
            ],
            terminal: .iterm,
            provider: .claude
        )

        XCTAssertTrue(
            settings.selectedSessionTargets(
                for: .iterm,
                provider: .claude
            ).isEmpty
        )
        XCTAssertGreaterThan(
            settings.autoContinueRouteRevision(for: .claude),
            revision
        )
    }

    @MainActor
    func testLegacyKittyIDsRequireAndAcceptLiveIdentityMigration() throws {
        let suiteName = "AutoContinueSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.setKittySession(17, enabled: true, for: .claude)
        XCTAssertTrue(
            settings.hasIncompleteSessionIdentity(
                for: .kitty,
                provider: .claude
            )
        )

        let live = TerminalSessionTarget(
            terminal: .kitty,
            provider: .claude,
            id: "17",
            displayTitle: "Model Meter",
            currentDirectory: "/Users/test/model-meter",
            processName: "claude",
            auxiliaryIdentifier: nil
        )
        settings.synchronizeEnrolledSessions(
            with: [live],
            terminal: .kitty,
            provider: .claude
        )

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

    private func terminalTarget(
        terminal: AutoContinueTerminal,
        provider: ProviderID,
        id: String,
        title: String = "Model Meter",
        tty: String = "/dev/ttys001"
    ) -> TerminalSessionTarget {
        TerminalSessionTarget(
            terminal: terminal,
            provider: provider,
            id: id,
            displayTitle: title,
            currentDirectory: "/Users/test/model-meter",
            processName: provider.rawValue,
            auxiliaryIdentifier: terminal == .iterm ? tty : nil
        )
    }
}
