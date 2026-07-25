import XCTest
@testable import ModelMeter

final class UsageDisplayModeTests: XCTestCase {
    func testUsedAndRemainingAreComplements() {
        XCTAssertEqual(
            UsageDisplayMode.used.fraction(forUsedFraction: 0.39),
            0.39,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            UsageDisplayMode.remaining.fraction(forUsedFraction: 0.39),
            0.61,
            accuracy: 0.000_1
        )
    }

    func testDisplayFractionsAreClamped() {
        XCTAssertEqual(UsageDisplayMode.used.fraction(forUsedFraction: 2), 1)
        XCTAssertEqual(UsageDisplayMode.remaining.fraction(forUsedFraction: -1), 1)
    }

    @MainActor
    func testDisplayPreferencePersists() throws {
        let suiteName = "ModelMeterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.usageDisplayMode, .used)
        settings.usageDisplayMode = .remaining

        XCTAssertEqual(AppSettings(defaults: defaults).usageDisplayMode, .remaining)
    }

    @MainActor
    func testProviderDisplayOrderDefaultsAndPersists() throws {
        let suiteName = "ModelMeterOrderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.providerDisplayOrder, .claudeFirst)
        XCTAssertEqual(settings.providerDisplayOrder.providers, [.claude, .codex])

        settings.providerDisplayOrder = .codexFirst

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.providerDisplayOrder, .codexFirst)
        XCTAssertEqual(restored.providerDisplayOrder.providers, [.codex, .claude])
    }

    @MainActor
    func testMultipleAlertThresholdsAndSoundPersist() throws {
        let suiteName = "ModelMeterAlertSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.usageAlertsEnabled)
        XCTAssertEqual(settings.usageAlertThresholdPercents, [20])
        XCTAssertEqual(settings.usageAlertSound, .defaultSound)

        settings.usageAlertsEnabled = true
        settings.addUsageAlertThreshold(10)
        settings.addUsageAlertThreshold(5)
        settings.addUsageAlertThreshold(10)
        settings.usageAlertSound = .none

        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.usageAlertsEnabled)
        XCTAssertEqual(restored.usageAlertThresholdPercents, [20, 10, 5])
        XCTAssertEqual(restored.usageAlertSound, .none)

        restored.replaceUsageAlertThreshold(20, with: 25)
        restored.removeUsageAlertThreshold(10)
        XCTAssertEqual(restored.usageAlertThresholdPercents, [25, 5])
    }
}
