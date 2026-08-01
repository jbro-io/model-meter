import Foundation
import XCTest
@testable import ModelMeter

final class AppSettingsTests: XCTestCase {
    @MainActor
    func testRefreshDefaultsToOneMinuteAndPreservesExplicitSelection() throws {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.refreshMinutes, 1)

        settings.refreshMinutes = 10
        XCTAssertEqual(AppSettings(defaults: defaults).refreshMinutes, 10)
    }
}
