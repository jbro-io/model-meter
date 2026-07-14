import SwiftUI

struct CombinedProviderWindowView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    let openSettings: @MainActor () -> Void
    let openProviderWindow: @MainActor (ProviderID) -> Void

    var body: some View {
        ZStack {
            ModelMeterBackdrop()

            VStack(spacing: 0) {
                providerScrollView
                    .zIndex(0)

                UsageStatusFooter(
                    store: store,
                    settings: settings,
                    idleDescription: "Waiting for first refresh",
                    quotaAccessibilityLabel: "Quota display for both providers",
                    openSettings: openSettings
                )
                .zIndex(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: 390,
            idealWidth: 840,
            maxWidth: .infinity,
            minHeight: 340,
            idealHeight: 560,
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
            ResponsiveProviderCards(
                store: store,
                settings: settings,
                openProviderWindow: openProviderWindow
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
