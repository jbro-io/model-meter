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

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let claudePath = "claudeExecutablePath"
        static let codexPath = "codexExecutablePath"
        static let refreshMinutes = "refreshMinutes"
        static let usageDisplayMode = "usageDisplayMode"
        static let usageAlertsEnabled = "usageAlertsEnabled"
        static let usageAlertThresholdPercents = "usageAlertThresholdPercents"
        static let usageAlertSound = "usageAlertSound"
        static let usageAlertSoundsByThreshold = "usageAlertSoundsByThreshold"
        static let customAlertSounds = "customAlertSounds"
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

    init(
        defaults: UserDefaults = .standard,
        customSoundStore: CustomAlertSoundStore = CustomAlertSoundStore()
    ) {
        self.defaults = defaults
        self.customSoundStore = customSoundStore
        claudePath = defaults.string(forKey: Key.claudePath) ?? ""
        codexPath = defaults.string(forKey: Key.codexPath) ?? ""
        let storedInterval = defaults.integer(forKey: Key.refreshMinutes)
        refreshMinutes = Self.allowedRefreshMinutes.contains(storedInterval) ? storedInterval : 5
        usageDisplayMode = defaults.string(forKey: Key.usageDisplayMode)
            .flatMap(UsageDisplayMode.init(rawValue:)) ?? .used
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
    }

    static let allowedRefreshMinutes = [1, 5, 10, 15, 30]
    static let allowedAlertThresholdPercents = [0, 5, 10, 15, 20, 25, 30, 40, 50]

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
}
