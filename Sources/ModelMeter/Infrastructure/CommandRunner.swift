@preconcurrency import Foundation
import Darwin

struct CommandOutput: Sendable {
    let standardOutput: Data
    let standardError: Data
    let exitCode: Int32

    var stdoutString: String {
        String(data: standardOutput, encoding: .utf8) ?? ""
    }

    var stderrString: String {
        String(data: standardError, encoding: .utf8) ?? ""
    }
}

struct CommandRunner: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval = 12,
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> CommandOutput {
        try await Task.detached(priority: .utility) {
            try Self.runSynchronously(
                executable: executable,
                arguments: arguments,
                timeout: timeout,
                environment: environment,
                currentDirectory: currentDirectory
            )
        }.value
    }

    private static func runSynchronously(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]?,
        currentDirectory: URL?
    ) throws -> CommandOutput {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutBuffer = LockedDataBuffer()
        let stderrBuffer = LockedDataBuffer()
        let completion = DispatchSemaphore(value: 0)

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.currentDirectoryURL = currentDirectory
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stdoutBuffer.append(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stderrBuffer.append(data) }
        }
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw UsageProviderError.processFailed(
                command: executable.lastPathComponent,
                detail: error.localizedDescription
            )
        }

        let completed = completion.wait(timeout: .now() + timeout) == .success
        if !completed {
            process.terminate()
            if completion.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = completion.wait(timeout: .now() + 1)
            }
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())

        guard completed else {
            throw UsageProviderError.timedOut(command: executable.lastPathComponent)
        }

        return CommandOutput(
            standardOutput: stdoutBuffer.value,
            standardError: stderrBuffer.value,
            exitCode: process.terminationStatus
        )
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private var storage = Data()
    private let lock = NSLock()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
