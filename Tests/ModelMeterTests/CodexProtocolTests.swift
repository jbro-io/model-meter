import Foundation
import XCTest
@testable import ModelMeter

final class CodexProtocolTests: XCTestCase {
    func testStartupPayloadUsesExpectedJSONLMethodsAndIDs() throws {
        let payload = try CodexProtocol.startupPayload(clientVersion: "0.1.0-test")
        let lines = payload.split(separator: 0x0A)
        let messages = try lines.map { line -> [String: Any] in
            let object = try JSONSerialization.jsonObject(with: Data(line))
            return try XCTUnwrap(object as? [String: Any])
        }

        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(payload.last, 0x0A)
        XCTAssertEqual(
            messages.compactMap { $0["method"] as? String },
            [
                "initialize",
                "initialized",
                "account/rateLimits/read",
                "account/usage/read",
            ]
        )
        XCTAssertEqual(
            messages.map { ($0["id"] as? NSNumber)?.intValue },
            [
                CodexProtocol.initializeID,
                nil,
                CodexProtocol.rateLimitsID,
                CodexProtocol.usageID,
            ]
        )

        let initializeParams = try XCTUnwrap(messages[0]["params"] as? [String: Any])
        let clientInfo = try XCTUnwrap(initializeParams["clientInfo"] as? [String: Any])
        XCTAssertEqual(clientInfo["name"] as? String, "model_meter")
        XCTAssertEqual(clientInfo["title"] as? String, "Model Meter")
        XCTAssertEqual(clientInfo["version"] as? String, "0.1.0-test")
        XCTAssertTrue(initializeParams["capabilities"] is NSNull)
    }

    func testDecodesRateLimitsWithMultipleBucketsAndCredits() throws {
        let result = try CodexProtocol.decode(
            CodexRateLimitsResult.self,
            from: fixtureData(named: "codex-rate-limits"),
            expectedID: CodexProtocol.rateLimitsID
        )

        XCTAssertEqual(result.rateLimits.limitId, "codex")
        XCTAssertEqual(result.rateLimits.limitName, "Codex")
        XCTAssertEqual(result.rateLimits.planType, "plus")

        let primary = try XCTUnwrap(result.rateLimits.primary)
        XCTAssertEqual(primary.usedPercent, 42)
        XCTAssertEqual(primary.windowDurationMins, 300)
        XCTAssertEqual(primary.resetsAt, 1_900_003_600)

        let secondary = try XCTUnwrap(result.rateLimits.secondary)
        XCTAssertEqual(secondary.usedPercent, 71)
        XCTAssertEqual(secondary.windowDurationMins, 10_080)
        XCTAssertEqual(secondary.resetsAt, 1_900_604_800)

        let credits = try XCTUnwrap(result.rateLimits.credits)
        XCTAssertTrue(credits.hasCredits)
        XCTAssertFalse(credits.unlimited)
        XCTAssertEqual(credits.balance, "17.50")

        let individualLimit = try XCTUnwrap(result.rateLimits.individualLimit)
        XCTAssertEqual(individualLimit.limit, "50.00")
        XCTAssertEqual(individualLimit.used, "12.50")
        XCTAssertEqual(individualLimit.remainingPercent, 75)
        XCTAssertEqual(individualLimit.resetsAt, 1_901_318_400)

        let buckets = try XCTUnwrap(result.rateLimitsByLimitId)
        XCTAssertEqual(Set(buckets.keys), ["codex", "codex-mini"])
        XCTAssertEqual(buckets["codex"]?.primary?.usedPercent, 42)
        XCTAssertEqual(buckets["codex-mini"]?.limitName, "Codex Mini")
        XCTAssertEqual(buckets["codex-mini"]?.primary?.usedPercent, 18)
        XCTAssertTrue(try XCTUnwrap(buckets["codex-mini"]?.credits).unlimited)
    }

    func testDecodesAccountUsageSummaryAndDailyBuckets() throws {
        let result = try CodexProtocol.decode(
            CodexAccountUsageResult.self,
            from: fixtureData(named: "codex-account-usage"),
            expectedID: CodexProtocol.usageID
        )

        XCTAssertEqual(result.summary.lifetimeTokens, 1_234_567)
        XCTAssertEqual(result.summary.peakDailyTokens, 98_765)
        XCTAssertEqual(result.summary.longestRunningTurnSec, 2_345)
        XCTAssertEqual(result.summary.currentStreakDays, 6)
        XCTAssertEqual(result.summary.longestStreakDays, 21)

        let buckets = try XCTUnwrap(result.dailyUsageBuckets)
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets[0].startDate, "2030-03-01")
        XCTAssertEqual(buckets[0].tokens, 12_345)
        XCTAssertEqual(buckets[2].startDate, "2030-03-03")
        XCTAssertEqual(buckets[2].tokens, 34_567)
    }

    func testMapsRPCAuthenticationErrorToNotAuthenticated() throws {
        XCTAssertThrowsError(
            try CodexProtocol.decode(
                CodexRateLimitsResult.self,
                from: fixtureData(named: "codex-auth-error"),
                expectedID: CodexProtocol.rateLimitsID
            )
        ) { error in
            XCTAssertEqual(
                error as? UsageProviderError,
                .notAuthenticated(provider: "Codex")
            )
        }
    }

    func testIgnoresUnknownFieldsAtEveryResponseLevel() throws {
        let result = try CodexProtocol.decode(
            CodexRateLimitsResult.self,
            from: fixtureData(named: "codex-unknown-fields"),
            expectedID: CodexProtocol.rateLimitsID
        )

        XCTAssertEqual(result.rateLimits.limitId, "future-compatible")
        XCTAssertEqual(result.rateLimits.primary?.usedPercent, 7)
        XCTAssertEqual(result.rateLimits.credits?.hasCredits, false)
        XCTAssertNil(result.rateLimitsByLimitId)
    }

    private func fixtureData(named name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        )
        return try Data(contentsOf: url)
    }
}
