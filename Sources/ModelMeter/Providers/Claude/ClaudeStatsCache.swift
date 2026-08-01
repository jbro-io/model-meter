import Foundation

struct ClaudeStatsSnapshot: Equatable, Sendable {
    let todayTokens: Int64?
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let totalSessions: Int?
    let totalMessages: Int?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
    let dailyTokens: [UsageActivityDay]
    let dataThroughDay: String?
    let isCurrent: Bool
    let usesTranscriptMetadata: Bool
}

struct ClaudeStatsAccumulator: Equatable, Sendable {
    var lastComputedDay: String?
    var tokensByDay: [String: Int64]
    var lifetimeTokens: Int64?
    var activeDays: Set<String>
    var totalSessions: Int?
    var totalMessages: Int?

    static let empty = ClaudeStatsAccumulator(
        lastComputedDay: nil,
        tokensByDay: [:],
        lifetimeTokens: nil,
        activeDays: [],
        totalSessions: nil,
        totalMessages: nil
    )

    var latestRecordedDay: String? {
        (Array(tokensByDay.keys) + Array(activeDays)).max()
    }

    var hasValues: Bool {
        lifetimeTokens != nil
            || totalSessions != nil
            || totalMessages != nil
            || !tokensByDay.isEmpty
            || !activeDays.isEmpty
    }

    mutating func merge(_ recent: ClaudeTranscriptStats) {
        for (day, tokens) in recent.tokensByDay {
            tokensByDay[day] = Self.adding(tokensByDay[day] ?? 0, tokens)
        }
        lifetimeTokens = Self.adding(lifetimeTokens ?? 0, recent.lifetimeTokens)
        activeDays.formUnion(recent.activeDays)
        totalSessions = Self.adding(totalSessions ?? 0, recent.totalSessions)
        totalMessages = Self.adding(totalMessages ?? 0, recent.totalMessages)
    }

    func snapshot(
        now: Date,
        calendar: Calendar,
        dataThroughDay: String?,
        isCurrent: Bool,
        usesTranscriptMetadata: Bool
    ) -> ClaudeStatsSnapshot {
        let today = ClaudeStatsDate.dayString(for: now)
        let historyEnd = isCurrent
            ? now
            : dataThroughDay.flatMap { ClaudeStatsDate.date(from: $0, calendar: calendar) }
                ?? now
        let streaks = streaks(endingOn: today)

        return ClaudeStatsSnapshot(
            todayTokens: isCurrent ? (tokensByDay[today] ?? 0) : nil,
            lifetimeTokens: lifetimeTokens,
            peakDailyTokens: tokensByDay.values.max(),
            totalSessions: totalSessions,
            totalMessages: totalMessages,
            currentStreakDays: isCurrent ? streaks.current : nil,
            longestStreakDays: activeDays.isEmpty ? nil : streaks.longest,
            dailyTokens: tokenHistory(endingAt: historyEnd, calendar: calendar),
            dataThroughDay: dataThroughDay,
            isCurrent: isCurrent,
            usesTranscriptMetadata: usesTranscriptMetadata
        )
    }

    private func tokenHistory(
        endingAt date: Date,
        calendar: Calendar
    ) -> [UsageActivityDay] {
        let end = calendar.startOfDay(for: date)
        return (-89...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: end)
            else { return nil }
            return UsageActivityDay(
                date: day,
                tokens: tokensByDay[ClaudeStatsDate.dayString(for: day)] ?? 0
            )
        }
    }

    private func streaks(endingOn today: String) -> (current: Int, longest: Int) {
        let orderedDays = activeDays.sorted()
        guard !orderedDays.isEmpty else { return (0, 0) }

        var longest = 1
        var run = 1
        for index in orderedDays.indices.dropFirst() {
            if ClaudeStatsDate.nextDay(after: orderedDays[index - 1]) == orderedDays[index] {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }

        let yesterday = ClaudeStatsDate.previousDay(before: today)
        var cursor: String?
        if activeDays.contains(today) {
            cursor = today
        } else if let yesterday, activeDays.contains(yesterday) {
            cursor = yesterday
        }

        var current = 0
        while let day = cursor, activeDays.contains(day) {
            current += 1
            cursor = ClaudeStatsDate.previousDay(before: day)
        }
        return (current, longest)
    }

    private static func adding(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : max(sum, 0)
    }

    private static func adding(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : max(sum, 0)
    }
}

struct ClaudeStatsCacheParser {
    func parse(
        _ data: Data,
        now: Date = Date(),
        calendar: Calendar = ClaudeStatsDate.utcCalendar
    ) throws -> ClaudeStatsSnapshot {
        let accumulator = try parseAccumulator(data)
        let currentDay = ClaudeStatsDate.dayString(for: now)
        let dataThrough = accumulator.lastComputedDay
            ?? accumulator.latestRecordedDay
            ?? currentDay
        let isCurrent = dataThrough >= currentDay
        return accumulator.snapshot(
            now: now,
            calendar: calendar,
            dataThroughDay: dataThrough,
            isCurrent: isCurrent,
            usesTranscriptMetadata: false
        )
    }

