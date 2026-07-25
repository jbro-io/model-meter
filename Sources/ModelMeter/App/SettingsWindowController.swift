import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let frameName = "ModelMeterSettings"

    init(
        settings: AppSettings,
        store: UsageStore,
        alertController: UsageAlertController,
        autoContinueController: AutoContinueController
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Model Meter Settings"
        window.isReleasedWhenClosed = false
        window.animationBehavior = .documentWindow
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentMinSize = NSSize(width: 620, height: 420)
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                store: store,
                alertController: alertController,
                autoContinueController: autoContinueController
            )
        )

        if !window.setFrameUsingName(Self.frameName) {
            window.center()
        }

        super.init(window: window)
        windowFrameAutosaveName = Self.frameName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present() {
        guard let window else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
