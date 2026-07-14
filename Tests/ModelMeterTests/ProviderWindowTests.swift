import AppKit
import SwiftUI
import XCTest
@testable import ModelMeter

final class ProviderWindowTests: XCTestCase {
    @MainActor
    func testCombinedWindowIsReusableResponsiveFloatingPanel() throws {
        _ = NSApplication.shared
        let (settings, store, cleanup) = try makeServices()
        defer { cleanup() }

        let controller = CombinedDashboardWindowController(
            store: store,
            settings: settings,
            openSettings: {},
            openProviderWindow: { _ in }
        )
        let panel = try XCTUnwrap(controller.window as? NSPanel)

        XCTAssertEqual(panel.title, "Model Meter — Combined")
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertEqual(panel.contentMinSize, NSSize(width: 390, height: 340))
        XCTAssertEqual(
            controller.windowFrameAutosaveName,
            CombinedDashboardWindowController.frameName
        )

        let hostingController = try XCTUnwrap(
            panel.contentViewController as? NSHostingController<CombinedProviderWindowView>
        )
        XCTAssertTrue(hostingController.rootView.settings === settings)
        XCTAssertTrue(hostingController.rootView.store === store)

        let originalWindow = panel
        controller.close()
        XCTAssertTrue(controller.window === originalWindow)
    }

    @MainActor
    func testProviderWindowIsReusableTransparentFloatingPanel() throws {
        _ = NSApplication.shared
        let (settings, store, cleanup) = try makeServices()
        defer { cleanup() }
        let prefix = "ModelMeterProviderWindowTests.\(UUID().uuidString)"

        let controller = ProviderUsageWindowController(
            provider: .claude,
            store: store,
            settings: settings,
            frameAutosavePrefix: prefix,
            openSettings: {}
        )
        let panel = try XCTUnwrap(controller.window as? NSPanel)

        XCTAssertEqual(controller.provider, .claude)
        XCTAssertEqual(panel.title, "Claude — Model Meter")
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertEqual(panel.contentMinSize, NSSize(width: 390, height: 340))
        XCTAssertEqual(controller.providerFrameAutosaveName, "\(prefix).claude")
        XCTAssertEqual(controller.windowFrameAutosaveName, "\(prefix).claude")
        XCTAssertEqual(panel.frameAutosaveName, "\(prefix).claude")

        let hostingController = try XCTUnwrap(
            panel.contentViewController as? NSHostingController<ProviderWindowView>
        )
        XCTAssertEqual(hostingController.rootView.provider, .claude)
        XCTAssertTrue(hostingController.rootView.settings === settings)
        XCTAssertTrue(hostingController.rootView.store === store)

        let originalWindow = panel
        controller.close()
        XCTAssertTrue(controller.window === originalWindow)
    }

    @MainActor
    func testCoordinatorReusesOneControllerPerProvider() throws {
        _ = NSApplication.shared
        let (settings, store, cleanup) = try makeServices()
        defer { cleanup() }

        let coordinator = ProviderWindowCoordinator(
            store: store,
            settings: settings,
            frameAutosavePrefix: "ModelMeterCoordinatorTests.\(UUID().uuidString)",
            openSettings: {}
        )
        let firstClaude = coordinator.controller(for: .claude)
        let secondClaude = coordinator.controller(for: .claude)
        let codex = coordinator.controller(for: .codex)

        XCTAssertTrue(firstClaude === secondClaude)
        XCTAssertFalse(firstClaude === codex)
        XCTAssertEqual(coordinator.controllerCount, 2)
        XCTAssertTrue(coordinator.existingController(for: .claude) === firstClaude)
        XCTAssertTrue(coordinator.existingController(for: .codex) === codex)
        XCTAssertNotEqual(
            firstClaude.providerFrameAutosaveName,
            codex.providerFrameAutosaveName
        )

        firstClaude.close()
        XCTAssertNotNil(codex.window)
        XCTAssertTrue(coordinator.existingController(for: .codex) === codex)
        codex.close()
    }

    func testFirstOpenLayoutCentersTwoNonOverlappingWindows() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_200, height: 900)
        let size = NSSize(width: 410, height: 520)
        let frames = ProviderWindowLayout.sideBySideFrames(
            size: size,
            in: visibleFrame
        )

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 0.001)
        XCTAssertEqual(
            frames[1].minX - frames[0].maxX,
            ProviderWindowLayout.gap,
            accuracy: 0.001
        )
        XCTAssertEqual(
            (frames[0].minX + frames[1].maxX) / 2,
            visibleFrame.midX,
            accuracy: 0.001
        )
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
            XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
            XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
            XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
        }
    }

    @MainActor
    private func makeServices() throws -> (
        settings: AppSettings,
        store: UsageStore,
        cleanup: () -> Void
    ) {
        let suiteName = "ModelMeterProviderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = AppSettings(defaults: defaults)
        let store = UsageStore(settings: settings)
        return (
            settings,
            store,
            { defaults.removePersistentDomain(forName: suiteName) }
        )
    }
}
