import Foundation

struct ClaudeUsageProvider: UsageProviding, Sendable {
    let providerID = ProviderID.claude

    private let configuredPath: String?
    private let resolver: CLIResolver
    private let runner: CommandRunner
    private let now: @Sendable () -> Date

    init(
        configuredPath: String? = nil,
        resolver: CLIResolver = CLIResolver(),
        runner: CommandRunner = CommandRunner(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuredPath = configuredPath
        self.resolver = resolver
        self.runner = runner
        self.now = now
    }

    func fetch() async throws -> ProviderUsageSnapshot {
        let executable = try resolver.resolve("claude", configuredPath: configuredPath)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let subscriptionEnvironment = [
            "ANTHROPIC_API_KEY": "",
            "ANTHROPIC_AUTH_TOKEN": "",
            "CLAUDE_CODE_USE_BEDROCK": "0",
            "CLAUDE_CODE_USE_VERTEX": "0",
            "CLAUDE_CODE_USE_FOUNDRY": "0"
        ]

        let preferredAuthOutput = try await runner.run(
            executable: executable,
            arguments: ["auth", "status", "--json"],
            timeout: 8,
            environment: subscriptionEnvironment,
            currentDirectory: home
        )
        var auth = try? parseAuth(preferredAuthOutput)
        var cliEnvironment: [String: String]? = subscriptionEnvironment

        if auth?.loggedIn != true {
            let inheritedAuthOutput = try await runner.run(
                executable: executable,
                arguments: ["auth", "status", "--json"],
                timeout: 8,
                currentDirectory: home
            )
            auth = try parseAuth(inheritedAuthOutput)
            cliEnvironment = nil
        }

        guard let auth else {
            throw UsageProviderError.malformedResponse(provider: "Claude auth status")
        }
        guard auth.loggedIn else { throw UsageProviderError.notAuthenticated(provider: "Claude") }

        var parsed = try await fetchUsage(
            executable: executable,
            environment: cliEnvironment,
            currentDirectory: home
        )
        if auth.expectsSubscriptionLimits && parsed.limits.isEmpty {
            try? await Task.sleep(nanoseconds: 500_000_000)
            parsed = try await fetchUsage(
                executable: executable,
                environment: cliEnvironment,
                currentDirectory: home
            )
        }

        let selectedEnvironment = cliEnvironment
        async let agentsCommand = runner.run(
            executable: executable,
            arguments: ["agents", "--json"],
            timeout: 8,
            environment: selectedEnvironment,
            currentDirectory: home
        )
        async let versionCommand = runner.run(
            executable: executable,
            arguments: ["--version"],
            timeout: 5,
            currentDirectory: home
        )

        let agentsOutput = try? await agentsCommand
        let cliSessionCount = agentsOutput.flatMap(activeSessionCount)
        let fetchedAt = now()
        let registryCount = cliSessionCount == nil
            ? ClaudeSessionRegistry().recentSessionCount(now: fetchedAt)
            : nil
        let activeSessions = cliSessionCount ?? registryCount
        let stats = await Task.detached(priority: .utility) {
            ClaudeActivityStore().load(now: fetchedAt)
        }.value

        let versionOutput = try? await versionCommand
        let version = versionOutput?.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note(
            for: auth,
            hasLimits: !parsed.limits.isEmpty,
            registryFallbackUsed: cliSessionCount == nil,
            stats: stats
        )

        return ProviderUsageSnapshot(
            provider: .claude,
            fetchedAt: fetchedAt,
            plan: auth.planLabel,
            account: auth.accountLabel,
            limits: parsed.limits,
            activity: UsageActivity(
                todayTokens: stats?.todayTokens,
                lifetimeTokens: stats?.lifetimeTokens,
                sessionCostUSD: parsed.sessionCostUSD.flatMap { $0 > 0 ? $0 : nil },
                activeSessions: activeSessions,
                currentStreakDays: stats?.currentStreakDays,
                totalSessions: stats?.totalSessions,
                totalMessages: stats?.totalMessages,
                dailyTokens: stats?.dailyTokens ?? [],
                scope: .claudeLocalProfile
            ),
            cliVersion: version,
            source: stats?.usesTranscriptMetadata == true
                ? "Claude CLI /usage + local usage metadata"
                : "Claude CLI /usage",
            note: note
        )
    }

    private func fetchUsage(
        executable: URL,
        environment: [String: String]?,
        currentDirectory: URL
    ) async throws -> ClaudeUsageParseResult {
        let output = try await runner.run(
            executable: executable,
            arguments: ["--print", "--output-format", "json", "--no-session-persistence", "--safe-mode", "/usage"],
            timeout: 12,
            environment: environment,
            currentDirectory: currentDirectory
        )
        guard output.exitCode == 0 else {
            throw UsageProviderError.processFailed(
                command: "claude /usage",
                detail: conciseError(output)
            )
        }
        guard let envelope = try? JSONDecoder().decode(
            ClaudePrintEnvelope.self,
            from: output.standardOutput
        ) else {
            throw UsageProviderError.malformedResponse(provider: "Claude /usage")
        }
        return ClaudeUsageParser().parse(envelope.result)
    }

    private func parseAuth(_ output: CommandOutput) throws -> ClaudeAuthStatus {
        guard let auth = try? JSONDecoder().decode(ClaudeAuthStatus.self, from: output.standardOutput) else {
            if output.exitCode != 0 { throw UsageProviderError.notAuthenticated(provider: "Claude") }
            throw UsageProviderError.malformedResponse(provider: "Claude auth status")
        }
        return auth
    }

    private func activeSessionCount(_ output: CommandOutput) -> Int? {
        guard output.exitCode == 0,
              let sessions = try? JSONDecoder().decode([ClaudeAgentSession].self, from: output.standardOutput)
        else { return nil }
        return sessions.filter { !$0.isFinished }.count
    }

    private func note(
        for auth: ClaudeAuthStatus,
        hasLimits: Bool,
        registryFallbackUsed: Bool,
        stats: ClaudeStatsSnapshot?
    ) -> String? {
        var parts: [String] = []
        if !hasLimits {
            if auth.authMethod == "api_key" || auth.authMethod == "api_key_helper" || auth.authMethod == "third_party" {
                parts.append("This Claude auth mode does not expose subscription quota bars; API spend remains in Claude Console.")
            } else {
                parts.append("Claude returned no plan quota windows for this account.")
            }
        }
        if registryFallbackUsed {
            parts.append("Active sessions are estimated from recently updated Claude registry entries.")
        }
        if let stats, !stats.isCurrent, let day = stats.dataThroughDay {
            parts.append("Local activity is only complete through \(day).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func conciseError(_ output: CommandOutput) -> String {
        let value = output.stderrString.isEmpty ? output.stdoutString : output.stderrString
        return value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300).description
    }
}

private struct ClaudePrintEnvelope: Decodable {
    let result: String
}

private struct ClaudeAuthStatus: Decodable {
    let loggedIn: Bool
    let authMethod: String?
    let apiProvider: String?
    let email: String?
    let orgName: String?
    let subscriptionType: String?

    var expectsSubscriptionLimits: Bool {
        authMethod == "claude.ai" || authMethod == "oauth_token"
    }

    var planLabel: String? {
        switch authMethod {
        case "claude.ai", "oauth_token": normalizedSubscriptionType ?? "Subscription"
        case "api_key", "api_key_helper": "API"
        case "third_party": apiProvider?.capitalized
        default: nil
        }
    }

    var accountLabel: String? {
        sanitized(email) ?? sanitized(orgName)
    }

    private var normalizedSubscriptionType: String? {
        guard let value = sanitized(subscriptionType) else { return nil }
        switch value.lowercased() {
        case "max": return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return value.capitalized
        }
    }

    private func sanitized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return String(value.prefix(100))
    }
}

private struct ClaudeAgentSession: Decodable {
    let state: String?
    let status: String?

    var isFinished: Bool {
        guard let state = state ?? status else { return false }
        return ["done", "failed", "stopped"].contains(state.lowercased())
    }
}

private struct ClaudeSessionRegistry {
    private struct Entry: Decodable {
        let status: String?
        let updatedAt: Int64?
    }

    func recentSessionCount(now: Date) -> Int {
        let base = ClaudeConfigurationDirectory.resolve(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )

        let directory = base.appendingPathComponent("sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let cutoff = now.addingTimeInterval(-5 * 60)
        return files.filter { $0.pathExtension == "json" }.reduce(into: 0) { count, file in
            guard let data = try? Data(contentsOf: file),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data)
            else { return }

            let updated = entry.updatedAt.map { Date(timeIntervalSince1970: Double($0) / 1_000) }
                ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            let finished = ["done", "failed", "stopped"].contains(entry.status?.lowercased() ?? "")
            if updated >= cutoff && !finished { count += 1 }
        }
    }
}
