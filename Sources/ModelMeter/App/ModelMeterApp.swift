import AppKit
import Combine
import SwiftUI

@MainActor
private final class AppServices {
    static let shared = AppServices()

    let settings: AppSettings
    let store: UsageStore
    let alertController: UsageAlertController

    private init() {
        let settings = AppSettings()
        self.settings = settings
        let store = UsageStore(settings: settings)
        self.store = store
        alertController = UsageAlertController(settings: settings, store: store)
    }
}

@main
@MainActor
struct ModelMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let services = AppServices.shared

    var body: some Scene {
        Settings {
            SettingsView(
                settings: services.settings,
                store: services.store,
                alertController: services.alertController
            )
        }
    }
}

@MainActor
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = AppServices.shared
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var statusHostingView: NSView?
    private var settingsWindowController: SettingsWindowController?
    private var combinedWindowController: CombinedDashboardWindowController?
    private var stateCancellable: AnyCancellable?
    private lazy var providerWindowCoordinator = ProviderWindowCoordinator(
        store: services.store,
        settings: services.settings,
        openSettings: { [weak self] in
            self?.showSettings()
        }
    )

    func applicationWillFinishLaunching(_ notification: Notification) {
        services.alertController.activate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Model Meter menu-bar utility")
        configureStatusItem()
        configurePopover()
        observeUsage()
        services.store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.store.stop()
        services.alertController.deactivate()
        ProcessInfo.processInfo.enableAutomaticTermination("Model Meter menu-bar utility")
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            services.store.refreshIfStale()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func showProviderWindow(_ provider: ProviderID) {
        popover.performClose(nil)
        providerWindowCoordinator.present(provider, on: presentationScreen)
    }

    private func showCombinedWindow() {
        popover.performClose(nil)

        if combinedWindowController == nil {
            combinedWindowController = CombinedDashboardWindowController(
                store: services.store,
                settings: services.settings,
                openSettings: { [weak self] in
                    self?.showSettings()
                },
                openProviderWindow: { [weak self] provider in
                    self?.showProviderWindow(provider)
                }
            )
        }
        combinedWindowController?.present(on: presentationScreen)
    }

    private func showAllProviderWindows() {
        popover.performClose(nil)
        providerWindowCoordinator.presentAll(on: presentationScreen)
    }

    private var presentationScreen: NSScreen? {
        statusItem?.button?.window?.screen ?? NSApplication.shared.keyWindow?.screen ?? NSScreen.main
    }

    private func showSettings() {
        popover.performClose(nil)

        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: services.settings,
                store: services.store,
                alertController: services.alertController
            )
        }
        settingsWindowController?.present()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: StatusItemDashboard.minimumWidth
        )
        item.autosaveName = "ModelMeterStatusItem"
        item.behavior = []
        item.isVisible = true

        guard let button = item.button else {
            statusItem = item
            return
        }

        button.image = nil
        button.title = ""
        button.toolTip = "Model Meter — usage unavailable"
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        let hostingView = PassthroughHostingView(
            rootView: StatusItemDashboard(
                store: services.store,
                settings: services.settings
            )
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        statusHostingView = hostingView
        statusItem = item
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 390, height: 640)
        popover.contentViewController = NSHostingController(
            rootView: UsagePopover(
                store: services.store,
                settings: services.settings,
                openSettings: { [weak self] in
                    self?.showSettings()
                },
                openProviderWindow: { [weak self] provider in
                    self?.showProviderWindow(provider)
                },
                openCombinedWindow: { [weak self] in
                    self?.showCombinedWindow()
                },
                openAllProviderWindows: { [weak self] in
                    self?.showAllProviderWindows()
                }
            )
        )
    }

    private func observeUsage() {
        stateCancellable = Publishers.CombineLatest(
            services.store.$states,
            services.settings.$usageDisplayMode
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] states, displayMode in
                self?.updateStatusItem(with: states, displayMode: displayMode)
            }
    }

    private func updateStatusItem(
        with states: [ProviderID: ProviderLoadState],
        displayMode: UsageDisplayMode
    ) {
        guard let button = statusItem?.button else { return }
        let rows = StatusItemPresentation.rows(
            states: states,
            displayMode: displayMode
        )
        statusItem?.length = StatusItemDashboard.preferredWidth(for: rows)

        let details = rows.map { row in
            if let percent = row.displayedPercent {
                return "\(row.provider.displayName) \(row.windowLabel): \(percent)% \(displayMode.metricWord)"
            }
            if row.isLoading {
                return "\(row.provider.displayName): refreshing"
            }
            if row.hasError {
                return "\(row.provider.displayName): usage unavailable"
            }
            return "\(row.provider.displayName): waiting for usage"
        }
        let summary = details.joined(separator: "\n")
        button.toolTip = "Model Meter\n\(summary)"
        button.setAccessibilityLabel(
            "Model Meter. \(details.joined(separator: ". "))"
        )
    }
}
