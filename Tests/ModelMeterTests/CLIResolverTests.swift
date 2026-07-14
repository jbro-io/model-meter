import Foundation
import XCTest
@testable import ModelMeter

final class CLIResolverTests: XCTestCase {
    private let fileManager = FileManager.default
    private var temporaryDirectory: URL!
    private var homeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ModelMeterTests-\(UUID().uuidString)", isDirectory: true)
        homeDirectory = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
        try fileManager.createDirectory(
            at: homeDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? fileManager.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        homeDirectory = nil
        try super.tearDownWithError()
    }

    func testConfiguredPathTakesPrecedenceOverDiscoveredCandidates() throws {
        let homeCandidate = try makeExecutable(
            at: homeDirectory.appendingPathComponent(".local/bin/claude")
        )
        let pathDirectory = temporaryDirectory.appendingPathComponent("path-bin", isDirectory: true)
        _ = try makeExecutable(at: pathDirectory.appendingPathComponent("claude"))
        let configured = try makeExecutable(
            at: temporaryDirectory.appendingPathComponent("configured/custom-claude")
        )
        let resolver = CLIResolver(
            fileManager: fileManager,
            environment: ["PATH": pathDirectory.path],
            homeDirectory: homeDirectory
        )

        XCTAssertNotEqual(homeCandidate.path, configured.path)
        XCTAssertEqual(
            try resolver.resolve("claude", configuredPath: configured.path).path,
            configured.path
        )
    }

    func testHomeLocalBinPrecedesPATHCandidates() throws {
        let homeCandidate = try makeExecutable(
            at: homeDirectory.appendingPathComponent(".local/bin/claude")
        )
        let firstPathDirectory = temporaryDirectory.appendingPathComponent("first-bin", isDirectory: true)
        let secondPathDirectory = temporaryDirectory.appendingPathComponent("second-bin", isDirectory: true)
        _ = try makeExecutable(at: firstPathDirectory.appendingPathComponent("claude"))
        _ = try makeExecutable(at: secondPathDirectory.appendingPathComponent("claude"))
        let resolver = CLIResolver(
            fileManager: fileManager,
            environment: [
                "PATH": [firstPathDirectory.path, secondPathDirectory.path]
                    .joined(separator: ":")
            ],
            homeDirectory: homeDirectory
        )

        XCTAssertEqual(
            try resolver.resolve("claude", configuredPath: nil).path,
            homeCandidate.path
        )
    }

    func testConfiguredPathExpandsTildeUsingInjectedHomeDirectory() throws {
        let executable = try makeExecutable(
            at: homeDirectory.appendingPathComponent("tools/claude")
        )
        let resolver = CLIResolver(
            fileManager: fileManager,
            environment: [:],
            homeDirectory: homeDirectory
        )

        XCTAssertEqual(
            try resolver.resolve("claude", configuredPath: "  ~/tools/claude\n").path,
            executable.path
        )
    }

    func testMissingExecutableThrowsTypedError() {
        let executable = "model-meter-definitely-missing-cli"
        let resolver = CLIResolver(
            fileManager: fileManager,
            environment: ["PATH": temporaryDirectory.path],
            homeDirectory: homeDirectory
        )

        XCTAssertThrowsError(try resolver.resolve(executable, configuredPath: nil)) { error in
            XCTAssertEqual(
                error as? UsageProviderError,
                .executableNotFound(name: executable)
            )
        }
    }

    @discardableResult
    private func makeExecutable(at url: URL) throws -> URL {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: url.path
        )
        return url
    }
}
