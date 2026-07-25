import AppKit
import SwiftUI

struct UsagePopover: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var autoContinueController: AutoContinueController
    let openSettings: @MainActor () -> Void
    let openProviderWindow: @MainActor (ProviderID) -> Void
    let openCombinedWindow: @MainActor () -> Void
    let openAllProviderWindows: @MainActor () -> Void
    @State private var showsSessionManager = false

    init(
        store: UsageStore,
        settings: AppSettings,
        autoContinueController: AutoContinueController,
        openSettings: @escaping @MainActor () -> Void,
        openProviderWindow: @escaping @MainActor (ProviderID) -> Void,
        openCombinedWindow: @escaping @MainActor () -> Void,
        openAllProviderWindows: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.autoContinueController = autoContinueController
        self.openSettings = openSettings
        self.openProviderWindow = openProviderWindow
        self.openCombinedWindow = openCombinedWindow
        self.openAllProviderWindows = openAllProviderWindows
    }

    var body: some View {
        ZStack {
            ModelMeterBackdrop()
            dashboardContent
        }
        .frame(
            minWidth: 390,
            idealWidth: 390,
            maxWidth: 390,
            minHeight: 640,
            idealHeight: 640,
            maxHeight: 640
        )
        .onAppear {
            store.start()
            store.refreshIfStale()
        }
    }

    private var dashboardContent: some View {
        VStack(spacing: 12) {
            header
                .zIndex(1)

            providerScrollView
                .zIndex(0)

            footer
                .zIndex(1)
        }
        .padding(12)
    }

    @ViewBuilder
    private var providerScrollView: some View {
        let scrollView = ScrollView {
            ResponsiveProviderCards(
                store: store,
                settings: settings,
                openProviderWindow: openProviderWindow
            )
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
        }
        .scrollClipDisabled(false)
        .clipped()

        if #available(macOS 26.0, *) {
            scrollView.scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            scrollView
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    LinearGradient(
                        colors: [.blue, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .shadow(color: .blue.opacity(0.22), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("Model Meter")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Text(refreshDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 74, maxWidth: .infinity, alignment: .leading)

            Picker("Quota display", selection: $settings.usageDisplayMode) {
                ForEach(UsageDisplayMode.allCases) { mode in
                    Text(mode.shortTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .frame(width: 86)
            .help("Show quota used or amount left")
            .accessibilityLabel("Quota display")

            Menu {
                Button(action: openCombinedWindow) {
                    Label("Combined Window", systemImage: "rectangle.split.2x1")
                }

                Button(action: openAllProviderWindows) {
                    Label("Separate Windows", systemImage: "rectangle.on.rectangle.angled")
                }
            } label: {
                Image(systemName: "rectangle.on.rectangle.angled")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .controlSize(.small)
            .frame(width: 28, height: 28)
            .help("Open dashboard window")
            .accessibilityLabel("Open dashboard window")

            Button {
                showsSessionManager.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "terminal")

                    Circle()
                        .fill(settings.autoContinueEnabled ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(.background, lineWidth: 1))
                        .offset(x: 3, y: -2)
                }
            }
            .modelMeterGlassButton()
            .controlSize(.small)
            .frame(width: 28, height: 28)
            .help("Manage Auto-Continue sessions")
            .accessibilityLabel("Manage Auto-Continue sessions")
            .popover(isPresented: $showsSessionManager, arrowEdge: .bottom) {
                AutoContinueQuickPanel(
                    settings: settings,
                    controller: autoContinueController,
                    openSettings: {
                        showsSessionManager = false
                        openSettings()
                    }
                )
            }

            Button {
                store.refresh()
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .modelMeterGlassButton()
            .controlSize(.small)
            .frame(width: 28, height: 28)
            .help("Refresh usage")
            .disabled(store.isRefreshing)
            .accessibilityLabel("Refresh usage")
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .modelMeterGlass(style: .regular, cornerRadius: 18)
    }

    private var footer: some View {
        HStack {
            Button(action: openSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .modelMeterGlassButton()
            .controlSize(.small)
            .keyboardShortcut(",", modifiers: .command)

            Spacer()

            Button("Quit Model Meter") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: .command)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .modelMeterGlass(style: .clear, cornerRadius: 16)
    }

    private var refreshDescription: String {
        if store.isRefreshing { return "Reading both CLIs…" }
        guard let date = store.lastCompletedRefresh else { return "Waiting for first refresh" }
        return "Updated \(date.formatted(.relative(presentation: .named)))"
    }
}
