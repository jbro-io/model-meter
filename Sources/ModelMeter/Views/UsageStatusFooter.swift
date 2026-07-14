import SwiftUI

struct UsageStatusFooter: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    let idleDescription: String
    let quotaAccessibilityLabel: String
    let openSettings: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text(refreshDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Picker("Quota display", selection: $settings.usageDisplayMode) {
                ForEach(UsageDisplayMode.allCases) { mode in
                    Text(mode.shortTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .labelsHidden()
            .frame(width: 88)
            .help("Show quota used or amount left")
            .accessibilityLabel(quotaAccessibilityLabel)

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
            .controlSize(.mini)
            .frame(width: 26, height: 26)
            .help("Refresh all usage")
            .disabled(store.isRefreshing)
            .accessibilityLabel("Refresh all usage")
            .keyboardShortcut("r", modifiers: .command)

            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .modelMeterGlassButton()
            .controlSize(.mini)
            .frame(width: 26, height: 26)
            .help("Open settings")
            .accessibilityLabel("Open settings")
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 36)
        .modelMeterGlass(style: .clear, cornerRadius: 0)
        .overlay(alignment: .top) {
            Divider()
                .opacity(0.4)
        }
    }

    private var refreshDescription: String {
        if store.isRefreshing { return "Reading both CLIs…" }
        guard let date = store.lastCompletedRefresh else { return idleDescription }
        return "Updated \(date.formatted(.relative(presentation: .named)))"
    }
}
