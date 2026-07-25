import Foundation

struct AutoContinueEvent: Equatable, Sendable {
    let provider: ProviderID
    let recoveredLimitIDs: Set<String>
    let expectedResetAt: Date?
}

struct AutoContinueEngine: Codable, Equatable, Sendable {
    struct ProviderState: Codable, Equatable, Sendable {
        var awaitingRecovery = false
        var exhaustedLimitIDs: Set<String> = []
        var expectedResetAt: Date?
    }

    private(set) var providerStates: [ProviderID: ProviderState] = [:]

    mutating func evaluate(
        snapshot: ProviderUsageSnapshot,
        enabled: Bool
    ) -> AutoContinueEvent? {
        guard enabled else {
            providerStates.removeValue(forKey: snapshot.provider)
            return nil
        }

        let fiveHourLimits = snapshot.limits.filter { $0.windowMinutes == 300 }
        guard !fiveHourLimits.isEmpty else { return nil }

        var state = providerStates[snapshot.provider] ?? ProviderState()
        let exhaustedLimits = fiveHourLimits.filter { $0.usedFraction >= 1 }

        if !exhaustedLimits.isEmpty {
            state.awaitingRecovery = true
            state.exhaustedLimitIDs.formUnion(exhaustedLimits.map(\.id))
            state.expectedResetAt = exhaustedLimits.compactMap(\.resetsAt).min()
                ?? state.expectedResetAt
            providerStates[snapshot.provider] = state
            return nil
        }

        providerStates[snapshot.provider] = state
        guard state.awaitingRecovery else { return nil }

        return AutoContinueEvent(
            provider: snapshot.provider,
            recoveredLimitIDs: state.exhaustedLimitIDs,
            expectedResetAt: state.expectedResetAt
        )
    }

    mutating func markDeliverySucceeded(for provider: ProviderID) {
        providerStates.removeValue(forKey: provider)
    }

    mutating func clear(_ provider: ProviderID) {
        providerStates.removeValue(forKey: provider)
    }

    func pendingResetDate(for provider: ProviderID) -> Date? {
        guard providerStates[provider]?.awaitingRecovery == true else { return nil }
        return providerStates[provider]?.expectedResetAt
    }

    func isAwaitingRecovery(for provider: ProviderID) -> Bool {
        providerStates[provider]?.awaitingRecovery == true
    }
}
