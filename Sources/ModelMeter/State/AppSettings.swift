import Combine
import Foundation

enum UsageDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case used
    case remaining

    var id: String { rawValue }

    var title: String {
        switch self {
        case .used: "Used"
        case .remaining: "Remaining"
        }
    }

    var shortTitle: String {
        switch self {
        case .used: "Used"
        case .remaining: "Left"
        }
    }

    var metricWord: String {
        switch self {
        case .used: "used"
        case .remaining: "left"
        }
    }

    func fraction(forUsedFraction usedFraction: Double) -> Double {
        let clamped = min(max(usedFraction, 0), 1)
        return switch self {
        case .used: clamped
        case .remaining: 1 - clamped
        }
    }
}

enum ProviderDisplayOrder: String, CaseIterable, Identifiable, Sendable {
    case claudeFirst
    case codexFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeFirst: "Claude · Codex"
        case .codexFirst: "Codex · Claude"
        }
    }

    var providers: [ProviderID] {
        switch self {
        case .claudeFirst: [.claude, .codex]
        case .codexFirst: [.codex, .claude]
        }
    }
}

enum UsageAlertSound: String, CaseIterable, Identifiable, Sendable {
    case defaultSound
    case basso
    case blow
    case bottle
    case frog
    case funk
    case glass
    case hero
    case morse
    case ping
    case pop
    case purr
    case sosumi
    case submarine
    case tink
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultSound: "System Default"
        case .none: "None"
        default: rawValue.capitalized
        }
    }

    var bundledFileName: String? {
        switch self {
        case .defaultSound, .none:
            nil
        default:
            "\(title).aiff"
        }
    }

    var systemSoundName: String? {
        bundledFileName.map { ($0 as NSString).deletingPathExtension }
    }
}