    func parseAccumulator(_ data: Data) throws -> ClaudeStatsAccumulator {
        let cache = try JSONDecoder().decode(Cache.self, from: data)
        let tokensByDay = Dictionary(
            (cache.dailyModelTokens ?? []).map { entry in
                (
                    entry.date,
                    entry.tokensByModel.values.reduce(Int64(0)) {
                        Self.adding($0, max($1, 0))
                    }
                )
            },
            uniquingKeysWith: Self.adding
        )
        let modelUsage = cache.modelUsage ?? [:]
        let lifetimeTokens: Int64? = modelUsage.isEmpty ? nil : modelUsage.values.reduce(Int64(0)) {
            Self.adding(
                $0,
                Self.adding(
                    Self.adding(max($1.inputTokens ?? 0, 0), max($1.outputTokens ?? 0, 0)),
                    Self.adding(
                        max($1.cacheCreationInputTokens ?? 0, 0),
                        max($1.cacheReadInputTokens ?? 0, 0)
                    )
                )
            )
        }
        let activeDays = Set(
            (cache.dailyActivity ?? [])
                .filter { ($0.messageCount ?? 0) > 0 }
                .map(\.date)
        )

        return ClaudeStatsAccumulator(
            lastComputedDay: cache.lastComputedDate,
            tokensByDay: tokensByDay,
            lifetimeTokens: lifetimeTokens,
            activeDays: activeDays,
            totalSessions: cache.totalSessions,
            totalMessages: cache.totalMessages
        )
    }

    private static func adding(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : max(sum, 0)
    }
}

struct ClaudeActivityStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectory: URL

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func load(
        now: Date = Date(),
        calendar: Calendar = ClaudeStatsDate.utcCalendar
    ) -> ClaudeStatsSnapshot? {
        let baseDirectory = ClaudeConfigurationDirectory.resolve(
            environment: environment,
            homeDirectory: homeDirectory
        )
        let cacheURL = baseDirectory.appendingPathComponent("stats-cache.json")
        let cached: ClaudeStatsAccumulator? = {
            guard fileManager.isReadableFile(atPath: cacheURL.path),
                  let data = try? Data(contentsOf: cacheURL)
            else { return nil }
            return try? ClaudeStatsCacheParser().parseAccumulator(data)
        }()

        let currentDay = ClaudeStatsDate.dayString(for: now)
        let cachedThrough = cached?.lastComputedDay ?? cached?.latestRecordedDay
        let fromDay = cachedThrough.flatMap(ClaudeStatsDate.nextDay(after:))
        let needsRecentScan = fromDay.map { $0 <= currentDay } ?? true
        var accumulator = cached ?? .empty
        var usedTranscriptMetadata = false

        if needsRecentScan {
            let projectsDirectory = baseDirectory.appendingPathComponent("projects")
            if let recent = try? ClaudeTranscriptStatsReader(fileManager: fileManager).read(
                projectsDirectory: projectsDirectory,
                fromDay: fromDay,
                throughDay: currentDay
            ) {
                if cached == nil || cachedThrough == nil {
                    accumulator = .empty
                }
                accumulator.merge(recent)
                usedTranscriptMetadata = true
                return accumulator.snapshot(
                    now: now,
                    calendar: calendar,
                    dataThroughDay: currentDay,
                    isCurrent: true,
                    usesTranscriptMetadata: true
                )
            }
        } else {
            return accumulator.snapshot(
                now: now,
                calendar: calendar,
                dataThroughDay: currentDay,
                isCurrent: true,
                usesTranscriptMetadata: false
            )
        }

        guard accumulator.hasValues else { return nil }
        return accumulator.snapshot(
            now: now,
            calendar: calendar,
            dataThroughDay: cachedThrough,
            isCurrent: cachedThrough.map { $0 >= currentDay } ?? false,
            usesTranscriptMetadata: usedTranscriptMetadata
        )
    }
}

enum ClaudeConfigurationDirectory {
    static func resolve(
        environment: [String: String],
        homeDirectory: URL
    ) -> URL {
        if let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)
        }
        return homeDirectory.appendingPathComponent(".claude")
    }
}

enum ClaudeStatsDate {
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    static func dayString(for date: Date) -> String {
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(from day: String, calendar: Calendar = utcCalendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }

    static func nextDay(after day: String) -> String? {
        shiftedDay(day, by: 1)
    }

    static func previousDay(before day: String) -> String? {
        shiftedDay(day, by: -1)
    }

    private static func shiftedDay(_ day: String, by offset: Int) -> String? {
        guard let date = date(from: day),
              let shifted = utcCalendar.date(byAdding: .day, value: offset, to: date)
        else { return nil }
        return dayString(for: shifted)
    }
}

private extension ClaudeStatsCacheParser {
    struct Cache: Decodable {
        let dailyActivity: [DailyActivity]?
        let dailyModelTokens: [DailyModelTokens]?
        let modelUsage: [String: ModelUsage]?
        let totalSessions: Int?
        let totalMessages: Int?
        let lastComputedDate: String?
    }

    struct DailyActivity: Decodable {
        let date: String
        let messageCount: Int?
    }

    struct DailyModelTokens: Decodable {
        let date: String
        let tokensByModel: [String: Int64]
    }

    struct ModelUsage: Decodable {
        let inputTokens: Int64?
        let outputTokens: Int64?
        let cacheCreationInputTokens: Int64?
        let cacheReadInputTokens: Int64?
    }
}
