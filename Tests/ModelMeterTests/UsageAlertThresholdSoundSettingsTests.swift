import XCTest
@testable import ModelMeter

final class UsageAlertThresholdSoundSettingsTests: XCTestCase {
    @MainActor
    func testThresholdsCanUseIndependentSoundsAndLegacySoundIsFallback() throws {
        let suiteName = "ModelMeterThresholdSoundTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.usageAlertSound = .basso
        settings.addUsageAlertThreshold(10)
        settings.setUsageAlertSound(.glass, forThreshold: 20)
        settings.setUsageAlertSound(.ping, forThreshold: 10)

        XCTAssertEqual(settings.usageAlertSound(forThreshold: 20), .glass)
        XCTAssertEqual(settings.usageAlertSound(forThreshold: 10), .ping)
        XCTAssertEqual(settings.usageAlertSound(forThreshold: 5), .basso)

        settings.usageAlertSound = .purr

        XCTAssertEqual(settings.usageAlertSound(forThreshold: 20), .glass)
        XCTAssertEqual(settings.usageAlertSound(forThreshold: 10), .ping)
        XCTAssertEqual(settings.usageAlertSound(forThreshold: 5), .purr)
    }

    @MainActor
    func testThresholdSoundsPersistAcrossSettingsInstances() throws {
        let suiteName = "ModelMeterThresholdSoundPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.usageAlertSound = .none
        settings.addUsageAlertThreshold(10)
        settings.setUsageAlertSound(.hero, forThreshold: 20)
        settings.setUsageAlertSound(.submarine, forThreshold: 10)

        let restored = AppSettings(defaults: defaults)

        XCTAssertEqual(restored.usageAlertSound(forThreshold: 20), .hero)
        XCTAssertEqual(restored.usageAlertSound(forThreshold: 10), .submarine)
        XCTAssertEqual(restored.usageAlertSound(forThreshold: 5), .none)
    }

    @MainActor
    func testReplacingThresholdTransfersItsSoundAndClearsOldOverride() throws {
        let suiteName = "ModelMeterThresholdSoundReplacementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.usageAlertSound = .frog
        settings.setUsageAlertSound(.morse, forThreshold: 20)

        settings.replaceUsageAlertThreshold(20, with: 25)

        XCTAssertEqual(settings.usageAlertThresholdPercents, [25])
        XCTAssertEqual(settings.usageAlertSound(forThreshold: 25), .morse)

        settings.addUsageAlertThreshold(20)
        XCTAssertEqual(settings.usageAlertSound(forThreshold: 20), .frog)
    }

    @MainActor
    func testRemovingThresholdClearsItsSoundOverride() throws {
        let suiteName = "ModelMeterThresholdSoundRemovalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.usageAlertSound = .tink
        settings.setUsageAlertSound(.bottle, forThreshold: 20)

        settings.removeUsageAlertThreshold(20)
        settings.addUsageAlertThreshold(20)

        XCTAssertEqual(settings.usageAlertSound(forThreshold: 20), .tink)
        XCTAssertEqual(
            AppSettings(defaults: defaults).usageAlertSound(forThreshold: 20),
            .tink
        )
    }

    @MainActor
    func testZeroThresholdSupportsItsOwnPersistedSound() throws {
        let suiteName = "ModelMeterEmptyThresholdSoundTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.addUsageAlertThreshold(0)
        settings.setUsageAlertSound(.sosumi, forThreshold: 0)

        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.usageAlertThresholdPercents.contains(0))
        XCTAssertEqual(restored.usageAlertSound(forThreshold: 0), .sosumi)
    }
}
