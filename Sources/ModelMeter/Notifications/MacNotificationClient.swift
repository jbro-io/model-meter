import AppKit
import Foundation
import UserNotifications

enum NotificationAuthorizationState: Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case authorized

    var canDeliver: Bool { self == .authorized }

    var description: String {
        switch self {
        case .unknown: "Checking notification access…"
        case .notDetermined: "macOS will ask for notification access."
        case .denied: "Notifications are blocked in System Settings."
        case .authorized: "Alerts can appear in Notification Center."
        }
    }
}

@MainActor
protocol UsageNotificationDelivering: AnyObject {
    func activate()
    func authorizationState() async -> NotificationAuthorizationState
    func requestAuthorization() async throws -> NotificationAuthorizationState
    func playSound(_ sound: UsageAlertSoundSelection) throws
    func deliver(_ event: UsageThresholdEvent, sound: UsageAlertSoundSelection) async throws
    func deliverTest(sound: UsageAlertSoundSelection) async throws
}

@MainActor
final class MacNotificationClient: NSObject, UsageNotificationDelivering {
    private let center: UNUserNotificationCenter
    private var activeSounds: [NSSound] = []

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    func activate() {
        center.delegate = self
    }

    func authorizationState() async -> NotificationAuthorizationState {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: Self.state(from: settings))
            }
        }
    }

    func requestAuthorization() async throws -> NotificationAuthorizationState {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            center.requestAuthorization(options: [.alert, .sound]) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        return await authorizationState()
    }

    func playSound(_ selection: UsageAlertSoundSelection) throws {
        activeSounds.removeAll { !$0.isPlaying }

        if selection == .none { return }
        if selection == .defaultSound {
            NSSound.beep()
            return
        }

        let sound: NSSound?
        switch selection {
        case .builtIn:
            sound = selection.systemSoundName.flatMap {
                NSSound(named: NSSound.Name($0))
            }
        case .custom(let customSound):
            sound = CustomAlertSoundStore()
                .url(for: customSound)
                .flatMap { NSSound(contentsOf: $0, byReference: true) }
        }

        guard let sound, sound.play() else {
            throw AlertSoundPlaybackError.unavailable(selection.title)
        }
        activeSounds.append(sound)
    }

    func deliver(
        _ event: UsageThresholdEvent,
        sound: UsageAlertSoundSelection
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = "\(event.provider.displayName) usage warning"
        content.subtitle = event.limitTitle
        content.body = alertBody(for: event)
        content.threadIdentifier = "usage.\(event.provider.rawValue)"
        // Model Meter plays the selected audio itself. Keeping the banner silent
        // prevents duplicate playback and works even when Notification Center's
        // custom-sound handling is unavailable.
        content.sound = nil

        try await add(
            UNNotificationRequest(
                identifier: event.notificationIdentifier,
                content: content,
                trigger: nil
            )
        )
    }

    func deliverTest(sound: UsageAlertSoundSelection) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Model Meter alerts are ready"
        content.body = "You’ll be notified when a configured quota threshold is crossed."
        content.sound = nil
        try await add(
            UNNotificationRequest(
                identifier: "usage.test.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func alertBody(for event: UsageThresholdEvent) -> String {
        let thresholdDescription = event.thresholdPercent == 0
            ? "usage exhausted"
            : "below \(event.thresholdPercent)%"
        var parts = [
            "\(event.remainingPercent)% remaining (\(thresholdDescription))"
        ]
        if let resetsAt = event.resetsAt {
            let exact = resetsAt.formatted(date: .abbreviated, time: .shortened)
            let relative = RelativeDateTimeFormatter().localizedString(
                for: resetsAt,
                relativeTo: Date()
            )
            parts.append("Resets \(exact) (\(relative))")
        } else if let description = event.resetDescription, !description.isEmpty {
            parts.append("Resets \(description)")
        }
        return parts.joined(separator: ". ") + "."
    }

    nonisolated private static func state(
        from settings: UNNotificationSettings
    ) -> NotificationAuthorizationState {
        switch settings.authorizationStatus {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized, .provisional:
            .authorized
        @unknown default:
            .denied
        }
    }
}

private enum AlertSoundPlaybackError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let title):
            "The \(title) alert sound could not be played."
        }
    }
}

extension MacNotificationClient: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
