import Foundation
import XCTest
@testable import ModelMeter

final class TerminalAutomationClientTests: XCTestCase {
    func testITermParsingKeepsClaudeAndCodexTargetsDistinct() throws {
        let data = Data(
            """
            [
              {
                "id": "claude-session",
                "name": "Model Meter — Claude Code",
                "tty": "/dev/ttys001",
                "jobName": "claude",
                "commandLine": "claude --resume",
                "path": "/Users/test/model-meter"
              },
              {
                "id": "codex-session",
                "name": "Model Meter — Codex",
                "tty": "/dev/ttys002",
                "jobName": "codex",
                "commandLine": "codex",
                "path": "file:///Users/test/model-meter"
              },
              {
                "id": "ambiguous-session",
                "name": "Claude and Codex notes",
                "tty": "/dev/ttys003",
                "jobName": "zsh",
                "commandLine": "compare claude codex",
                "path": "/Users/test"
              },
              {
                "id": "returned-shell",
                "name": "Model Meter — Claude Code",
                "tty": "/dev/ttys004",
                "jobName": "zsh",
                "commandLine": "zsh",
                "path": "/Users/test/model-meter"
              },
              {
                "id": "vim-note",
                "name": "Claude Code",
                "tty": "/dev/ttys005",
                "jobName": "vim",
                "commandLine": "vim claude.md",
                "path": "/Users/test/model-meter"
              },
              {
                "id": "title-only",
                "name": "Claude Code",
                "tty": "/dev/ttys006",
                "jobName": "",
                "commandLine": "",
                "path": "/Users/test/model-meter"
              }
            ]
            """.utf8
        )

        let claude = try ITermAutomationClient.parseTargets(
            data,
            provider: .claude
        )
        let codex = try ITermAutomationClient.parseTargets(
            data,
            provider: .codex
        )

        XCTAssertEqual(
            claude.targets.map(\.id),
            ["claude-session", "title-only"]
        )
        XCTAssertEqual(codex.targets.map(\.id), ["codex-session"])
        XCTAssertEqual(codex.targets.first?.currentDirectory, "/Users/test/model-meter")
    }

    func testGhosttyRequiresProviderSpecificAnchoredTitles() throws {
        let data = Data(
            """
            [
              {
                "id": "claude-terminal",
                "name": "Model Meter — Claude Code",
                "workingDirectory": "/Users/test/model-meter"
              },
              {
                "id": "codex-terminal",
                "name": "Codex",
                "workingDirectory": "/Users/test/model-meter"
              },
              {
                "id": "notes-terminal",
                "name": "Claude planning notes",
                "workingDirectory": "/Users/test"
              }
            ]
            """.utf8
        )

        let claude = try GhosttyAutomationClient.parseTargets(
            data,
            provider: .claude
        )
        let codex = try GhosttyAutomationClient.parseTargets(
            data,
            provider: .codex
        )

        XCTAssertEqual(claude.targets.map(\.id), ["claude-terminal"])
        XCTAssertEqual(codex.targets.map(\.id), ["codex-terminal"])
    }

    func testPersistedIdentityFailsClosedWhenLiveSessionChanges() {
        let enrolled = target(
            terminal: .iterm,
            id: "session-id",
            title: "Model Meter",
            directory: "/Users/test/model-meter",
            auxiliaryIdentifier: "/dev/ttys001"
        )
        let same = target(
            terminal: .iterm,
            id: "session-id",
            title: "A refreshed title",
            directory: "/Users/test/model-meter",
            auxiliaryIdentifier: "/dev/ttys001"
        )
        let reusedTTY = target(
            terminal: .iterm,
            id: "session-id",
            title: "Model Meter",
            directory: "/Users/test/model-meter",
            auxiliaryIdentifier: "/dev/ttys009"
        )
        let movedDirectory = target(
            terminal: .iterm,
            id: "session-id",
            title: "Model Meter",
            directory: "/Users/test/other",
            auxiliaryIdentifier: "/dev/ttys001"
        )

        XCTAssertTrue(enrolled.identifiesSameLiveSession(as: same))
        XCTAssertFalse(enrolled.identifiesSameLiveSession(as: reusedTTY))
        XCTAssertFalse(enrolled.identifiesSameLiveSession(as: movedDirectory))
    }

    func testGhosttyVersionGateStartsAtOnePointThree() {
        XCTAssertFalse(GhosttyAutomationClient.version("1.2.9", isAtLeast: "1.3.0"))
        XCTAssertTrue(GhosttyAutomationClient.version("1.3.0", isAtLeast: "1.3.0"))
        XCTAssertTrue(GhosttyAutomationClient.version("1.3.1", isAtLeast: "1.3.0"))
        XCTAssertTrue(GhosttyAutomationClient.version("2.0.0-dev", isAtLeast: "1.3.0"))
    }

    func testAppleEventDeliveryReportsPartialSuccesses() {
        let first = target(
            terminal: .iterm,
            id: "first",
            title: "First",
            directory: "/Users/test/model-meter",
            auxiliaryIdentifier: "/dev/ttys001"
        )
        let second = target(
            terminal: .iterm,
            id: "second",
            title: "Second",
            directory: "/Users/test/model-meter",
            auxiliaryIdentifier: "/dev/ttys002"
        )

        let result = AppleEventDeliveryParser.parse(
            #"{"sentIDs":["first"],"failedIDs":["second"]}"#,
            targets: [first, second],
            terminal: .iterm,
            targetNoun: "session"
        )

        XCTAssertEqual(
            result,
            .partial(
                sent: TerminalTargetSummary(targets: [first]),
                issue: .partial(
                    terminal: .iterm,
                    detail: "1 selected session failed during delivery"
                )
            )
        )
    }

    private func target(
        terminal: AutoContinueTerminal,
        id: String,
        title: String,
        directory: String,
        auxiliaryIdentifier: String
    ) -> TerminalSessionTarget {
        TerminalSessionTarget(
            terminal: terminal,
            provider: .claude,
            id: id,
            displayTitle: title,
            currentDirectory: directory,
            processName: "claude",
            auxiliaryIdentifier: auxiliaryIdentifier
        )
    }
}
