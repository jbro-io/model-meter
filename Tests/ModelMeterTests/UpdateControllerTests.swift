import XCTest
@testable import ModelMeter

@MainActor
final class UpdateControllerTests: XCTestCase {
    func testAvailabilityTracksFoundAndClearedUpdates() {
        let controller = UpdateController(startingUpdater: false)

        XCTAssertNil(controller.availableVersion)

        controller.recordUpdateAvailable(version: "0.11.2")
        XCTAssertEqual(controller.availableVersion, "0.11.2")

        controller.recordNoUpdateAvailable()
        XCTAssertNil(controller.availableVersion)
    }
}
