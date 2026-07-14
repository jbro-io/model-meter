import Foundation

enum CodexProtocol {
    static let initializeID = 1
    static let rateLimitsID = 2
    static let usageID = 3

    static func startupPayload(clientVersion: String) throws -> Data {
        let messages: [[String: Any]] = [
            [
                "method": "initialize",
                "id": initializeID,
                "params": [
                    "clientInfo": [
                        "name": "model_meter",
                        "title": "Model Meter",
                        "version": clientVersion,
                    ],
                    "capabilities": NSNull(),
                ],
            ],
            [
                "method": "initialized",
            ],
            [
                "method": "account/rateLimits/read",
                "id": rateLimitsID,
            ],
            [
                "method": "account/usage/read",
                "id": usageID,
            ],
        ]

        var payload = Data()
        for message in messages {
            payload.append(try JSONSerialization.data(withJSONObject: message, options: []))
            payload.append(0x0A)
        }
        return payload
    }

    static func responseID(in line: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let number = object["id"] as? NSNumber
        else { return nil }
        return number.intValue
    }

    static func decode<Result: Decodable>(
        _ type: Result.Type,
        from line: Data,
        expectedID: Int
    ) throws -> Result {
        let response: CodexRPCResponse<Result>
        do {
            response = try JSONDecoder().decode(CodexRPCResponse<Result>.self, from: line)
        } catch {
            throw UsageProviderError.malformedResponse(provider: "Codex")
        }

        guard response.id == expectedID else {
            throw UsageProviderError.malformedResponse(provider: "Codex")
        }
        if let error = response.error {
            let message = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.localizedCaseInsensitiveContains("authentication required")
                || message.localizedCaseInsensitiveContains("sign in")
                || message.localizedCaseInsensitiveContains("not logged in")
            {
                throw UsageProviderError.notAuthenticated(provider: "Codex")
            }
            throw UsageProviderError.processFailed(
                command: "codex app-server",
                detail: message.isEmpty ? "Request failed with code \(error.code)." : message
            )
        }
        guard let result = response.result else {
            throw UsageProviderError.malformedResponse(provider: "Codex")
        }
        return result
    }
}

struct CodexRPCResponse<Result: Decodable>: Decodable {
    let id: Int
    let result: Result?
    let error: CodexRPCError?
}

struct CodexRPCError: Decodable, Equatable {
    let code: Int
    let message: String
}

struct CodexInitializeResult: Decodable, Equatable {
    let userAgent: String?
    let codexHome: String?
    let platformFamily: String?
    let platformOs: String?
}

struct CodexRateLimitsResult: Decodable, Equatable {
    let rateLimits: CodexRateLimitSnapshot
    let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
}

struct CodexRateLimitSnapshot: Decodable, Equatable {
    let limitId: String?
    let limitName: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let credits: CodexCreditsSnapshot?
    let individualLimit: CodexSpendControlLimitSnapshot?
    let planType: String?
    let rateLimitReachedType: String?
}

struct CodexRateLimitWindow: Decodable, Equatable {
    let usedPercent: Int
    let windowDurationMins: Int64?
    let resetsAt: Int64?
}

struct CodexCreditsSnapshot: Decodable, Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct CodexSpendControlLimitSnapshot: Decodable, Equatable {
    let limit: String
    let used: String
    let remainingPercent: Int
    let resetsAt: Int64
}

struct CodexAccountUsageResult: Decodable, Equatable {
    let summary: CodexAccountUsageSummary
    let dailyUsageBuckets: [CodexDailyUsageBucket]?
}

struct CodexAccountUsageSummary: Decodable, Equatable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int64?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
}

struct CodexDailyUsageBucket: Decodable, Equatable {
    let startDate: String
    let tokens: Int64
}
