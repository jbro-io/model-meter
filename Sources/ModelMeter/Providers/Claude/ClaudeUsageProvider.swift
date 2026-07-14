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
        let cliSessionCount = agentsOutput.flatMap(activeSessionCount) ?? 0
        let registryCount = ClaudeSessionRegistry().recentSessionCount(now: now())
        let activeSessions = max(cliSessionCount, registryCount)

        let versionOutput = try? await versionCommand
        let version = versionOutput?.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note(for: auth, hasLimits: !parsed.limits.isEmpty, registryFallbackUsed: registryCount > cliSessionCount)

        return ProviderUsageSnapshot(
            provider: .claude,
            fetchedAt: now(),
            plan: auth.planLabel,
            limits: parsed.limits,
            activity: UsageActivity(
                todayTokens: nil,
                lifetimeTokens: nil,
                sessionCostUSD: parsed.sessionCostUSD.flatMap { $0 > 0 ? $0 : nil },
                activeSessions: activeSessions,
                currentStreakDays: nil
            ),
            cliVersion: version,
            source: "Claude CLI /usage",
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

    private func note(for auth: ClaudeAuthStatus, hasLimits: Bool, registryFallbackUsed: Bool) -> String? {
        var parts: [String] = []
        if !hasLimits {
            if auth.authMethod == "api_key" || auth.authMethod == "api_key_helper" || auth.authMethod == "third_party" {
                parts.append("This Claude auth mode does not expose subscription quota bars; API spend remains in Claude Console.")
            } else {
                parts.append("Claude returned no plan quota windows for this account.")
            }
        }
        if registryFallbackUsed {
            parts.append("Active sessions include recently updated Claude registry entries.")
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

    var expectsSubscriptionLimits: Bool {
        authMethod == "claude.ai" || authMethod == "oauth_token"
    }

    var planLabel: String? {
        switch authMethod {
        case "claude.ai", "oauth_token": "Subscription"
        case "api_key", "api_key_helper": "API"
        case "third_party": apiProvider?.capitalized
        default: nil
        }
    }
}

private struct ClaudeAgentSession: Decodable {
    let state: String?
    let status: String?

    var isFinished: Bool {
        guard let state else { return false }
        return ["done", "failed", "stopped"].contains(state.lowercased())
    }
}

private struct ClaudeSessionRegistry {
    private struct Entry: Decodable {
        let status: String?
        let updatedAt: Int64?
    }

    func recentSessionCount(now: Date) -> Int {
        let environment = ProcessInfo.processInfo.environment
        let base: URL
        if let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            base = URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        }

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
