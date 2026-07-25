import AppKit
import SwiftUI

enum ProviderWindowLayout {
    static let gap: CGFloat = 14

    static func centeredFrame(size: NSSize, in visibleFrame: NSRect) -> NSRect {
        constrained(
            NSRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            to: visibleFrame
        )
    }

    static func sideBySideFrames(size: NSSize, in visibleFrame: NSRect) -> [NSRect] {
        let totalWidth = size.width * 2 + gap
        guard totalWidth <= visibleFrame.width else {
            let first = centeredFrame(size: size, in: visibleFrame)
            let second = constrained(first.offsetBy(dx: 28, dy: -28), to: visibleFrame)
            return [first, second]
        }

        let first = NSRect(
            x: visibleFrame.midX - totalWidth / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let second = first.offsetBy(dx: size.width + gap, dy: 0)
        return [
            constrained(first, to: visibleFrame),
            constrained(second, to: visibleFrame)
        ]
    }

    static func adjacentFrame(
        size: NSSize,
        to anchor: NSRect,
        in visibleFrame: NSRect
    ) -> NSRect {
        let right = NSRect(
            x: anchor.maxX + gap,
            y: anchor.minY,
            width: size.width,
            height: size.height
        )
        if right.maxX <= visibleFrame.maxX {
            return constrained(right, to: visibleFrame)
        }

        let left = NSRect(
            x: anchor.minX - gap - size.width,
            y: anchor.minY,
            width: size.width,
            height: size.height
        )
        if left.minX >= visibleFrame.minX {
            return constrained(left, to: visibleFrame)
        }

        return constrained(anchor.offsetBy(dx: 28, dy: -28), to: visibleFrame)
    }

    static func constrained(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        var result = frame
        result.size.width = min(result.width, visibleFrame.width)
        result.size.height = min(result.height, visibleFrame.height)
        result.origin.x = min(
            max(result.minX, visibleFrame.minX),
            visibleFrame.maxX - result.width
        )
        result.origin.y = min(
            max(result.minY, visibleFrame.minY),
            visibleFrame.maxY - result.height
        )
        return result
    }
}

@MainActor
final class ProviderUsageWindowController: NSWindowController {
    static let initialContentSize = NSSize(width: 410, height: 520)

    let provider: ProviderID
    let didRestoreFrame: Bool
    let providerFrameAutosaveName: String
    private(set) var hasBeenPresented = false

    init(
        provider: ProviderID,
        store: UsageStore,
        settings: AppSettings,
        frameAutosavePrefix: String = "ModelMeterFloatingProvider",
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.provider = provider

        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "\(provider.displayName) — Model Meter"
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
            rootView: ProviderWindowView(
                provider: provider,
                store: store,
                settings: settings,
                openSettings: openSettings
            )
        )

        let frameName = "\(frameAutosavePrefix).\(provider.rawValue)"
        providerFrameAutosaveName = frameName
        didRestoreFrame = window.setFrameUsingName(frameName)

        super.init(window: window)
        windowFrameAutosaveName = frameName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present() {
        guard let window else { return }
        hasBeenPresented = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.level = .floating
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class ProviderWindowCoordinator {
    private let store: UsageStore
    private let settings: AppSettings
    private let frameAutosavePrefix: String
    private let openSettings: @MainActor () -> Void
    private var controllers: [ProviderID: ProviderUsageWindowController] = [:]

    init(
        store: UsageStore,
        settings: AppSettings,
        frameAutosavePrefix: String = "ModelMeterFloatingProvider",
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.frameAutosavePrefix = frameAutosavePrefix
        self.openSettings = openSettings
    }

    var controllerCount: Int { controllers.count }

    func existingController(for provider: ProviderID) -> ProviderUsageWindowController? {
        controllers[provider]
    }

    @discardableResult
    func controller(for provider: ProviderID) -> ProviderUsageWindowController {
        if let controller = controllers[provider] {
            return controller
        }

        let controller = ProviderUsageWindowController(
            provider: provider,
            store: store,
            settings: settings,
            frameAutosavePrefix: frameAutosavePrefix,
            openSettings: openSettings
        )
        controllers[provider] = controller
        return controller
    }

    func present(_ provider: ProviderID, on screen: NSScreen?) {
        let controller = controller(for: provider)
        let visibleFrame = preferredVisibleFrame(on: screen)

        if !controller.didRestoreFrame && !controller.hasBeenPresented {
            if let visibleFrame, let window = controller.window {
                window.setFrame(
                    ProviderWindowLayout.centeredFrame(size: window.frame.size, in: visibleFrame),
                    display: false
                )
            } else {
                controller.window?.center()
            }
        } else {
            ensureVisible(controller, preferredVisibleFrame: visibleFrame)
        }

        controller.present()
    }

    func presentAll(on screen: NSScreen?) {
        let pair = settings.providerDisplayOrder.providers.map(controller(for:))
        let visibleFrame = preferredVisibleFrame(on: screen)

        if let visibleFrame {
            let unplaced = pair.filter { !$0.didRestoreFrame && !$0.hasBeenPresented }

            if unplaced.count == pair.count {
                let frames = ProviderWindowLayout.sideBySideFrames(
                    size: pair.first?.window?.frame.size
                        ?? ProviderUsageWindowController.initialContentSize,
                    in: visibleFrame
                )
                for (controller, frame) in zip(pair, frames) {
                    controller.window?.setFrame(frame, display: false)
                }
            } else if unplaced.count == 1,
                      let newController = unplaced.first,
                      let anchor = pair.first(where: { $0 !== newController })?.window?.frame,
                      let window = newController.window {
                window.setFrame(
                    ProviderWindowLayout.adjacentFrame(
                        size: window.frame.size,
                        to: anchor,
                        in: visibleFrame
                    ),
                    display: false
                )
            }

            for controller in pair where !unplaced.contains(where: { $0 === controller }) {
                ensureVisible(controller, preferredVisibleFrame: visibleFrame)
            }
        }

        pair.forEach { $0.present() }
    }

    private func preferredVisibleFrame(on screen: NSScreen?) -> NSRect? {
        screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
    }

    private func ensureVisible(
        _ controller: ProviderUsageWindowController,
        preferredVisibleFrame: NSRect?
    ) {
        guard let window = controller.window else { return }
        let isVisibleOnAttachedScreen = NSScreen.screens.contains { screen in
            let intersection = screen.visibleFrame.intersection(window.frame)
            return intersection.width >= 80 && intersection.height >= 80
        }

        guard !isVisibleOnAttachedScreen, let preferredVisibleFrame else { return }
        window.setFrame(
            ProviderWindowLayout.centeredFrame(size: window.frame.size, in: preferredVisibleFrame),
            display: false
        )
    }
}
