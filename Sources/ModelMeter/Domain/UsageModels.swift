import Foundation

enum ProviderID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var systemImage: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct UsageLimit: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let usedFraction: Double
    let resetsAt: Date?
    let resetDescription: String?
    let windowMinutes: Int?

    init(
        id: String,
        title: String,
        usedFraction: Double,
        resetsAt: Date? = nil,
        resetDescription: String? = nil,
        windowMinutes: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.usedFraction = min(max(usedFraction, 0), 1)
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
        self.windowMinutes = windowMinutes
    }

    var usedPercent: Int {
        Int((usedFraction * 100).rounded())
    }
}

struct UsageActivity: Equatable, Sendable {
    var todayTokens: Int64?
    var lifetimeTokens: Int64?
    var sessionCostUSD: Double?
    var activeSessions: Int?
    var currentStreakDays: Int?
    var totalSessions: Int?
    var totalMessages: Int?
    var dailyTokens: [UsageActivityDay] = []

    static let empty = UsageActivity()
}

struct UsageActivityDay: Identifiable, Equatable, Sendable {
    let date: Date
    let tokens: Int64

    var id: Date { date }
}

struct UsageResetCredit: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let expiresAt: Date?
}

struct UsageResetCredits: Equatable, Sendable {
    let availableCount: Int
    let credits: [UsageResetCredit]
}

struct ProviderUsageSnapshot: Equatable, Sendable {
    let provider: ProviderID
    let fetchedAt: Date
    let plan: String?
    let limits: [UsageLimit]
    let resetCredits: UsageResetCredits?
    let activity: UsageActivity
    let cliVersion: String?
    let source: String
    let note: String?

    init(
        provider: ProviderID,
        fetchedAt: Date,
        plan: String?,
        limits: [UsageLimit],
        resetCredits: UsageResetCredits? = nil,
        activity: UsageActivity,
        cliVersion: String?,
        source: String,
        note: String?
    ) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.plan = plan
        self.limits = limits
        self.resetCredits = resetCredits
        self.activity = activity
        self.cliVersion = cliVersion
        self.source = source
        self.note = note
    }

    var highestUsedFraction: Double? {
        limits.map(\.usedFraction).max()
    }
}

enum ProviderLoadState: Equatable, Sendable {
    case idle
    case loading(previous: ProviderUsageSnapshot?)
    case loaded(ProviderUsageSnapshot)
    case failed(message: String, previous: ProviderUsageSnapshot?)

    var snapshot: ProviderUsageSnapshot? {
        switch self {
        case .idle:
            nil
        case .loading(let previous), .failed(_, let previous):
            previous
        case .loaded(let snapshot):
            snapshot
        }
    }

    var isLoading: Bool {
        if case .loading = self { true } else { false }
    }

    var errorMessage: String? {
        if case .failed(let message, _) = self { message } else { nil }
    }
}
