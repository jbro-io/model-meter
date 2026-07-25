import Foundation

struct ClaudeStatsSnapshot: Equatable, Sendable {
    let todayTokens: Int64
    let lifetimeTokens: Int64
    let totalSessions: Int?
    let totalMessages: Int?
    let currentStreakDays: Int
    let dailyTokens: [UsageActivityDay]
}

struct ClaudeStatsCacheParser {
    func parse(
        _ data: Data,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> ClaudeStatsSnapshot {
        let cache = try JSONDecoder().decode(Cache.self, from: data)
        let today = dayString(for: now, calendar: calendar)
        let tokensByDay = Dictionary(
            cache.dailyModelTokens.map { entry in
                (
                    entry.date,
                    entry.tokensByModel.values.reduce(Int64(0)) {
                        $0 + max($1, 0)
                    }
                )
            },
            uniquingKeysWith: +
        )
        let lifetimeTokens = cache.modelUsage.values.reduce(Int64(0)) {
            $0
                + max($1.inputTokens ?? 0, 0)
                + max($1.outputTokens ?? 0, 0)
                + max($1.cacheCreationInputTokens ?? 0, 0)
                + max($1.cacheReadInputTokens ?? 0, 0)
        }
        let activeDays = Set(
            cache.dailyActivity
                .filter { ($0.messageCount ?? 0) > 0 }
                .map(\.date)
        )

        return ClaudeStatsSnapshot(
            todayTokens: tokensByDay[today] ?? 0,
            lifetimeTokens: lifetimeTokens,
            totalSessions: cache.totalSessions,
            totalMessages: cache.totalMessages,
            currentStreakDays: streak(
                activeDays: activeDays,
                now: now,
                calendar: calendar
            ),
            dailyTokens: tokenHistory(
                tokensByDay: tokensByDay,
                now: now,
                calendar: calendar
            )
        )
    }

    private func tokenHistory(
        tokensByDay: [String: Int64],
        now: Date,
        calendar: Calendar
    ) -> [UsageActivityDay] {
        let today = calendar.startOfDay(for: now)
        return (-89...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today)
            else { return nil }
            return UsageActivityDay(
                date: date,
                tokens: tokensByDay[dayString(for: date, calendar: calendar)] ?? 0
            )
        }
    }

    private func streak(
        activeDays: Set<String>,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var cursor = activeDays.contains(dayString(for: today, calendar: calendar))
            ? today
            : yesterday
        guard activeDays.contains(dayString(for: cursor, calendar: calendar))
        else { return 0 }

        var count = 0
        while activeDays.contains(dayString(for: cursor, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor)
            else { break }
            cursor = previous
        }
        return count
    }

    private func dayString(for date: Date, calendar: Calendar) -> String {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.calendar = calendar
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

struct ClaudeStatsCacheStore: @unchecked Sendable {
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

    func load(now: Date = Date(), calendar: Calendar = .current) -> ClaudeStatsSnapshot? {
        let baseDirectory: URL
        if let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            baseDirectory = URL(
                fileURLWithPath: (configured as NSString).expandingTildeInPath
            )
        } else {
            baseDirectory = homeDirectory.appendingPathComponent(".claude")
        }
        let url = baseDirectory.appendingPathComponent("stats-cache.json")
        guard fileManager.isReadableFile(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? ClaudeStatsCacheParser().parse(data, now: now, calendar: calendar)
    }
}

private extension ClaudeStatsCacheParser {
    struct Cache: Decodable {
        let dailyActivity: [DailyActivity]
        let dailyModelTokens: [DailyModelTokens]
        let modelUsage: [String: ModelUsage]
        let totalSessions: Int?
        let totalMessages: Int?
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
