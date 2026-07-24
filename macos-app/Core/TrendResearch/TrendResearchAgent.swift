import Foundation

// 阶段三：TrendResearchAgent 运行循环。
//
// 维护消息状态，逐轮调用模型；模型返回 tool_call 后经 Registry 执行只读工具，
// 工具结果作为 tool message 回灌；submit_trend_report 成功则结束并返回报告，
// 校验失败把错误回灌模型做有限次自动修正。运行时有轮次、工具次数、修正次数、
// 超时和取消边界。

/// Agent 抽象，便于 AppModel 注入（测试可替换为 Fake Agent）。
protocol TrendResearchAgentProtocol: Sendable {
    func run(
        snapshot: TrendResearchSnapshot,
        settings: TrendAIProviderSettings,
        webSearchSettings: TavilySearchSettings,
        eventHandler: @escaping @Sendable (TrendResearchAgentEvent) -> Void
    ) async throws -> TrendAnalysisReport
}

extension TrendResearchAgent: TrendResearchAgentProtocol {}

// MARK: - 客户端协议（便于注入 Fake Client 做循环测试）

protocol TrendResearchAgentClient: Sendable {
    func complete(
        messages: [AgentChatMessage],
        tools: [AgentToolDefinition],
        toolChoice: AgentToolChoice,
        temperature: Double,
        settings: TrendAIProviderSettings,
        timeout: Double?
    ) async throws -> AgentCompletionResult
}

extension OpenAICompatibleAgentClient: TrendResearchAgentClient {}

// MARK: - 运行策略与事件

struct TrendResearchRunPolicy: Sendable {
    var maxTurns: Int = 8
    var maxToolCalls: Int = 16
    var maxInvalidSubmissions: Int = 2
    var maxPlainTextResponses: Int = 2
    var perRequestTimeoutSeconds: Double = 90
    var totalTimeoutSeconds: Double = 300
    var maxToolResultBytes: Int = 32 * 1024
    var temperature: Double = 0.2

    init() {}
}

enum TrendResearchAgentEvent: Sendable {
    case started(runID: UUID)
    case turnStarted(Int)
    case modelRequestStarted(turn: Int)
    case modelResponseReceived(turn: Int, duration: Double)
    case toolStarted(name: String)
    case toolFinished(name: String, summary: String)
    case reportValidationFailed(errors: [String], remainingAttempts: Int)
    case completed(duration: Double)
    case failed(message: String)
    case cancelled
}

enum TrendResearchAgentError: Error, LocalizedError {
    case missingConfiguration
    case turnLimitExceeded
    case toolCallLimitExceeded
    case missingToolCalls
    case invalidSubmissionLimitExceeded(errors: [String])
    case totalTimeoutExceeded

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "尚未配置趋势分析模型。请填写模型地址、模型名称和 API Key。"
        case .turnLimitExceeded:
            return "趋势 Agent 已达最大轮次仍未提交有效报告。"
        case .toolCallLimitExceeded:
            return "趋势 Agent 已达最大工具调用次数。"
        case .missingToolCalls:
            return "模型连续返回普通文本，未调用工具。"
        case .invalidSubmissionLimitExceeded(let errors):
            return "报告多次校验未通过：\n" + errors.joined(separator: "\n")
        case .totalTimeoutExceeded:
            return "趋势 Agent 整体超时。"
        }
    }
}

// MARK: - Agent

struct TrendResearchAgent: Sendable {
    let client: any TrendResearchAgentClient
    let registry: TrendResearchToolRegistry
    let promptBuilder: TrendResearchPromptBuilder
    let policy: TrendResearchRunPolicy

    /// 运行时强制：submit 前必须先调用的工具。
    static let overviewToolName = "get_portfolio_overview"
    static let webSearchToolName = "web_search"
    static let submitToolName = "submit_trend_report"

    init(
        client: any TrendResearchAgentClient = OpenAICompatibleAgentClient(),
        webSearchClient: any TavilySearchClientProtocol = TavilySearchClient(),
        policy: TrendResearchRunPolicy = .init()
    ) {
        self.client = client
        self.registry = TrendResearchToolRegistry(webSearchClient: webSearchClient)
        self.promptBuilder = TrendResearchPromptBuilder()
        self.policy = policy
    }

