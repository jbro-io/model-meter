import Combine
import Foundation

enum AutoContinueProviderStatus: Equatable, Sendable {
    case idle
    case scanning
    case ready(TerminalTargetSummary)
    case armed(resetAt: Date?)
    case sending
    case sent(windowCount: Int, at: Date)
    case failed(String)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

@MainActor
final class AutoContinueController: ObservableObject {
    private enum Persistence {
        static let engineKey = "autoContinueEngine.v1"
    }

    @Published private(set) var statuses: [
        ProviderID: AutoContinueProviderStatus
    ] = [
        .claude: .idle,
        .codex: .idle
    ]
    @Published private(set) var discoveredSessions: [
        ProviderID: [TerminalSessionTarget]
    ] = [
        .claude: [],
        .codex: []
    ]
    @Published private(set) var scannedProviders: Set<ProviderID> = []

    private let settings: AppSettings
    private weak var store: UsageStore?
    private let clients: [
        AutoContinueTerminal: any TerminalAutomationClient
    ]
    private let defaults: UserDefaults
    private var engine: AutoContinueEngine
    private var configuredTerminal: AutoContinueTerminal
    private var configuredRouteRevisions: [ProviderID: Int]
    private var snapshotHandlerID: UUID?
    private var settingsCancellable: AnyCancellable?
    private var recoveryTasks: [ProviderID: Task<Void, Never>] = [:]
    private var scheduledResetDates: [ProviderID: Date] = [:]
    private var deliveriesInFlight: Set<ProviderID> = []
    private var deliveryTasks: [ProviderID: Task<Void, Never>] = [:]

    init(
        settings: AppSettings,
        store: UsageStore,
        clients: [any TerminalAutomationClient]? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.settings = settings
        self.store = store
        self.defaults = defaults
        let resolvedClients = clients ?? [
            KittyTerminalAutomationClient(),
            ITermAutomationClient(),
            GhosttyAutomationClient()
        ]
        self.clients = Dictionary(
            uniqueKeysWithValues: resolvedClients.map {
                ($0.terminal, $0)
            }
        )
        configuredTerminal = settings.autoContinueTerminal
        configuredRouteRevisions = settings.autoContinueRouteRevisions
        if let data = defaults.data(forKey: Persistence.engineKey),
           let decoded = try? JSONDecoder().decode(AutoContinueEngine.self, from: data) {
            engine = decoded
        } else {
            engine = AutoContinueEngine()
        }

        for provider in ProviderID.allCases {
            guard engine.isAwaitingRecovery(for: provider) else { continue }
            if settings.autoContinueTerminal == .kitty,
               !settings.allSessions(for: .kitty, provider: provider),
               settings.hasIncompleteSessionIdentity(
                for: .kitty,
                provider: provider
            ) {
                engine.clear(provider)
                statuses[provider] = .failed(
                    "Saved Kitty enrollments need a live identity scan before "
                        + "Auto-Continue can resume safely."
                )
            } else if engine.pendingRouteRevision(for: provider)
                == settings.autoContinueRouteRevision(for: provider) {
                statuses[provider] = .armed(
                    resetAt: engine.pendingResetDate(for: provider)
                )
            } else {
                engine.clear(provider)
                statuses[provider] = .failed(
                    "Auto-Continue targets changed while recovery was armed. "
                        + "A live exhausted snapshot is required to arm the new route."
                )
            }
        }
        persistEngine()
    }

    func activate() {
        guard snapshotHandlerID == nil else { return }
        snapshotHandlerID = store?.addSuccessfulSnapshotHandler { [weak self] snapshot in
            self?.processSuccessfulSnapshot(snapshot)
        }
        settingsCancellable = Publishers.CombineLatest4(
            settings.$autoContinueEnabled,
            settings.$autoContinueClaudeEnabled,
            settings.$autoContinueCodexEnabled,
            settings.$autoContinueRouteRevisions
        )
        .dropFirst()
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            self?.configurationDidChange()
        }
        restoreRecoverySchedules()
        if settings.autoContinueTerminal == .kitty {
            for provider in ProviderID.allCases
            where settings.autoContinueEnabled(for: provider)
                && !settings.allSessions(for: .kitty, provider: provider)
                && settings.hasIncompleteSessionIdentity(
                    for: .kitty,
                    provider: provider
                ) {
                scanTargets(for: provider)
            }
        }
    }

