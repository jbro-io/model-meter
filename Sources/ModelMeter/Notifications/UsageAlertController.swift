import Combine
import Foundation

@MainActor
final class UsageAlertController: ObservableObject {
    private enum Persistence {
        static let engineKey = "usageThresholdEngine.v1"
    }

    @Published private(set) var authorizationState: NotificationAuthorizationState = .unknown
    @Published private(set) var lastErrorMessage: String?

    private let settings: AppSettings
    private weak var store: UsageStore?
    private let notifier: any UsageNotificationDelivering
    private let defaults: UserDefaults
    private var engine: UsageThresholdEngine
    private var snapshotHandlerID: UUID?

    init(
        settings: AppSettings,
        store: UsageStore,
        notifier: (any UsageNotificationDelivering)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.settings = settings
        self.store = store
        self.notifier = notifier ?? MacNotificationClient()
        self.defaults = defaults
        if let data = defaults.data(forKey: Persistence.engineKey),
           let decoded = try? JSONDecoder().decode(UsageThresholdEngine.self, from: data) {
            engine = decoded
        } else {
            engine = UsageThresholdEngine()
        }
    }

    func activate() {
        notifier.activate()
        snapshotHandlerID = store?.addSuccessfulSnapshotHandler { [weak self] snapshot in
            self?.processSuccessfulSnapshot(snapshot)
        }
        refreshAuthorizationState()
    }

    func deactivate() {
        if let snapshotHandlerID {
            store?.removeSuccessfulSnapshotHandler(snapshotHandlerID)
            self.snapshotHandlerID = nil
        }
    }

    func setAlertsEnabled(_ enabled: Bool) {
        guard enabled else {
            settings.usageAlertsEnabled = false
            lastErrorMessage = nil
            return
        }

        Task { [weak self] in
            await self?.enableAlerts()
        }
    }

    func refreshAuthorizationState() {
        Task { [weak self] in
            guard let self else { return }
            authorizationState = await notifier.authorizationState()
        }
    }

    func previewSound(_ sound: UsageAlertSoundSelection) {
        lastErrorMessage = playbackError(for: sound)
    }

    func sendTestAlert(sound: UsageAlertSoundSelection? = nil) {
        let selectedSound = sound ?? .builtIn(settings.usageAlertSound)
        let soundError = playbackError(for: selectedSound)
        lastErrorMessage = soundError

        Task { [weak self] in
            guard let self else { return }
            do {
                let state = try await ensureAuthorization()
                guard state.canDeliver else {
                    lastErrorMessage = combinedError(
                        soundError,
                        "Notification banners are blocked in System Settings."
                    )
                    return
                }
                try await notifier.deliverTest(sound: selectedSound)
                lastErrorMessage = soundError
            } catch {
                lastErrorMessage = combinedError(
                    soundError,
                    error.localizedDescription
                )
            }
        }
    }

    func processSuccessfulSnapshot(_ snapshot: ProviderUsageSnapshot, now: Date = Date()) {
        guard settings.usageAlertsEnabled else { return }
        if authorizationState == .unknown {
            Task { [weak self] in
                guard let self else { return }
                authorizationState = await notifier.authorizationState()
                processSuccessfulSnapshot(snapshot, now: now)
            }
            return
        }
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        guard age >= -30, age <= 120 else { return }

        let events = engine.evaluate(
            snapshot: snapshot,
            thresholds: settings.usageAlertThresholdPercents
        )
        persistEngine()

        for event in events {
            Task { [weak self] in
                guard let self else { return }
                let sound = settings.usageAlertSound(
                    forThreshold: event.thresholdPercent
                )
                let soundError = playbackError(for: sound)
                let deliveredAudibly = sound != .none && soundError == nil

                if authorizationState.canDeliver {
                    do {
                        try await notifier.deliver(event, sound: sound)
                        lastErrorMessage = soundError
                    } catch {
                        if !deliveredAudibly {
                            engine.markDeliveryFailed(event)
                            persistEngine()
                        }
                        lastErrorMessage = combinedError(
                            soundError,
                            error.localizedDescription
                        )
                    }
                } else {
                    lastErrorMessage = combinedError(
                        soundError,
                        "Notification banners are blocked in System Settings."
                    )
                }
            }
        }
    }

    private func enableAlerts() async {
        do {
            let state = try await ensureAuthorization()
            authorizationState = state
            settings.usageAlertsEnabled = true
            lastErrorMessage = state.canDeliver
                ? nil
                : "Sound alerts are active. Allow notifications in System Settings to also show banners."
            store?.refresh()
        } catch {
            settings.usageAlertsEnabled = true
            lastErrorMessage = "Sound alerts are active, but Notification Center could not be enabled: \(error.localizedDescription)"
            store?.refresh()
        }
    }

    private func ensureAuthorization() async throws -> NotificationAuthorizationState {
        let current = await notifier.authorizationState()
        let state = current == .notDetermined
            ? try await notifier.requestAuthorization()
            : current
        authorizationState = state
        return state
    }

    private func playbackError(for sound: UsageAlertSoundSelection) -> String? {
        do {
            try notifier.playSound(sound)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func combinedError(_ messages: String?...) -> String? {
        let value: [String] = messages.compactMap { message -> String? in
            guard let message, !message.isEmpty else { return nil }
            return message
        }
        return value.isEmpty ? nil : value.joined(separator: " ")
    }

    private func persistEngine() {
        guard let data = try? JSONEncoder().encode(engine) else { return }
        defaults.set(data, forKey: Persistence.engineKey)
    }
}
