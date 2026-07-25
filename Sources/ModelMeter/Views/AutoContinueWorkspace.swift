import SwiftUI

struct AutoContinueWorkspace: View {
    private static let sessionsPerPage = 8

    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AutoContinueController
    let close: @MainActor () -> Void
    let openSettings: @MainActor () -> Void

    @State private var sessionPages: [ProviderID: Int] = [:]

    var body: some View {
        VStack(spacing: 11) {
            header
            overviewStrip

            HStack(spacing: 11) {
                ForEach(settings.providerDisplayOrder.providers) { provider in
                    providerCard(provider)
                }
            }
            .frame(maxHeight: .infinity)

            footer
        }
        .padding(14)
        .onAppear(perform: scanAllProviders)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Button(action: close) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .modelMeterGlassButton()
            .help("Back to usage")
            .accessibilityLabel("Back to usage dashboard")

            Image(systemName: "terminal.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(
                        colors: [.green, .teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .shadow(color: .green.opacity(0.18), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("Session Autopilot")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text("Choose exactly where each agent wakes back up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(settings.autoContinueEnabled ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                    .shadow(
                        color: settings.autoContinueEnabled
                            ? Color.green.opacity(0.45)
                            : .clear,
                        radius: 4
                    )

                VStack(alignment: .trailing, spacing: 0) {
                    Text(settings.autoContinueEnabled ? "Autopilot on" : "Autopilot off")
                        .font(.caption.weight(.semibold))
                    Text("5-hour recovery only")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Toggle("Auto-Continue", isOn: $settings.autoContinueEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .modelMeterGlass(style: .clear, cornerRadius: 13)
        }
    }

    private var overviewStrip: some View {
        HStack(spacing: 0) {
            overviewMetric(
                title: connectionTitle,
                detail: settings.autoContinueTerminal.title,
                systemImage: connectionSystemImage,
                color: connectionColor
            )

            overviewDivider

            overviewMetric(
                title: "\(enrolledSessionCount) enrolled",
                detail: "Selected sessions",
                systemImage: "checkmark.square.fill",
                color: .blue
            )

            overviewDivider

            overviewMetric(
                title: armedProviderCount == 0
                    ? "No recovery queued"
                    : "\(armedProviderCount) recovery queued",
                detail: "5-hour windows",
                systemImage: "bolt.badge.clock.fill",
                color: armedProviderCount == 0 ? .secondary : .orange
            )
        }
        .padding(.vertical, 8)
        .modelMeterGlass(style: .clear, cornerRadius: 15)
    }

    private var overviewDivider: some View {
        Divider()
            .frame(height: 28)
    }

    private func overviewMetric(
        title: String,
        detail: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private func providerCard(_ provider: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            providerHeader(provider)

            if settings.autoContinueEnabled(for: provider) {
                Picker(
                    "Target scope",
                    selection: allSessionsBinding(for: provider)
                ) {
                    Text("Selected Sessions").tag(false)
                    Text("All Matching").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)

                Divider()

                if settings.kittyAllSessions(for: provider) {
                    allSessionsState(provider)
                } else {
                    selectedSessionsState(provider)
                }

                Divider()

                providerFooter(provider)
            } else {
                disabledProviderState(provider)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modelMeterGlass(
            style: .regular,
            tint: provider.tint.opacity(0.12),
            cornerRadius: 18
        )
    }

    private func providerHeader(_ provider: ProviderID) -> some View {
        HStack(spacing: 9) {
            Image(systemName: provider.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(provider.tint)
                .frame(width: 30, height: 30)
                .background(
                    provider.tint.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(provider.displayName)
                    .font(.headline)
                Text(providerSubtitle(provider))
                    .font(.caption2)
                    .foregroundStyle(
                        controller.status(for: provider).isFailure
                            ? Color.red
                            : Color.secondary
                    )
                    .lineLimit(1)
            }

            Spacer()

            providerStatusBadge(provider)

            Toggle(
                "Enable \(provider.displayName)",
                isOn: providerEnabledBinding(for: provider)
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func selectedSessionsState(_ provider: ProviderID) -> some View {
        let sessions = controller.discoveredSessions[provider] ?? []

        if sessions.isEmpty {
            VStack(spacing: 10) {
                if controller.status(for: provider) == .scanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(
                        systemName: controller.status(for: provider).isFailure
                            ? "exclamationmark.triangle.fill"
                            : "scope"
                    )
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(
                        controller.status(for: provider).isFailure
                            ? Color.red
                            : provider.tint
                    )
                }

                Text(emptyTitle(provider))
                    .font(.subheadline.weight(.semibold))

                Text(emptyDetail(provider))
                    .font(.caption)
                    .foregroundStyle(
                        controller.status(for: provider).isFailure
                            ? Color.red
                            : Color.secondary
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if controller.status(for: provider) != .scanning {
                    Button {
                        controller.scanTargets(for: provider)
                    } label: {
                        Label("Scan \(provider.displayName)", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
        } else {
            sessionGrid(sessions, provider: provider)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func sessionGrid(
        _ sessions: [KittySessionTarget],
        provider: ProviderID
    ) -> some View {
        let pageCount = max(
            1,
            Int(ceil(Double(sessions.count) / Double(Self.sessionsPerPage)))
        )
        let page = min(max(sessionPages[provider, default: 0], 0), pageCount - 1)
        let start = page * Self.sessionsPerPage
        let end = min(start + Self.sessionsPerPage, sessions.count)
        let visibleSessions = Array(sessions[start..<end])
        let columns = [
            GridItem(.flexible(), spacing: 7),
            GridItem(.flexible(), spacing: 7)
        ]

        return VStack(spacing: 8) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
                ForEach(visibleSessions) { session in
                    sessionTile(session, provider: provider)
                }
            }

            Spacer(minLength: 0)

            if pageCount > 1 {
                HStack(spacing: 8) {
                    Button {
                        sessionPages[provider] = max(page - 1, 0)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .disabled(page == 0)

                    Text("\(start + 1)–\(end) of \(sessions.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        sessionPages[provider] = min(page + 1, pageCount - 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(page == pageCount - 1)
                }
            }
        }
    }

    private func sessionTile(
        _ session: KittySessionTarget,
        provider: ProviderID
    ) -> some View {
        Toggle(
            isOn: sessionEnabledBinding(session.id, provider: provider)
        ) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.displayTitle)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    Text("#\(session.id)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Text(
                    session.currentDirectory.map(abbreviatedPath)
                        ?? "Live Kitty tab"
                )
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(
            settings.kittySessionIDs(for: provider).contains(session.id)
                ? provider.tint.opacity(0.085)
                : Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    settings.kittySessionIDs(for: provider).contains(session.id)
                        ? provider.tint.opacity(0.22)
                        : Color.primary.opacity(0.06),
                    lineWidth: 0.5
                )
        )
        .help(session.displayTitle)
    }

    private func allSessionsState(_ provider: ProviderID) -> some View {
        VStack(spacing: 12) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(provider.tint.opacity(0.07 + Double(index) * 0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(provider.tint.opacity(0.16), lineWidth: 0.5)
                        )
                        .frame(width: 90, height: 54)
                        .offset(x: CGFloat(index - 1) * 16)
                }

                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(provider.tint)
            }
            .frame(height: 72)

            Text("Every matching \(provider.displayName) tab")
                .font(.subheadline.weight(.semibold))

            Text("New sessions join automatically. Model Meter still validates every live target before typing anything.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text(settings.kittyMatch(for: provider))
                .font(.caption2.monospaced())
                .foregroundStyle(provider.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(provider.tint.opacity(0.08), in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    private func disabledProviderState(_ provider: ProviderID) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "power")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
            Text("\(provider.displayName) autopilot is off")
                .font(.subheadline.weight(.semibold))
            Text("Turn it on to select individual sessions or automatically target every matching tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    private func providerFooter(_ provider: ProviderID) -> some View {
        HStack(spacing: 8) {
            Button {
                sessionPages[provider] = 0
                controller.scanTargets(for: provider)
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(controller.status(for: provider) == .scanning)

            Spacer()

            if settings.kittyAllSessions(for: provider) {
                Text("Dynamic targeting")
            } else {
                let selectedCount = settings.kittySessionIDs(for: provider).count
                Text("\(selectedCount) selected")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func providerStatusBadge(_ provider: ProviderID) -> some View {
        if controller.isArmed(for: provider) {
            statusBadge("Armed", systemImage: "bolt.fill", color: .orange)
        } else {
            switch controller.status(for: provider) {
            case .scanning:
                ProgressView()
                    .controlSize(.mini)
            case .sent:
                statusBadge("Sent", systemImage: "checkmark", color: .green)
            case .failed:
                statusBadge(
                    "Issue",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .red
                )
            default:
                EmptyView()
            }
        }
    }

    private func statusBadge(
        _ title: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.09), in: Capsule())
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Local Kitty socket · exact window IDs · no terminal focus stealing")
            }

            Spacer()

            Button {
                scanAllProviders()
            } label: {
                Label("Scan All", systemImage: "arrow.clockwise")
            }
            .modelMeterGlassButton()
            .controlSize(.small)

            Button(action: openSettings) {
                Label("Full Settings", systemImage: "slider.horizontal.3")
            }
            .modelMeterGlassButton()
            .controlSize(.small)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var enrolledSessionCount: Int {
        ProviderID.allCases.reduce(0) {
            $0 + settings.kittySessionIDs(for: $1).count
        }
    }

    private var armedProviderCount: Int {
        ProviderID.allCases.filter { controller.isArmed(for: $0) }.count
    }

    private var connectionTitle: String {
        if ProviderID.allCases.contains(where: {
            controller.status(for: $0).isFailure
        }) {
            return "Connection issue"
        }
        if ProviderID.allCases.contains(where: {
            controller.status(for: $0) == .scanning
        }) {
            return "Scanning tabs"
        }
        if !controller.scannedProviders.isEmpty {
            return "Kitty linked"
        }
        return "Ready to scan"
    }

    private var connectionSystemImage: String {
        if ProviderID.allCases.contains(where: {
            controller.status(for: $0).isFailure
        }) {
            return "exclamationmark.triangle.fill"
        }
        if !controller.scannedProviders.isEmpty {
            return "checkmark.circle.fill"
        }
        return "terminal"
    }

    private var connectionColor: Color {
        if ProviderID.allCases.contains(where: {
            controller.status(for: $0).isFailure
        }) {
            return .red
        }
        if !controller.scannedProviders.isEmpty {
            return .green
        }
        return .secondary
    }

    private func providerSubtitle(_ provider: ProviderID) -> String {
        if !settings.autoContinueEnabled(for: provider) {
            return "Disabled"
        }
        if controller.isArmed(for: provider) {
            if let resetAt = controller.pendingResetDate(for: provider) {
                return "Wakes at \(resetAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Waiting for quota recovery"
        }
        switch controller.status(for: provider) {
        case .scanning:
            return "Discovering Kitty tabs…"
        case .ready(let summary):
            return summary.windowCount == 1
                ? "1 live session"
                : "\(summary.windowCount) live sessions"
        case .sent(let count, _):
            return count == 1 ? "Continued 1 session" : "Continued \(count) sessions"
        case .failed:
            return "Kitty connection needs attention"
        default:
            return settings.kittyAllSessions(for: provider)
                ? "All matching sessions"
                : "\(settings.kittySessionIDs(for: provider).count) enrolled"
        }
    }

    private func emptyTitle(_ provider: ProviderID) -> String {
        switch controller.status(for: provider) {
        case .scanning:
            return "Looking for \(provider.displayName)…"
        case .failed:
            return "Couldn’t reach matching sessions"
        default:
            return "No live \(provider.displayName) tabs"
        }
    }

    private func emptyDetail(_ provider: ProviderID) -> String {
        switch controller.status(for: provider) {
        case .failed(let message):
            return message
        case .scanning:
            return "Reading foreground processes and cleaned Kitty tab titles."
        default:
            return "Open \(provider.displayName) in Kitty, then scan again."
        }
    }

    private func scanAllProviders() {
        for provider in settings.providerDisplayOrder.providers
        where controller.status(for: provider) != .scanning {
            sessionPages[provider] = 0
            controller.scanTargets(for: provider)
        }
    }

    private func providerEnabledBinding(for provider: ProviderID) -> Binding<Bool> {
        switch provider {
        case .claude: $settings.autoContinueClaudeEnabled
        case .codex: $settings.autoContinueCodexEnabled
        }
    }

    private func allSessionsBinding(for provider: ProviderID) -> Binding<Bool> {
        switch provider {
        case .claude: $settings.kittyClaudeAllSessions
        case .codex: $settings.kittyCodexAllSessions
        }
    }

    private func sessionEnabledBinding(
        _ id: Int,
        provider: ProviderID
    ) -> Binding<Bool> {
        Binding(
            get: { settings.kittySessionIDs(for: provider).contains(id) },
            set: { settings.setKittySession(id, enabled: $0, for: provider) }
        )
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
