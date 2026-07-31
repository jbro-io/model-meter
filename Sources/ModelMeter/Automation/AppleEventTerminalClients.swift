import AppKit
import Foundation
@preconcurrency import OSAKit

struct AppleEventScriptFailure: Error, Equatable, Sendable {
    let number: Int?
    let message: String
}

actor AppleEventScriptExecutor {
    func executeJavaScript(
        _ source: String,
        authorization: (@MainActor @Sendable () -> Bool)? = nil
    ) async -> Result<String, AppleEventScriptFailure> {
        if let authorization, !(await authorization()) {
            return .failure(
                AppleEventScriptFailure(
                    number: nil,
                    message: "MODEL_METER_ROUTE_CHANGED"
                )
            )
        }
        return Self.execute(source)
    }

    private static func execute(
        _ source: String
    ) -> Result<String, AppleEventScriptFailure> {
            guard let language = OSALanguage(forName: "JavaScript") else {
                return .failure(
                    AppleEventScriptFailure(
                        number: nil,
                        message: "JavaScript for Automation is unavailable"
                    )
                )
            }

            let script = OSAScript(source: source, language: language)
            var errorInfo: NSDictionary?
            guard let result = script.executeAndReturnError(&errorInfo) else {
                return .failure(Self.failure(from: errorInfo))
            }
            return .success(result.stringValue ?? "")
    }

    private static func failure(from errorInfo: NSDictionary?) -> AppleEventScriptFailure {
        let number = (
            errorInfo?["OSAScriptErrorNumber"] as? NSNumber
        )?.intValue
        let message = (
            errorInfo?["OSAScriptErrorMessage"] as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppleEventScriptFailure(
            number: number,
            message: (message?.isEmpty == false)
                ? message!
                : "Apple Events request failed"
        )
    }
}

struct TerminalApplicationInspector: Sendable {
    @MainActor
    func runningVersion(bundleIdentifier: String) -> String? {
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first else {
            return nil
        }
        guard let bundleURL = application.bundleURL,
              let bundle = Bundle(url: bundleURL)
        else {
            return ""
        }
        return bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
    }
}

struct ITermAutomationClient: TerminalAutomationClient {
    let terminal = AutoContinueTerminal.iterm
    private let executor: AppleEventScriptExecutor
    private let applicationInspector: TerminalApplicationInspector

    @MainActor
    init(
        executor: AppleEventScriptExecutor = AppleEventScriptExecutor(),
        applicationInspector: TerminalApplicationInspector = TerminalApplicationInspector()
    ) {
        self.executor = executor
        self.applicationInspector = applicationInspector
    }

    func preflight(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalPreflightResult {
        guard configuration.terminal == terminal else {
            return .failure(
                .configuration(terminal: terminal, detail: "terminal mismatch")
            )
        }
        guard applicationInspector.runningVersion(
            bundleIdentifier: "com.googlecode.iterm2"
        ) != nil else {
            return .failure(.notRunning(terminal))
        }
        return .ready
    }

    func scan(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalScanResult {
        let preflightResult = await preflight(configuration: configuration)
        guard case .ready = preflightResult else {
            if case .failure(let issue) = preflightResult {
                return .failure(issue)
            }
            return .failure(.partial(terminal: terminal, detail: "preflight failed"))
        }

        switch await executor.executeJavaScript(Self.scanScript) {
        case .success(let output):
            do {
                return .complete(
                    try Self.parseTargets(
                        Data(output.utf8),
                        provider: configuration.provider
                    )
                )
            } catch {
                return .failure(
                    .partial(terminal: terminal, detail: "unreadable session data")
                )
            }
        case .failure(let failure):
            return .failure(issue(from: failure))
        }
    }

    func sendContinue(
        configuration: TerminalAutomationConfiguration,
        authorization: @escaping @MainActor @Sendable () -> Bool
    ) async -> TerminalSendResult {
        guard !configuration.allSessions else {
            return .failure(
                .configuration(
                    terminal: terminal,
                    detail: "All Matching is unavailable; enroll explicit sessions"
                )
            )
        }
        guard !configuration.enrolledTargets.isEmpty else {
            return .failure(.noSelectedSessions(terminal: terminal))
        }

        let scanResult = await scan(configuration: configuration)
        guard case .complete(let liveSummary) = scanResult else {
            if case .failure(let issue) = scanResult {
                return .failure(issue)
            }
            return .failure(.partial(terminal: terminal, detail: "scan failed"))
        }
        switch Self.validatedTargets(
            enrolled: configuration.enrolledTargets,
            live: liveSummary.targets,
            terminal: terminal
        ) {
        case .failure(let issue):
            return .failure(issue)
        case .success(let targets):
            let script = Self.sendScript(ids: targets.map(\.id))
            switch await executor.executeJavaScript(
                script,
                authorization: {
                    authorization() && !Task.isCancelled
                }
            ) {
            case .failure(let failure):
                return .failure(issue(from: failure))
            case .success(let output):
                return AppleEventDeliveryParser.parse(
                    output,
                    targets: targets,
                    terminal: terminal,
                    targetNoun: "session"
                )
            }
        }
    }

    nonisolated static func parseTargets(
        _ data: Data,
        provider: ProviderID
    ) throws -> TerminalTargetSummary {
        let records = try JSONDecoder().decode([ITermSessionRecord].self, from: data)
        let targets = records.compactMap { record -> TerminalSessionTarget? in
            guard TerminalAgentMatcher.detectedITermProvider(
                jobName: record.jobName,
                commandLine: record.commandLine,
                title: record.name
            ) == provider else {
                return nil
            }
            let title = KittySessionTitleFormatter.clean(record.name)
            return TerminalSessionTarget(
                terminal: .iterm,
                provider: provider,
                id: record.id,
                displayTitle: title.isEmpty
                    ? "\(provider.displayName) iTerm2 session"
                    : title,
                currentDirectory: normalizedDirectory(record.path),
                processName: provider.rawValue,
                auxiliaryIdentifier: record.tty
            )
        }
        guard Set(targets.map(\.id)).count == targets.count else {
            throw TerminalTargetParsingError.duplicateID
        }
        return TerminalTargetSummary(targets: targets)
    }

    fileprivate static func validatedTargets(
        enrolled: [TerminalSessionTarget],
        live: [TerminalSessionTarget],
        terminal: AutoContinueTerminal
    ) -> Result<[TerminalSessionTarget], TerminalAutomationIssue> {
        let liveByID = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        var targets: [TerminalSessionTarget] = []
        for enrolledTarget in enrolled {
            guard enrolledTarget.terminal == terminal,
                  let liveTarget = liveByID[enrolledTarget.id],
                  enrolledTarget.identifiesSameLiveSession(as: liveTarget)
            else {
                return .failure(
                    .noLongerMatches(
                        terminal: terminal,
                        title: enrolledTarget.displayTitle
                    )
                )
            }
            targets.append(liveTarget)
        }
        return .success(targets)
    }

    private static func sendScript(ids: [String]) -> String {
        let idsLiteral = jsonLiteral(ids)
        return """
        (() => {
          const app = Application("iTerm");
          if (!app.running()) throw new Error("MODEL_METER_NOT_RUNNING");
          const wanted = new Set(\(idsLiteral));
          const targets = [];
          (app.windows() || []).forEach(window => {
            (window.tabs() || []).forEach(tab => {
              (tab.sessions() || []).forEach(session => {
                const id = String(session.id());
                if (wanted.has(id)) {
                  targets.push({id: id, session: session});
                }
              });
            });
          });
          if (targets.length !== wanted.size) {
            throw new Error("MODEL_METER_TARGET_CHANGED");
          }
          const sentIDs = [];
          const failedIDs = [];
          targets.forEach(target => {
            try {
              target.session.write({text: "continue", newline: true});
              sentIDs.push(target.id);
            } catch (_) {
              failedIDs.push(target.id);
            }
          });
          return JSON.stringify({sentIDs: sentIDs, failedIDs: failedIDs});
        })()
        """
    }

    private func issue(from failure: AppleEventScriptFailure) -> TerminalAutomationIssue {
        if failure.number == -1743 {
            return .unauthorized(terminal)
        }
        if failure.message.contains("MODEL_METER_NOT_RUNNING") {
            return .notRunning(terminal)
        }
        if failure.message.contains("MODEL_METER_TARGET_CHANGED") {
            return .partial(
                terminal: terminal,
                detail: "a selected session changed before delivery"
            )
        }
        if failure.message.contains("MODEL_METER_ROUTE_CHANGED") {
            return .routeChanged(terminal)
        }
        return .partial(terminal: terminal, detail: failure.message)
    }

    private static let scanScript = """
    (() => {
      const app = Application("iTerm");
      if (!app.running()) throw new Error("MODEL_METER_NOT_RUNNING");
      const text = value => value == null ? "" : String(value);
      const variable = (session, name) => {
        try { return text(session.variable({named: name})); }
        catch (_) { return ""; }
      };
      const sessions = [];
      (app.windows() || []).forEach(window => {
        (window.tabs() || []).forEach(tab => {
          (tab.sessions() || []).forEach(session => {
            sessions.push({
              id: text(session.id()),
              name: text(session.name()),
              tty: text(session.tty()),
              jobName: variable(session, "jobName"),
              commandLine: variable(session, "commandLine"),
              path: variable(session, "path")
            });
          });
        });
      });
      return JSON.stringify(sessions);
    })()
    """
}

struct GhosttyAutomationClient: TerminalAutomationClient {
    let terminal = AutoContinueTerminal.ghostty
    private let executor: AppleEventScriptExecutor
    private let applicationInspector: TerminalApplicationInspector

    @MainActor
    init(
        executor: AppleEventScriptExecutor = AppleEventScriptExecutor(),
        applicationInspector: TerminalApplicationInspector = TerminalApplicationInspector()
    ) {
        self.executor = executor
        self.applicationInspector = applicationInspector
    }

    func preflight(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalPreflightResult {
        guard configuration.terminal == terminal else {
            return .failure(
                .configuration(terminal: terminal, detail: "terminal mismatch")
            )
        }
        guard let version = applicationInspector.runningVersion(
            bundleIdentifier: "com.mitchellh.ghostty"
        ) else {
            return .failure(.notRunning(terminal))
        }
        guard Self.version(version, isAtLeast: "1.3.0") else {
            return .failure(
                .unsupportedVersion(terminal: terminal, minimum: "1.3.0")
            )
        }
        return .ready
    }

    func scan(
        configuration: TerminalAutomationConfiguration
    ) async -> TerminalScanResult {
        let preflightResult = await preflight(configuration: configuration)
        guard case .ready = preflightResult else {
            if case .failure(let issue) = preflightResult {
                return .failure(issue)
            }
            return .failure(.partial(terminal: terminal, detail: "preflight failed"))
        }

        switch await executor.executeJavaScript(Self.scanScript) {
        case .success(let output):
            do {
                return .complete(
                    try Self.parseTargets(
                        Data(output.utf8),
                        provider: configuration.provider
                    )
                )
            } catch {
                return .failure(
                    .partial(terminal: terminal, detail: "unreadable terminal data")
                )
            }
        case .failure(let failure):
            return .failure(issue(from: failure))
        }
    }

    func sendContinue(
        configuration: TerminalAutomationConfiguration,
        authorization: @escaping @MainActor @Sendable () -> Bool
    ) async -> TerminalSendResult {
        guard !configuration.allSessions else {
            return .failure(
                .configuration(
                    terminal: terminal,
                    detail: "Ghostty preview requires explicit session enrollment"
                )
            )
        }
        guard !configuration.enrolledTargets.isEmpty else {
            return .failure(.noSelectedSessions(terminal: terminal))
        }

        let scanResult = await scan(configuration: configuration)
        guard case .complete(let liveSummary) = scanResult else {
            if case .failure(let issue) = scanResult {
                return .failure(issue)
            }
            return .failure(.partial(terminal: terminal, detail: "scan failed"))
        }
        switch ITermAutomationClient.validatedTargets(
            enrolled: configuration.enrolledTargets,
            live: liveSummary.targets,
            terminal: terminal
        ) {
        case .failure(let issue):
            return .failure(issue)
        case .success(let targets):
            let script = Self.sendScript(ids: targets.map(\.id))
            switch await executor.executeJavaScript(
                script,
                authorization: {
                    authorization() && !Task.isCancelled
                }
            ) {
            case .failure(let failure):
                return .failure(issue(from: failure))
            case .success(let output):
                return AppleEventDeliveryParser.parse(
                    output,
                    targets: targets,
                    terminal: terminal,
                    targetNoun: "terminal"
                )
            }
        }
    }

    nonisolated static func parseTargets(
        _ data: Data,
        provider: ProviderID
    ) throws -> TerminalTargetSummary {
        let records = try JSONDecoder().decode([GhosttyTerminalRecord].self, from: data)
        let targets = records.compactMap { record -> TerminalSessionTarget? in
            guard TerminalAgentMatcher.exactTitleMatches(
                record.name,
                provider: provider
            ) else {
                return nil
            }
            let title = KittySessionTitleFormatter.clean(record.name)
            return TerminalSessionTarget(
                terminal: .ghostty,
                provider: provider,
                id: record.id,
                displayTitle: title.isEmpty
                    ? "\(provider.displayName) Ghostty terminal"
                    : title,
                currentDirectory: normalizedDirectory(record.workingDirectory),
                processName: nil,
                auxiliaryIdentifier: nil
            )
        }
        guard Set(targets.map(\.id)).count == targets.count else {
            throw TerminalTargetParsingError.duplicateID
        }
        return TerminalTargetSummary(targets: targets)
    }

    nonisolated static func version(
        _ candidate: String,
        isAtLeast minimum: String
    ) -> Bool {
        let left = numericVersion(candidate)
        let right = numericVersion(minimum)
        guard !left.isEmpty, !right.isEmpty else { return false }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return true
    }

    nonisolated private static func numericVersion(_ value: String) -> [Int] {
        value.split(separator: ".").compactMap { component in
            let digits = component.prefix(while: \.isNumber)
            return digits.isEmpty ? nil : Int(digits)
        }
    }

    private static func sendScript(ids: [String]) -> String {
        let idsLiteral = jsonLiteral(ids)
        return """
        (() => {
          const app = Application("Ghostty");
          if (!app.running()) throw new Error("MODEL_METER_NOT_RUNNING");
          const wanted = new Set(\(idsLiteral));
          const targets = [];
          (app.terminals() || []).forEach(terminal => {
            const id = String(terminal.id());
            if (wanted.has(id)) {
              targets.push({id: id, terminal: terminal});
            }
          });
          if (targets.length !== wanted.size) {
            throw new Error("MODEL_METER_TARGET_CHANGED");
          }
          const sentIDs = [];
          const failedIDs = [];
          targets.forEach(target => {
            try {
              app.inputText("continue", {to: target.terminal});
              app.sendKey("enter", {to: target.terminal});
              sentIDs.push(target.id);
            } catch (_) {
              failedIDs.push(target.id);
            }
          });
          return JSON.stringify({sentIDs: sentIDs, failedIDs: failedIDs});
        })()
        """
    }

    private func issue(from failure: AppleEventScriptFailure) -> TerminalAutomationIssue {
        if failure.number == -1743 {
            return .unauthorized(terminal)
        }
        if failure.message.contains("MODEL_METER_NOT_RUNNING") {
            return .notRunning(terminal)
        }
        if failure.message.contains("MODEL_METER_TARGET_CHANGED") {
            return .partial(
                terminal: terminal,
                detail: "a selected terminal changed before delivery"
            )
        }
        if failure.message.contains("MODEL_METER_ROUTE_CHANGED") {
            return .routeChanged(terminal)
        }
        return .partial(terminal: terminal, detail: failure.message)
    }

    private static let scanScript = """
    (() => {
      const app = Application("Ghostty");
      if (!app.running()) throw new Error("MODEL_METER_NOT_RUNNING");
      const text = value => value == null ? "" : String(value);
      return JSON.stringify((app.terminals() || []).map(terminal => ({
        id: text(terminal.id()),
        name: text(terminal.name()),
        workingDirectory: text(terminal.workingDirectory())
      })));
    })()
    """
}

private struct ITermSessionRecord: Decodable {
    let id: String
    let name: String
    let tty: String
    let jobName: String
    let commandLine: String
    let path: String
}

private struct GhosttyTerminalRecord: Decodable {
    let id: String
    let name: String
    let workingDirectory: String
}

private struct AppleEventDeliveryReport: Decodable {
    let sentIDs: [String]
    let failedIDs: [String]
}

enum AppleEventDeliveryParser {
    static func parse(
        _ output: String,
        targets: [TerminalSessionTarget],
        terminal: AutoContinueTerminal,
        targetNoun: String
    ) -> TerminalSendResult {
        guard let report = try? JSONDecoder().decode(
            AppleEventDeliveryReport.self,
            from: Data(output.utf8)
        ) else {
            return .failure(
                .partial(
                    terminal: terminal,
                    detail: "the delivery result was unreadable"
                )
            )
        }

        let expectedIDs = Set(targets.map(\.id))
        let sentIDs = Set(report.sentIDs)
        let failedIDs = Set(report.failedIDs)
        guard sentIDs.count == report.sentIDs.count,
              failedIDs.count == report.failedIDs.count,
              sentIDs.isDisjoint(with: failedIDs),
              sentIDs.union(failedIDs) == expectedIDs
        else {
            return .failure(
                .ambiguous(
                    terminal: terminal,
                    detail: "the delivery result did not match the selected targets"
                )
            )
        }

        let sentTargets = targets.filter { sentIDs.contains($0.id) }
        let summary = TerminalTargetSummary(targets: sentTargets)
        guard !failedIDs.isEmpty else {
            return .sent(summary)
        }

        let count = failedIDs.count
        let plural = count == 1 ? targetNoun : "\(targetNoun)s"
        let issue = TerminalAutomationIssue.partial(
            terminal: terminal,
            detail: "\(count) selected \(plural) failed during delivery"
        )
        return sentTargets.isEmpty
            ? .failure(issue)
            : .partial(sent: summary, issue: issue)
    }
}

private enum TerminalTargetParsingError: Error {
    case duplicateID
}

enum TerminalAgentMatcher {
    static func detectedITermProvider(
        jobName: String,
        commandLine: String,
        title: String
    ) -> ProviderID? {
        if let jobExecutable = executableName(in: jobName) {
            return ProviderID(rawValue: jobExecutable)
        }
        if let commandExecutable = executableName(in: commandLine) {
            return ProviderID(rawValue: commandExecutable)
        }
        let titleMatches = ProviderID.allCases.filter {
            exactTitleMatches(title, provider: $0)
        }
        return titleMatches.count == 1 ? titleMatches[0] : nil
    }

    static func exactTitleMatches(_ title: String, provider: ProviderID) -> Bool {
        let normalized = ANSITextCleaner.clean(title)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
        let names: [String] = switch provider {
        case .claude: ["claude", "claude code"]
        case .codex: ["codex"]
        }
        return names.contains { name in
            normalized == name
                || normalized.hasSuffix(" — \(name)")
                || normalized.hasSuffix(" - \(name)")
                || normalized.hasSuffix(" | \(name)")
        }
    }

    private static func executableName(in value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let executable: Substring
        if let quote = trimmed.first, quote == "\"" || quote == "'" {
            let remainder = trimmed.dropFirst()
            guard let closingQuote = remainder.firstIndex(of: quote) else {
                return nil
            }
            executable = remainder[..<closingQuote]
        } else {
            executable = trimmed.split(
                maxSplits: 1,
                whereSeparator: \.isWhitespace
            )[0]
        }
        let name = (String(executable) as NSString)
            .lastPathComponent
            .lowercased()
        return name.isEmpty ? nil : name
    }
}

private func normalizedDirectory(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let url = URL(string: trimmed), url.isFileURL {
        return url.standardizedFileURL.path
    }
    return (trimmed as NSString).standardizingPath
}

private func jsonLiteral(_ values: [String]) -> String {
    guard let data = try? JSONEncoder().encode(values),
          let literal = String(data: data, encoding: .utf8)
    else {
        return "[]"
    }
    return literal
}
