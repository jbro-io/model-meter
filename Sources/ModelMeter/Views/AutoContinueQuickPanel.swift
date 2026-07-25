import SwiftUI

struct AutoContinueQuickPanel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AutoContinueController
    let openSettings: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .padding(.horizontal, 12)

            if settings.autoContinueEnabled {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(settings.providerDisplayOrder.providers) { provider in
                            providerCard(provider)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 410)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "bolt.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Auto-Continue is off")
                        .font(.headline)
                    Text("Enable it above, then enroll only the tabs you want Model Meter to resume.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 26)
            }

            Divider()
                .padding(.horizontal, 12)

            footer
        }
        .frame(width: 350)
        .background(.regularMaterial)
        .onAppear(perform: scanAllProviders)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: [.green, .teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Session Autopilot")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text("Resume enrolled tabs when quota returns")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Auto-Continue", isOn: $settings.autoContinueEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(12)
    }

    private func providerCard(_ provider: ProviderID) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: provider.systemImage)
                    .foregroundStyle(provider.tint)
                    .frame(width: 18)

                Text(provider.displayName)
                    .font(.headline)

                statusPill(for: provider)

                Spacer()

                Toggle(
                    "Enable \(provider.displayName)",
                    isOn: providerEnabledBinding(for: provider)
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if settings.autoContinueEnabled(for: provider) {
                Picker(
                    "Target scope",
                    selection: allSessionsBinding(for: provider)
                ) {
                    Text("Selected").tag(false)
                    Text("All matching").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)

                if settings.kittyAllSessions(for: provider) {
                    Label(
                        "Every live \(provider.displayName) tab",
                        systemImage: "rectangle.stack.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    sessionRows(for: provider)
                }
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(provider.tint.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(provider.tint.opacity(0.16), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private func sessionRows(for provider: ProviderID) -> some View {
        let sessions = controller.discoveredSessions[provider] ?? []

        if sessions.isEmpty {
            HStack(spacing: 7) {
                if controller.status(for: provider) == .scanning {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "scope")
                        .foregroundStyle(.secondary)
                }

                Text(emptyMessage(for: provider))
                    .font(.caption)
                    .foregroundStyle(
                        controller.status(for: provider).isFailure
                            ? Color.red
                            : Color.secondary
                    )
                    .lineLimit(2)

                Spacer(minLength: 4)

                Button {
                    controller.scanTargets(for: provider)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Scan \(provider.displayName) sessions")
                .disabled(controller.status(for: provider) == .scanning)
            }
        } else {
            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    Toggle(
                        isOn: sessionEnabledBinding(session.id, provider: provider)
                    ) {
                        HStack(spacing: 6) {
                            Text(session.displayTitle)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("#\(session.id)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .padding(.vertical, 5)

                    if session.id != sessions.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusPill(for provider: ProviderID) -> some View {
        if controller.isArmed(for: provider) {
            Label("Armed", systemImage: "bolt.fill")
                .foregroundStyle(.orange)
                .quickStatusPill()
        } else {
            switch controller.status(for: provider) {
            case .sent:
                Label("Sent", systemImage: "checkmark")
                    .foregroundStyle(.green)
                    .quickStatusPill()
            case .sending:
                Text("Sending…")
                    .foregroundStyle(.secondary)
                    .quickStatusPill()
            case .failed:
                Label("Issue", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .quickStatusPill()
            default:
                EmptyView()
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                scanAllProviders()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: openSettings) {
                Label("Full Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func scanAllProviders() {
        for provider in settings.providerDisplayOrder.providers
        where controller.status(for: provider) != .scanning {
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

    private func emptyMessage(for provider: ProviderID) -> String {
        switch controller.status(for: provider) {
        case .scanning:
            "Discovering live tabs…"
        case .failed(let message):
            message
        default:
            "No matching live tabs"
        }
    }
}

private extension View {
    func quickStatusPill() -> some View {
        font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

extension AutoContinueProviderStatus {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
