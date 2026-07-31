import Foundation

struct KittySessionTarget: Identifiable, Equatable, Sendable {
    let id: Int
    let tabTitle: String
    let windowTitle: String
    let currentDirectory: String?
    let commandLine: [String]
    let foregroundCommandLines: [[String]]

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

    func matchesSmartQuery(_ query: String) -> Bool {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return false }

        if Self.knownAgentNames.contains(needle) {
            let runningAgents = directlyRunningAgentNames
            if !runningAgents.isEmpty {
                return runningAgents.contains(needle)
            }

            return [tabTitle, windowTitle].contains {
                $0.localizedCaseInsensitiveContains(needle)
            }
        }

        let searchableValues = [
            tabTitle,
            windowTitle,
            commandLine.joined(separator: " ")
        ] + foregroundCommandLines.map { $0.joined(separator: " ") }
        return searchableValues.contains {
            $0.localizedCaseInsensitiveContains(needle)
        }
    }

    private static let knownAgentNames: Set<String> = ["claude", "codex"]

    private var directlyRunningAgentNames: Set<String> {
        Set(
            ([commandLine] + foregroundCommandLines).compactMap { commandLine in
                guard let executable = commandLine.first else { return nil }
                let name = (executable as NSString).lastPathComponent.lowercased()
                return Self.knownAgentNames.contains(name) ? name : nil
            }
        )
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
    case selectedSessionsChanged
    case deliveryCancelled

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
        case .selectedSessionsChanged:
            "An enrolled Kitty session changed while delivery was being validated. Scan targets before sending."
        case .deliveryCancelled:
            "Kitty targets changed before delivery. No text was sent."
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
        let address = try resolveListenAddress(configuredAddress: listenAddress)
        let normalizedMatch = match.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMatch.isEmpty else { throw KittyRemoteControlError.missingMatch }

        return try await matchingTargets(
            executable: executable,
            address: address,
            match: normalizedMatch
        )
    }

    func sendContinue(
        configuredPath: String,
        listenAddress: String,
        match: String,
        selectedWindowIDs: Set<Int>?,
        beforeSend: @escaping @Sendable () async -> Bool = { true }
    ) async throws -> KittyTargetSummary {
        let executable = try resolveExecutable(configuredPath: configuredPath)
        let address = try resolveListenAddress(configuredAddress: listenAddress)
        let normalizedMatch = match.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMatch.isEmpty else { throw KittyRemoteControlError.missingMatch }
        let matching = try await matchingTargets(
            executable: executable,
            address: address,
            match: normalizedMatch
        )
        guard matching.windowCount > 0 else {
            throw KittyRemoteControlError.noMatchingWindows(normalizedMatch)
        }

        let targets: [KittySessionTarget]
        if let selectedWindowIDs {
            targets = matching.targets.filter { selectedWindowIDs.contains($0.id) }
            guard !targets.isEmpty else {
                throw KittyRemoteControlError.noSelectedSessions
            }
            guard Set(targets.map(\.id)) == selectedWindowIDs else {
                throw KittyRemoteControlError.selectedSessionsChanged
            }
        } else {
            targets = matching.targets
        }

        let exactMatch = targets
            .map { "id:\($0.id)" }
            .joined(separator: " or ")
        guard await beforeSend() else {
            throw KittyRemoteControlError.deliveryCancelled
        }
        let output = try await runner.run(
            executable: executable,
            arguments: [
                "@",
                "--to",
                address,
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

    private func matchingTargets(
        executable: URL,
        address: String,
        match: String
    ) async throws -> KittyTargetSummary {
        if let smartQuery = smartQuery(from: match) {
            let summary = try await allTargets(executable: executable, address: address)
            return KittyTargetSummary(
                targets: summary.targets.filter { $0.matchesSmartQuery(smartQuery) }
            )
        }

        let output = try await runner.run(
            executable: executable,
            arguments: [
                "@", "--to", address, "ls", "--match", match
            ],
            timeout: 8
        )
        if output.exitCode != 0,
           output.stderrString.localizedCaseInsensitiveContains("no matching windows") {
            return KittyTargetSummary(targets: [])
        }
        guard output.exitCode == 0 else {
            throw commandError(from: output)
        }
        return try Self.parseTargetSummary(output.standardOutput)
    }

    private func allTargets(
        executable: URL,
        address: String
    ) async throws -> KittyTargetSummary {
        let output = try await runner.run(
            executable: executable,
            arguments: ["@", "--to", address, "ls"],
            timeout: 8
        )
        guard output.exitCode == 0 else {
            throw commandError(from: output)
        }
        return try Self.parseTargetSummary(output.standardOutput)
    }

    private func smartQuery(from match: String) -> String? {
        let components = match.split(separator: ":", maxSplits: 1)
        guard components.count == 2,
              String(components[0]).caseInsensitiveCompare("smart") == .orderedSame
        else { return nil }
        let query = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
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
                            commandLine: window["cmdline"] as? [String] ?? [],
                            foregroundCommandLines: (
                                window["foreground_processes"] as? [[String: Any]]
                            )?.compactMap { $0["cmdline"] as? [String] } ?? []
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

    private func resolveListenAddress(configuredAddress: String) throws -> String {
        let resolver = KittyListenAddressResolver(
            fileManager: fileManager,
            environment: environment,
            homeDirectory: homeDirectory
        )
        if let address = resolver.resolve(configuredAddress: configuredAddress) {
            return address
        }
        throw KittyRemoteControlError.missingListenAddress
    }

    private func commandError(from output: CommandOutput) -> KittyRemoteControlError {
        let detail = output.stderrString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .commandFailed(
            detail.isEmpty ? "the command exited with status \(output.exitCode)" : detail
        )
    }
}

struct KittyListenAddressResolver: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectory: URL

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func resolve(configuredAddress: String) -> String? {
        var addresses: [String] = []
        let configured = normalizedAddress(configuredAddress)
        if let configured {
            addresses.append(configured)
        }
        if let kittyConfigAddress = listenAddressFromKittyConfig(),
           !addresses.contains(kittyConfigAddress) {
            addresses.append(kittyConfigAddress)
        }

        for address in addresses {
            if exactSocketExists(for: address) {
                return address
            }
            if let liveAddress = newestPIDSuffixedAddress(for: address) {
                return liveAddress
            }
        }
        return configured ?? addresses.first
    }

    func parseListenAddress(from configuration: String) -> String? {
        configuration
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine -> String? in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
                let components = line.split(
                    maxSplits: 1,
                    whereSeparator: \.isWhitespace
                )
                guard components.count == 2, components[0] == "listen_on" else {
                    return nil
                }
                return normalizedAddress(String(components[1]))
            }
            .last
    }

    private func listenAddressFromKittyConfig() -> String? {
        for url in configurationCandidates() {
            guard let data = fileManager.contents(atPath: url.path),
                  let configuration = String(data: data, encoding: .utf8),
                  let address = parseListenAddress(from: configuration)
            else { continue }
            return address
        }
        return nil
    }

    private func configurationCandidates() -> [URL] {
        var urls: [URL] = []
        if let directory = environment["KITTY_CONFIG_DIRECTORY"], !directory.isEmpty {
            urls.append(
                URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
                    .appendingPathComponent("kitty.conf")
            )
        }
        if let directory = environment["XDG_CONFIG_HOME"], !directory.isEmpty {
            urls.append(
                URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
                    .appendingPathComponent("kitty/kitty.conf")
            )
        }
        urls.append(
            homeDirectory.appendingPathComponent(".config/kitty/kitty.conf")
        )
        urls.append(
            homeDirectory.appendingPathComponent(
                "Library/Preferences/kitty/kitty.conf"
            )
        )

        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func normalizedAddress(_ value: String) -> String? {
        let address = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty,
              address.caseInsensitiveCompare("none") != .orderedSame
        else { return nil }
        return address
    }

    private func exactSocketExists(for address: String) -> Bool {
        guard let path = unixSocketPath(from: address) else { return true }
        return fileManager.fileExists(atPath: path)
    }

    private func newestPIDSuffixedAddress(for address: String) -> String? {
        guard let socketPath = unixSocketPath(from: address) else { return nil }
        let url = URL(fileURLWithPath: socketPath)
        let directory = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + "-"
        guard let candidates = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let matches = candidates.filter {
            $0.lastPathComponent.hasPrefix(prefix)
                && fileManager.fileExists(atPath: $0.path)
        }
        let newest = matches.max { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            return leftDate < rightDate
        }
        guard let newest else { return nil }
        return "unix:\(newest.path)"
    }

    private func unixSocketPath(from address: String) -> String? {
        guard address.hasPrefix("unix:") else { return nil }
        let path = String(address.dropFirst("unix:".count))
        guard !path.isEmpty, !path.hasPrefix("@") else { return nil }
        return (path as NSString).expandingTildeInPath
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
