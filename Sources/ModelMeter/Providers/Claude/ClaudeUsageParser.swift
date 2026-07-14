import Foundation

struct ClaudeUsageParseResult: Equatable {
    let limits: [UsageLimit]
    let sessionCostUSD: Double?
}

struct ClaudeUsageParser {
    private static let usageLine = try! NSRegularExpression(
        pattern: #"^\s*(.+?):\s*(\d+(?:\.\d+)?)%\s+used(?:\s*[·•-]\s*resets\s+(.+?))?\s*$"#,
        options: [.caseInsensitive]
    )
    private static let costLine = try! NSRegularExpression(
        pattern: #"Total cost:\s*\$([0-9]+(?:\.[0-9]+)?)"#,
        options: [.caseInsensitive]
    )
    private static let weekdayReset = try! NSRegularExpression(
        pattern: #"(?i)\b(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#
    )
    private static let calendarDateReset = try! NSRegularExpression(
        pattern: #"(?i)\b([a-z]+)\s+(\d{1,2})(?:,\s*(\d{4}))?\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?:\s*\(([^)]+)\))?"#
    )
    private static let clockReset = try! NSRegularExpression(
        pattern: #"(?i)\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#
    )
    private static let relativeReset = try! NSRegularExpression(
        pattern: #"(?i)\bin\s+(?:(\d+)\s*(?:hours?|hrs?|h))?\s*(?:(\d+)\s*(?:minutes?|mins?|m))?\b"#
    )

    func parse(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ClaudeUsageParseResult {
        let cleanText = ANSITextCleaner.clean(text)
        var limits: [UsageLimit] = []

        for line in cleanText.split(whereSeparator: \.isNewline).map(String.init) {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = Self.usageLine.firstMatch(in: line, range: range),
                  let rawTitle = capture(1, match: match, in: line),
                  let percentText = capture(2, match: match, in: line),
                  let percent = Double(percentText)
            else { continue }

            let reset = capture(3, match: match, in: line)
            let title = normalizedTitle(rawTitle)
            let id = title.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "·", with: "-")

            limits.append(
                UsageLimit(
                    id: "claude-\(id)",
                    title: title,
                    usedFraction: percent / 100,
                    resetsAt: reset.flatMap {
                        parsedResetDate(from: $0, now: now, calendar: calendar)
                    },
                    resetDescription: reset?.trimmingCharacters(in: .whitespacesAndNewlines),
                    windowMinutes: inferredWindowMinutes(from: rawTitle)
                )
            )
        }

        let cost = firstDouble(using: Self.costLine, in: cleanText)
        return ClaudeUsageParseResult(limits: uniqued(limits), sessionCostUSD: cost)
    }