    func deactivate() {
        if let snapshotHandlerID {
            store?.removeSuccessfulSnapshotHandler(snapshotHandlerID)
            self.snapshotHandlerID = nil
        }
        settingsCancellable = nil
        for task in recoveryTasks.values {
            task.cancel()
        }
        recoveryTasks.removeAll()
        scheduledResetDates.removeAll()
        for task in deliveryTasks.values {
            task.cancel()
        }
        deliveryTasks.removeAll()
        deliveriesInFlight.removeAll()
    }

    func status(for provider: ProviderID) -> AutoContinueProviderStatus {
        statuses[provider] ?? .idle
    }

    func isArmed(for provider: ProviderID) -> Bool {
        engine.isAwaitingRecovery(for: provider)
    }

    func pendingResetDate(for provider: ProviderID) -> Date? {
        engine.pendingResetDate(for: provider)
    }

    func processSuccessfulSnapshot(
        _ snapshot: ProviderUsageSnapshot,
        now: Date = Date()
    ) {
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        guard age >= -30, age <= 120 else { return }

        let enabled = settings.autoContinueEnabled(for: snapshot.provider)
        guard enabled else {
            _ = engine.evaluate(
                snapshot: snapshot,
                enabled: false,
                routeRevision: settings.autoContinueRouteRevision(
                    for: snapshot.provider
                )
            )
            persistEngine()
            cancelRecoveryCheck(for: snapshot.provider)
            statuses[snapshot.provider] = .idle
            return
        }

        if settings.autoContinueTerminal == .kitty,
           !settings.allSessions(for: .kitty, provider: snapshot.provider),
           settings.hasIncompleteSessionIdentity(
            for: .kitty,
            provider: snapshot.provider
        ) {
            engine.clear(snapshot.provider)
            persistEngine()
            cancelRecoveryCheck(for: snapshot.provider)
            if statuses[snapshot.provider] != .scanning {
                statuses[snapshot.provider] = .failed(
                    "Saved Kitty enrollments need a live identity scan before "
                        + "Auto-Continue can resume safely."
                )
                scanTargets(for: snapshot.provider)
            }
            return
        }

        let event = engine.evaluate(
            snapshot: snapshot,
            enabled: true,
            routeRevision: settings.autoContinueRouteRevision(
                for: snapshot.provider
            )
        )
        persistEngine()

        if let event {
            deliver(event)
        } else if engine.isAwaitingRecovery(for: snapshot.provider) {
            let resetAt = engine.pendingResetDate(for: snapshot.provider)
            statuses[snapshot.provider] = .armed(resetAt: resetAt)
            scheduleRecoveryCheck(for: snapshot.provider, resetAt: resetAt, now: now)
        }
    }

    func scanTargets(for provider: ProviderID) {
        scannedProviders.remove(provider)
        discoveredSessions[provider] = []
        statuses[provider] = .scanning
        let configuration = terminalConfiguration(for: provider)
        guard let client = clients[configuration.terminal] else {
            statuses[provider] = .failed(
                "No \(configuration.terminal.title) automation adapter is available."
            )
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await client.scan(configuration: configuration)
            guard isScanConfigurationCurrent(configuration) else {
                return
            }
            switch result {
            case .complete(let summary):
                settings.synchronizeEnrolledSessions(
                    with: summary.targets,
                    terminal: configuration.terminal,
                    provider: provider
                )
                discoveredSessions[provider] = summary.targets
                scannedProviders.insert(provider)
                statuses[provider] = .ready(summary)
            case .failure(let issue):
                statuses[provider] = .failed(issue.localizedDescription)
            }
        }
    }

