import Combine
import Foundation

enum AutoContinueProviderStatus: Equatable, Sendable {
    case idle
    case scanning
    case ready(KittyTargetSummary)
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
        ProviderID: [KittySessionTarget]
    ] = [
        .claude: [],
        .codex: []
    ]
    @Published private(set) var scannedProviders: Set<ProviderID> = []

    private let settings: AppSettings
    private weak var store: UsageStore?
    private let client: KittyRemoteControlClient
    private let defaults: UserDefaults
    private var engine: AutoContinueEngine
    private var snapshotHandlerID: UUID?
    private var settingsCancellable: AnyCancellable?
    private var recoveryTasks: [ProviderID: Task<Void, Never>] = [:]
    private var scheduledResetDates: [ProviderID: Date] = [:]
    private var deliveriesInFlight: Set<ProviderID> = []

    init(
        settings: AppSettings,
        store: UsageStore,
        client: KittyRemoteControlClient = KittyRemoteControlClient(),
        defaults: UserDefaults = .standard
    ) {
        self.settings = settings
        self.store = store
        self.client = client
        self.defaults = defaults
        if let data = defaults.data(forKey: Persistence.engineKey),
           let decoded = try? JSONDecoder().decode(AutoContinueEngine.self, from: data) {
            engine = decoded
        } else {
            engine = AutoContinueEngine()
        }

        for provider in ProviderID.allCases
        where engine.isAwaitingRecovery(for: provider) {
            statuses[provider] = .armed(resetAt: engine.pendingResetDate(for: provider))
        }
    }

    func activate() {
        guard snapshotHandlerID == nil else { return }
        snapshotHandlerID = store?.addSuccessfulSnapshotHandler { [weak self] snapshot in
            self?.processSuccessfulSnapshot(snapshot)
        }
        settingsCancellable = Publishers.CombineLatest3(
            settings.$autoContinueEnabled,
            settings.$autoContinueClaudeEnabled,
            settings.$autoContinueCodexEnabled
        )
        .dropFirst()
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in
            self?.configurationDidChange()
        }
        restoreRecoverySchedules()
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
        let event = engine.evaluate(snapshot: snapshot, enabled: enabled)
        persistEngine()

        guard enabled else {
            cancelRecoveryCheck(for: snapshot.provider)
            statuses[snapshot.provider] = .idle
            return
        }

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
        let configuration = kittyConfiguration(for: provider)
        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await client.matchingTargets(
                    configuredPath: configuration.path,
                    listenAddress: configuration.address,
                    match: configuration.match
                )
                discoveredSessions[provider] = summary.targets
                scannedProviders.insert(provider)
                statuses[provider] = .ready(summary)
            } catch {
                statuses[provider] = .failed(error.localizedDescription)
            }
        }
    }

    func sendNow(to provider: ProviderID) {
        guard !deliveriesInFlight.contains(provider) else { return }
        deliveriesInFlight.insert(provider)
        statuses[provider] = .sending
        let configuration = kittyConfiguration(for: provider)
        Task { [weak self] in
            guard let self else { return }
            defer { deliveriesInFlight.remove(provider) }
            do {
                let summary = try await client.sendContinue(
                    configuredPath: configuration.path,
                    listenAddress: configuration.address,
                    match: configuration.match,
                    selectedWindowIDs: configuration.selectedWindowIDs
                )
                statuses[provider] = .sent(windowCount: summary.windowCount, at: Date())
            } catch {
                statuses[provider] = .failed(error.localizedDescription)
            }
        }
    }

    private func deliver(_ event: AutoContinueEvent) {
        let provider = event.provider
        guard !deliveriesInFlight.contains(provider) else { return }
        deliveriesInFlight.insert(provider)
        statuses[provider] = .sending
        let configuration = kittyConfiguration(for: provider)

        Task { [weak self] in
            guard let self else { return }
            defer { deliveriesInFlight.remove(provider) }
            do {
                let summary = try await client.sendContinue(
                    configuredPath: configuration.path,
                    listenAddress: configuration.address,
                    match: configuration.match,
                    selectedWindowIDs: configuration.selectedWindowIDs
                )
                engine.markDeliverySucceeded(for: provider)
                persistEngine()
                cancelRecoveryCheck(for: provider)
                statuses[provider] = .sent(windowCount: summary.windowCount, at: Date())
            } catch {
                statuses[provider] = .failed(error.localizedDescription)
            }
        }
    }

    private func kittyConfiguration(
        for provider: ProviderID
    ) -> (
        path: String,
        address: String,
        match: String,
        selectedWindowIDs: Set<Int>?
    ) {
        (
            settings.kittyExecutablePath,
            settings.kittyListenAddress,
            settings.kittyMatch(for: provider),
            settings.kittyAllSessions(for: provider)
                ? nil
                : settings.kittySessionIDs(for: provider)
        )
    }

    private func configurationDidChange() {
        for provider in ProviderID.allCases
        where !settings.autoContinueEnabled(for: provider) {
            engine.clear(provider)
            cancelRecoveryCheck(for: provider)
            statuses[provider] = .idle
        }
        persistEngine()
        if settings.autoContinueEnabled {
            store?.refresh()
        }
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
