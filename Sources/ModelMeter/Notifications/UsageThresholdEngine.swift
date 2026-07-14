import Foundation

struct UsageThresholdEvent: Equatable, Sendable {
    let provider: ProviderID
    let limitID: String
    let limitTitle: String
    let thresholdPercent: Int
    let crossedThresholds: Set<Int>
    let remainingPercent: Int
    let resetsAt: Date?
    let resetDescription: String?

    var notificationIdentifier: String {
        "usage.\(provider.rawValue).\(limitID).\(thresholdPercent)"
    }
}

struct UsageThresholdEngine: Codable, Equatable, Sendable {
    struct LimitState: Codable, Equatable, Sendable {
        var lastResetsAt: Date?
        var lastResetDescription: String?
        var firedThresholds: Set<Int> = []
    }

    private(set) var limitStates: [String: LimitState] = [:]

    mutating func markDeliveryFailed(_ event: UsageThresholdEvent) {
        let key = "\(event.provider.rawValue)::\(event.limitID)"
        guard var state = limitStates[key] else { return }
        state.firedThresholds.subtract(event.crossedThresholds)
        limitStates[key] = state
    }

    mutating func evaluate(
        snapshot: ProviderUsageSnapshot,
        thresholds: [Int]
    ) -> [UsageThresholdEvent] {
        let normalizedThresholds = Array(Set(thresholds.filter { (0...99).contains($0) }))
            .sorted(by: >)
        guard !normalizedThresholds.isEmpty else { return [] }

        return snapshot.limits.compactMap { limit in
            evaluate(
                provider: snapshot.provider,
                limit: limit,
                thresholds: normalizedThresholds
            )
        }
    }

    private mutating func evaluate(
        provider: ProviderID,
        limit: UsageLimit,
        thresholds: [Int]
    ) -> UsageThresholdEvent? {
        let key = "\(provider.rawValue)::\(limit.id)"
        var state = limitStates[key] ?? LimitState()

        if representsNewCycle(previous: state, current: limit) {
            state.firedThresholds.removeAll()
        }

        let remainingFraction = 1 - limit.usedFraction
        for threshold in state.firedThresholds
        where remainingFraction > Double(threshold) / 100 {
            state.firedThresholds.remove(threshold)
        }

        let newlyBreached = thresholds.filter { threshold in
            remainingFraction <= Double(threshold) / 100
                && !state.firedThresholds.contains(threshold)
        }

        state.firedThresholds.formUnion(newlyBreached)
        if let resetsAt = limit.resetsAt {
            state.lastResetsAt = resetsAt
        }
        if let resetDescription = normalizedResetDescription(limit.resetDescription) {
            state.lastResetDescription = resetDescription
        }
        limitStates[key] = state

        guard let mostUrgentThreshold = newlyBreached.min() else { return nil }
        let remainingPercent = Int((remainingFraction * 100).rounded())

        return UsageThresholdEvent(
            provider: provider,
            limitID: limit.id,
            limitTitle: limit.title,
            thresholdPercent: mostUrgentThreshold,
            crossedThresholds: Set(newlyBreached),
            remainingPercent: min(max(remainingPercent, 0), 100),
            resetsAt: limit.resetsAt,
            resetDescription: limit.resetDescription
        )
    }

    private func representsNewCycle(previous: LimitState, current: UsageLimit) -> Bool {
        if let previousReset = previous.lastResetsAt, let currentReset = current.resetsAt {
            let windowSeconds = Double(current.windowMinutes ?? 0) * 60
            let meaningfulAdvance = max(15 * 60, windowSeconds * 0.5)
            return currentReset.timeIntervalSince(previousReset) > meaningfulAdvance
        }

        guard previous.lastResetsAt == nil, current.resetsAt == nil,
              let previousDescription = previous.lastResetDescription,
              let currentDescription = normalizedResetDescription(current.resetDescription)
        else { return false }

        return previousDescription != currentDescription
    }

    private func normalizedResetDescription(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