    func sendNow(to provider: ProviderID) {
        guard !deliveriesInFlight.contains(provider) else { return }
        deliveriesInFlight.insert(provider)
        statuses[provider] = .sending
        let configuration = terminalConfiguration(for: provider)
        guard let client = clients[configuration.terminal] else {
            deliveriesInFlight.remove(provider)
            statuses[provider] = .failed(
                "No \(configuration.terminal.title) automation adapter is available."
            )
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                deliveriesInFlight.remove(provider)
                deliveryTasks[provider] = nil
            }
            let result = await client.sendContinue(
                configuration: configuration,
                authorization: { [weak self] in
                    self?.isConfigurationCurrent(configuration) == true
                }
            )
            guard isConfigurationCurrent(configuration), !Task.isCancelled else {
                statuses[provider] = .failed(
                    TerminalAutomationIssue.routeChanged(
                        configuration.terminal
                    ).localizedDescription
                )
                return
            }
            switch result {
            case .sent(let summary):
                statuses[provider] = .sent(windowCount: summary.windowCount, at: Date())
            case .partial(let sent, let issue):
                statuses[provider] = .failed(
                    partialDeliveryMessage(
                        sentCount: sent.windowCount,
                        issue: issue,
                        willRetry: false
                    )
                )
            case .failure(let issue):
                statuses[provider] = .failed(issue.localizedDescription)
            }
        }
        deliveryTasks[provider] = task
    }

    private func deliver(_ event: AutoContinueEvent) {
        let provider = event.provider
        guard event.routeRevision
            == settings.autoContinueRouteRevision(for: provider)
        else {
            statuses[provider] = .failed(
                "Auto-Continue targets changed after recovery was armed. "
                    + "No text was sent."
            )
            return
        }
        guard !deliveriesInFlight.contains(provider) else { return }
        deliveriesInFlight.insert(provider)
        statuses[provider] = .sending
        let previouslyDelivered = engine.deliveredTargetIDs(for: provider)
        let configuration = terminalConfiguration(
            for: provider,
            excludingTargetIDs: previouslyDelivered
        )
        if !configuration.allSessions,
           !previouslyDelivered.isEmpty,
           configuration.enrolledTargets.isEmpty {
            deliveriesInFlight.remove(provider)
            engine.markDeliverySucceeded(
                for: provider,
                routeRevision: configuration.routeRevision
            )
            persistEngine()
            cancelRecoveryCheck(for: provider)
            statuses[provider] = .sent(
                windowCount: previouslyDelivered.count,
                at: Date()
            )
            return
        }
        guard let client = clients[configuration.terminal] else {
            deliveriesInFlight.remove(provider)
            statuses[provider] = .failed(
                "No \(configuration.terminal.title) automation adapter is available."
            )
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                deliveriesInFlight.remove(provider)
                deliveryTasks[provider] = nil
            }
            let result = await client.sendContinue(
                configuration: configuration,
                authorization: { [weak self] in
                    self?.isConfigurationCurrent(configuration) == true
                }
            )
            switch result {
            case .sent(let summary):
                let belongsToArmedRoute = engine.pendingRouteRevision(
                    for: provider
                ) == configuration.routeRevision
                engine.markDeliverySucceeded(
                    for: provider,
                    routeRevision: configuration.routeRevision
                )
                persistEngine()
                if belongsToArmedRoute {
                    cancelRecoveryCheck(for: provider)
                }
                guard isDeliveryRouteCurrent(configuration) else { return }
                let deliveredIDs = previouslyDelivered.union(
                    summary.targets.map(\.id)
                )
                statuses[provider] = .sent(
                    windowCount: deliveredIDs.count,
                    at: Date()
                )
            case .partial(let sent, let issue):
                engine.markDeliveryProgress(
                    for: provider,
                    routeRevision: configuration.routeRevision,
                    targetIDs: Set(sent.targets.map(\.id))
                )
                persistEngine()
                guard isDeliveryRouteCurrent(configuration) else { return }
                statuses[provider] = .failed(
                    partialDeliveryMessage(
                        sentCount: sent.windowCount,
                        issue: issue,
                        willRetry: true
                    )
                )
            case .failure(let issue):
                guard isConfigurationCurrent(configuration) else {
                    statuses[provider] = .failed(
                        TerminalAutomationIssue.routeChanged(
                            configuration.terminal
                        ).localizedDescription
                    )
                    return
                }
                statuses[provider] = .failed(issue.localizedDescription)
            }
        }
        deliveryTasks[provider] = task
    }

    private func terminalConfiguration(
        for provider: ProviderID,
        excludingTargetIDs: Set<String> = []
    ) -> TerminalAutomationConfiguration {
        let terminal = settings.autoContinueTerminal
        return TerminalAutomationConfiguration(
            terminal: terminal,
            provider: provider,
            routeRevision: settings.autoContinueRouteRevision(for: provider),
            kittyExecutablePath: settings.kittyExecutablePath,
            kittyListenAddress: settings.kittyListenAddress,
            kittyMatch: settings.kittyMatch(for: provider),
            allSessions: settings.allSessions(for: terminal, provider: provider),
            enrolledTargets: settings.selectedSessionTargets(
                for: terminal,
                provider: provider
            )
            .filter { !excludingTargetIDs.contains($0.id) }
        )
    }

    private func configurationDidChange() {
        let terminalChanged = configuredTerminal != settings.autoContinueTerminal
        let currentRevisions = settings.autoContinueRouteRevisions
        if terminalChanged {
            discoveredSessions = [.claude: [], .codex: []]
            scannedProviders.removeAll()
            for provider in ProviderID.allCases {
                statuses[provider] = .idle
            }
        }

        for provider in ProviderID.allCases {
            let routeChanged = terminalChanged
                || configuredRouteRevisions[provider]
                    != currentRevisions[provider]
            if routeChanged || !settings.autoContinueEnabled(for: provider) {
                deliveryTasks[provider]?.cancel()
            }
            if !settings.autoContinueEnabled(for: provider) {
                engine.clear(provider)
                cancelRecoveryCheck(for: provider)
                statuses[provider] = .idle
            } else if let armedRevision = engine.pendingRouteRevision(for: provider),
                      armedRevision
                        != settings.autoContinueRouteRevision(for: provider) {
                engine.clear(provider)
                cancelRecoveryCheck(for: provider)
                statuses[provider] = .failed(
                    "Auto-Continue targets changed while recovery was armed. "
                        + "No text will be sent until the new route is armed."
                )
            }
        }
        configuredTerminal = settings.autoContinueTerminal
        configuredRouteRevisions = currentRevisions
        persistEngine()
        if settings.autoContinueEnabled {
            store?.refresh()
        }
    }

    private func isConfigurationCurrent(
        _ configuration: TerminalAutomationConfiguration
    ) -> Bool {
        !Task.isCancelled
            && isDeliveryRouteCurrent(configuration)
    }

    private func isDeliveryRouteCurrent(
        _ configuration: TerminalAutomationConfiguration
    ) -> Bool {
        settings.autoContinueEnabled(for: configuration.provider)
            && settings.autoContinueTerminal == configuration.terminal
            && settings.autoContinueRouteRevision(
                for: configuration.provider
            ) == configuration.routeRevision
    }

    private func isScanConfigurationCurrent(
        _ configuration: TerminalAutomationConfiguration
    ) -> Bool {
        guard settings.autoContinueTerminal == configuration.terminal else {
            return false
        }
        guard configuration.terminal == .kitty else { return true }
        return settings.kittyExecutablePath == configuration.kittyExecutablePath
            && settings.kittyListenAddress == configuration.kittyListenAddress
            && settings.kittyMatch(for: configuration.provider)
                == configuration.kittyMatch
    }

    private func partialDeliveryMessage(
        sentCount: Int,
        issue: TerminalAutomationIssue,
        willRetry: Bool
    ) -> String {
        let prefix = sentCount == 1
            ? "Sent to 1 session."
            : "Sent to \(sentCount) sessions."
        let retry = willRetry
            ? " Only unsent sessions will be retried."
            : ""
        return "\(prefix) \(issue.localizedDescription)\(retry)"
    }

    private func restoreRecoverySchedules() {
        let now = Date()
        for provider in ProviderID.allCases
        where settings.autoContinueEnabled(for: provider)
            && engine.isAwaitingRecovery(for: provider) {
            scheduleRecoveryCheck(
                for: provider,
                resetAt: engine.pendingResetDate(for: provider),
                now: now
            )
        }
    }

    private func scheduleRecoveryCheck(
        for provider: ProviderID,
        resetAt: Date?,
        now: Date
    ) {
        guard let resetAt else { return }
        if let scheduled = scheduledResetDates[provider],
           abs(scheduled.timeIntervalSince(resetAt)) < 1,
           recoveryTasks[provider] != nil {
            return
        }

        cancelRecoveryCheck(for: provider)
        scheduledResetDates[provider] = resetAt
        let desiredCheck = resetAt.addingTimeInterval(3)
        let delay = max(desiredCheck.timeIntervalSince(now), 30)
        recoveryTasks[provider] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self else { return }
            recoveryTasks[provider] = nil
            scheduledResetDates[provider] = nil
            store?.refresh()
        }
    }

    private func cancelRecoveryCheck(for provider: ProviderID) {
        recoveryTasks[provider]?.cancel()
        recoveryTasks[provider] = nil
        scheduledResetDates[provider] = nil
    }

    private func persistEngine() {
        guard let data = try? JSONEncoder().encode(engine) else { return }
        defaults.set(data, forKey: Persistence.engineKey)
    }

    deinit {
        for task in recoveryTasks.values {
            task.cancel()
        }
    }
}