    func run(
        snapshot: TrendResearchSnapshot,
        settings: TrendAIProviderSettings,
        webSearchSettings: TavilySearchSettings = .empty,
        eventHandler: @escaping @Sendable (TrendResearchAgentEvent) -> Void
    ) async throws -> TrendAnalysisReport {
        guard settings.isConfigured else {
            throw TrendResearchAgentError.missingConfiguration
        }

        let ledger = TrendEvidenceLedger()
        var messages = promptBuilder.initialMessages(snapshot: snapshot)

        var turnCount = 0
        var toolCallCount = 0
        var plainTextResponses = 0
        var invalidSubmissions = 0
        var executedByID: [String: TrendResearchToolResult] = [:]
        var calledTools: Set<String> = []
        let started = Date()

        eventHandler(.started(runID: snapshot.runID))

        do {
            while turnCount < policy.maxTurns {
                try Task.checkCancellation()
                // 整体超时是硬截止：剩余预算不足则不再发起新请求；单次请求超时不超过剩余预算。
                let remainingTotal = policy.totalTimeoutSeconds - Date().timeIntervalSince(started)
                if remainingTotal <= 0 {
                    throw TrendResearchAgentError.totalTimeoutExceeded
                }
                let perRequestTimeout = min(policy.perRequestTimeoutSeconds, remainingTotal)

                turnCount += 1
                eventHandler(.turnStarted(turnCount))
                eventHandler(.modelRequestStarted(turn: turnCount))
                let requestStarted = Date()

                let response = try await client.complete(
                    messages: messages,
                    tools: registry.definitions,
                    toolChoice: .auto,
                    temperature: policy.temperature,
                    settings: settings,
                    timeout: perRequestTimeout
                )

                eventHandler(.modelResponseReceived(turn: turnCount, duration: Date().timeIntervalSince(requestStarted)))
                messages.append(response.assistantMessage)

                // 响应被 token 上限截断：不执行可能不完整的工具参数，要求模型重发完整 tool call。
                if case .length = response.stopReason {
                    messages.append(correctionMessage("上次响应被截断，不得执行不完整的工具参数，请重新发出完整 tool call。"))
                    continue
                }

                guard !response.toolCalls.isEmpty else {
                    plainTextResponses += 1
                    if plainTextResponses > policy.maxPlainTextResponses {
                        throw TrendResearchAgentError.missingToolCalls
                    }
                    messages.append(correctionMessage("普通文本不会被接收。请先调用只读工具读取数据，最后通过 submit_trend_report 提交。"))
                    continue
                }

                for call in response.toolCalls {
                    if toolCallCount >= policy.maxToolCalls {
                        throw TrendResearchAgentError.toolCallLimitExceeded
                    }

                    let toolName = call.function.name
                    let isSubmit = toolName == Self.submitToolName
                    // 运行时强制：submit 前必须先调用 get_portfolio_overview。
                    let missingOverview = isSubmit && !calledTools.contains(Self.overviewToolName)
                    // 配置了 Tavily 时至少尝试一次联网搜索，避免把模型记忆冒充最新行业/政策信息。
                    let missingWebSearch = isSubmit
                        && webSearchSettings.isConfigured
                        && !calledTools.contains(Self.webSearchToolName)
                    let missingRequiredTool = missingOverview || missingWebSearch

                    let toolResult: TrendResearchToolResult
                    if missingOverview {
                        toolResult = .content(TrendResearchToolEnvelope.error(code: "missing_required_tool", message: "提交报告前必须先调用 get_portfolio_overview 取得组合基线，请先调用它再重新提交。"), isError: true)
                    } else if missingWebSearch {
                        toolResult = .content(TrendResearchToolEnvelope.error(code: "missing_required_tool", message: "已配置 Tavily，提交报告前必须至少调用一次 web_search 获取最新行业或政策信息。"), isError: true)
                    } else if let cached = executedByID[call.id] {
                        toolResult = cached
                        calledTools.insert(toolName)
                    } else {
                        eventHandler(.toolStarted(name: toolName))
                        var context = TrendResearchToolContext(
                            snapshot: snapshot,
                            evidenceLedger: ledger,
                            webSearchSettings: webSearchSettings
                        )
                        context.invalidSubmissionBudget = policy.maxInvalidSubmissions
                        context.invalidSubmissionsUsed = invalidSubmissions
                        toolResult = await registry.execute(call, context: context)
                        executedByID[call.id] = toolResult
                        calledTools.insert(toolName)
                        eventHandler(.toolFinished(name: toolName, summary: Self.summary(of: toolResult)))
                    }

                    // 工具结果超过字节上限：截断后再回灌，避免单个超大结果撑爆上下文。
                    messages.append(toolMessage(callID: call.id, content: Self.truncate(toolResult.contentJSON, limit: policy.maxToolResultBytes)))
                    toolCallCount += 1

                    // submit 成功 → 结束。
                    if case .report(let report) = toolResult.completion {
                        eventHandler(.completed(duration: Date().timeIntervalSince(started)))
                        return report
                    }

                    // submit 校验失败（实际执行了 submit，非缺 overview 的拒绝）→ 记数；超过预算则终止。
                    if isSubmit, toolResult.isError, !missingRequiredTool {
                        invalidSubmissions += 1
                        let errors = Self.parseErrors(from: toolResult.contentJSON)
                        let remaining = max(0, policy.maxInvalidSubmissions - invalidSubmissions)
                        eventHandler(.reportValidationFailed(errors: errors, remainingAttempts: remaining))
                        if invalidSubmissions > policy.maxInvalidSubmissions {
                            throw TrendResearchAgentError.invalidSubmissionLimitExceeded(errors: errors)
                        }
                    }
                }

                compactContextIfNeeded(&messages)
            }

            throw TrendResearchAgentError.turnLimitExceeded
        } catch is CancellationError {
            eventHandler(.cancelled)
            throw CancellationError()
        } catch let error as TrendResearchAgentError {
            eventHandler(.failed(message: error.localizedDescription))
            throw error
        } catch {
            eventHandler(.failed(message: error.localizedDescription))
            throw error
        }
    }

