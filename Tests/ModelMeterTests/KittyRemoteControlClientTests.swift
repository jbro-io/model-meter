import Foundation
import XCTest
@testable import ModelMeter

final class KittyRemoteControlClientTests: XCTestCase {
    func testParsesKittyTabsAndUsesCleanTabTitles() throws {
        let data = Data(
            """
            [
              {
                "id": 1,
                "tabs": [
                  {
                    "id": 10,
                    "title": "  ✳  Model Meter — Claude Code  ",
                    "windows": [
                      {
                        "id": 101,
                        "title": "claude",
                        "cwd": "/Users/test/model-meter",
                        "cmdline": ["claude"]
                      }
                    ]
                  },
                  {
                    "id": 11,
                    "title": "kitty",
                    "windows": [
                      {
                        "id": 102,
                        "title": "API cleanup — Codex",
                        "cwd": "/Users/test/api",
                        "cmdline": ["/bin/zsh"],
                        "foreground_processes": [
                          {"cmdline":["codex"],"cwd":"/Users/test/api","pid":42}
                        ]
                      }
                    ]
                  }
                ]
              }
            ]
            """.utf8
        )

        let summary = try KittyRemoteControlClient.parseTargetSummary(data)

        XCTAssertEqual(summary.windowCount, 2)
        XCTAssertEqual(summary.targets[0].id, 101)
        XCTAssertEqual(summary.targets[0].tabTitle, "  ✳  Model Meter — Claude Code  ")
        XCTAssertEqual(summary.targets[0].displayTitle, "Model Meter")
        XCTAssertEqual(summary.targets[0].currentDirectory, "/Users/test/model-meter")
        XCTAssertEqual(summary.targets[1].displayTitle, "API cleanup")
        XCTAssertTrue(summary.targets[1].matchesSmartQuery("codex"))
        XCTAssertFalse(summary.targets[1].matchesSmartQuery("claude"))
    }

    func testTitleCleanupRemovesANSIWhitespaceAndTerminalDecoration() {
        XCTAssertEqual(
            KittySessionTitleFormatter.clean(
                "\u{001B}[31m  •  Release   prep — Kitty \u{001B}[0m"
            ),
            "Release prep"
        )
        XCTAssertTrue(KittySessionTitleFormatter.isGeneric("Claude Code"))
        XCTAssertFalse(KittySessionTitleFormatter.isGeneric("Release prep"))
    }

    func testMalformedJSONThrowsTypedError() {
        XCTAssertThrowsError(
            try KittyRemoteControlClient.parseTargetSummary(Data("nope".utf8))
        ) { error in
            XCTAssertEqual(error as? KittyRemoteControlError, .malformedWindowList)
        }
    }

    func testParsesLastActiveListenAddressFromKittyConfiguration() {
        let resolver = KittyListenAddressResolver()
        let address = resolver.parseListenAddress(
            from: """
            # listen_on none
            listen_on unix:/tmp/old-kitty
            allow_remote_control yes
            listen_on unix:/tmp/current-kitty
            """
        )

        XCTAssertEqual(address, "unix:/tmp/current-kitty")
    }

    func testFallsBackToPIDSuffixedSocketFromKittyConfiguration() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "KittyListenAddressResolverTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let home = root.appendingPathComponent("home", isDirectory: true)
        let configDirectory = home.appendingPathComponent(
            ".config/kitty",
            isDirectory: true
        )
        let socketBase = root.appendingPathComponent("agent-kitty-tabs").path
        let liveSocket = socketBase + "-12345"
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true
        )
        try Data("listen_on unix:\(socketBase)\n".utf8).write(
            to: configDirectory.appendingPathComponent("kitty.conf")
        )
        XCTAssertTrue(fileManager.createFile(atPath: liveSocket, contents: Data()))

        let resolver = KittyListenAddressResolver(
            fileManager: fileManager,
            environment: [:],
            homeDirectory: home
        )

        let resolved = try XCTUnwrap(
            resolver.resolve(configuredAddress: "unix:/tmp/missing-model-meter")
        )
        let resolvedPath = String(resolved.dropFirst("unix:".count))
        XCTAssertEqual(
            URL(fileURLWithPath: resolvedPath).lastPathComponent,
            URL(fileURLWithPath: liveSocket).lastPathComponent
        )
        XCTAssertTrue(fileManager.fileExists(atPath: resolvedPath))
    }
}
