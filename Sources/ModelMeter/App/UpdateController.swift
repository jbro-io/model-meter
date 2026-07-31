import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateController: NSObject, ObservableObject {
    @Published private(set) var availableVersion: String?

    private var standardUpdaterController: SPUStandardUpdaterController?

    init(startingUpdater: Bool = true) {
        super.init()

        guard startingUpdater,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        standardUpdaterController = controller

        controller.updater.automaticallyChecksForUpdates = true
        controller.updater.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
        standardUpdaterController?.checkForUpdates(nil)
    }

    func recordUpdateAvailable(version: String) {
        availableVersion = version
    }

    func recordNoUpdateAvailable() {
        availableVersion = nil
    }
}

extension UpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        recordUpdateAvailable(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        recordNoUpdateAvailable()
    }

    func updater(
        _ updater: SPUUpdater,
        userDidSkipThisVersion item: SUAppcastItem
    ) {
        recordNoUpdateAvailable()
    }
}

extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        recordUpdateAvailable(version: update.displayVersionString)
    }
}