    // MARK: - 消息构造

    private func correctionMessage(_ text: String) -> AgentChatMessage {
        AgentChatMessage(role: .user, content: text)
    }

    private func toolMessage(callID: String, content: String) -> AgentChatMessage {
        AgentChatMessage(role: .tool, content: content, toolCallID: callID)
    }

    // MARK: - 上下文裁剪（确定性）

    /// 第一版不做模型摘要式压缩，只做确定性裁剪：消息体积超预算时，把已被后续 assistant
    /// 消费过的旧 tool 结果内容替换为短摘要。system 与初始 user 永远保留；最近若干条保留。
    private func compactContextIfNeeded(_ messages: inout [AgentChatMessage]) {
        let budget = 64 * 1024
        let total = messages.reduce(0) { $0 + ($1.content ?? "").utf8.count }
        guard total > budget, messages.count > 8 else { return }

        let preservedTail = 4
        let lastAllowedIndex = messages.count - preservedTail
        guard lastAllowedIndex > 2 else { return }
        for index in 2..<lastAllowedIndex where messages[index].role == .tool {
            if (messages[index].content ?? "").utf8.count > 200 {
                messages[index] = AgentChatMessage(
                    role: .tool,
                    content: "(早期工具结果已省略，evidence 已登记，可按需重新调用工具)",
                    toolCallID: messages[index].toolCallID
                )
            }
        }
    }

    // MARK: - 工具结果摘要与错误解析

    /// 超过字节上限的工具结果按字节截断并标注，避免单个超大结果整段塞入上下文。
    private static func truncate(_ content: String, limit: Int) -> String {
        let bytes = content.utf8
        guard bytes.count > limit else { return content }
        let truncated = String(decoding: Array(bytes.prefix(limit)), as: UTF8.self)
        return "\(truncated)\n…（结果超过 \(limit) 字节已截断，请缩小范围或分页重新读取完整数据）"
    }

    private static func summary(of result: TrendResearchToolResult) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(result.contentJSON.utf8)) as? [String: Any] else {
            return result.isError ? "失败" : "完成"
        }
        if result.isError {
            let message = (object["error"] as? [String: Any])?["message"] as? String
            return "失败" + (message.map { "：\($0)" } ?? "")
        }
        if let data = object["data"] as? [String: Any] {
            if let count = data["count"] as? Int { return "完成（\(count) 条）" }
            if let total = data["total_count"] as? Int { return "完成（\(total) 条）" }
        }
        return "完成"
    }

    private static func parseErrors(from contentJSON: String) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(contentJSON.utf8)) as? [String: Any],
              let errors = object["errors"] as? [String] else { return [] }
        return errors
    }
}
