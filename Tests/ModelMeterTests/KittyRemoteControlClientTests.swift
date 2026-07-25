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
                        "cmdline": ["codex"]
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
}
