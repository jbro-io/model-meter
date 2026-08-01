import XCTest
@testable import ModelMeter

final class LiveProviderTests: XCTestCase {
    private var liveTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["MODEL_METER_LIVE_TESTS"] == "1"
    }

    func testClaudeProviderAgainstInstalledCLI() async throws {
        guard liveTestsEnabled else {
            throw XCTSkip("Set MODEL_METER_LIVE_TESTS=1 to contact the installed CLIs.")
        }

        let snapshot = try await ClaudeUsageProvider().fetch()
        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertTrue(snapshot.source.hasPrefix("Claude CLI /usage"))
        XCTAssertNotNil(snapshot.cliVersion)
        if ProcessInfo.processInfo.environment["MODEL_METER_EXPECT_CLAUDE_LIMITS"] == "1" {
            XCTAssertFalse(snapshot.limits.isEmpty, "Expected subscription quota windows from Claude /usage")
        }
    }

    func testCodexProviderAgainstInstalledCLI() async throws {
        guard liveTestsEnabled else {
            throw XCTSkip("Set MODEL_METER_LIVE_TESTS=1 to contact the installed CLIs.")
        }

        let snapshot = try await CodexUsageProvider().fetch()
        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.source, "Codex app-server")
        XCTAssertFalse(snapshot.limits.isEmpty)
        XCTAssertNotNil(snapshot.cliVersion)
    }
}
