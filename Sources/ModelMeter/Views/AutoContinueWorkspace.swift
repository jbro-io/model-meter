import SwiftUI

struct AutoContinueWorkspace: View {
    private static let sessionsPerPage = 5

    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AutoContinueController
    let close: @MainActor () -> Void
    let openSettings: @MainActor () -> Void

    @State private var selectedProvider: ProviderID = .claude
    @State private var sessionPages: [ProviderID: Int] = [:]

    var body: some View {
        VStack(spacing: 11) {
            header
            providerSelector
            providerWorkspace(selectedProvider)
                .id(selectedProvider)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            footer
        }
        .padding(14)
        .animation(.snappy(duration: 0.24), value: selectedProvider)
        .onAppear {
            selectedProvider = settings.providerDisplayOrder.providers.first ?? .claude
            scanAllProviders()
        }
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
                Text("Full-width targeting for every live agent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                Image(systemName: connectionSystemImage)
                    .foregroundStyle(connectionColor)
                Text(connectionTitle)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(connectionColor.opacity(0.08), in: Capsule())

            HStack(spacing: 8) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .modelMeterGlass(style: .clear, cornerRadius: 13)
        }
    }

    private var providerSelector: some View {
        HStack(spacing: 8) {
            ForEach(settings.providerDisplayOrder.providers) { provider in
                Button {
                    selectedProvider = provider
                } label: {
                    HStack(spacing: 9) {
                        ProviderBrandIcon(provider: provider, size: 27)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(provider.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(providerTabDetail(provider))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if controller.isArmed(for: provider) {
                            Label("Armed", systemImage: "bolt.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        } else {
                            Circle()
                                .fill(
                                    settings.autoContinueEnabled(for: provider)
                                        ? Color.green
                                        : Color.secondary.opacity(0.5)
                                )
                                .frame(width: 7, height: 7)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(
                                selectedProvider == provider
                                    ? provider.tint
                                    : Color.secondary.opacity(0.45)
                            )
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        selectedProvider == provider
                            ? provider.tint.opacity(0.09)
                            : Color.primary.opacity(0.025),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(
                                selectedProvider == provider
                                    ? provider.tint.opacity(0.28)
                                    : Color.primary.opacity(0.07),
                                lineWidth: selectedProvider == provider ? 1 : 0.5
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func providerWorkspace(_ provider: ProviderID) -> some View {
        VStack(spacing: 10) {
            providerCommandBar(provider)

            Divider()

            if !settings.autoContinueEnabled(for: provider) {
                disabledState(provider)
            } else if settings.kittyAllSessions(for: provider) {
                allSessionsState(provider)
            } else {
                selectedSessionsState(provider)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modelMeterGlass(
            style: .regular,
            tint: provider.tint.opacity(0.1),
            cornerRadius: 18
        )
    }

    private func providerCommandBar(_ provider: ProviderID) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("\(provider.displayName) targets")
                        .font(.headline)
                    providerStatusBadge(provider)
                }

                Text(providerSubtitle(provider))
                    .font(.caption)
                    .foregroundStyle(
                        controller.status(for: provider).isFailure
                            ? Color.red
                            : Color.secondary
                    )
                    .lineLimit(1)
            }

            Spacer()

            Toggle(
                "Enable \(provider.displayName)",
                isOn: providerEnabledBinding(for: provider)
            )
            .toggleStyle(.switch)
            .controlSize(.small)

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
            .frame(width: 250)
            .disabled(!settings.autoContinueEnabled(for: provider))
        }
    }

    @ViewBuilder
    private func selectedSessionsState(_ provider: ProviderID) -> some View {
        let sessions = controller.discoveredSessions[provider] ?? []

        if sessions.isEmpty {
            emptyState(provider)
        } else {
            sessionList(sessions, provider: provider)
        }
    }

    private func sessionList(
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
        let selectedCount = settings.kittySessionIDs(for: provider).count

        return VStack(spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("LIVE SESSION TARGETS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.7)
                    Text("Click anywhere on a row to enroll or remove it.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("\(selectedCount) enrolled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        selectedCount > 0 ? provider.tint : Color.secondary
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (selectedCount > 0 ? provider.tint : Color.secondary)
                            .opacity(0.08),
                        in: Capsule()
                    )

                if pageCount > 1 {
                    HStack(spacing: 7) {
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

                Button {
                    sessionPages[provider] = 0
                    controller.scanTargets(for: provider)
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .modelMeterGlassButton()
                .controlSize(.small)
                .disabled(controller.status(for: provider) == .scanning)
            }

            ForEach(visibleSessions) { session in
                AutoContinueSessionRow(
                    session: session,
                    provider: provider,
                    isEnrolled: sessionEnabledBinding(
                        session.id,
                        provider: provider
                    )
                )
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func emptyState(_ provider: ProviderID) -> some View {
        VStack(spacing: 10) {
            if controller.status(for: provider) == .scanning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(
                    systemName: controller.status(for: provider).isFailure
                        ? "exclamationmark.triangle.fill"
                        : "rectangle.and.text.magnifyingglass"
                )
                .font(.system(size: 27, weight: .light))
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
        .padding(.horizontal, 28)
    }

    private func allSessionsState(_ provider: ProviderID) -> some View {
        HStack(spacing: 24) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(provider.tint.opacity(0.07 + Double(index) * 0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(provider.tint.opacity(0.17), lineWidth: 0.6)
                        )
                        .frame(width: 128, height: 76)
                        .offset(x: CGFloat(index - 1) * 24)
                }

                Image(systemName: "bolt.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(provider.tint)
            }
            .frame(width: 190)

            VStack(alignment: .leading, spacing: 8) {
                Text("Dynamic \(provider.displayName) targeting")
                    .font(.title3.weight(.semibold))
                Text("Every current and future matching tab is eligible. Model Meter validates live window IDs immediately before sending and never steals terminal focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(settings.kittyMatch(for: provider))
                    .font(.caption.monospaced())
                    .foregroundStyle(provider.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(provider.tint.opacity(0.08), in: Capsule())
            }

            Spacer()

            Button {
                controller.scanTargets(for: provider)
            } label: {
                Label("Validate Targets", systemImage: "checkmark.shield")
            }
            .modelMeterGlassButton()
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 34)
    }

    private func disabledState(_ provider: ProviderID) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "power")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.secondary)
            Text("\(provider.displayName) autopilot is off")
                .font(.title3.weight(.semibold))
            Text("Enable this provider above to enroll individual sessions or dynamically target every matching tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
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
                Text("Local Kitty socket · exact window IDs · no focus stealing")
            }

            Spacer()

            Text("\(enrolledSessionCount) total enrolled")
                .monospacedDigit()

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

    private func providerTabDetail(_ provider: ProviderID) -> String {
        let liveCount = controller.discoveredSessions[provider]?.count ?? 0
        if controller.status(for: provider) == .scanning {
            return "Scanning live tabs…"
        }
        if !settings.autoContinueEnabled(for: provider) {
            return "Autopilot disabled"
        }
        if settings.kittyAllSessions(for: provider) {
            return "\(liveCount) live · all matching"
        }
        let enrolled = settings.kittySessionIDs(for: provider).count
        return "\(liveCount) live · \(enrolled) enrolled"
    }

    private func providerSubtitle(_ provider: ProviderID) -> String {
        if controller.isArmed(for: provider) {
            if let resetAt = controller.pendingResetDate(for: provider) {
                return "Armed for \(resetAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Armed and waiting for the 5-hour quota to recover"
        }
        switch controller.status(for: provider) {
        case .scanning:
            return "Reading foreground processes and cleaned Kitty tab titles…"
        case .ready(let summary):
            return summary.windowCount == 1
                ? "1 live session found"
                : "\(summary.windowCount) live sessions found"
        case .sent(let count, _):
            return count == 1 ? "Continued 1 session" : "Continued \(count) sessions"
        case .failed(let message):
            return message
        default:
            return settings.kittyAllSessions(for: provider)
                ? "Every matching session is eligible"
                : "\(settings.kittySessionIDs(for: provider).count) sessions enrolled"
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
}

private struct AutoContinueSessionRow: View {
    let session: KittySessionTarget
    let provider: ProviderID
    @Binding var isEnrolled: Bool

    @State private var isHovering = false

    var body: some View {
        Button {
            isEnrolled.toggle()
        } label: {
            HStack(spacing: 12) {
                selectionControl

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.displayTitle)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 9, weight: .medium))
                        Text(
                            session.currentDirectory.map(abbreviatedPath)
                                ?? "Live Kitty session"
                        )
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Text("LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.08), in: Capsule())

                Text("WINDOW #\(session.id)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .trailing)

                Text(isEnrolled ? "ENROLLED" : "AVAILABLE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(
                        isEnrolled ? provider.tint : Color.secondary
                    )
                    .frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isEnrolled
                            ? provider.tint.opacity(0.3)
                            : Color.primary.opacity(isHovering ? 0.13 : 0.065),
                        lineWidth: isEnrolled ? 1 : 0.6
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(
            isEnrolled
                ? "Remove \(session.displayTitle) from Auto-Continue"
                : "Enroll \(session.displayTitle) in Auto-Continue"
        )
        .accessibilityLabel(
            "\(session.displayTitle), window \(session.id), "
                + (isEnrolled ? "enrolled" : "not enrolled")
        )
    }

    @ViewBuilder
    private var selectionControl: some View {
        ZStack {
            if isEnrolled {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [provider.tint, provider.tint.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: provider.tint.opacity(0.22), radius: 3, y: 1)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.055 : 0.025))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isHovering
                            ? provider.tint.opacity(0.55)
                            : Color.secondary.opacity(0.35),
                        lineWidth: 1
                    )
                Circle()
                    .fill(Color.secondary.opacity(0.38))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: 25, height: 25)
    }

    private var rowBackground: Color {
        if isEnrolled {
            return provider.tint.opacity(0.075)
        }
        if isHovering {
            return provider.tint.opacity(0.035)
        }
        return Color.primary.opacity(0.018)
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
