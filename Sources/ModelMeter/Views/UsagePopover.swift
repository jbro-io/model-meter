import AppKit
import SwiftUI

private enum HUDMetrics {
    static let cornerRadius: CGFloat = 8
    static let innerCornerRadius: CGFloat = 6
}

struct UsagePopover: View {
    static let dashboardSize = CGSize(width: 390, height: 680)
    static let sessionWorkspaceSize = CGSize(width: 700, height: 640)

    enum DashboardLayout {
        static let outerPadding: CGFloat = 6
        static let sectionSpacing: CGFloat = 6
        static let providerPadding: CGFloat = 1
        static let headerHeight: CGFloat = 38
        static let footerHeight: CGFloat = 24

        static var compactCardWidth: CGFloat {
            UsagePopover.dashboardSize.width
                - (outerPadding * 2)
                - (providerPadding * 2)
        }

        static var providerViewportHeight: CGFloat {
            UsagePopover.dashboardSize.height
                - (outerPadding * 2)
                - headerHeight
                - footerHeight
                - (sectionSpacing * 2)
        }
    }

    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var autoContinueController: AutoContinueController
    let openSettings: @MainActor () -> Void
    let openProviderWindow: @MainActor (ProviderID) -> Void
    let openCombinedWindow: @MainActor () -> Void
    let openAllProviderWindows: @MainActor () -> Void
    let resizePopover: @MainActor (CGSize) -> Void
    @State private var showsSessionManager = false

    init(
        store: UsageStore,
        settings: AppSettings,
        autoContinueController: AutoContinueController,
        openSettings: @escaping @MainActor () -> Void,
        openProviderWindow: @escaping @MainActor (ProviderID) -> Void,
        openCombinedWindow: @escaping @MainActor () -> Void,
        openAllProviderWindows: @escaping @MainActor () -> Void,
        resizePopover: @escaping @MainActor (CGSize) -> Void
    ) {
        self.store = store
        self.settings = settings
        self.autoContinueController = autoContinueController
        self.openSettings = openSettings
        self.openProviderWindow = openProviderWindow
        self.openCombinedWindow = openCombinedWindow
        self.openAllProviderWindows = openAllProviderWindows
        self.resizePopover = resizePopover
    }

    var body: some View {
        ZStack {
            ModelMeterBackdrop()

            if showsSessionManager {
                AutoContinueWorkspace(
                    settings: settings,
                    controller: autoContinueController,
                    close: hideSessionManager,
                    openSettings: {
                        hideSessionManager()
                        openSettings()
                    }
                )
                .transition(
                    .move(edge: .trailing)
                        .combined(with: .opacity)
                )
            } else {
                dashboardContent
                    .transition(
                        .move(edge: .leading)
                            .combined(with: .opacity)
                    )
            }
        }
        .frame(
            width: showsSessionManager
                ? Self.sessionWorkspaceSize.width
                : Self.dashboardSize.width,
            height: showsSessionManager
                ? Self.sessionWorkspaceSize.height
                : Self.dashboardSize.height
        )
        .clipped()
        .animation(.snappy(duration: 0.34), value: showsSessionManager)
        .onAppear {
            store.start()
            store.refreshIfStale()
            resizePopover(
                showsSessionManager
                    ? Self.sessionWorkspaceSize
                    : Self.dashboardSize
            )
        }
    }

