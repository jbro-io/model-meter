import Foundation

struct TerminalSessionTarget: Identifiable, Codable, Equatable, Sendable {
    let terminal: AutoContinueTerminal
    let provider: ProviderID
    let id: String
    let displayTitle: String
    let currentDirectory: String?
    let processName: String?
    let auxiliaryIdentifier: String?

    var shortIdentifier: String {
        switch terminal {
        case .kitty:
            "#\(id)"
        case .iterm, .ghostty:
            String(id.suffix(8))
        }
    }

    var hasIdentitySnapshot: Bool {
        switch terminal {
        case .kitty:
            processName == provider.rawValue
        case .iterm:
            processName == provider.rawValue
                && !(auxiliaryIdentifier ?? "").isEmpty
        case .ghostty:
            !normalizedTitle.isEmpty
        }
    }

    func identifiesSameLiveSession(as live: TerminalSessionTarget) -> Bool {
        guard terminal == live.terminal,
              provider == live.provider,
              id == live.id,
              hasIdentitySnapshot,
              live.hasIdentitySnapshot
        else {
            return false
        }

        switch terminal {
        case .kitty:
            return processName == live.processName
                && optionalPathMatches(currentDirectory, live.currentDirectory)
        case .iterm:
            return processName == live.processName
                && auxiliaryIdentifier == live.auxiliaryIdentifier
                && optionalPathMatches(currentDirectory, live.currentDirectory)
        case .ghostty:
            return normalizedTitle == live.normalizedTitle
                && optionalPathMatches(currentDirectory, live.currentDirectory)
        }
    }

    static func legacyKitty(id: Int, provider: ProviderID) -> Self {
        Self(
            terminal: .kitty,
            provider: provider,
            id: String(id),
            displayTitle: "Kitty session \(id)",
            currentDirectory: nil,
            processName: nil,
            auxiliaryIdentifier: nil
        )
    }

    private var normalizedTitle: String {
        KittySessionTitleFormatter.clean(displayTitle).lowercased()
    }

    private func optionalPathMatches(_ stored: String?, _ live: String?) -> Bool {
        guard let stored, !stored.isEmpty else { return true }
        return Self.normalizedPath(stored) == live.map(Self.normalizedPath)
    }

    private static func normalizedPath(_ path: String) -> String {
        if let url = URL(string: path), url.isFileURL {
            return url.standardizedFileURL.path
        }
        return (path as NSString).standardizingPath
    }
}

struct TerminalTargetSummary: Equatable, Sendable {
    let targets: [TerminalSessionTarget]

    var windowCount: Int { targets.count }
    var titles: [String] { targets.map(\.displayTitle) }
}

struct TerminalAutomationConfiguration: Sendable {
    let terminal: AutoContinueTerminal
    let provider: ProviderID
    let routeRevision: Int
    let kittyExecutablePath: String
    let kittyListenAddress: String
    let kittyMatch: String
    let allSessions: Bool
    let enrolledTargets: [TerminalSessionTarget]
}

enum TerminalAutomationIssue: LocalizedError, Equatable, Sendable {
    case notRunning(AutoContinueTerminal)
    case unauthorized(AutoContinueTerminal)
    case unsupportedVersion(terminal: AutoContinueTerminal, minimum: String)
    case partial(terminal: AutoContinueTerminal, detail: String)
    case ambiguous(terminal: AutoContinueTerminal, detail: String)
    case noMatchingSessions(terminal: AutoContinueTerminal, provider: ProviderID)
    case noSelectedSessions(terminal: AutoContinueTerminal)
    case noLongerMatches(terminal: AutoContinueTerminal, title: String)
    case routeChanged(AutoContinueTerminal)
    case configuration(terminal: AutoContinueTerminal, detail: String)

    var errorDescription: String? {
        switch self {
        case .notRunning(let terminal):
            "\(terminal.title) is not running. Open it and scan again."
        case .unauthorized(let terminal):
            "Allow Model Meter to control \(terminal.title) in System Settings → Privacy & Security → Automation, then scan again."
        case .unsupportedVersion(let terminal, let minimum):
            "\(terminal.title) \(minimum) or newer is required for Auto-Continue."
        case .partial(let terminal, let detail):
            "\(terminal.title) returned an incomplete session list: \(detail)"
        case .ambiguous(let terminal, let detail):
            "\(terminal.title) could not safely identify the target: \(detail)"
        case .noMatchingSessions(let terminal, let provider):
            "No live \(provider.displayName) sessions were found in \(terminal.title). The continuation remains armed."
        case .noSelectedSessions(let terminal):
            "No enrolled \(terminal.title) sessions are open. Scan and enroll at least one live session."
        case .noLongerMatches(let terminal, let title):
            "“\(title)” no longer matches its enrolled \(terminal.title) identity. Scan targets before sending."
        case .routeChanged(let terminal):
            "\(terminal.title) targets changed before delivery. No text was sent."
        case .configuration(let terminal, let detail):
            "\(terminal.title) Auto-Continue is not ready: \(detail)"
        }
    }
}

enum TerminalPreflightResult: Equatable, Sendable {
    case ready
    case failure(TerminalAutomationIssue)
}

enum TerminalScanResult: Equatable, Sendable {
    case complete(TerminalTargetSummary)
    case failure(TerminalAutomationIssue)
}

