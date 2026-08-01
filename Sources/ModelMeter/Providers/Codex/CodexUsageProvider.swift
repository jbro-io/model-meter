@preconcurrency import Foundation
import Darwin

struct CodexUsageProvider: UsageProviding, Sendable {
    let providerID = ProviderID.codex

    private let configuredPath: String?
    private let resolver: CLIResolver
    private let now: @Sendable () -> Date

    init(
        configuredPath: String? = nil,
        resolver: CLIResolver = CLIResolver(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuredPath = configuredPath
        self.resolver = resolver
        self.now = now
    }

    func fetch() async throws -> ProviderUsageSnapshot {
        let executable = try resolver.resolve("codex", configuredPath: configuredPath)
        let clientVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"

        let responses = try await Task.detached(priority: .utility) {
            try Self.runAppServer(
                executable: executable,
                clientVersion: clientVersion,
                timeout: 14
            )
        }.value

        let rateLimits = try CodexProtocol.decode(
            CodexRateLimitsResult.self,
            from: responses.rateLimits,
            expectedID: CodexProtocol.rateLimitsID
        )
        let usage = try? CodexProtocol.decode(
            CodexAccountUsageResult.self,
            from: responses.usage,
            expectedID: CodexProtocol.usageID
        )
        let initialize = responses.initialize.flatMap {
            try? CodexProtocol.decode(
                CodexInitializeResult.self,
                from: $0,
                expectedID: CodexProtocol.initializeID
            )
        }

        let fetchedAt = now()
        let limits = makeLimits(from: rateLimits)

        return ProviderUsageSnapshot(
            provider: .codex,
            fetchedAt: fetchedAt,
            plan: planLabel(from: rateLimits),
            limits: limits,
            resetCredits: makeResetCredits(from: rateLimits.rateLimitResetCredits),
            activity: Self.makeActivity(from: usage, at: fetchedAt),
            cliVersion: initialize?.userAgent.flatMap(Self.version(from:)),
            source: "Codex app-server",
            note: snapshotNote(hasLimits: !limits.isEmpty, hasUsage: usage != nil)
        )
    }

    static func makeActivity(
        from usage: CodexAccountUsageResult?,
        at fetchedAt: Date
    ) -> UsageActivity {
        let today = dayString(for: fetchedAt)
        let todayTokens = usage?.dailyUsageBuckets?
            .filter { $0.startDate == today }
            .reduce(Int64(0)) { partial, bucket in
                partial + max(bucket.tokens, 0)
            }

        return UsageActivity(
            todayTokens: todayTokens,
            lifetimeTokens: usage?.summary.lifetimeTokens,
            peakDailyTokens: usage?.summary.peakDailyTokens,
            sessionCostUSD: nil,
            activeSessions: nil,
            currentStreakDays: usage?.summary.currentStreakDays,
            longestStreakDays: usage?.summary.longestStreakDays,
            longestRunningTurnSeconds: usage?.summary.longestRunningTurnSec,
            dailyTokens: usage.flatMap(\.dailyUsageBuckets).map {
                tokenHistory(
                    buckets: $0,
                    endingAt: fetchedAt
                )
            } ?? [],
            scope: .codexAccount
        )
    }

    private func snapshotNote(hasLimits: Bool, hasUsage: Bool) -> String? {
        var notes: [String] = []
        if !hasLimits {
            notes.append("Codex returned no rate-limit windows.")
        }
        if !hasUsage {
            notes.append("Token history was unavailable; quota windows are still current.")
        }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    private func makeLimits(from response: CodexRateLimitsResult) -> [UsageLimit] {
        let snapshots: [(String, CodexRateLimitSnapshot)]
        if let byID = response.rateLimitsByLimitId, !byID.isEmpty {
            snapshots = byID.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        } else {
            snapshots = [(response.rateLimits.limitId ?? "codex", response.rateLimits)]
        }

        let showScope = snapshots.count > 1
        return snapshots.flatMap { limitID, snapshot in
            let scope = scopeName(id: limitID, snapshot: snapshot)
            var limits: [UsageLimit] = []

            if let primary = snapshot.primary {
                limits.append(makeLimit(
                    id: "codex-\(slug(limitID))-primary",
                    scope: showScope ? scope : nil,
                    fallbackTitle: "Primary",
                    window: primary
                ))
            }
            if let secondary = snapshot.secondary {
                limits.append(makeLimit(
                    id: "codex-\(slug(limitID))-secondary",
                    scope: showScope ? scope : nil,
                    fallbackTitle: "Secondary",
                    window: secondary
                ))
            }
            if let individual = snapshot.individualLimit {
                let title = [showScope ? scope : nil, "Spend limit"]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                limits.append(UsageLimit(
                    id: "codex-\(slug(limitID))-individual",
                    title: title,
                    usedFraction: 1 - (Double(individual.remainingPercent) / 100),
                    resetsAt: Date(timeIntervalSince1970: TimeInterval(individual.resetsAt)),
                    resetDescription: "\(individual.used) of \(individual.limit)",
                    windowMinutes: nil
                ))
            }
            return limits
        }
    }

    private func makeResetCredits(
        from response: CodexRateLimitResetCredits?
    ) -> UsageResetCredits? {
        guard let response else { return nil }

        let credits = response.credits.compactMap { credit -> UsageResetCredit? in
            guard credit.status.caseInsensitiveCompare("available") == .orderedSame else {
                return nil
            }
            let title = credit.title?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Usage reset"
            return UsageResetCredit(
                id: credit.id,
                title: displayTitle,
                expiresAt: credit.expiresAt.map {
                    Date(timeIntervalSince1970: TimeInterval($0))
                }
            )
        }

        guard response.availableCount > 0 || !credits.isEmpty else { return nil }
        return UsageResetCredits(
            availableCount: max(response.availableCount, credits.count),
            credits: credits
        )
    }

    private func makeLimit(
        id: String,
        scope: String?,
        fallbackTitle: String,
        window: CodexRateLimitWindow
    ) -> UsageLimit {
        let windowMinutes = window.windowDurationMins.flatMap(Int.init(exactly:))
        let title = [scope, windowTitle(minutes: windowMinutes) ?? fallbackTitle]
            .compactMap { $0 }
            .joined(separator: " · ")
        return UsageLimit(
            id: id,
            title: title,
            usedFraction: Double(window.usedPercent) / 100,
            resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            windowMinutes: windowMinutes
        )
    }

    private func windowTitle(minutes: Int?) -> String? {
        switch minutes {
        case 300: "5-hour"
        case 10_080: "Weekly"
        case 43_200, 44_640: "Monthly"
        case .some(let value) where value > 0 && value.isMultiple(of: 1_440):
            "\(value / 1_440)-day"
        case .some(let value) where value > 0 && value.isMultiple(of: 60):
            "\(value / 60)-hour"
        case .some(let value) where value > 0:
            "\(value)-minute"
        default:
            nil
        }
    }

    private func scopeName(id: String, snapshot: CodexRateLimitSnapshot) -> String {
        if let name = snapshot.limitName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty
        {
            return name
        }
        return id
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func planLabel(from response: CodexRateLimitsResult) -> String? {
        let raw = response.rateLimits.planType
            ?? response.rateLimitsByLimitId?.values.compactMap(\.planType).first
        guard let raw, !raw.isEmpty else { return nil }
        return raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return value.lowercased().unicodeScalars.map {
            allowed.contains($0) ? Character(String($0)) : "-"
        }.reduce(into: "") { $0.append($1) }
    }

    private static func dayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func tokenHistory(
        buckets: [CodexDailyUsageBucket],
        endingAt date: Date
    ) -> [UsageActivityDay] {
        let tokensByDay = Dictionary(
            buckets.map { ($0.startDate, max($0.tokens, 0)) },
            uniquingKeysWith: +
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let today = calendar.startOfDay(for: date)
        return (-89...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today)
            else { return nil }
            return UsageActivityDay(
                date: day,
                tokens: tokensByDay[dayString(for: day)] ?? 0
            )
        }
    }

    private static func version(from userAgent: String) -> String? {
        let pattern = #"/(\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: userAgent,
                  range: NSRange(userAgent.startIndex..., in: userAgent)
              ),
              let range = Range(match.range(at: 1), in: userAgent)
        else { return nil }
        return String(userAgent[range])
    }

    private static func runAppServer(
        executable: URL,
        clientVersion: String,
        timeout: TimeInterval
    ) throws -> CodexAppServerResponses {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        let collector = CodexResponseCollector()
        let stderrBuffer = CodexLockedDataBuffer()
        let wakeup = DispatchSemaphore(value: 0)

        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if collector.append(data), collector.markCompletionSignaled() {
                wakeup.signal()
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stderrBuffer.append(data) }
        }
        process.terminationHandler = { _ in wakeup.signal() }

        do {
            try process.run()
            try stdin.fileHandleForWriting.write(
                contentsOf: CodexProtocol.startupPayload(clientVersion: clientVersion)
            )
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            throw UsageProviderError.processFailed(
                command: "codex app-server",
                detail: error.localizedDescription
            )
        }

        let waitResult = wakeup.wait(timeout: .now() + timeout)
        if !collector.hasRequiredResponses, !process.isRunning {
            collector.append(stdout.fileHandleForReading.readDataToEndOfFile())
        }

        let timedOut = waitResult == .timedOut && !collector.hasRequiredResponses
        try? stdin.fileHandleForWriting.close()
        Self.stop(process, wakeup: wakeup)

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        collector.append(stdout.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())

        if timedOut && !collector.hasRequiredResponses {
            throw UsageProviderError.timedOut(command: "codex app-server")
        }
        guard let responses = collector.responses else {
            let detail = String(data: stderrBuffer.value, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !detail.isEmpty {
                throw UsageProviderError.processFailed(
                    command: "codex app-server",
                    detail: String(detail.prefix(500))
                )
            }
            throw UsageProviderError.malformedResponse(provider: "Codex")
        }
        return responses
    }

    private static func stop(_ process: Process, wakeup: DispatchSemaphore) {
        guard process.isRunning else { return }
        if wakeup.wait(timeout: .now() + 0.5) == .success, !process.isRunning { return }
        process.terminate()
        if wakeup.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = wakeup.wait(timeout: .now() + 1)
        }
    }
}

private struct CodexAppServerResponses: Sendable {
    let initialize: Data?
    let rateLimits: Data
    let usage: Data
}

private final class CodexResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var lines: [Int: Data] = [:]
    private var completionSignaled = false

    @discardableResult
    func append(_ data: Data) -> Bool {
        guard !data.isEmpty else { return hasRequiredResponses }
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard !line.isEmpty, let id = CodexProtocol.responseID(in: line) else { continue }
            if id == CodexProtocol.initializeID
                || id == CodexProtocol.rateLimitsID
                || id == CodexProtocol.usageID
            {
                lines[id] = line
            }
        }
        return lines[CodexProtocol.rateLimitsID] != nil
            && lines[CodexProtocol.usageID] != nil
    }

    var hasRequiredResponses: Bool {
        lock.lock()
        defer { lock.unlock() }
        return lines[CodexProtocol.rateLimitsID] != nil
            && lines[CodexProtocol.usageID] != nil
    }

    func markCompletionSignaled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completionSignaled else { return false }
        completionSignaled = true
        return true
    }

    var responses: CodexAppServerResponses? {
        lock.lock()
        defer { lock.unlock() }
        guard let rateLimits = lines[CodexProtocol.rateLimitsID],
              let usage = lines[CodexProtocol.usageID]
        else { return nil }
        return CodexAppServerResponses(
            initialize: lines[CodexProtocol.initializeID],
            rateLimits: rateLimits,
            usage: usage
        )
    }
}

private final class CodexLockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
