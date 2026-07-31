import Foundation

struct AutoContinueEvent: Equatable, Sendable {
    let provider: ProviderID
    let recoveredLimitIDs: Set<String>
    let expectedResetAt: Date?
    let routeRevision: Int
}

struct AutoContinueEngine: Codable, Equatable, Sendable {
    struct ProviderState: Codable, Equatable, Sendable {
        var awaitingRecovery = false
        var exhaustedLimitIDs: Set<String> = []
        var expectedResetAt: Date?
        var routeRevision: Int?
        var deliveredTargetIDs: Set<String>?
    }

    private(set) var providerStates: [ProviderID: ProviderState] = [:]

    mutating func evaluate(
        snapshot: ProviderUsageSnapshot,
        enabled: Bool,
        routeRevision: Int = 0
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
            if !state.awaitingRecovery || state.routeRevision == nil {
                state.routeRevision = routeRevision
                state.deliveredTargetIDs = []
            }
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
            expectedResetAt: state.expectedResetAt,
            routeRevision: state.routeRevision ?? routeRevision
        )
    }

    mutating func markDeliverySucceeded(
        for provider: ProviderID,
        routeRevision: Int? = nil
    ) {
        if let routeRevision,
           providerStates[provider]?.routeRevision != routeRevision {
            return
        }
        providerStates.removeValue(forKey: provider)
    }

    mutating func markDeliveryProgress(
        for provider: ProviderID,
        routeRevision: Int? = nil,
        targetIDs: Set<String>
    ) {
        guard !targetIDs.isEmpty,
              var state = providerStates[provider],
              state.awaitingRecovery,
              routeRevision == nil || state.routeRevision == routeRevision
        else {
            return
        }
        state.deliveredTargetIDs = (state.deliveredTargetIDs ?? [])
            .union(targetIDs)
        providerStates[provider] = state
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

    func pendingRouteRevision(for provider: ProviderID) -> Int? {
        guard providerStates[provider]?.awaitingRecovery == true else { return nil }
        return providerStates[provider]?.routeRevision
    }

    func deliveredTargetIDs(for provider: ProviderID) -> Set<String> {
        guard providerStates[provider]?.awaitingRecovery == true else { return [] }
        return providerStates[provider]?.deliveredTargetIDs ?? []
    }
}
