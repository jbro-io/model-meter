import SwiftUI

struct ResponsiveProviderCards: View {
    static let compactSpacing: CGFloat = 6

    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    var expandedActivity = false
    var openProviderWindow: (@MainActor (ProviderID) -> Void)? = nil

    var body: some View {
        glassProviderCards
    }

    private var cardSpacing: CGFloat {
        expandedActivity ? 12 : Self.compactSpacing
    }

    @ViewBuilder
    private var glassProviderCards: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: cardSpacing) {
                responsiveProviderCards
            }
        } else {
            responsiveProviderCards
        }
    }

    private var responsiveProviderCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: cardSpacing) {
                ForEach(settings.providerDisplayOrder.providers) { provider in
                    providerCard(provider)
                        .frame(minWidth: 335, maxWidth: .infinity, alignment: .top)
                }
            }

            VStack(spacing: cardSpacing) {
                ForEach(settings.providerDisplayOrder.providers) { provider in
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
                activityStyle: expandedActivity ? .expanded : .compact,
                openWindow: {
                    openProviderWindow(provider)
                }
            )
        } else {
            ProviderUsageCard(
                provider: provider,
                state: store.states[provider] ?? .idle,
                displayMode: settings.usageDisplayMode,
                activityStyle: expandedActivity ? .expanded : .compact
            )
        }
    }
}
