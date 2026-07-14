import Foundation

/// A notification sound chosen from Model Meter's bundled sounds or the
/// user's imported sound catalog.
enum UsageAlertSoundSelection: Hashable, Identifiable, Sendable {
    case builtIn(UsageAlertSound)
    case custom(CustomAlertSound)

    static let defaultSound = Self.builtIn(UsageAlertSound.defaultSound)
    static let basso = Self.builtIn(UsageAlertSound.basso)
    static let blow = Self.builtIn(UsageAlertSound.blow)
    static let bottle = Self.builtIn(UsageAlertSound.bottle)
    static let frog = Self.builtIn(UsageAlertSound.frog)
    static let funk = Self.builtIn(UsageAlertSound.funk)
    static let glass = Self.builtIn(UsageAlertSound.glass)
    static let hero = Self.builtIn(UsageAlertSound.hero)
    static let morse = Self.builtIn(UsageAlertSound.morse)
    static let ping = Self.builtIn(UsageAlertSound.ping)
    static let pop = Self.builtIn(UsageAlertSound.pop)
    static let purr = Self.builtIn(UsageAlertSound.purr)
    static let sosumi = Self.builtIn(UsageAlertSound.sosumi)
    static let submarine = Self.builtIn(UsageAlertSound.submarine)
    static let tink = Self.builtIn(UsageAlertSound.tink)
    static let none = Self.builtIn(UsageAlertSound.none)

    static var builtInCases: [Self] {
        UsageAlertSound.allCases.map(Self.builtIn)
    }

    static func pickerOptions(customCatalog: [CustomAlertSound]) -> [Self] {
        builtInCases.filter { $0 != .none }
            + customCatalog.map(Self.custom)
            + [.none]
    }

    var id: String { persistenceValue }

    var title: String {
        switch self {
        case let .builtIn(sound):
            sound.title
        case let .custom(sound):
            sound.title
        }
    }

    /// Stable storage representation. Bundled sounds retain their original
    /// raw values so existing preferences continue to decode unchanged.
    var persistenceValue: String {
        switch self {
        case let .builtIn(sound):
            sound.rawValue
        case let .custom(sound):
            "custom:\(sound.id)"
        }
    }

    /// The filename passed to `UNNotificationSound`. `nil` represents either
    /// the system default sound or an intentionally silent notification.
    var notificationFileName: String? {
        switch self {
        case let .builtIn(sound):
            sound.bundledFileName
        case let .custom(sound):
            sound.fileName
        }
    }

    var builtInSound: UsageAlertSound? {
        guard case let .builtIn(sound) = self else { return nil }
        return sound
    }

    var customSound: CustomAlertSound? {
        guard case let .custom(sound) = self else { return nil }
        return sound
    }

    var systemSoundName: String? {
        switch self {
        case let .builtIn(sound):
            sound.systemSoundName
        case let .custom(sound):
            (sound.fileName as NSString).deletingPathExtension
        }
    }

    init?(
        persistenceValue: String,
        customCatalog: [CustomAlertSound]
    ) {
        guard let decoded = Self.decode(
            persistenceValue: persistenceValue,
            customCatalog: customCatalog
        ) else {
            return nil
        }
        self = decoded
    }

    static func decode(
        persistenceValue: String,
        customCatalog: [CustomAlertSound]
    ) -> Self? {
        if persistenceValue.hasPrefix(customPersistencePrefix) {
            let customID = String(
                persistenceValue.dropFirst(customPersistencePrefix.count)
            )
            guard !customID.isEmpty,
                  let sound = customCatalog.first(where: { $0.id == customID }) else {
                return nil
            }
            return .custom(sound)
        }

        return UsageAlertSound(rawValue: persistenceValue).map(Self.builtIn)
    }

    static func decode(
        _ persistenceValue: String,
        customCatalog: [CustomAlertSound]
    ) -> Self? {
        decode(persistenceValue: persistenceValue, customCatalog: customCatalog)
    }

    static func decode(
        _ persistenceValue: String,
        customSounds: [CustomAlertSound]
    ) -> Self? {
        decode(persistenceValue: persistenceValue, customCatalog: customSounds)
    }

    private static let customPersistencePrefix = "custom:"
}
