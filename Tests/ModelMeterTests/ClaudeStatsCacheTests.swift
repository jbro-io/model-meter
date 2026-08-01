import Foundation
import XCTest
@testable import ModelMeter

final class ClaudeStatsCacheTests: XCTestCase {
    func testParsesAggregateStatsAndBuildsNinetyDayHistory() throws {
        let data = Data(
            """
            {
              "dailyActivity": [
                {"date":"2026-07-23","messageCount":3,"sessionCount":1,"toolCallCount":2},
                {"date":"2026-07-24","messageCount":8,"sessionCount":2,"toolCallCount":5},
                {"date":"2026-07-25","messageCount":2,"sessionCount":1,"toolCallCount":1}
              ],
              "dailyModelTokens": [
                {"date":"2026-07-24","tokensByModel":{"claude-opus":1200}},
                {"date":"2026-07-25","tokensByModel":{"claude-opus":2000,"claude-sonnet":500}}
              ],
              "modelUsage": {
                "claude-opus": {
                  "inputTokens":100,
                  "outputTokens":200,
                  "cacheCreationInputTokens":300,
                  "cacheReadInputTokens":400
                },
                "claude-sonnet": {
                  "inputTokens":10,
                  "outputTokens":20,
                  "cacheCreationInputTokens":30,
                  "cacheReadInputTokens":40
                }
              },
              "totalSessions":42,
              "totalMessages":900,
              "version":4,
              "lastComputedDate":"2026-07-25",
              "hourCounts":{},
              "firstSessionDate":"2026-01-01",
              "longestSession":null
            }
            """.utf8
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 12))
        )

        let stats = try ClaudeStatsCacheParser().parse(
            data,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(stats.todayTokens, 2_500)
        XCTAssertEqual(stats.lifetimeTokens, 1_100)
        XCTAssertEqual(stats.peakDailyTokens, 2_500)
        XCTAssertEqual(stats.totalSessions, 42)
        XCTAssertEqual(stats.totalMessages, 900)
        XCTAssertEqual(stats.currentStreakDays, 3)
        XCTAssertEqual(stats.longestStreakDays, 3)
        XCTAssertEqual(stats.dataThroughDay, "2026-07-25")
        XCTAssertTrue(stats.isCurrent)
        XCTAssertFalse(stats.usesTranscriptMetadata)
        XCTAssertEqual(stats.dailyTokens.count, 90)
        XCTAssertEqual(
            stats.dailyTokens.suffix(7).map(\.tokens),
            [0, 0, 0, 0, 0, 1_200, 2_500]
        )
    }

    func testStreakCanContinueFromYesterdayWhenTodayHasNoActivity() throws {
        let data = Data(
            """
            {
              "dailyActivity": [
                {"date":"2026-07-23","messageCount":1},
                {"date":"2026-07-24","messageCount":1}
              ],
              "dailyModelTokens":[],
              "modelUsage":{},
              "totalSessions":2,
              "totalMessages":2,
              "lastComputedDate":"2026-07-25"
            }
            """.utf8
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 8))
        )

        let stats = try ClaudeStatsCacheParser().parse(
            data,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(stats.currentStreakDays, 2)
        XCTAssertEqual(stats.todayTokens, 0)
    }
}
