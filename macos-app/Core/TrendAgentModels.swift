import Foundation

enum TrendAgentKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case automatic
    case claudeCLI
    case codexCLI
    case openClaw
    case hermes
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "自动选择"
        case .claudeCLI:
            return "Claude CLI"
        case .codexCLI:
            return "Codex CLI"
        case .openClaw:
            return "OpenClaw"
        case .hermes:
            return "Hermes"
        case .custom:
            return "自定义"
        }
    }
}

enum TrendAgentCapability: String, Codable, Hashable {
    case nonInteractive
    case jsonSchema
    case outputFile
}

struct TrendAgentSettings: Codable, Hashable {
    var kind: TrendAgentKind
    var commandPath: String
    var model: String
    var profile: String
    var timeoutSeconds: Double
    var customCommandTemplate: String

    static let defaultTimeoutSeconds: Double = 300

    static let `default` = TrendAgentSettings(
        kind: .automatic,
        commandPath: "",
        model: "",
        profile: "",
        timeoutSeconds: defaultTimeoutSeconds,
        customCommandTemplate: ""
    )

    func resolvedCandidate(from candidates: [TrendAgentCandidate]) -> TrendAgentCandidate? {
        let installed = candidates.filter(\.isRunnable)
        switch kind {
        case .automatic:
            return installed.first
        case .custom:
            return nil
        default:
            return installed.first { $0.kind == kind }
        }
    }

    func isRunnable(with candidates: [TrendAgentCandidate]) -> Bool {
        if kind == .custom {
            return !commandPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return resolvedCandidate(from: candidates) != nil
    }
}

struct TrendAgentCandidate: Identifiable, Codable, Hashable {
    let id: String
    let kind: TrendAgentKind
    let displayName: String
    let commandPath: String
    let version: String?
    let isInstalled: Bool
    let isExecutable: Bool
    let capabilities: [TrendAgentCapability]
    let warning: String?

    var isRunnable: Bool {
        isInstalled && isExecutable
    }
}

struct TrendAgentCheckResult: Codable, Hashable {
    let agentName: String
    let commandPath: String
    let preview: String
}

struct TrendAgentRunResult: Codable, Hashable {
    let reportJSON: String
    let agentName: String
    let commandPath: String
    let durationSeconds: Double
}