    private var dashboardContent: some View {
        VStack(spacing: DashboardLayout.sectionSpacing) {
            header
                .zIndex(1)

            providerScrollView
                .zIndex(0)

            footer
                .zIndex(1)
        }
        .padding(DashboardLayout.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var providerCards: some View {
        ResponsiveProviderCards(
            store: store,
            settings: settings,
            openProviderWindow: openProviderWindow
        )
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(DashboardLayout.providerPadding)
    }

    @ViewBuilder
    private var providerScrollView: some View {
        let scrollView = ScrollView {
            providerCards
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled(false)
        .clipped()

        if #available(macOS 26.0, *) {
            scrollView.scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            scrollView
        }
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            HStack(spacing: 6) {
                HUDLogo()

                VStack(alignment: .leading, spacing: 1) {
                    Text("MODEL//METER")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .tracking(0.85)
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        Circle()
                            .fill(store.isRefreshing ? Color.cyan : Color.green)
                            .frame(width: 4, height: 4)
                            .shadow(
                                color: (store.isRefreshing ? Color.cyan : Color.green)
                                    .opacity(0.5),
                                radius: 2
                            )

                        Text(syncDescription(at: context.date))
                            .font(
                                .system(
                                    size: 7.5,
                                    weight: .medium,
                                    design: .monospaced
                                )
                            )
                            .tracking(0.35)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 94, alignment: .leading)

                Spacer(minLength: 0)

                HUDModeSwitch(selection: $settings.usageDisplayMode)

                HStack(spacing: 0) {
                    Menu {
                        Button(action: openCombinedWindow) {
                            Label("Combined Window", systemImage: "rectangle.split.2x1")
                        }

                        Button(action: openAllProviderWindows) {
                            Label(
                                "Separate Windows",
                                systemImage: "rectangle.on.rectangle.angled"
                            )
                        }
                    } label: {
                        HUDActionGlyph(systemImage: "rectangle.3.group")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28, height: 28)
                    .help("Open dashboard window")
                    .accessibilityLabel("Open dashboard window")

                    HUDRailDivider()

                    Button {
                        showSessionManager()
                    } label: {
                        HUDActionGlyph(
                            systemImage: "terminal",
                            statusColor: settings.autoContinueEnabled ? .green : .secondary
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    .help("Manage Auto-Continue sessions")
                    .accessibilityLabel("Manage Auto-Continue sessions")

                    HUDRailDivider()

                    Button {
                        store.refresh()
                    } label: {
                        HUDActionGlyph(
                            systemImage: "arrow.clockwise",
                            showsProgress: store.isRefreshing
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    .help("Refresh usage")
                    .disabled(store.isRefreshing)
                    .accessibilityLabel("Refresh usage")
                    .keyboardShortcut("r", modifiers: .command)
                }
                .background(
                    .primary.opacity(0.026),
                    in: RoundedRectangle(cornerRadius: HUDMetrics.cornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: HUDMetrics.cornerRadius)
                        .strokeBorder(.primary.opacity(0.09), lineWidth: 0.5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(height: DashboardLayout.headerHeight)
            .modelMeterGlass(style: .clear, cornerRadius: HUDMetrics.cornerRadius)
            .overlay {
                ModelMeterInstrumentFrame(
                    tint: .cyan,
                    cornerRadius: HUDMetrics.cornerRadius
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: openSettings) {
                Label("CONFIG", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)

            Spacer()

            Text("LOCAL TELEMETRY")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("QUIT", systemImage: "power")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .frame(height: DashboardLayout.footerHeight)
        .background(.primary.opacity(0.018))
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.cyan.opacity(0.55), .indigo.opacity(0.22), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.5)
        }
    }

    private func syncDescription(at date: Date) -> String {
        if store.isRefreshing { return "SYNC // ACTIVE" }
        guard let refreshedAt = store.lastCompletedRefresh else {
            return "SYNC // STANDBY"
        }

        let seconds = max(Int(date.timeIntervalSince(refreshedAt)), 0)
        if seconds < 60 { return "SYNC // \(seconds)S" }
        if seconds < 3_600 { return "SYNC // \(seconds / 60)M" }
        return "SYNC // \(seconds / 3_600)H"
    }

    private func showSessionManager() {
        resizePopover(Self.sessionWorkspaceSize)
        withAnimation(.snappy(duration: 0.34)) {
            showsSessionManager = true
        }
    }

    private func hideSessionManager() {
        withAnimation(.snappy(duration: 0.3)) {
            showsSessionManager = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !showsSessionManager else { return }
            resizePopover(Self.dashboardSize)
        }
    }
}

private struct HUDLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: HUDMetrics.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.cyan.opacity(0.16), .indigo.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(.primary.opacity(0.1), lineWidth: 2)
                .frame(width: 15, height: 15)

            Circle()
                .trim(from: 0, to: 0.68)
                .stroke(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 15, height: 15)
                .shadow(color: .cyan.opacity(0.35), radius: 2)

            Circle()
                .fill(.primary.opacity(0.72))
                .frame(width: 3, height: 3)
        }
        .frame(width: 24, height: 24)
        .overlay {
            RoundedRectangle(cornerRadius: HUDMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.cyan.opacity(0.2), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

private struct HUDModeSwitch: View {
    @Binding var selection: UsageDisplayMode

    var body: some View {
        HStack(spacing: 1) {
            ForEach(UsageDisplayMode.allCases) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.shortTitle.uppercased())
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(0.25)
                        .foregroundStyle(selection == mode ? Color.cyan : .secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            selection == mode ? Color.cyan.opacity(0.11) : .clear,
                            in: RoundedRectangle(
                                cornerRadius: HUDMetrics.innerCornerRadius,
                                style: .continuous
                            )
                        )
                        .overlay(alignment: .bottom) {
                            if selection == mode {
                                Capsule()
                                    .fill(.cyan)
                                    .frame(width: 13, height: 1)
                                    .shadow(color: .cyan.opacity(0.45), radius: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show quota \(mode.title.lowercased())")
            }
        }
        .padding(2)
        .frame(width: 70, height: 24)
        .background(
            .primary.opacity(0.026),
            in: RoundedRectangle(cornerRadius: HUDMetrics.cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HUDMetrics.cornerRadius)
                .strokeBorder(.primary.opacity(0.09), lineWidth: 0.5)
        }
        .help("Show quota used or amount left")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quota display")
        .accessibilityValue(selection.title)
    }
}

private struct HUDActionGlyph: View {
    let systemImage: String
    var statusColor: Color? = nil
    var showsProgress = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.78)
                    .tint(.cyan)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.78))
            }

            if let statusColor {
                Circle()
                    .fill(statusColor)
                    .frame(width: 4.5, height: 4.5)
                    .shadow(color: statusColor.opacity(0.45), radius: 1.5)
                    .offset(x: 1, y: -1)
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
}

private struct HUDRailDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.085))
            .frame(width: 0.5, height: 14)
            .accessibilityHidden(true)
    }
}