enum AutoContinueTerminal: String, CaseIterable, Codable, Identifiable, Sendable {
    case kitty
    case iterm
    case ghostty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kitty: "Kitty"
        case .iterm: "iTerm2"
        case .ghostty: "Ghostty"
        }
    }

    var supportsAllSessions: Bool {
        self == .kitty
    }

    var usesAppleEvents: Bool {
        self != .kitty
    }

    var isPreview: Bool {
        self == .ghostty
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let claudePath = "claudeExecutablePath"
        static let codexPath = "codexExecutablePath"
        static let refreshMinutes = "refreshMinutes"
        static let usageDisplayMode = "usageDisplayMode"
        static let providerDisplayOrder = "providerDisplayOrder"
        static let usageAlertsEnabled = "usageAlertsEnabled"
        static let usageAlertThresholdPercents = "usageAlertThresholdPercents"
        static let usageAlertSound = "usageAlertSound"
        static let usageAlertSoundsByThreshold = "usageAlertSoundsByThreshold"
        static let customAlertSounds = "customAlertSounds"
        static let autoContinueEnabled = "autoContinueEnabled"
        static let autoContinueClaudeEnabled = "autoContinueClaudeEnabled"
        static let autoContinueCodexEnabled = "autoContinueCodexEnabled"
        static let autoContinueTerminal = "autoContinueTerminal"
        static let autoContinueRouteRevision = "autoContinueRouteRevision"
        static let autoContinueRouteRevisions = "autoContinueRouteRevisions.v2"
        static let terminalEnrollmentSnapshots = "terminalEnrollmentSnapshots.v2"
        static let kittyExecutablePath = "kittyExecutablePath"
        static let kittyListenAddress = "kittyListenAddress"
        static let kittyClaudeMatch = "kittyClaudeMatch"
        static let kittyCodexMatch = "kittyCodexMatch"
        static let kittyClaudeAllSessions = "kittyClaudeAllSessions"
        static let kittyCodexAllSessions = "kittyCodexAllSessions"
        static let kittyClaudeSessionIDs = "kittyClaudeSessionIDs"
        static let kittyCodexSessionIDs = "kittyCodexSessionIDs"
    }

    private let defaults: UserDefaults
    private let customSoundStore: CustomAlertSoundStore

    @Published var claudePath: String {
        didSet { defaults.set(claudePath, forKey: Key.claudePath) }
    }

    @Published var codexPath: String {
        didSet { defaults.set(codexPath, forKey: Key.codexPath) }
    }

    @Published var refreshMinutes: Int {
        didSet { defaults.set(refreshMinutes, forKey: Key.refreshMinutes) }
    }

    @Published var usageDisplayMode: UsageDisplayMode {
        didSet { defaults.set(usageDisplayMode.rawValue, forKey: Key.usageDisplayMode) }
    }

    @Published var providerDisplayOrder: ProviderDisplayOrder {
        didSet {
            defaults.set(providerDisplayOrder.rawValue, forKey: Key.providerDisplayOrder)
        }
    }

    @Published var usageAlertsEnabled: Bool {
        didSet { defaults.set(usageAlertsEnabled, forKey: Key.usageAlertsEnabled) }
    }

    @Published private(set) var usageAlertThresholdPercents: [Int] {
        didSet {
            defaults.set(usageAlertThresholdPercents, forKey: Key.usageAlertThresholdPercents)
        }
    }

    @Published var usageAlertSound: UsageAlertSound {
        didSet { defaults.set(usageAlertSound.rawValue, forKey: Key.usageAlertSound) }
    }

    @Published private(set) var customAlertSounds: [CustomAlertSound] {
        didSet {
            if let data = try? JSONEncoder().encode(customAlertSounds) {
                defaults.set(data, forKey: Key.customAlertSounds)
            }
        }
    }

    @Published private(set) var usageAlertSoundsByThreshold: [Int: UsageAlertSoundSelection] {
        didSet {
            let stored = Dictionary(
                uniqueKeysWithValues: usageAlertSoundsByThreshold.map {
                    (String($0.key), $0.value.persistenceValue)
                }
            )
            defaults.set(stored, forKey: Key.usageAlertSoundsByThreshold)
        }
    }

    @Published var autoContinueEnabled: Bool {
        didSet {
            defaults.set(autoContinueEnabled, forKey: Key.autoContinueEnabled)
            if autoContinueEnabled != oldValue {
                bumpAutoContinueRouteRevisions()
            }
        }
    }

    @Published var autoContinueClaudeEnabled: Bool {
        didSet {
            defaults.set(autoContinueClaudeEnabled, forKey: Key.autoContinueClaudeEnabled)
            if autoContinueClaudeEnabled != oldValue {
                bumpAutoContinueRouteRevision(for: .claude)
            }
        }
    }

    @Published var autoContinueCodexEnabled: Bool {
        didSet {
            defaults.set(autoContinueCodexEnabled, forKey: Key.autoContinueCodexEnabled)
            if autoContinueCodexEnabled != oldValue {
                bumpAutoContinueRouteRevision(for: .codex)
            }
        }
    }

    @Published var autoContinueTerminal: AutoContinueTerminal {
        didSet {
            defaults.set(autoContinueTerminal.rawValue, forKey: Key.autoContinueTerminal)
            if autoContinueTerminal != oldValue {
                bumpAutoContinueRouteRevisions()
            }
        }
    }

    @Published var kittyExecutablePath: String {
        didSet {
            defaults.set(kittyExecutablePath, forKey: Key.kittyExecutablePath)
            if kittyExecutablePath != oldValue,
               autoContinueTerminal == .kitty {
                bumpAutoContinueRouteRevisions()
            }
        }
    }

    @Published var kittyListenAddress: String {
        didSet {
            defaults.set(kittyListenAddress, forKey: Key.kittyListenAddress)
            if kittyListenAddress != oldValue,
               autoContinueTerminal == .kitty {
                bumpAutoContinueRouteRevisions()
            }
        }
    }

    @Published var kittyClaudeMatch: String {
        didSet {
            defaults.set(kittyClaudeMatch, forKey: Key.kittyClaudeMatch)
            if kittyClaudeMatch != oldValue,
               autoContinueTerminal == .kitty {
                bumpAutoContinueRouteRevision(for: .claude)
            }
        }
    }

    @Published var kittyCodexMatch: String {
        didSet {
            defaults.set(kittyCodexMatch, forKey: Key.kittyCodexMatch)
            if kittyCodexMatch != oldValue,
               autoContinueTerminal == .kitty {
                bumpAutoContinueRouteRevision(for: .codex)
            }
        }
    }

    @Published var kittyClaudeAllSessions: Bool {
        didSet {
            defaults.set(kittyClaudeAllSessions, forKey: Key.kittyClaudeAllSessions)
            if kittyClaudeAllSessions != oldValue,
               autoContinueTerminal == .kitty {
                bumpAutoContinueRouteRevision(for: .claude)
            }
        }
    }

    @Published var kittyCodexAllSessions: Bool {
        didSet {
            defaults.set(kittyCodexAllSessions, forKey: Key.kittyCodexAllSessions)
            if kittyCodexAllSessions != oldValue,
               autoContinueTerminal == .kitty {
                bumpAutoContinueRouteRevision(for: .codex)
            }
        }
    }

    @Published private(set) var autoContinueRouteRevisions: [ProviderID: Int] {
        didSet {
            defaults.set(
                Dictionary(
                    uniqueKeysWithValues: autoContinueRouteRevisions.map {
                        ($0.key.rawValue, $0.value)
                    }
                ),
                forKey: Key.autoContinueRouteRevisions
            )
        }
    }

    @Published private(set) var terminalEnrollmentSnapshots: [
        String: [TerminalSessionTarget]
    ] {
        didSet {
            if let data = try? JSONEncoder().encode(terminalEnrollmentSnapshots) {
                defaults.set(data, forKey: Key.terminalEnrollmentSnapshots)
            }
        }
    }

    @Published private(set) var kittyClaudeSessionIDs: Set<Int> {
        didSet {
            defaults.set(kittyClaudeSessionIDs.sorted(), forKey: Key.kittyClaudeSessionIDs)
        }
    }

    @Published private(set) var kittyCodexSessionIDs: Set<Int> {
        didSet {
            defaults.set(kittyCodexSessionIDs.sorted(), forKey: Key.kittyCodexSessionIDs)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        customSoundStore: CustomAlertSoundStore = CustomAlertSoundStore()
    ) {
        self.defaults = defaults
        self.customSoundStore = customSoundStore
        claudePath = defaults.string(forKey: Key.claudePath) ?? ""
        codexPath = defaults.string(forKey: Key.codexPath) ?? ""
        let storedInterval = defaults.integer(forKey: Key.refreshMinutes)
        refreshMinutes = Self.allowedRefreshMinutes.contains(storedInterval) ? storedInterval : 1
        usageDisplayMode = defaults.string(forKey: Key.usageDisplayMode)
            .flatMap(UsageDisplayMode.init(rawValue:)) ?? .used
        providerDisplayOrder = defaults.string(forKey: Key.providerDisplayOrder)
            .flatMap(ProviderDisplayOrder.init(rawValue:)) ?? .claudeFirst
        usageAlertsEnabled = defaults.bool(forKey: Key.usageAlertsEnabled)
        let storedThresholds = defaults.array(forKey: Key.usageAlertThresholdPercents)?
            .compactMap { ($0 as? NSNumber)?.intValue }
        usageAlertThresholdPercents = Self.normalizedAlertThresholds(
            storedThresholds ?? [20]
        )
        usageAlertSound = defaults.string(forKey: Key.usageAlertSound)
            .flatMap(UsageAlertSound.init(rawValue:)) ?? .defaultSound
        let decodedCustomSounds = defaults.data(forKey: Key.customAlertSounds)
            .flatMap { try? JSONDecoder().decode([CustomAlertSound].self, from: $0) }
            ?? []
        customAlertSounds = decodedCustomSounds
        usageAlertSoundsByThreshold = (defaults.dictionary(
            forKey: Key.usageAlertSoundsByThreshold
        ) ?? [:]).reduce(into: [:]) { result, entry in
            guard let threshold = Int(entry.key),
                  Self.allowedAlertThresholdPercents.contains(threshold),
                  let rawValue = entry.value as? String,
                  let sound = UsageAlertSoundSelection.decode(
                    persistenceValue: rawValue,
                    customCatalog: decodedCustomSounds
                  ) else {
                return
            }
            result[threshold] = sound
        }
        autoContinueEnabled = defaults.bool(forKey: Key.autoContinueEnabled)
        autoContinueClaudeEnabled = defaults.object(
            forKey: Key.autoContinueClaudeEnabled
        ) as? Bool ?? true
        autoContinueCodexEnabled = defaults.object(
            forKey: Key.autoContinueCodexEnabled
        ) as? Bool ?? true
        autoContinueTerminal = defaults.string(forKey: Key.autoContinueTerminal)
            .flatMap(AutoContinueTerminal.init(rawValue:)) ?? .kitty
        let legacyRouteRevision = defaults.integer(
            forKey: Key.autoContinueRouteRevision
        )
        let storedRouteRevisions = defaults.dictionary(
            forKey: Key.autoContinueRouteRevisions
        ) ?? [:]
        autoContinueRouteRevisions = Dictionary(
            uniqueKeysWithValues: ProviderID.allCases.map { provider in
                (
                    provider,
                    (storedRouteRevisions[provider.rawValue] as? NSNumber)?.intValue
                        ?? legacyRouteRevision
                )
            }
        )
        terminalEnrollmentSnapshots = defaults.data(
            forKey: Key.terminalEnrollmentSnapshots
        )
        .flatMap {
            try? JSONDecoder().decode(
                [String: [TerminalSessionTarget]].self,
                from: $0
            )
        } ?? [:]
        kittyExecutablePath = defaults.string(forKey: Key.kittyExecutablePath) ?? ""
        kittyListenAddress = defaults.string(forKey: Key.kittyListenAddress)
            ?? "unix:/tmp/model-meter-kitty"
        kittyClaudeMatch = Self.normalizedKittyMatch(
            defaults.string(forKey: Key.kittyClaudeMatch),
            provider: .claude
        )
        kittyCodexMatch = Self.normalizedKittyMatch(
            defaults.string(forKey: Key.kittyCodexMatch),
            provider: .codex
        )
        kittyClaudeAllSessions = defaults.bool(forKey: Key.kittyClaudeAllSessions)
        kittyCodexAllSessions = defaults.bool(forKey: Key.kittyCodexAllSessions)
        kittyClaudeSessionIDs = Set(
            defaults.array(forKey: Key.kittyClaudeSessionIDs)?
                .compactMap { ($0 as? NSNumber)?.intValue } ?? []
        )
        kittyCodexSessionIDs = Set(
            defaults.array(forKey: Key.kittyCodexSessionIDs)?
                .compactMap { ($0 as? NSNumber)?.intValue } ?? []
        )
    }

    static let allowedRefreshMinutes = [1, 5, 10, 15, 30]
    static let allowedAlertThresholdPercents = [0, 5, 10, 15, 20, 25, 30, 40, 50]

    func autoContinueEnabled(for provider: ProviderID) -> Bool {
        guard autoContinueEnabled else { return false }
        return switch provider {
        case .claude: autoContinueClaudeEnabled
        case .codex: autoContinueCodexEnabled
        }
    }

    func kittyMatch(for provider: ProviderID) -> String {
        switch provider {
        case .claude: kittyClaudeMatch
        case .codex: kittyCodexMatch
        }
    }

    func kittyAllSessions(for provider: ProviderID) -> Bool {
        switch provider {
        case .claude: kittyClaudeAllSessions
        case .codex: kittyCodexAllSessions
        }
    }

    func kittySessionIDs(for provider: ProviderID) -> Set<Int> {
        switch provider {
        case .claude: kittyClaudeSessionIDs
        case .codex: kittyCodexSessionIDs
        }
    }

    func autoContinueRouteRevision(for provider: ProviderID) -> Int {
        autoContinueRouteRevisions[provider] ?? 0
    }

    func setKittySession(_ id: Int, enabled: Bool, for provider: ProviderID) {
        let existing = kittySessionIDs(for: provider).contains(id)
        guard existing != enabled else { return }
        switch provider {
        case .claude:
            if enabled {
                kittyClaudeSessionIDs.insert(id)
            } else {
                kittyClaudeSessionIDs.remove(id)
            }
        case .codex:
            if enabled {
                kittyCodexSessionIDs.insert(id)
            } else {
                kittyCodexSessionIDs.remove(id)
            }
        }
        if !enabled {
            removeEnrollmentSnapshot(
                id: String(id),
                terminal: .kitty,
                provider: provider
            )
        }
        if autoContinueTerminal == .kitty {
            bumpAutoContinueRouteRevision(for: provider)
        }
    }

    func retainKittySessions(
        withIDs liveIDs: Set<Int>,
        for provider: ProviderID
    ) {
        let previous = kittySessionIDs(for: provider)
        switch provider {
        case .claude:
            kittyClaudeSessionIDs.formIntersection(liveIDs)
        case .codex:
            kittyCodexSessionIDs.formIntersection(liveIDs)
        }
        guard previous != kittySessionIDs(for: provider) else { return }
        let liveStringIDs = Set(liveIDs.map(String.init))
        updateEnrollmentSnapshots(
            terminal: .kitty,
            provider: provider
        ) {
            $0.filter { liveStringIDs.contains($0.id) }
        }
        if autoContinueTerminal == .kitty {
            bumpAutoContinueRouteRevision(for: provider)
        }
    }

    func allSessions(
        for terminal: AutoContinueTerminal,
        provider: ProviderID
    ) -> Bool {
        terminal == .kitty && kittyAllSessions(for: provider)
    }

    func selectedSessionIDs(
        for terminal: AutoContinueTerminal,
        provider: ProviderID
    ) -> Set<String> {
        if terminal == .kitty {
            return Set(kittySessionIDs(for: provider).map(String.init))
        }
        return Set(
            enrollmentSnapshots(for: terminal, provider: provider).map(\.id)
        )
    }

    func selectedSessionTargets(
        for terminal: AutoContinueTerminal,
        provider: ProviderID
    ) -> [TerminalSessionTarget] {
        let snapshots = enrollmentSnapshots(for: terminal, provider: provider)
        guard terminal == .kitty else { return snapshots }
        let snapshotsByID = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.id, $0) }
        )
        return kittySessionIDs(for: provider)
            .sorted()
            .map {
                snapshotsByID[String($0)]
                    ?? .legacyKitty(id: $0, provider: provider)
            }
    }

    func hasIncompleteSessionIdentity(
        for terminal: AutoContinueTerminal,
        provider: ProviderID
    ) -> Bool {
        selectedSessionTargets(for: terminal, provider: provider)
            .contains { !$0.hasIdentitySnapshot }
    }

    func setTerminalSession(
        _ target: TerminalSessionTarget,
        enabled: Bool
    ) {
        let selected = selectedSessionIDs(
            for: target.terminal,
            provider: target.provider
        ).contains(target.id)
        guard selected != enabled else { return }

        if target.terminal == .kitty, let id = Int(target.id) {
            switch target.provider {
            case .claude:
                if enabled {
                    kittyClaudeSessionIDs.insert(id)
                } else {
                    kittyClaudeSessionIDs.remove(id)
                }
            case .codex:
                if enabled {
                    kittyCodexSessionIDs.insert(id)
                } else {
                    kittyCodexSessionIDs.remove(id)
                }
            }
        }

        updateEnrollmentSnapshots(
            terminal: target.terminal,
            provider: target.provider
        ) { snapshots in
            var snapshots = snapshots.filter { $0.id != target.id }
            if enabled {
                snapshots.append(target)
            }
            return snapshots.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        }
        if autoContinueTerminal == target.terminal {
            bumpAutoContinueRouteRevision(for: target.provider)
        }
    }

    func synchronizeEnrolledSessions(
        with liveTargets: [TerminalSessionTarget],
        terminal: AutoContinueTerminal,
        provider: ProviderID
    ) {
        let previousTargets = selectedSessionTargets(
            for: terminal,
            provider: provider
        )
        let previousByID = Dictionary(
            uniqueKeysWithValues: previousTargets.map { ($0.id, $0) }
        )
        let selectedIDs = selectedSessionIDs(for: terminal, provider: provider)
        let liveByID = Dictionary(uniqueKeysWithValues: liveTargets.map { ($0.id, $0) })
        let retained = selectedIDs.compactMap { id -> TerminalSessionTarget? in
            guard let live = liveByID[id],
                  let previous = previousByID[id]
            else {
                return nil
            }
            return !previous.hasIdentitySnapshot
                || previous.identifiesSameLiveSession(as: live)
                ? live
                : nil
        }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }

        let storedSnapshotsChanged = enrollmentSnapshots(
            for: terminal,
            provider: provider
        ) != retained
        var persistenceChanged = storedSnapshotsChanged
        if terminal == .kitty {
            let retainedIDs = Set(retained.compactMap { Int($0.id) })
            if retainedIDs != kittySessionIDs(for: provider) {
                persistenceChanged = true
                switch provider {
                case .claude: kittyClaudeSessionIDs = retainedIDs
                case .codex: kittyCodexSessionIDs = retainedIDs
                }
            }
        }
        guard persistenceChanged else { return }
        if storedSnapshotsChanged {
            updateEnrollmentSnapshots(
                terminal: terminal,
                provider: provider
            ) { _ in retained }
        }

        let retainedByID = Dictionary(
            uniqueKeysWithValues: retained.map { ($0.id, $0) }
        )
        let routeChanged = Set(previousByID.keys) != Set(retainedByID.keys)
            || previousByID.contains { id, previous in
                guard let live = retainedByID[id] else { return true }
                return !previous.hasIdentitySnapshot
                    || !previous.identifiesSameLiveSession(as: live)
            }
        if routeChanged, autoContinueTerminal == terminal {
            bumpAutoContinueRouteRevision(for: provider)
        }
    }

    private func enrollmentSnapshots(
        for terminal: AutoContinueTerminal,
        provider: ProviderID
    ) -> [TerminalSessionTarget] {
        terminalEnrollmentSnapshots[enrollmentKey(terminal, provider)] ?? []
    }

    private func updateEnrollmentSnapshots(
        terminal: AutoContinueTerminal,
        provider: ProviderID,
        transform: ([TerminalSessionTarget]) -> [TerminalSessionTarget]
    ) {
        let key = enrollmentKey(terminal, provider)
        var snapshots = terminalEnrollmentSnapshots
        let updated = transform(snapshots[key] ?? [])
        if updated.isEmpty {
            snapshots.removeValue(forKey: key)
        } else {
            snapshots[key] = updated
        }
        terminalEnrollmentSnapshots = snapshots
    }

    private func removeEnrollmentSnapshot(
        id: String,
        terminal: AutoContinueTerminal,
        provider: ProviderID
    ) {
        updateEnrollmentSnapshots(terminal: terminal, provider: provider) {
            $0.filter { $0.id != id }
        }
    }

    private func enrollmentKey(
        _ terminal: AutoContinueTerminal,
        _ provider: ProviderID
    ) -> String {
        "\(terminal.rawValue).\(provider.rawValue)"
    }

    private func bumpAutoContinueRouteRevision(for provider: ProviderID) {
        var revisions = autoContinueRouteRevisions
        revisions[provider, default: 0] &+= 1
        autoContinueRouteRevisions = revisions
    }

    private func bumpAutoContinueRouteRevisions() {
        var revisions = autoContinueRouteRevisions
        for provider in ProviderID.allCases {
            revisions[provider, default: 0] &+= 1
        }
        autoContinueRouteRevisions = revisions
    }

    func addUsageAlertThreshold(_ percent: Int) {
        usageAlertThresholdPercents = Self.normalizedAlertThresholds(
            usageAlertThresholdPercents + [percent]
        )
        if usageAlertThresholdPercents.contains(percent),
           usageAlertSoundsByThreshold[percent] == nil {
            usageAlertSoundsByThreshold[percent] = .builtIn(usageAlertSound)
        }
    }

    func removeUsageAlertThreshold(_ percent: Int) {
        usageAlertThresholdPercents.removeAll { $0 == percent }
        usageAlertSoundsByThreshold.removeValue(forKey: percent)
    }

    func replaceUsageAlertThreshold(_ oldPercent: Int, with newPercent: Int) {
        let transferredSound = usageAlertSound(forThreshold: oldPercent)
        var sounds = usageAlertSoundsByThreshold
        sounds.removeValue(forKey: oldPercent)
        if sounds[newPercent] == nil {
            sounds[newPercent] = transferredSound
        }
        usageAlertThresholdPercents = Self.normalizedAlertThresholds(
            usageAlertThresholdPercents.map { $0 == oldPercent ? newPercent : $0 }
        )
        usageAlertSoundsByThreshold = sounds
    }

    func usageAlertSound(forThreshold threshold: Int) -> UsageAlertSoundSelection {
        usageAlertSoundsByThreshold[threshold] ?? .builtIn(usageAlertSound)
    }

    func setUsageAlertSound(
        _ sound: UsageAlertSoundSelection,
        forThreshold threshold: Int
    ) {
        guard usageAlertThresholdPercents.contains(threshold) else { return }
        usageAlertSoundsByThreshold[threshold] = sound
    }

    var availableUsageAlertSounds: [UsageAlertSoundSelection] {
        UsageAlertSoundSelection.pickerOptions(customCatalog: customAlertSounds)
    }

    @discardableResult
    func importCustomAlertSound(
        from sourceURL: URL,
        forThreshold threshold: Int
    ) throws -> CustomAlertSound {
        guard usageAlertThresholdPercents.contains(threshold) else {
            throw CustomAlertSoundStore.ImportError.sourceUnavailable
        }
        let imported = try customSoundStore.importSound(from: sourceURL)
        let sound = CustomAlertSound(
            id: imported.id,
            title: uniqueCustomSoundTitle(imported.title),
            fileName: imported.fileName
        )
        customAlertSounds.append(sound)
        usageAlertSoundsByThreshold[threshold] = .custom(sound)
        return sound
    }

    func url(for customSound: CustomAlertSound) -> URL? {
        customSoundStore.url(for: customSound)
    }

    private func uniqueCustomSoundTitle(_ proposedTitle: String) -> String {
        let existing = Set(customAlertSounds.map { $0.title.lowercased() })
        guard existing.contains(proposedTitle.lowercased()) else {
            return proposedTitle
        }

        var suffix = 2
        while existing.contains("\(proposedTitle) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(proposedTitle) \(suffix)"
    }

    private static func normalizedAlertThresholds(_ values: [Int]) -> [Int] {
        Array(
            Set(values.filter(allowedAlertThresholdPercents.contains))
        )
        .sorted(by: >)
    }

    private static func normalizedKittyMatch(
        _ storedValue: String?,
        provider: ProviderID
    ) -> String {
        let legacyDefault = "cmdline:\(provider.rawValue)"
        guard let storedValue,
              storedValue.caseInsensitiveCompare(legacyDefault) != .orderedSame
        else {
            return "smart:\(provider.rawValue)"
        }
        return storedValue
    }
}