    private func normalizedTitle(_ rawTitle: String) -> String {
        let lower = rawTitle.lowercased()
        if lower == "current session" { return "5-hour" }
        if lower == "current week (all models)" { return "Weekly" }

        if lower.hasPrefix("current week (") && lower.hasSuffix(")") {
            let start = rawTitle.index(rawTitle.startIndex, offsetBy: "Current week (".count)
            let end = rawTitle.index(before: rawTitle.endIndex)
            let scope = rawTitle[start..<end]
                .replacingOccurrences(of: " only", with: "", options: .caseInsensitive)
            return "Weekly · \(scope)"
        }

        return rawTitle
            .replacingOccurrences(of: "Current ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }

    private func inferredWindowMinutes(from title: String) -> Int? {
        let lower = title.lowercased()
        if lower.contains("session") { return 300 }
        if lower.contains("week") { return 10_080 }
        return nil
    }

    private func parsedResetDate(
        from description: String,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let range = NSRange(description.startIndex..., in: description)

        if let match = Self.relativeReset.firstMatch(in: description, range: range) {
            let hours = capture(1, match: match, in: description).flatMap(Int.init) ?? 0
            let minutes = capture(2, match: match, in: description).flatMap(Int.init) ?? 0
            if hours > 0 || minutes > 0 {
                return calendar.date(byAdding: .minute, value: hours * 60 + minutes, to: now)
            }
        }

        if let match = Self.calendarDateReset.firstMatch(in: description, range: range),
           let monthName = capture(1, match: match, in: description),
           let month = monthNumber(monthName),
           let dayText = capture(2, match: match, in: description),
           let day = Int(dayText),
           let hourText = capture(4, match: match, in: description),
           let meridiem = capture(6, match: match, in: description),
           let hour = normalizedHour(hourText, meridiem: meridiem) {
            var resetCalendar = calendar
            if let zoneName = capture(7, match: match, in: description),
               let timeZone = TimeZone(identifier: zoneName) {
                resetCalendar.timeZone = timeZone
            }

            let explicitYear = capture(3, match: match, in: description).flatMap(Int.init)
            var components = DateComponents(
                year: explicitYear ?? resetCalendar.component(.year, from: now),
                month: month,
                day: day,
                hour: hour,
                minute: capture(5, match: match, in: description).flatMap(Int.init) ?? 0
            )
            components.timeZone = resetCalendar.timeZone

            guard var date = resetCalendar.date(from: components) else { return nil }
            if explicitYear == nil, date <= now {
                components.year = (components.year ?? 0) + 1
                date = resetCalendar.date(from: components) ?? date
            }
            return date
        }

        if let match = Self.weekdayReset.firstMatch(in: description, range: range),
           let weekdayName = capture(1, match: match, in: description),
           let hourText = capture(2, match: match, in: description),
           let meridiem = capture(4, match: match, in: description),
           let hour = normalizedHour(hourText, meridiem: meridiem),
           let weekday = weekdayNumber(weekdayName) {
            let minute = capture(3, match: match, in: description).flatMap(Int.init) ?? 0
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            return calendar.nextDate(
                after: now,
                matching: components,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        }

        if let match = Self.clockReset.firstMatch(in: description, range: range),
           let hourText = capture(1, match: match, in: description),
           let meridiem = capture(3, match: match, in: description),
           let hour = normalizedHour(hourText, meridiem: meridiem) {
            let minute = capture(2, match: match, in: description).flatMap(Int.init) ?? 0
            return calendar.nextDate(
                after: now,
                matching: DateComponents(hour: hour, minute: minute),
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        }

        return nil
    }

    private func normalizedHour(_ value: String, meridiem: String) -> Int? {
        guard let rawHour = Int(value), (1...12).contains(rawHour) else { return nil }
        let base = rawHour % 12
        return meridiem.lowercased() == "pm" ? base + 12 : base
    }

    private func weekdayNumber(_ value: String) -> Int? {
        switch value.lowercased() {
        case "sunday": 1
        case "monday": 2
        case "tuesday": 3
        case "wednesday": 4
        case "thursday": 5
        case "friday": 6
        case "saturday": 7
        default: nil
        }
    }

    private func monthNumber(_ value: String) -> Int? {
        switch value.lowercased().prefix(3) {
        case "jan": 1
        case "feb": 2
        case "mar": 3
        case "apr": 4
        case "may": 5
        case "jun": 6
        case "jul": 7
        case "aug": 8
        case "sep": 9
        case "oct": 10
        case "nov": 11
        case "dec": 12
        default: nil
        }
    }

    private func capture(_ index: Int, match: NSTextCheckingResult, in text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private func firstDouble(using regex: NSRegularExpression, in text: String) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let value = capture(1, match: match, in: text)
        else { return nil }
        return Double(value)
    }

    private func uniqued(_ limits: [UsageLimit]) -> [UsageLimit] {
        var seen = Set<String>()
        return limits.filter { seen.insert($0.id).inserted }
    }
}

enum ANSITextCleaner {
    private static let escapeSequence = try! NSRegularExpression(
        pattern: #"\u001B(?:\[[0-?]*[ -/]*[@-~]|\][^\u0007]*(?:\u0007|\u001B\\))"#
    )

    static func clean(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return escapeSequence.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
