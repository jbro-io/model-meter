import Foundation

struct KittySessionTarget: Identifiable, Equatable, Sendable {
    let id: Int
    let tabTitle: String
    let windowTitle: String
    let currentDirectory: String?
    let commandLine: [String]

    var displayTitle: String {
        let cleanedTab = KittySessionTitleFormatter.clean(tabTitle)
        if !cleanedTab.isEmpty,
           !KittySessionTitleFormatter.isGeneric(cleanedTab) {
            return cleanedTab
        }

        let cleanedWindow = KittySessionTitleFormatter.clean(windowTitle)
        if !cleanedWindow.isEmpty,
           !KittySessionTitleFormatter.isGeneric(cleanedWindow) {
            return cleanedWindow
        }
        return cleanedTab.isEmpty
            ? (cleanedWindow.isEmpty ? "Kitty session \(id)" : cleanedWindow)
            : cleanedTab
    }
}

struct KittyTargetSummary: Equatable, Sendable {
    let targets: [KittySessionTarget]

    var windowCount: Int { targets.count }
    var titles: [String] { targets.map(\.displayTitle) }
}

enum KittyRemoteControlError: LocalizedError, Equatable {
    case executableNotFound
    case missingListenAddress
    case missingMatch
    case commandFailed(String)
    case malformedWindowList
    case noMatchingWindows(String)
    case noSelectedSessions

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Kitty could not be found. Choose its executable in Auto-Continue settings."
        case .missingListenAddress:
            "Enter Kitty's listen_on address."
        case .missingMatch:
            "Enter a Kitty window match expression."
        case .commandFailed(let detail):
            "Kitty remote control failed: \(detail)"
        case .malformedWindowList:
            "Kitty returned an unreadable window list."
        case .noMatchingWindows(let match):
            "No open Kitty windows matched “\(match)”. The continuation is still armed."
        case .noSelectedSessions:
            "No enrolled Kitty sessions are currently open. Scan targets and enable at least one session, or choose All sessions."
        }
    }
}

struct KittyRemoteControlClient: @unchecked Sendable {
    private let runner: CommandRunner
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectory: URL

    init(
        runner: CommandRunner = CommandRunner(),
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.runner = runner
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func matchingTargets(
        configuredPath: String,
        listenAddress: String,
        match: String
    ) async throws -> KittyTargetSummary {
        let executable = try resolveExecutable(configuredPath: configuredPath)
        let address = listenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { throw KittyRemoteControlError.missingListenAddress }
        let normalizedMatch = match.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMatch.isEmpty else { throw KittyRemoteControlError.missingMatch }

        let output = try await runner.run(
            executable: executable,
            arguments: [
                "@", "--to", address, "ls", "--match", normalizedMatch
            ],
            timeout: 8
        )
        guard output.exitCode == 0 else {
            throw commandError(from: output)
        }

        return try Self.parseTargetSummary(output.standardOutput)
    }

    func sendContinue(
        configuredPath: String,
        listenAddress: String,
        match: String,
        selectedWindowIDs: Set<Int>?
    ) async throws -> KittyTargetSummary {
        let matching = try await matchingTargets(
            configuredPath: configuredPath,
            listenAddress: listenAddress,
            match: match
        )
        guard matching.windowCount > 0 else {
            throw KittyRemoteControlError.noMatchingWindows(
                match.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let targets: [KittySessionTarget]
        if let selectedWindowIDs {
            targets = matching.targets.filter { selectedWindowIDs.contains($0.id) }
            guard !targets.isEmpty else {
                throw KittyRemoteControlError.noSelectedSessions
            }
        } else {
            targets = matching.targets
        }

        let executable = try resolveExecutable(configuredPath: configuredPath)
        let exactMatch = targets
            .map { "id:\($0.id)" }
            .joined(separator: " or ")
        let output = try await runner.run(
            executable: executable,
            arguments: [
                "@",
                "--to",
                listenAddress.trimmingCharacters(in: .whitespacesAndNewlines),
                "send-text",
                "--match",
                exactMatch,
                "continue\\r"
            ],
            timeout: 8
        )
        guard output.exitCode == 0 else {
            throw commandError(from: output)
        }
        return KittyTargetSummary(targets: targets)
    }

    static func parseTargetSummary(_ data: Data) throws -> KittyTargetSummary {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            throw KittyRemoteControlError.malformedWindowList
        }

        var targets: [KittySessionTarget] = []
        for osWindow in root {
            guard let tabs = osWindow["tabs"] as? [[String: Any]] else { continue }
            for tab in tabs {
                let tabTitle = tab["title"] as? String ?? ""
                guard let windows = tab["windows"] as? [[String: Any]] else { continue }
                for window in windows {
                    guard let id = (window["id"] as? NSNumber)?.intValue else { continue }
                    targets.append(
                        KittySessionTarget(
                            id: id,
                            tabTitle: tabTitle,
                            windowTitle: window["title"] as? String ?? "",
                            currentDirectory: window["cwd"] as? String,
                            commandLine: window["cmdline"] as? [String] ?? []
                        )
                    )
                }
            }
        }
        return KittyTargetSummary(targets: targets)
    }

    private func resolveExecutable(configuredPath: String) throws -> URL {
        let configured = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            do {
                return try CLIResolver(
                    fileManager: fileManager,
                    environment: environment,
                    homeDirectory: homeDirectory
                ).resolve("kitty", configuredPath: configured)
            } catch {
                throw KittyRemoteControlError.executableNotFound
            }
        }

        let applicationExecutable = "/Applications/kitty.app/Contents/MacOS/kitty"
        if fileManager.isExecutableFile(atPath: applicationExecutable) {
            return URL(fileURLWithPath: applicationExecutable)
        }
        do {
            return try CLIResolver(
                fileManager: fileManager,
                environment: environment,
                homeDirectory: homeDirectory
            ).resolve("kitty", configuredPath: nil)
        } catch {
            throw KittyRemoteControlError.executableNotFound
        }
    }

    private func commandError(from output: CommandOutput) -> KittyRemoteControlError {
        let detail = output.stderrString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .commandFailed(
            detail.isEmpty ? "the command exited with status \(output.exitCode)" : detail
        )
    }
}

enum KittySessionTitleFormatter {
    private static let leadingNoise = CharacterSet(
        charactersIn: " \t\n\r•●◉○◌✳✻✽✦◆◇›»|:—–-"
    )
    private static let genericTitles = [
        "kitty",
        "claude",
        "claude code",
        "codex",
        "shell",
        "zsh",
        "bash",
        "fish"
    ]
    private static let removableSuffixes = [
        " — kitty",
        " - kitty",
        " — claude code",
        " - claude code",
        " — codex",
        " - codex"
    ]

    static func clean(_ rawValue: String) -> String {
        var value = ANSITextCleaner.clean(rawValue)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: leadingNoise)

        var removedSuffix = true
        while removedSuffix {
            removedSuffix = false
            let lowercased = value.lowercased()
            for suffix in removableSuffixes where lowercased.hasSuffix(suffix) {
                value.removeLast(suffix.count)
                value = value.trimmingCharacters(in: leadingNoise)
                removedSuffix = true
                break
            }
        }
        return value
    }

    static func isGeneric(_ title: String) -> Bool {
        genericTitles.contains(title.lowercased())
    }
}
