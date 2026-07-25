import AppKit
import SwiftUI

struct AutoContinueSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AutoContinueController
    @State private var showAdvancedSetup = false

    var body: some View {
        Section("Auto-Continue") {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume agents when the 5-hour window returns")
                        .font(.headline)
                    Text("Types “continue” and presses Return only after an observed exhaustion and recovery.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Enabled", isOn: $settings.autoContinueEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Enable Auto-Continue")
            }

            if settings.autoContinueEnabled {
                HStack {
                    Label("Terminal", systemImage: "terminal")
                    Spacer()
                    Picker("Terminal", selection: $settings.autoContinueTerminal) {
                        ForEach(AutoContinueTerminal.allCases) { terminal in
                            Text(terminal.title).tag(terminal)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                ForEach(settings.providerDisplayOrder.providers) { provider in
                    providerCard(provider)
                }

                DisclosureGroup("Kitty connection & advanced targeting", isExpanded: $showAdvancedSetup) {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Listen address") {
                            TextField(
                                "unix:/tmp/model-meter-kitty",
                                text: $settings.kittyListenAddress
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 330)
                        }

                        LabeledContent("Kitty executable") {
                            HStack(spacing: 8) {
                                TextField(
                                    "Auto-detect /Applications/kitty.app",
                                    text: $settings.kittyExecutablePath
                                )
                                .textFieldStyle(.roundedBorder)

                                Button("Choose…") {
                                    chooseKittyExecutable()
                                }
                                .controlSize(.small)
                            }
                            .frame(maxWidth: 430)
                        }

                        ForEach(settings.providerDisplayOrder.providers) { provider in
                            LabeledContent("\(provider.displayName) match") {
                                TextField(
                                    "cmdline:\(provider.rawValue)",
                                    text: kittyMatchBinding(for: provider)
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 330)
                            }
                        }

                        HStack {
                            Button {
                                copyKittyConfiguration()
                            } label: {
                                Label("Copy Kitty setup", systemImage: "doc.on.doc")
                            }
                            .controlSize(.small)

                            Text("Requires Kitty remote control over a local socket.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                }

                Text("Selected Sessions is the default. Session IDs are checked against live \(settings.autoContinueTerminal.title) windows matching that provider before any text is sent. Pending recovery survives a Model Meter restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func providerCard(_ provider: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(provider.displayName, systemImage: provider.systemImage)
                    .font(.headline)
                Spacer()
                Toggle(
                    "Auto-continue \(provider.displayName)",
                    isOn: providerEnabledBinding(for: provider)
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if settings.autoContinueEnabled(for: provider) {
                Picker(
                    "Target scope",
                    selection: allSessionsBinding(for: provider)
                ) {
                    Text("Selected Sessions").tag(false)
                    Text("All Sessions").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if settings.kittyAllSessions(for: provider) {
                    Label(
                        "Every open \(provider.displayName) session matching \(settings.kittyMatch(for: provider))",
                        systemImage: "rectangle.stack.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    sessionPicker(for: provider)
                }

                HStack(spacing: 10) {
                    statusView(for: provider)

                    Spacer()

                    Button {
                        controller.scanTargets(for: provider)
                    } label: {
                        Label("Scan", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .disabled(controller.status(for: provider) == .scanning)

                    Button("Send now") {
                        controller.sendNow(to: provider)
                    }
                    .controlSize(.small)
                    .help("Immediately type “continue” and Return into the enrolled session targets")
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func sessionPicker(for provider: ProviderID) -> some View {
        let sessions = controller.discoveredSessions[provider] ?? []
        let liveIDs = Set(sessions.map(\.id))
        let offlineIDs = settings.kittySessionIDs(for: provider).subtracting(liveIDs)
        if sessions.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(.secondary)
                Text("Scan to discover open \(provider.displayName) sessions, then enable the ones to resume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    Toggle(
                        isOn: sessionEnabledBinding(session.id, provider: provider)
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(session.displayTitle)
                                    .lineLimit(1)
                                Text("#\(session.id)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            if let directory = session.currentDirectory {
                                Text(abbreviatedPath(directory))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.vertical, 6)

                    if session.id != sessions.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.background.opacity(0.35))
            )
        }

        if controller.scannedProviders.contains(provider), !offlineIDs.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz")
                    .foregroundStyle(.secondary)
                Text(
                    offlineIDs.count == 1
                        ? "1 enrolled session is currently offline"
                        : "\(offlineIDs.count) enrolled sessions are currently offline"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Forget offline") {
                    for id in offlineIDs {
                        settings.setKittySession(id, enabled: false, for: provider)
                    }
                }
                .buttonStyle(.link)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func statusView(for provider: ProviderID) -> some View {
        let status = controller.status(for: provider)
        HStack(spacing: 6) {
            if controller.isArmed(for: provider), !status.isFailure {
                Image(systemName: "bolt.badge.clock.fill")
                    .foregroundStyle(.orange)
                if let resetAt = controller.pendingResetDate(for: provider) {
                    Text("Armed · \(resetAt.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("Armed · waiting for reset")
                }
            } else {
                switch status {
                case .idle:
                    Image(systemName: "circle")
                    Text("Not scanned")
                case .scanning:
                    ProgressView()
                        .controlSize(.mini)
                    Text("Scanning…")
                case .ready(let summary):
                    Image(
                        systemName: summary.windowCount > 0
                            ? "checkmark.circle.fill"
                            : "circle.dashed"
                    )
                    .foregroundStyle(
                        summary.windowCount > 0 ? Color.green : Color.secondary
                    )
                    Text(targetCountText(summary.windowCount))
                case .armed(let resetAt):
                    Image(systemName: "bolt.badge.clock.fill")
                        .foregroundStyle(.orange)
                    if let resetAt {
                        Text(
                            "Armed · \(resetAt.formatted(date: .omitted, time: .shortened))"
                        )
                    } else {
                        Text("Armed · waiting for reset")
                    }
                case .sending:
                    ProgressView()
                        .controlSize(.mini)
                    Text("Sending…")
                case .sent(let count, _):
                    Image(systemName: "paperplane.circle.fill")
                        .foregroundStyle(.green)
                    Text("Continued \(targetCountText(count))")
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .lineLimit(2)
                        .help(message)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(status.isFailure ? Color.red : Color.secondary)
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

    private func kittyMatchBinding(for provider: ProviderID) -> Binding<String> {
        switch provider {
        case .claude: $settings.kittyClaudeMatch
        case .codex: $settings.kittyCodexMatch
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

    private func targetCountText(_ count: Int) -> String {
        count == 1 ? "1 session" : "\(count) sessions"
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private func chooseKittyExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose Kitty executable"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.kittyExecutablePath = url.path
        }
    }

    private func copyKittyConfiguration() {
        let configuration = """
        # Model Meter Auto-Continue
        allow_remote_control socket-only
        listen_on \(settings.kittyListenAddress)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configuration, forType: .string)
    }
}

private extension AutoContinueProviderStatus {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
