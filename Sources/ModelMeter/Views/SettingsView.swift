import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    @ObservedObject var alertController: UsageAlertController
    @ObservedObject var autoContinueController: AutoContinueController
    let checkForUpdates: @MainActor () -> Void
    @State private var soundImportError: String?

    var body: some View {
        ZStack {
            ModelMeterBackdrop()

            Form {
                Section("Presentation") {
                    Picker("Show quota as", selection: $settings.usageDisplayMode) {
                        ForEach(UsageDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)

                    Picker("Model order", selection: $settings.providerDisplayOrder) {
                        ForEach(ProviderDisplayOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)

                    Text("Model order applies to the menu bar, popover, combined dashboard, and separate-window layout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("CLI executables") {
                    executableRow(
                        name: "Claude",
                        placeholder: "Auto-detect claude",
                        path: $settings.claudePath
                    )
                    executableRow(
                        name: "Codex",
                        placeholder: "Auto-detect codex",
                        path: $settings.codexPath
                    )

                    Text("Leave a path empty to search ~/.local/bin, Homebrew, /usr/local/bin, and PATH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Refresh") {
                    Picker("Check every", selection: $settings.refreshMinutes) {
                        ForEach(AppSettings.allowedRefreshMinutes, id: \.self) { minutes in
                            Text(minutes == 1 ? "1 minute" : "\(minutes) minutes")
                                .tag(minutes)
                        }
                    }
                    .frame(maxWidth: 220)

                    Button("Refresh now") {
                        store.refresh()
                    }
                    .modelMeterGlassButton()
                    .controlSize(.small)
                    .disabled(store.isRefreshing)
                }

                Section("Updates") {
                    LabeledContent("Installed version") {
                        Text(installedVersion)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        checkForUpdates()
                    } label: {
                        Label(
                            "Check for Updates…",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .modelMeterGlassButton()
                    .controlSize(.small)

                    Text("Model Meter can check GitHub Releases and securely install signed updates without downloading or rebuilding the project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                AutoContinueSettingsSection(
                    settings: settings,
                    controller: autoContinueController
                )

                Section("Usage alerts") {
                    Toggle(
                        "Notify me when quota is running low",
                        isOn: Binding(
                            get: { settings.usageAlertsEnabled },
                            set: { alertController.setAlertsEnabled($0) }
                        )
                    )

                    if settings.usageAlertThresholdPercents.isEmpty {
                        Text("No alert thresholds configured.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(settings.usageAlertThresholdPercents, id: \.self) { threshold in
                            HStack {
                                Text(threshold == 0 ? "At" : "Below")

                                Picker(
                                    "Threshold",
                                    selection: thresholdBinding(for: threshold)
                                ) {
                                    ForEach(selectableThresholds(replacing: threshold), id: \.self) {
                                        value in
                                        Text("\(value)%").tag(value)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 82)

                                Text("remaining")

                                Spacer()

                                Picker(
                                    "Sound for \(threshold)% threshold",
                                    selection: thresholdSoundBinding(for: threshold)
                                ) {
                                    ForEach(settings.availableUsageAlertSounds) { sound in
                                        Text(sound.title).tag(sound)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 170)

                                Button {
                                    alertController.previewSound(
                                        settings.usageAlertSound(forThreshold: threshold)
                                    )
                                } label: {
                                    Image(systemName: "speaker.wave.2")
                                }
                                .buttonStyle(.borderless)
                                .disabled(
                                    settings.usageAlertSound(forThreshold: threshold) == .none
                                )
                                .help("Preview the \(threshold)% threshold sound")
                                .accessibilityLabel(
                                    "Preview sound for \(threshold)% threshold"
                                )

                                Button {
                                    importCustomSound(for: threshold)
                                } label: {
                                    Image(systemName: "folder.badge.plus")
                                }
                                .buttonStyle(.borderless)
                                .help("Import a custom sound for the \(threshold)% threshold")
                                .accessibilityLabel(
                                    "Import custom sound for \(threshold)% threshold"
                                )

                                Button {
                                    settings.removeUsageAlertThreshold(threshold)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove \(threshold)% threshold")
                                .accessibilityLabel("Remove \(threshold)% threshold")
                            }
                        }
                    }

                    Menu {
                        ForEach(availableThresholds, id: \.self) { threshold in
                            Button("\(threshold)% remaining") {
                                settings.addUsageAlertThreshold(threshold)
                            }
                        }
                    } label: {
                        Label("Add threshold", systemImage: "plus")
                    }
                    .disabled(availableThresholds.isEmpty)

                    HStack {
                        Menu {
                            if settings.usageAlertThresholdPercents.isEmpty {
                                Button("System Default") {
                                    alertController.sendTestAlert(sound: .defaultSound)
                                }
                            } else {
                                ForEach(
                                    settings.usageAlertThresholdPercents,
                                    id: \.self
                                ) { threshold in
                                    let sound = settings.usageAlertSound(
                                        forThreshold: threshold
                                    )
                                    Button("\(threshold)% · \(sound.title)") {
                                        alertController.sendTestAlert(sound: sound)
                                    }
                                }
                            }
                        } label: {
                            Label("Send Test Alert", systemImage: "bell.badge")
                        }
                        .modelMeterGlassButton()
                        .controlSize(.small)

                        Text(alertController.authorizationState.description)
                            .font(.caption)
                            .foregroundStyle(
                                alertController.authorizationState == .denied
                                    ? Color.red
                                    : Color.secondary
                            )

                        Spacer()

                        notificationAccessButton
                    }

                    if let error = alertController.lastErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let soundImportError {
                        Text(soundImportError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text("Each threshold fires once per provider quota window and re-arms after recovery or reset. Import any macOS-readable audio file up to 30 seconds; Model Meter converts it to a notification-safe format.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Privacy") {
                    Text("Model Meter launches your installed CLIs. It never reads, stores, or logs their access tokens. App Sandbox is disabled so the CLIs can use their existing login and inspect concurrent local sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(8)
        }
        .frame(minWidth: 620, minHeight: 420)
        .onAppear {
            alertController.refreshAuthorizationState()
            if settings.autoContinueEnabled {
                for provider in settings.providerDisplayOrder.providers
                where settings.autoContinueEnabled(for: provider) {
                    autoContinueController.scanTargets(for: provider)
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            alertController.refreshAuthorizationState()
        }
    }

    private var availableThresholds: [Int] {
        AppSettings.allowedAlertThresholdPercents.filter {
            !settings.usageAlertThresholdPercents.contains($0)
        }
    }

    private var installedVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String

        guard let version, !version.isEmpty else {
            return "Development build"
        }
        guard let build, !build.isEmpty else {
            return version
        }
        return "\(version) (\(build))"
    }

    private func selectableThresholds(replacing current: Int) -> [Int] {
        AppSettings.allowedAlertThresholdPercents.filter {
            $0 == current || !settings.usageAlertThresholdPercents.contains($0)
        }
    }

    private func thresholdBinding(for threshold: Int) -> Binding<Int> {
        Binding(
            get: { threshold },
            set: { settings.replaceUsageAlertThreshold(threshold, with: $0) }
        )
    }

    private func thresholdSoundBinding(
        for threshold: Int
    ) -> Binding<UsageAlertSoundSelection> {
        Binding(
            get: { settings.usageAlertSound(forThreshold: threshold) },
            set: { settings.setUsageAlertSound($0, forThreshold: threshold) }
        )
    }

    @ViewBuilder
    private var notificationAccessButton: some View {
        switch alertController.authorizationState {
        case .notDetermined:
            Button("Allow Notifications…") {
                alertController.setAlertsEnabled(true)
            }
            .controlSize(.small)
        case .denied:
            Button("Open Notification Settings…") {
                openNotificationSettings()
            }
            .controlSize(.small)
        case .authorized:
            Button {
                openNotificationSettings()
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .help("Open Notification Settings")
            .accessibilityLabel("Open Notification Settings")
        case .unknown:
            ProgressView()
                .controlSize(.small)
        }
    }

    private func executableRow(
        name: String,
        placeholder: String,
        path: Binding<String>
    ) -> some View {
        LabeledContent(name) {
            HStack(spacing: 8) {
                TextField(placeholder, text: path)
                    .textFieldStyle(.roundedBorder)

                Button("Choose…") {
                    chooseExecutable(path: path)
                }
                .modelMeterGlassButton()
                .controlSize(.small)
            }
            .frame(maxWidth: 350)
        }
    }

    private func chooseExecutable(path: Binding<String>) {
        let panel = NSOpenPanel()
        panel.title = "Choose CLI executable"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        if panel.runModal() == .OK, let url = panel.url {
            path.wrappedValue = url.path
            store.refresh()
        }
    }

    private func importCustomSound(for threshold: Int) {
        let panel = NSOpenPanel()
        panel.title = "Import Alert Sound"
        panel.message = "Choose an audio file up to 30 seconds. MP3, M4A, WAV, AIFF, CAF, and other macOS-readable formats are converted automatically."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let customSound = try settings.importCustomAlertSound(
                from: url,
                forThreshold: threshold
            )
            soundImportError = nil
            alertController.previewSound(.custom(customSound))
        } catch {
            soundImportError = error.localizedDescription
        }
    }

    private func openNotificationSettings() {
        let identifier = Bundle.main.bundleIdentifier ?? "io.jbro.modelmeter"
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(identifier)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
