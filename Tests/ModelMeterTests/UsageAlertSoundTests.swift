import XCTest
@testable import ModelMeter

final class UsageAlertSoundTests: XCTestCase {
    func testCatalogContainsStandardMacOSSoundsInPickerOrder() {
        XCTAssertEqual(
            UsageAlertSound.allCases,
            [
                .defaultSound,
                .basso,
                .blow,
                .bottle,
                .frog,
                .funk,
                .glass,
                .hero,
                .morse,
                .ping,
                .pop,
                .purr,
                .sosumi,
                .submarine,
                .tink,
                .none,
            ]
        )

        XCTAssertEqual(
            UsageAlertSound.allCases.map(\.title),
            [
                "System Default",
                "Basso",
                "Blow",
                "Bottle",
                "Frog",
                "Funk",
                "Glass",
                "Hero",
                "Morse",
                "Ping",
                "Pop",
                "Purr",
                "Sosumi",
                "Submarine",
                "Tink",
                "None",
            ]
        )
    }

    func testNamedSoundsMapToBundledAIFFFiles() {
        XCTAssertEqual(
            UsageAlertSound.allCases.map(\.bundledFileName),
            [
                nil,
                "Basso.aiff",
                "Blow.aiff",
                "Bottle.aiff",
                "Frog.aiff",
                "Funk.aiff",
                "Glass.aiff",
                "Hero.aiff",
                "Morse.aiff",
                "Ping.aiff",
                "Pop.aiff",
                "Purr.aiff",
                "Sosumi.aiff",
                "Submarine.aiff",
                "Tink.aiff",
                nil,
            ]
        )
    }

    @MainActor
    func testNamedSoundChoicePersists() throws {
        let suiteName = "ModelMeterSoundSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.usageAlertSound = .glass

        XCTAssertEqual(AppSettings(defaults: defaults).usageAlertSound, .glass)
        XCTAssertEqual(defaults.string(forKey: "usageAlertSound"), "glass")
    }
}
