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
