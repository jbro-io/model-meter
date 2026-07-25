import SwiftUI

struct ProviderWindowView: View {
    let provider: ProviderID
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    let openSettings: @MainActor () -> Void

    var body: some View {
        ZStack {
            ModelMeterBackdrop()

            VStack(spacing: 0) {
                providerScrollView
                    .zIndex(0)

                UsageStatusFooter(
                    store: store,
                    settings: settings,
                    idleDescription: provider.displayName,
                    quotaAccessibilityLabel: "Quota display for \(provider.displayName)",
                    openSettings: openSettings
                )
                    .zIndex(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: 390,
            idealWidth: 410,
            maxWidth: .infinity,
            minHeight: 340,
            idealHeight: 520,
            maxHeight: .infinity
        )
        .onAppear {
            store.start()
            store.refreshIfStale()
        }
    }

    @ViewBuilder
    private var providerScrollView: some View {
        let scrollView = ScrollView {
            ProviderUsageCard(
                provider: provider,
                state: store.states[provider] ?? .idle,
                displayMode: settings.usageDisplayMode,
                activityStyle: .expanded
            )
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollClipDisabled(false)
        .clipped()

        if #available(macOS 26.0, *) {
            scrollView.scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            scrollView
        }
    }
}
