import Foundation

struct CLIResolver: @unchecked Sendable {
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

    func resolve(_ executable: String, configuredPath: String?) throws -> URL {
        let configured = configuredPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !configured.isEmpty {
            let expanded = expandTilde(in: configured)
            guard fileManager.isExecutableFile(atPath: expanded) else {
                throw UsageProviderError.executableNotFound(name: executable)
            }
            return URL(fileURLWithPath: expanded)
        }

        for path in candidatePaths(for: executable) where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        throw UsageProviderError.executableNotFound(name: executable)
    }

    func candidatePaths(for executable: String) -> [String] {
        var directories = [
            homeDirectory.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

        if let path = environment["PATH"] {
            directories.append(contentsOf: path.split(separator: ":").map(String.init))
        }

        var seen = Set<String>()
        return directories
            .map { URL(fileURLWithPath: $0).appendingPathComponent(executable).path }
            .filter { seen.insert($0).inserted }
    }

    private func expandTilde(in path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        if path == "~" { return homeDirectory.path }
        return homeDirectory.appendingPathComponent(String(path.dropFirst(2))).path
    }
}
