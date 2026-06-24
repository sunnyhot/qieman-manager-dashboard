import Foundation

protocol TrendAgentRunnerProtocol {
    func generateReport(
        packet: TrendRunPacket,
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentRunResult

    func check(
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentCheckResult
}

enum TrendAgentRunnerError: LocalizedError {
    case noRunnableAgent
    case commandFailed(String)
    case emptyOutput
    case missingOutputFile(String)

    var errorDescription: String? {
        switch self {
        case .noRunnableAgent:
            return "未找到可运行的本地趋势分析 Agent。"
        case .commandFailed(let detail):
            return "本地 Agent 执行失败：\(detail)"
        case .emptyOutput:
            return "本地 Agent 没有返回趋势分析 JSON。"
        case .missingOutputFile(let path):
            return "本地 Agent 未生成结果文件：\(path)"
        }
    }
}

struct TrendAgentRunner: TrendAgentRunnerProtocol {
    let processClient: TrendAgentProcessClient
    private let fileManager: FileManager

    init(
        processClient: TrendAgentProcessClient = TrendAgentProcessClient(),
        fileManager: FileManager = .default
    ) {
        self.processClient = processClient
        self.fileManager = fileManager
    }

    func generateReport(
        packet: TrendRunPacket,
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentRunResult {
        let start = Date()
        let command = try resolvedCommand(settings: settings, candidates: candidates)
        let result: TrendAgentProcessResult
        switch command.kind {
        case .claudeCLI:
            result = try await runClaude(command: command.path, packet: packet, settings: settings)
        case .codexCLI:
            result = try await runCodex(command: command.path, packet: packet, settings: settings)
        case .custom, .openClaw, .hermes:
            result = try await runExternal(command: command.path, packet: packet, settings: settings)
        case .automatic:
            throw TrendAgentRunnerError.noRunnableAgent
        }

        guard result.exitCode == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? result.stdout
                : result.stderr
            throw TrendAgentRunnerError.commandFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let outputText: String
        if fileManager.fileExists(atPath: packet.outputURL.path) {
            outputText = try String(contentsOf: packet.outputURL)
        } else if command.kind == .claudeCLI {
            outputText = try decodeClaudePrintOutput(result.stdout)
        } else {
            outputText = result.stdout
        }
        let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TrendAgentRunnerError.emptyOutput
        }

        return TrendAgentRunResult(
            reportJSON: trimmed,
            agentName: command.kind.displayName,
            commandPath: command.path,
            durationSeconds: Date().timeIntervalSince(start)
        )
    }

    func check(
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentCheckResult {
        let command = try resolvedCommand(settings: settings, candidates: candidates)
        return TrendAgentCheckResult(
            agentName: command.kind.displayName,
            commandPath: command.path,
            preview: "可执行"
        )
    }

    private func resolvedCommand(
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) throws -> (kind: TrendAgentKind, path: String) {
        if settings.kind == .custom {
            let path = settings.commandPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { throw TrendAgentRunnerError.noRunnableAgent }
            return (.custom, path)
        }
        guard let candidate = settings.resolvedCandidate(from: candidates) else {
            throw TrendAgentRunnerError.noRunnableAgent
        }
        return (candidate.kind, candidate.commandPath)
    }

    private func runClaude(
        command: String,
        packet: TrendRunPacket,
        settings: TrendAgentSettings
    ) async throws -> TrendAgentProcessResult {
        var arguments = [
            "-p",
            "--output-format", "json",
            "--json-schema", try String(contentsOf: packet.schemaURL),
            "--no-session-persistence",
            "--tools", "",
            "--add-dir", packet.runDirectory.path
        ]
        if !settings.model.isEmpty {
            arguments.append(contentsOf: ["--model", settings.model])
        }
        return try await processClient.run(
            executableURL: URL(fileURLWithPath: command),
            arguments: arguments,
            currentDirectoryURL: packet.runDirectory,
            standardInput: try String(contentsOf: packet.promptURL),
            timeoutSeconds: settings.timeoutSeconds
        )
    }

    private func runCodex(
        command: String,
        packet: TrendRunPacket,
        settings: TrendAgentSettings
    ) async throws -> TrendAgentProcessResult {
        var arguments = [
            "exec",
            "--ephemeral",
            "--sandbox", "read-only",
            "--ask-for-approval", "never",
            "--cd", packet.runDirectory.path,
            "--output-schema", packet.schemaURL.path,
            "--output-last-message", packet.outputURL.path,
            "-"
        ]
        if !settings.model.isEmpty {
            arguments.insert(contentsOf: ["--model", settings.model], at: 1)
        }
        return try await processClient.run(
            executableURL: URL(fileURLWithPath: command),
            arguments: arguments,
            currentDirectoryURL: packet.runDirectory,
            standardInput: try String(contentsOf: packet.promptURL),
            timeoutSeconds: settings.timeoutSeconds
        )
    }

    private func runExternal(
        command: String,
        packet: TrendRunPacket,
        settings: TrendAgentSettings
    ) async throws -> TrendAgentProcessResult {
        let template = settings.customCommandTemplate.isEmpty
            ? "{{command}} {{promptFile}} {{schemaFile}} {{outputFile}} {{runDir}}"
            : settings.customCommandTemplate
        let parts = expand(template: template, command: command, packet: packet)
        guard let executable = parts.first else { throw TrendAgentRunnerError.noRunnableAgent }
        return try await processClient.run(
            executableURL: URL(fileURLWithPath: executable),
            arguments: Array(parts.dropFirst()),
            currentDirectoryURL: packet.runDirectory,
            standardInput: nil,
            timeoutSeconds: settings.timeoutSeconds
        )
    }

    private func expand(template: String, command: String, packet: TrendRunPacket) -> [String] {
        template
            .replacingOccurrences(of: "{{command}}", with: command)
            .replacingOccurrences(of: "{{promptFile}}", with: packet.promptURL.path)
            .replacingOccurrences(of: "{{schemaFile}}", with: packet.schemaURL.path)
            .replacingOccurrences(of: "{{outputFile}}", with: packet.outputURL.path)
            .replacingOccurrences(of: "{{runDir}}", with: packet.runDirectory.path)
            .split(separator: " ")
            .map(String.init)
    }

    private func decodeClaudePrintOutput(_ output: String) throws -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TrendAgentRunnerError.emptyOutput }
        let data = Data(trimmed.utf8)
        guard let response = try? JSONDecoder().decode(ClaudePrintResponse.self, from: data) else {
            return trimmed
        }

        if response.isError == true {
            let detail = response.result?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Claude CLI returned an error."
            throw TrendAgentRunnerError.commandFailed(detail)
        }

        guard let result = response.result?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty else {
            throw TrendAgentRunnerError.emptyOutput
        }
        return result
    }
}

private struct ClaudePrintResponse: Decodable {
    let result: String?
    let error: String?
    let isError: Bool?

    private enum CodingKeys: String, CodingKey {
        case result
        case error
        case isError = "is_error"
    }
}
