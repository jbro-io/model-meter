import AppKit
import SwiftUI
import XCTest
@testable import ModelMeter

final class SettingsWindowTests: XCTestCase {
    @MainActor
    func testSettingsUsesReusableNativeWindow() throws {
        _ = NSApplication.shared
        let suiteName = "ModelMeterSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let store = UsageStore(settings: settings)
        let alertController = UsageAlertController(
            settings: settings,
            store: store,
            notifier: TestNotificationClient(),
            defaults: defaults
        )
        let autoContinueController = AutoContinueController(
            settings: settings,
            store: store,
            defaults: defaults
        )
        let updateCheckRecorder = UpdateCheckRecorder()
        let controller = SettingsWindowController(
            settings: settings,
            store: store,
            alertController: alertController,
            autoContinueController: autoContinueController,
            checkForUpdates: {
                updateCheckRecorder.callCount += 1
            }
        )
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(window.title, "Model Meter Settings")
        XCTAssertEqual(window.level, .normal)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertEqual(window.contentMinSize, NSSize(width: 620, height: 420))
        XCTAssertEqual(controller.windowFrameAutosaveName, "ModelMeterSettings")
        let hostingController = try XCTUnwrap(
            window.contentViewController as? NSHostingController<SettingsView>
        )
        XCTAssertTrue(hostingController.rootView.settings === settings)
        XCTAssertTrue(hostingController.rootView.store === store)
        XCTAssertTrue(hostingController.rootView.alertController === alertController)
        XCTAssertTrue(
            hostingController.rootView.autoContinueController === autoContinueController
        )
        hostingController.rootView.checkForUpdates()
        XCTAssertEqual(updateCheckRecorder.callCount, 1)

        let originalWindow = window
        controller.close()
        XCTAssertTrue(controller.window === originalWindow)
    }
}

@MainActor
private final class UpdateCheckRecorder {
    var callCount = 0
}

@MainActor
private final class TestNotificationClient: UsageNotificationDelivering {
    func activate() {}

    func authorizationState() async -> NotificationAuthorizationState {
        .authorized
    }

    func requestAuthorization() async throws -> NotificationAuthorizationState {
        .authorized
    }

    func playSound(_ sound: UsageAlertSoundSelection) throws {}

    func deliver(
        _ event: UsageThresholdEvent,
        sound: UsageAlertSoundSelection
    ) async throws {}

    func deliverTest(sound: UsageAlertSoundSelection) async throws {}
}
