import AppKit
import SwiftUI

@MainActor
final class CombinedDashboardWindowController: NSWindowController {
    static let frameName = "ModelMeterCombinedDashboard"
    let didRestoreFrame: Bool
    private(set) var hasBeenPresented = false

    init(
        store: UsageStore,
        settings: AppSettings,
        openSettings: @escaping @MainActor () -> Void,
        openProviderWindow: @escaping @MainActor (ProviderID) -> Void
    ) {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Model Meter — Combined"
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.animationBehavior = .utilityWindow
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentMinSize = NSSize(width: 390, height: 340)
        window.contentViewController = NSHostingController(
            rootView: CombinedProviderWindowView(
                store: store,
                settings: settings,
                openSettings: openSettings,
                openProviderWindow: openProviderWindow
            )
        )

        didRestoreFrame = window.setFrameUsingName(Self.frameName)

        super.init(window: window)
        windowFrameAutosaveName = Self.frameName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present(on screen: NSScreen?) {
        guard let window else { return }
        if !didRestoreFrame && !hasBeenPresented {
            if let visibleFrame = screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? NSScreen.screens.first?.visibleFrame {
                window.setFrame(
                    ProviderWindowLayout.centeredFrame(
                        size: window.frame.size,
                        in: visibleFrame
                    ),
                    display: false
                )
            } else {
                window.center()
            }
        }

        hasBeenPresented = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.level = .floating
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
