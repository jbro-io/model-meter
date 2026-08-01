import Foundation
import XCTest
@testable import ModelMeter

final class ClaudeActivityStoreTests: XCTestCase {
    func testMergesNewTranscriptUsageOntoCacheWithoutReadingConversationContent() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try writeCache(to: fixture.config)
        let project = fixture.config.appendingPathComponent("projects/project-one")
        try FileManager.default.createDirectory(
            at: project,
            withIntermediateDirectories: true
        )

        try writeLines(
            [
                entry(type: "user", timestamp: "2026-07-25T08:00:00.000Z"),
                entry(type: "user", timestamp: "2026-07-27T08:00:00.000Z"),
                assistant(
                    timestamp: "2026-07-27T08:01:00.000Z",
                    input: 10,
                    output: 5,
                    cacheCreation: 20,
                    cacheRead: 30,
                    content: #"[{"type":"text","text":"private prompt that must be ignored"}]"#
                ),
                entry(type: "system", timestamp: "2026-07-27T08:02:00.000Z"),
                assistant(
                    timestamp: "2026-07-27T08:03:00.000Z",
                    input: 1_000,
                    output: 1_000,
                    cacheCreation: 1_000,
                    cacheRead: 1_000,
                    isSidechain: true
                ),
                entry(type: "progress", timestamp: "2026-07-27T08:04:00.000Z"),
                assistant(
                    timestamp: "2026-07-27T08:05:00.000Z",
                    model: "<synthetic>",
                    input: 999,
                    output: 999,
                    cacheCreation: 999,
                    cacheRead: 999
                )
            ],
            to: project.appendingPathComponent("old-session.jsonl")
        )

        try writeLines(
            [
                entry(type: "user", timestamp: "2026-07-27T09:00:00.000Z"),
                assistant(
                    timestamp: "2026-07-27T09:01:00.000Z",
                    input: 7,
                    output: 3,
                    cacheCreation: 4,
                    cacheRead: 6
                )
            ],
            to: project.appendingPathComponent("new-session.jsonl")
        )

        let subagents = project
            .appendingPathComponent("new-session")
            .appendingPathComponent("subagents")
        try FileManager.default.createDirectory(
            at: subagents,
            withIntermediateDirectories: true
        )
        try writeLines(
            [
                assistant(
                    timestamp: "2026-07-27T09:02:00.000Z",
                    input: 2,
                    output: 8,
                    cacheCreation: 1,
                    cacheRead: 9
                )
            ],
            to: subagents.appendingPathComponent("agent-worker.jsonl")
        )

        let now = try XCTUnwrap(
            ClaudeStatsDate.date(from: "2026-07-28")?.addingTimeInterval(12 * 60 * 60)
        )
        let stats = try XCTUnwrap(
            ClaudeActivityStore(
                environment: ["CLAUDE_CONFIG_DIR": fixture.config.path],
                homeDirectory: fixture.root
            ).load(now: now)
        )

        XCTAssertEqual(stats.todayTokens, 0)
        XCTAssertEqual(stats.lifetimeTokens, 1_105)
        XCTAssertEqual(stats.peakDailyTokens, 50)
        XCTAssertEqual(stats.totalSessions, 3)
        XCTAssertEqual(stats.totalMessages, 16)
        XCTAssertEqual(stats.currentStreakDays, 1)
        XCTAssertEqual(stats.longestStreakDays, 2)
        XCTAssertEqual(stats.dataThroughDay, "2026-07-28")
        XCTAssertTrue(stats.isCurrent)
        XCTAssertTrue(stats.usesTranscriptMetadata)
        XCTAssertEqual(
            stats.dailyTokens.suffix(4).map(\.tokens),
            [50, 0, 35, 0]
        )
    }

    func testDoesNotPresentMissingRecentDaysAsZeroWhenTranscriptDirectoryIsUnavailable() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeCache(to: fixture.config)

        let now = try XCTUnwrap(
            ClaudeStatsDate.date(from: "2026-07-28")?.addingTimeInterval(12 * 60 * 60)
        )
        let stats = try XCTUnwrap(
            ClaudeActivityStore(
                environment: ["CLAUDE_CONFIG_DIR": fixture.config.path],
                homeDirectory: fixture.root
            ).load(now: now)
        )

        XCTAssertNil(stats.todayTokens)
        XCTAssertNil(stats.currentStreakDays)
        XCTAssertEqual(stats.dataThroughDay, "2026-07-25")
        XCTAssertFalse(stats.isCurrent)
        XCTAssertFalse(stats.usesTranscriptMetadata)
        XCTAssertEqual(stats.dailyTokens.last?.tokens, 50)
    }

    private func makeFixture() throws -> (root: URL, config: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-meter-claude-stats-\(UUID().uuidString)")
        let config = root.appendingPathComponent("claude-profile")
        try FileManager.default.createDirectory(
            at: config,
            withIntermediateDirectories: true
        )
        return (root, config)
    }

    private func writeCache(to directory: URL) throws {
        let data = Data(
            """
            {
              "dailyActivity": [
                {"date":"2026-07-24","messageCount":1},
                {"date":"2026-07-25","messageCount":1}
              ],
              "dailyModelTokens": [
                {"date":"2026-07-25","tokensByModel":{"claude-opus":50}}
              ],
              "modelUsage": {
                "claude-opus": {
                  "inputTokens":100,
                  "outputTokens":200,
                  "cacheCreationInputTokens":300,
                  "cacheReadInputTokens":400
                }
              },
              "totalSessions":2,
              "totalMessages":10,
              "lastComputedDate":"2026-07-25"
            }
            """.utf8
        )
        try data.write(to: directory.appendingPathComponent("stats-cache.json"))
    }

    private func writeLines(_ lines: [String], to url: URL) throws {
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        try data.write(to: url)
    }

    private func entry(type: String, timestamp: String) -> String {
        #"{"type":"\#(type)","timestamp":"\#(timestamp)","uuid":"entry"}"#
    }

    private func assistant(
        timestamp: String,
        model: String = "claude-opus",
        input: Int64,
        output: Int64,
        cacheCreation: Int64,
        cacheRead: Int64,
        isSidechain: Bool = false,
        content: String = "[]"
    ) -> String {
        """
        {"type":"assistant","timestamp":"\(timestamp)","uuid":"assistant","isSidechain":\(isSidechain),"message":{"model":"\(model)","content":\(content),"usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(cacheCreation),"cache_read_input_tokens":\(cacheRead)}}}
        """
    }
}
