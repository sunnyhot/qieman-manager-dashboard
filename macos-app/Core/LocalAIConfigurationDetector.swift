import Foundation

struct LocalAIConfigurationDetector {
    let homeDirectory: URL
    let environment: [String: String]
    let fileManager: FileManager

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.fileManager = fileManager
    }

    func detect() -> [LocalAIConfigurationCandidate] {
        var candidates: [LocalAIConfigurationCandidate] = []
        if let envCandidate = openAIEnvironmentCandidate() {
            candidates.append(envCandidate)
        }
        candidates.append(contentsOf: codexCandidates())
        if let claudeCandidate = claudeCandidate() {
            candidates.append(claudeCandidate)
        }
        return candidates
            .uniquedByID()
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.providerName < rhs.providerName
                }
                return lhs.confidence > rhs.confidence
            }
    }

    private func openAIEnvironmentCandidate() -> LocalAIConfigurationCandidate? {
        guard let apiKey = environment["OPENAI_API_KEY"], !apiKey.isEmpty else { return nil }
        let baseURL = environment["OPENAI_BASE_URL"] ?? environment["OPENAI_API_BASE"] ?? "https://api.openai.com/v1"
        let model = environment["OPENAI_MODEL"] ?? environment["MODEL"] ?? ""
        return LocalAIConfigurationCandidate(
            id: "env-openai",
            providerName: "OpenAI-compatible environment",
            sourceDescription: "Process environment: OPENAI_API_KEY",
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            apiKeySource: "OPENAI_API_KEY",
            compatibility: model.isEmpty ? .incomplete : .openAICompatible,
            confidence: model.isEmpty ? 60 : 95,
            warning: model.isEmpty ? "检测到 API Key，但缺少 OPENAI_MODEL。" : nil
        )
    }

    private func codexCandidates() -> [LocalAIConfigurationCandidate] {
        let configURL = homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)
        guard
            fileManager.fileExists(atPath: configURL.path),
            let content = try? String(contentsOf: configURL, encoding: .utf8)
        else {
            return []
        }

        let globalModel = firstQuotedValue(named: "model", in: content)
        return parseProviderBlocks(content).compactMap { block in
            guard let baseURL = firstQuotedValue(named: "base_url", in: block.body) else { return nil }
            let envKey = firstQuotedValue(named: "env_key", in: block.body)
            let apiKey = envKey.flatMap { environment[$0] }
            let model = firstQuotedValue(named: "model", in: block.body) ?? globalModel ?? ""
            let isCompatible = baseURL.contains("/v1") || baseURL.contains("openai") || baseURL.contains("openrouter")
            let hasImportableKey = apiKey != nil || envKey != nil
            return LocalAIConfigurationCandidate(
                id: "codex-\(block.name)",
                providerName: "Codex \(block.name)",
                sourceDescription: "~/.codex/config.toml",
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                apiKeySource: envKey,
                compatibility: isCompatible && !model.isEmpty && hasImportableKey ? .openAICompatible : .incomplete,
                confidence: isCompatible && apiKey != nil && !model.isEmpty ? 90 : 55,
                warning: apiKey == nil && envKey != nil ? "检测到 \(envKey!) 引用，但当前 App 进程没有这个环境变量。" : nil
            )
        }
    }

    private func claudeCandidate() -> LocalAIConfigurationCandidate? {
        let claudeJSON = homeDirectory.appendingPathComponent(".claude.json", isDirectory: false)
        let claudeDirectory = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        let hasClaudeConfig = fileManager.fileExists(atPath: claudeJSON.path) || fileManager.fileExists(atPath: claudeDirectory.path)
        guard hasClaudeConfig || environment["ANTHROPIC_API_KEY"] != nil else { return nil }
        return LocalAIConfigurationCandidate(
            id: "claude-direct",
            providerName: "Claude/cc direct",
            sourceDescription: hasClaudeConfig ? "Claude local config" : "Process environment: ANTHROPIC_API_KEY",
            baseURL: environment["ANTHROPIC_BASE_URL"],
            model: environment["ANTHROPIC_MODEL"],
            apiKey: environment["ANTHROPIC_API_KEY"],
            apiKeySource: "ANTHROPIC_API_KEY",
            compatibility: .needsCompatibleEndpoint,
            confidence: 50,
            warning: "检测到 Claude/cc 配置；首版趋势分析只直接支持 OpenAI-compatible endpoint。"
        )
    }

    private func firstQuotedValue(named name: String, in content: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?m)^\\s*\(escapedName)\\s*=\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard
            let match = regex.firstMatch(in: content, range: range),
            let valueRange = Range(match.range(at: 1), in: content)
        else {
            return nil
        }
        return String(content[valueRange])
    }

    private func parseProviderBlocks(_ content: String) -> [(name: String, body: String)] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [(name: String, body: [String])] = []
        var currentName: String?
        var currentBody: [String] = []

        for line in lines {
            if let name = providerName(from: line) {
                if let currentName {
                    blocks.append((currentName, currentBody))
                }
                currentName = name
                currentBody = []
            } else if currentName != nil {
                currentBody.append(line)
            }
        }
        if let currentName {
            blocks.append((currentName, currentBody))
        }

        return blocks.map { ($0.name, $0.body.joined(separator: "\n")) }
    }

    private func providerName(from line: String) -> String? {
        let pattern = #"^\s*\[model_providers\.([^\]]+)\]\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard
            let match = regex.firstMatch(in: line, range: range),
            let valueRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[valueRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}

private extension Array where Element == LocalAIConfigurationCandidate {
    func uniquedByID() -> [LocalAIConfigurationCandidate] {
        var seen = Set<String>()
        var result: [LocalAIConfigurationCandidate] = []
        for candidate in self where !seen.contains(candidate.id) {
            seen.insert(candidate.id)
            result.append(candidate)
        }
        return result
    }
}