enum TerminalSendResult: Equatable, Sendable {
    case sent(TerminalTargetSummary)
    case partial(
        sent: TerminalTargetSummary,
        issue: TerminalAutomationIssue
    )
    case failure(TerminalAutomationIssue)
}

@MainActor
protocol TerminalAutomationClient: Sendable {
    var terminal: AutoContinueTerminal { get }

    func preflight(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalPreflightResult

    func scan(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalScanResult

    func sendContinue(
        configuration: TerminalAutomationConfiguration,
        authorization: @escaping @MainActor @Sendable () -> Bool
    ) async -> TerminalSendResult
}

struct KittyTerminalAutomationClient: TerminalAutomationClient {
    let terminal = AutoContinueTerminal.kitty
    private let client: KittyRemoteControlClient

    init(client: KittyRemoteControlClient = KittyRemoteControlClient()) {
        self.client = client
    }

    func preflight(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalPreflightResult {
        guard configuration.terminal == .kitty else {
            return .failure(
                .configuration(terminal: .kitty, detail: "terminal mismatch")
            )
        }
        return .ready
    }

    func scan(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalScanResult {
        do {
            let summary = try await client.matchingTargets(
                configuredPath: configuration.kittyExecutablePath,
                listenAddress: configuration.kittyListenAddress,
                match: configuration.kittyMatch
            )
            let targets = summary.targets.map {
                terminalTarget(from: $0, provider: configuration.provider)
            }
            guard Set(targets.map(\.id)).count == targets.count else {
                return .failure(
                    .ambiguous(
                        terminal: .kitty,
                        detail: "Kitty returned a duplicate window ID"
                    )
                )
            }
            return .complete(TerminalTargetSummary(targets: targets))
        } catch {
            return .failure(map(error, configuration: configuration))
        }
    }

    func sendContinue(
        configuration: TerminalAutomationConfiguration,
        authorization: @escaping @MainActor @Sendable () -> Bool
    ) async -> TerminalSendResult {
        let scanResult = await scan(configuration: configuration)
        guard case .complete(let liveSummary) = scanResult else {
            if case .failure(let issue) = scanResult {
                return .failure(issue)
            }
            return .failure(.partial(terminal: .kitty, detail: "scan failed"))
        }

        let targets: [TerminalSessionTarget]
        if configuration.allSessions {
            targets = liveSummary.targets
        } else {
            guard !configuration.enrolledTargets.isEmpty else {
                return .failure(.noSelectedSessions(terminal: .kitty))
            }
            let liveByID = Dictionary(
                uniqueKeysWithValues: liveSummary.targets.map { ($0.id, $0) }
            )
            for enrolled in configuration.enrolledTargets {
                guard let live = liveByID[enrolled.id],
                      enrolled.identifiesSameLiveSession(as: live)
                else {
                    return .failure(
                        .noLongerMatches(
                            terminal: .kitty,
                            title: enrolled.displayTitle
                        )
                    )
                }
            }
            targets = configuration.enrolledTargets.compactMap {
                liveByID[$0.id]
            }
        }

        guard !targets.isEmpty else {
            return .failure(
                .noMatchingSessions(
                    terminal: .kitty,
                    provider: configuration.provider
                )
            )
        }

        let selectedIDs = Set(targets.compactMap { Int($0.id) })
        guard selectedIDs.count == targets.count else {
            return .failure(
                .ambiguous(
                    terminal: .kitty,
                    detail: "a saved window ID is no longer numeric"
                )
            )
        }

        do {
            let sent = try await client.sendContinue(
                configuredPath: configuration.kittyExecutablePath,
                listenAddress: configuration.kittyListenAddress,
                match: configuration.kittyMatch,
                selectedWindowIDs: selectedIDs,
                beforeSend: {
                    await authorization() && !Task.isCancelled
                }
            )
            let liveByID = Dictionary(
                uniqueKeysWithValues: liveSummary.targets.map { ($0.id, $0) }
            )
            return .sent(
                TerminalTargetSummary(
                    targets: sent.targets.compactMap {
                        liveByID[String($0.id)]
                    }
                )
            )
        } catch {
            return .failure(map(error, configuration: configuration))
        }
    }

    private func terminalTarget(
        from target: KittySessionTarget,
        provider: ProviderID
    ) -> TerminalSessionTarget {
        TerminalSessionTarget(
            terminal: .kitty,
            provider: provider,
            id: String(target.id),
            displayTitle: target.displayTitle,
            currentDirectory: target.currentDirectory,
            processName: provider.rawValue,
            auxiliaryIdentifier: nil
        )
    }

    private func map(
        _ error: Error,
        configuration: TerminalAutomationConfiguration
    ) -> TerminalAutomationIssue {
        guard let kittyError = error as? KittyRemoteControlError else {
            return .partial(
                terminal: .kitty,
                detail: error.localizedDescription
            )
        }
        switch kittyError {
        case .noMatchingWindows:
            return .noMatchingSessions(
                terminal: .kitty,
                provider: configuration.provider
            )
        case .noSelectedSessions:
            return .noSelectedSessions(terminal: .kitty)
        case .selectedSessionsChanged:
            return .partial(
                terminal: .kitty,
                detail: "an enrolled session changed before delivery"
            )
        case .deliveryCancelled:
            return .routeChanged(.kitty)
        default:
            return .configuration(
                terminal: .kitty,
                detail: kittyError.localizedDescription
            )
        }
    }
}
