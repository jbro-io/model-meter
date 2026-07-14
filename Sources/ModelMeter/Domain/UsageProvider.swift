import Foundation

protocol UsageProviding: Sendable {
    var providerID: ProviderID { get }
    func fetch() async throws -> ProviderUsageSnapshot
}

enum UsageProviderError: LocalizedError, Equatable {
    case executableNotFound(name: String)
    case notAuthenticated(provider: String)
    case processFailed(command: String, detail: String)
    case timedOut(command: String)
    case malformedResponse(provider: String)
    case unsupported(message: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            "Could not find \(name). Set its path in Model Meter settings."
        case .notAuthenticated(let provider):
            "\(provider) CLI is not signed in."
        case .processFailed(let command, let detail):
            detail.isEmpty ? "\(command) failed." : "\(command) failed: \(detail)"
        case .timedOut(let command):
            "\(command) did not respond in time."
        case .malformedResponse(let provider):
            "\(provider) returned usage data in an unrecognized format."
        case .unsupported(let message):
            message
        }
    }
}
