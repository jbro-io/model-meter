import XCTest
@testable import ModelMeter

final class CustomAlertSoundSettingsTests: XCTestCase {
    @MainActor
    func testCustomSelectionRestoresAndAppearsBeforeNoneInPicker() throws {
        let suiteName = "ModelMeterCustomSoundSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let custom = CustomAlertSound(
            id: "custom-chime",
            title: "My Chime",
            fileName: "ModelMeter-custom-chime.caf"
        )
        defaults.set(
            try JSONEncoder().encode([custom]),
            forKey: "customAlertSounds"
        )
        defaults.set(
            ["20": "custom:custom-chime"],
            forKey: "usageAlertSoundsByThreshold"
        )

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.usageAlertSound(forThreshold: 20), .custom(custom))
        XCTAssertEqual(
            settings.availableUsageAlertSounds.last,
            UsageAlertSoundSelection.none
        )
        XCTAssertTrue(settings.availableUsageAlertSounds.contains(.custom(custom)))
    }

    @MainActor
    func testTestAlertPlaysSelectedSoundEvenWhenNotificationsAreDenied() throws {
        let suiteName = "ModelMeterSoundFallbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let store = UsageStore(settings: settings)
        let notifier = RecordingNotificationClient()
        let controller = UsageAlertController(
            settings: settings,
            store: store,
            notifier: notifier,
            defaults: defaults
        )

        controller.sendTestAlert(sound: .ping)

        XCTAssertEqual(notifier.playedSounds, [.ping])
    }
}

@MainActor
private final class RecordingNotificationClient: UsageNotificationDelivering {
    private(set) var playedSounds: [UsageAlertSoundSelection] = []

    func activate() {}

    func authorizationState() async -> NotificationAuthorizationState { .denied }

    func requestAuthorization() async throws -> NotificationAuthorizationState { .denied }

    func playSound(_ sound: UsageAlertSoundSelection) throws {
        playedSounds.append(sound)
    }

    func deliver(
        _ event: UsageThresholdEvent,
        sound: UsageAlertSoundSelection
    ) async throws {}

    func deliverTest(sound: UsageAlertSoundSelection) async throws {}
}
