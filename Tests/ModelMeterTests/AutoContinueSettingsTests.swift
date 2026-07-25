import Foundation
import XCTest
@testable import ModelMeter

final class AutoContinueSettingsTests: XCTestCase {
    @MainActor
    func testSessionTargetingIsDefaultAndSelectionsPersistPerProvider() throws {
        let suiteName = "AutoContinueSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.autoContinueEnabled)
        XCTAssertFalse(settings.kittyAllSessions(for: .claude))
        XCTAssertFalse(settings.kittyAllSessions(for: .codex))
        XCTAssertTrue(settings.kittySessionIDs(for: .claude).isEmpty)
        XCTAssertEqual(settings.kittyMatch(for: .claude), "smart:claude")
        XCTAssertEqual(settings.kittyMatch(for: .codex), "smart:codex")

        settings.autoContinueEnabled = true
        settings.setKittySession(17, enabled: true, for: .claude)
        settings.setKittySession(22, enabled: true, for: .codex)
        settings.kittyCodexAllSessions = true

        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.autoContinueEnabled)
        XCTAssertEqual(restored.kittySessionIDs(for: .claude), [17])
        XCTAssertEqual(restored.kittySessionIDs(for: .codex), [22])
        XCTAssertFalse(restored.kittyAllSessions(for: .claude))
        XCTAssertTrue(restored.kittyAllSessions(for: .codex))
    }
}
