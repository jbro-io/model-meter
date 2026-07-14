import Foundation
import XCTest
@testable import ModelMeter

final class ClaudeUsageParserTests: XCTestCase {
    private let parser = ClaudeUsageParser()

    func testParsesSubscriptionRowsFromFixture() throws {
        let result = parser.parse(try fixture(named: "claude-subscription-usage"))

        XCTAssertNil(result.sessionCostUSD)
        XCTAssertEqual(result.limits.count, 4)

        let session = try limit(titled: "5-hour", in: result)
        XCTAssertEqual(session.id, "claude-5-hour")
        XCTAssertEqual(session.usedFraction, 0.37, accuracy: 0.000_1)
        XCTAssertEqual(session.windowMinutes, 300)

        let weekly = try limit(titled: "Weekly", in: result)
        XCTAssertEqual(weekly.id, "claude-weekly")
        XCTAssertEqual(weekly.usedFraction, 0.63, accuracy: 0.000_1)
        XCTAssertEqual(weekly.windowMinutes, 10_080)
    }

    func testNormalizesModelOnlyRowsAndPreservesDecimalPercentages() throws {
        let result = parser.parse(try fixture(named: "claude-subscription-usage"))

        let sonnet = try limit(titled: "Weekly · Sonnet", in: result)
        XCTAssertEqual(sonnet.usedFraction, 0.14, accuracy: 0.000_1)
        XCTAssertEqual(sonnet.windowMinutes, 10_080)
        XCTAssertNil(sonnet.resetDescription)

        let opus = try limit(titled: "Weekly · Opus", in: result)
        XCTAssertEqual(opus.usedFraction, 0.095, accuracy: 0.000_1)
        XCTAssertEqual(opus.windowMinutes, 10_080)
    }

    func testPreservesResetTextForSupportedSeparators() throws {
        let result = parser.parse(try fixture(named: "claude-subscription-usage"))

        XCTAssertEqual(
            try limit(titled: "5-hour", in: result).resetDescription,
            "2pm (local time)"
        )
        XCTAssertEqual(
            try limit(titled: "Weekly", in: result).resetDescription,
            "Monday at 12am"
        )
        XCTAssertEqual(
            try limit(titled: "Weekly · Opus", in: result).resetDescription,
            "Friday at 6pm"
        )
    }

    func testStripsCSIAndOSCANSIEscapesBeforeParsing() throws {
        let decorated = "\u{001B}]0;redacted title\u{0007}"
            + "\u{001B}[2mCurrent session: 42% used · resets 3pm\u{001B}[0m"

        let result = parser.parse(decorated)

        XCTAssertEqual(ANSITextCleaner.clean(decorated), "Current session: 42% used · resets 3pm")
        let session = try XCTUnwrap(result.limits.first)
        XCTAssertEqual(session.title, "5-hour")
        XCTAssertEqual(session.usedFraction, 0.42, accuracy: 0.000_1)
        XCTAssertEqual(session.resetDescription, "3pm")
    }

    func testParsesAPIOnlySessionCostWithoutInventingLimits() {
        let text = """
        Total cost:            $12.34
        Total duration (API):  4m 12s
        Total duration (wall): 9m 3s
        Total code changes:    0 lines added, 0 lines removed
        """

        let result = parser.parse(text)

        XCTAssertTrue(result.limits.isEmpty)
        XCTAssertEqual(result.sessionCostUSD, 12.34)
    }

    func testParsesCurrentSubscriptionFormatWithModelScopedWeek() throws {
        let text = """
        Current session: 12% used · resets Jul 11 at 2:39pm (America/Phoenix)
        Current week (all models): 34% used · resets Jul 15 at 11:59pm (America/Phoenix)
        Current week (Fable): 67% used · resets Jul 15 at 11:59pm (America/Phoenix)
        """

        let result = parser.parse(text)

        XCTAssertEqual(result.limits.count, 3)
        XCTAssertEqual(try limit(titled: "5-hour", in: result).usedFraction, 0.12, accuracy: 0.000_1)
        XCTAssertEqual(try limit(titled: "Weekly", in: result).usedFraction, 0.34, accuracy: 0.000_1)
        XCTAssertEqual(try limit(titled: "Weekly · Fable", in: result).usedFraction, 0.67, accuracy: 0.000_1)
        XCTAssertEqual(
            try limit(titled: "Weekly · Fable", in: result).resetDescription,
            "Jul 15 at 11:59pm (America/Phoenix)"
        )
    }

    func testResolvesClockWeekdayAndCalendarResetDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Phoenix"))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 13))
        )
        let text = """
        Current session: 12% used · resets 2pm (local time)
        Current week (all models): 34% used · resets Monday at 12am
        Current week (Fable): 67% used · resets Jul 15 at 11:59pm (America/Phoenix)
        """

        let result = parser.parse(text, now: now, calendar: calendar)

        XCTAssertEqual(
            calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: try XCTUnwrap(limit(titled: "5-hour", in: result).resetsAt)
            ),
            DateComponents(year: 2026, month: 7, day: 11, hour: 14, minute: 0)
        )
        XCTAssertEqual(
            calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: try XCTUnwrap(limit(titled: "Weekly", in: result).resetsAt)
            ),
            DateComponents(year: 2026, month: 7, day: 13, hour: 0, minute: 0)
        )
        XCTAssertEqual(
            calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: try XCTUnwrap(limit(titled: "Weekly · Fable", in: result).resetsAt)
            ),
            DateComponents(year: 2026, month: 7, day: 15, hour: 23, minute: 59)
        )
    }

    private func fixture(named name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "txt",
                subdirectory: "Fixtures"
            )
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func limit(
        titled title: String,
        in result: ClaudeUsageParseResult
    ) throws -> UsageLimit {
        try XCTUnwrap(result.limits.first { $0.title == title })
    }
}
