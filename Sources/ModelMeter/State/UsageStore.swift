import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var states: [ProviderID: ProviderLoadState] = [
        .claude: .idle,
        .codex: .idle
    ]
    @Published private(set) var lastCompletedRefresh: Date?

    private let settings: AppSettings
    private var refreshTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var successfulSnapshotHandlers: [
        UUID: @MainActor (ProviderUsageSnapshot) -> Void
    ] = [:]

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isRefreshing: Bool {
        states.values.contains(where: \.isLoading)
    }

    @discardableResult
    func addSuccessfulSnapshotHandler(
        _ handler: @escaping @MainActor (ProviderUsageSnapshot) -> Void
    ) -> UUID {
        let id = UUID()
        successfulSnapshotHandlers[id] = handler
        return id
    }

    func removeSuccessfulSnapshotHandler(_ id: UUID) {
        successfulSnapshotHandlers.removeValue(forKey: id)
    }

    func start() {
        guard pollingTask == nil else { return }
        refresh()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let minutes = self.settings.refreshMinutes
                do {
                    try await Task.sleep(for: .seconds(minutes * 60))
                } catch {
                    return
                }
                self.refresh()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        pollingTask?.cancel()
        refreshTask = nil
        pollingTask = nil
    }

    func refreshIfStale() {
        let staleAfter: TimeInterval = 15
        if lastCompletedRefresh.map({ Date().timeIntervalSince($0) >= staleAfter }) ?? true {
            refresh()
        }
    }

    func refresh() {
        guard refreshTask == nil else { return }

        for provider in ProviderID.allCases {
            states[provider] = .loading(previous: states[provider]?.snapshot)
        }

        let claudePath = settings.claudePath
        let codexPath = settings.codexPath

        refreshTask = Task { [weak self] in
            guard let self else { return }
            let providers: [any UsageProviding] = [
                ClaudeUsageProvider(configuredPath: claudePath),
                CodexUsageProvider(configuredPath: codexPath)
            ]

            await withTaskGroup(of: FetchOutcome.self) { group in
                for provider in providers {
                    group.addTask {
                        do {
                            return .success(provider.providerID, try await provider.fetch())
                        } catch {
                            return .failure(
                                provider.providerID,
                                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            )
                        }
                    }
                }

                for await outcome in group {
                    switch outcome {
                    case .success(let provider, let snapshot):
                        self.states[provider] = .loaded(snapshot)
                        for handler in self.successfulSnapshotHandlers.values {
                            handler(snapshot)
                        }
                    case .failure(let provider, let message):
                        self.states[provider] = .failed(
                            message: message,
                            previous: self.states[provider]?.snapshot
                        )
                    }
                }
            }

            self.lastCompletedRefresh = Date()
            self.refreshTask = nil
        }
    }

    deinit {
        refreshTask?.cancel()
        pollingTask?.cancel()
    }
}

private enum FetchOutcome: Sendable {
    case success(ProviderID, ProviderUsageSnapshot)
    case failure(ProviderID, String)
}
