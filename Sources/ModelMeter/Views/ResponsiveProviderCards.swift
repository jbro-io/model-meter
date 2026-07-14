import SwiftUI

struct ResponsiveProviderCards: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    var openProviderWindow: (@MainActor (ProviderID) -> Void)? = nil

    var body: some View {
        glassProviderCards
    }

    @ViewBuilder
    private var glassProviderCards: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                responsiveProviderCards
            }
        } else {
            responsiveProviderCards
        }
    }

    private var responsiveProviderCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(ProviderID.allCases) { provider in
                    providerCard(provider)
                        .frame(minWidth: 335, maxWidth: .infinity, alignment: .top)
                }
            }

            VStack(spacing: 12) {
                ForEach(ProviderID.allCases) { provider in
                    providerCard(provider)
                }
            }
        }
    }

    @ViewBuilder
    private func providerCard(_ provider: ProviderID) -> some View {
        if let openProviderWindow {
            ProviderUsageCard(
                provider: provider,
                state: store.states[provider] ?? .idle,
                displayMode: settings.usageDisplayMode,
                openWindow: {
                    openProviderWindow(provider)
                }
            )
        } else {
            ProviderUsageCard(
                provider: provider,
                state: store.states[provider] ?? .idle,
                displayMode: settings.usageDisplayMode
            )
        }
    }
}
