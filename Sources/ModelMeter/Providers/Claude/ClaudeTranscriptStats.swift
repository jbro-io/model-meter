import Foundation

struct ClaudeTranscriptStats: Equatable, Sendable {
    var tokensByDay: [String: Int64] = [:]
    var lifetimeTokens: Int64 = 0
    var activeDays: Set<String> = []
    var totalSessions = 0
    var totalMessages = 0
}

struct ClaudeTranscriptStatsReader: @unchecked Sendable {
    private let fileManager: FileManager
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func read(
        projectsDirectory: URL,
        fromDay: String? = nil,
        throughDay: String
    ) throws -> ClaudeTranscriptStats {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: projectsDirectory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .contentModificationDateKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var result = ClaudeTranscriptStats()
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  isSupportedTranscript(fileURL, projectsDirectory: projectsDirectory)
            else { continue }

            let values = try fileURL.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            if let fromDay,
               let modified = values.contentModificationDate,
               ClaudeStatsDate.dayString(for: modified) < fromDay {
                continue
            }

            let fileStats = try readFile(
                fileURL,
                isSubagent: isSubagentTranscript(fileURL),
                fromDay: fromDay,
                throughDay: throughDay
            )
            merge(fileStats, into: &result)
        }
        return result
    }

    private func readFile(
        _ fileURL: URL,
        isSubagent: Bool,
        fromDay: String?,
        throughDay: String
    ) throws -> ClaudeTranscriptStats {
        var result = ClaudeTranscriptStats()
        var firstEntryDay: String?
        var lastEntryDay: String?

        try enumerateLines(in: fileURL) { data in
            guard let entry = try? decoder.decode(TranscriptEntry.self, from: data),
                  entry.isUsageEntry,
                  isSubagent || entry.isSidechain != true,
                  let day = entry.day
            else { return }

            if firstEntryDay == nil { firstEntryDay = day }
            lastEntryDay = day

            guard fromDay.map({ day >= $0 }) ?? true,
                  day <= throughDay
            else { return }

            if !isSubagent {
                result.activeDays.insert(day)
                result.totalMessages = adding(result.totalMessages, 1)
            }

            guard entry.type == "assistant",
                  entry.message?.model != "<synthetic>",
                  let usage = entry.message?.usage
            else { return }

            let dailyTokens = adding(
                max(usage.inputTokens ?? 0, 0),
                max(usage.outputTokens ?? 0, 0)
            )
            result.tokensByDay[day] = adding(
                result.tokensByDay[day] ?? 0,
                dailyTokens
            )
            result.lifetimeTokens = adding(
                result.lifetimeTokens,
                adding(
                    dailyTokens,
                    adding(
                        max(usage.cacheCreationInputTokens ?? 0, 0),
                        max(usage.cacheReadInputTokens ?? 0, 0)
                    )
                )
            )
        }

        if !isSubagent,
           let firstEntryDay,
           lastEntryDay != nil,
           fromDay.map({ firstEntryDay >= $0 }) ?? true,
           firstEntryDay <= throughDay {
            result.totalSessions = 1
        }
        return result
    }

    private func enumerateLines(
        in fileURL: URL,
        _ body: (Data) throws -> Void
    ) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var buffer = Data()
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                if !line.isEmpty { try body(Data(line)) }
                buffer.removeSubrange(...newline)
            }
        }
        if !buffer.isEmpty { try body(buffer) }
    }

    private func isSupportedTranscript(
        _ fileURL: URL,
        projectsDirectory: URL
    ) -> Bool {
        let rootComponents = projectsDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .pathComponents
        let fileComponents = fileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .pathComponents
        guard fileComponents.starts(with: rootComponents) else { return false }
        let components = Array(fileComponents.dropFirst(rootComponents.count))
        if components.count == 2 { return true }
        return components.count == 4
            && components[2] == "subagents"
            && fileURL.deletingPathExtension().lastPathComponent.hasPrefix("agent-")
    }

    private func isSubagentTranscript(_ fileURL: URL) -> Bool {
        fileURL.deletingLastPathComponent().lastPathComponent == "subagents"
    }

    private func merge(
        _ source: ClaudeTranscriptStats,
        into destination: inout ClaudeTranscriptStats
    ) {
        for (day, tokens) in source.tokensByDay {
            destination.tokensByDay[day] = adding(
                destination.tokensByDay[day] ?? 0,
                tokens
            )
        }
        destination.lifetimeTokens = adding(
            destination.lifetimeTokens,
            source.lifetimeTokens
        )
        destination.activeDays.formUnion(source.activeDays)
        destination.totalSessions = adding(
            destination.totalSessions,
            source.totalSessions
        )
        destination.totalMessages = adding(
            destination.totalMessages,
            source.totalMessages
        )
    }

    private func adding(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : max(sum, 0)
    }

    private func adding(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : max(sum, 0)
    }
}

private extension ClaudeTranscriptStatsReader {
    struct TranscriptEntry: Decodable {
        let type: String
        let timestamp: String?
        let isSidechain: Bool?
        let message: TranscriptMessage?

        var isUsageEntry: Bool {
            ["user", "assistant", "attachment", "system"].contains(type)
        }

        var day: String? {
            guard let timestamp, timestamp.count >= 10 else { return nil }
            let day = String(timestamp.prefix(10))
            return ClaudeStatsDate.date(from: day) == nil ? nil : day
        }
    }

    struct TranscriptMessage: Decodable {
        let model: String?
        let usage: TranscriptUsage?
    }

    struct TranscriptUsage: Decodable {
        let inputTokens: Int64?
        let outputTokens: Int64?
        let cacheCreationInputTokens: Int64?
        let cacheReadInputTokens: Int64?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }
}
