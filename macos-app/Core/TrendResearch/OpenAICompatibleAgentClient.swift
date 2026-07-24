import Foundation

// 阶段一：OpenAI-compatible chat/completions 传输层。
//
// OpenAICompatibleAgentClient 只负责请求/响应协议：
//   - 发送 messages / tools / tool_choice / temperature
//   - 解析 assistant 消息及其 tool_calls（content 为 null 也合法）
//   - 把 HTTP 错误、超时、限流映射成用户可读说明
//   - 提供真实工具调用能力探测，决定是否允许启动内嵌 Agent
//
// 不包含趋势分析业务规则；业务规则在 Agent、工具和 Validator 中。

/// 一次工具调用能力探测的结果。
struct TrendProviderCapabilities: Hashable, Sendable {
    /// 模型是否能发起原生 tool_calls。只有为 true 才允许启动内嵌 Agent。
    let supportsToolCalls: Bool
    /// 是否支持指定函数的 tool_choice（部分供应商只支持 auto）。
    let supportsForcedToolChoice: Bool
    /// 探测时所用的 Provider 指纹；与当前配置不符时检测结果视为过期，需重新探测。
    let providerFingerprint: String
    let checkedAt: String
    let detail: String
}

enum OpenAICompatibleAgentClientError: Error, LocalizedError {
    case missingConfiguration
    case invalidBaseURL
    case requestFailed(statusCode: Int?, detail: String?)
    case timedOut(Double)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "尚未配置趋势分析模型。请填写模型地址、模型名称和 API Key。"
        case .invalidBaseURL:
            return "趋势分析模型地址无效。"
        case .requestFailed(let statusCode, let detail):
            let suffix = detail.map { " \($0)" } ?? ""
            if statusCode == 429 {
                return Self.rateLimitDescription(detail: detail)
            }
            if let statusCode {
                return "趋势分析模型请求失败：HTTP \(statusCode)。\(suffix)"
            }
            return "趋势分析模型请求失败。\(suffix)"
        case .timedOut(let seconds):
            return "趋势分析模型请求超时：\(Int(seconds)) 秒内未返回。建议稍后重试或减少明细范围。"
        case .invalidResponse(let detail):
            return "模型接口返回格式不符合 OpenAI-compatible chat/completions：\(detail)"
        }
    }

    /// 能力探测时，哪些错误可以退回 auto 再试一次（只有「供应商不接受指定函数 tool_choice」这类才退回）。
    var isCapabilityProbeRecoverable: Bool {
        switch self {
        case .requestFailed(let statusCode, _) where statusCode == 400 || statusCode == 422:
            return true
        default:
            return false
        }
    }

    private static func rateLimitDescription(detail: String?) -> String {
        let normalized = detail?.lowercased() ?? ""
        let original = detail.map { " 原始信息：\($0)" } ?? ""
        if normalized.contains("余额不足") || normalized.contains("无可用资源包") || normalized.contains("1113") {
            return "趋势分析模型请求失败：HTTP 429。服务商提示余额不足或无可用资源包，请确认 API Key 对应的套餐/资源包。\(original)"
        }
        if normalized.contains("rate limit") || normalized.contains("1302") || normalized.contains("limit reached") {
            return "趋势分析模型请求失败：HTTP 429。服务商提示请求频率或并发超限，请稍后重试或检查该 API Key 的限额。\(original)"
        }
        return "趋势分析模型请求失败：HTTP 429。服务商限流或资源不可用，请稍后重试并检查 API Key 套餐/限额。\(original)"
    }
}

struct OpenAICompatibleAgentClient: Sendable {
    let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// 能力探针使用的无副作用工具名。
    static let capabilityProbeToolName = "agent_capability_probe"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// 发起一轮 chat/completions，返回 assistant 消息、工具调用与停止原因。
    ///
    /// 普通文本响应（无 tool_calls）不是错误，由调用方决定如何处理。
    /// `timeout` 非空时覆盖 settings 的请求超时，用于 Agent 运行策略的单次请求上限。
    func complete(
        messages: [AgentChatMessage],
        tools: [AgentToolDefinition],
        toolChoice: AgentToolChoice = .auto,
        temperature: Double = 0.2,
        settings: TrendAIProviderSettings,
        timeout: Double? = nil
    ) async throws -> AgentCompletionResult {
        guard settings.isConfigured else {
            throw OpenAICompatibleAgentClientError.missingConfiguration
        }

        let url = try Self.chatCompletionsURL(baseURL: settings.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let effectiveTimeout = timeout ?? settings.timeoutSeconds
        request.timeoutInterval = effectiveTimeout
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            AgentChatCompletionRequest(
                model: settings.model,
                messages: messages,
                tools: tools.isEmpty ? nil : tools,
                toolChoice: tools.isEmpty ? nil : toolChoice,
                temperature: temperature
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw OpenAICompatibleAgentClientError.timedOut(effectiveTimeout)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleAgentClientError.requestFailed(statusCode: nil, detail: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAICompatibleAgentClientError.requestFailed(
                statusCode: http.statusCode,
                detail: Self.providerErrorMessage(from: data, decoder: decoder)
            )
        }

        let completion: AgentChatCompletionResponse
        do {
            completion = try decoder.decode(AgentChatCompletionResponse.self, from: data)
        } catch {
            throw OpenAICompatibleAgentClientError.invalidResponse(Self.decodingSummary(error, data: data))
        }

        guard let choice = completion.choices.first else {
            throw OpenAICompatibleAgentClientError.invalidResponse("响应缺少 choices")
        }

        let message = choice.message
        let toolCalls = message.toolCalls ?? []
        return AgentCompletionResult(
            assistantMessage: message,
            toolCalls: toolCalls,
            stopReason: AgentStopReason(finishReason: choice.finishReason),
            finishReason: choice.finishReason
        )
    }

    /// 真实工具调用能力探测。
    ///
    /// 优先用指定函数的 `tool_choice` 探测；供应商不接受（400/422）或仅返回普通文本时
    /// 退回 `auto` 再探一次。只有响应里出现合法 `tool_calls` 才视为支持内嵌 Agent。
    /// 鉴权、限流、5xx、网络和超时等错误不退回，直接抛出交给调用方展示。
    func checkToolCallingCapability(settings: TrendAIProviderSettings) async throws -> TrendProviderCapabilities {
        guard settings.isConfigured else {
            throw OpenAICompatibleAgentClientError.missingConfiguration
        }

        let tool = AgentToolDefinition.function(
            name: Self.capabilityProbeToolName,
            description: "连通性探针。被调用时立即返回 ok=true，无副作用。仅用于检测模型是否支持工具调用。",
            parameters: [
                "type": "object",
                "properties": [:],
                "additionalProperties": false
            ]
        )
        let messages: [AgentChatMessage] = [
            .init(role: .system, content: "你是工具调用能力探针。必须调用 agent_capability_probe 工具，不要输出普通文本。"),
            .init(role: .user, content: "请立即调用 agent_capability_probe 工具。")
        ]

        // 1) 优先探测指定函数的 tool_choice。
        do {
            let result = try await complete(
                messages: messages,
                tools: [tool],
                toolChoice: .function(name: Self.capabilityProbeToolName),
                temperature: 0,
                settings: settings
            )
            if result.toolCalls.contains(where: { $0.function.name == Self.capabilityProbeToolName }) {
                return TrendProviderCapabilities(
                    supportsToolCalls: true,
                    supportsForcedToolChoice: true,
                    providerFingerprint: settings.fingerprint,
                    checkedAt: Self.nowTimestamp(),
                    detail: "模型支持指定函数的 tool_choice。"
                )
            }
            // 指定函数 tool_choice 下仍只返回普通文本，退回 auto 再探。
        } catch let error as OpenAICompatibleAgentClientError {
            // 400/422 视为供应商不接受指定函数 tool_choice，退回 auto；
            // 鉴权、限流、5xx、超时、协议错误等直接抛出。
            guard error.isCapabilityProbeRecoverable else { throw error }
        }

        // 2) 退回 auto 再探一次。
        let result = try await complete(
            messages: messages,
            tools: [tool],
            toolChoice: .auto,
            temperature: 0,
            settings: settings
        )
        let supports = result.toolCalls.contains(where: { $0.function.name == Self.capabilityProbeToolName })
        return TrendProviderCapabilities(
            supportsToolCalls: supports,
            supportsForcedToolChoice: false,
            providerFingerprint: settings.fingerprint,
            checkedAt: Self.nowTimestamp(),
            detail: supports
                ? "模型在 auto 模式下可发起工具调用。"
                : "模型仅返回普通文本，未发起工具调用，不支持内嵌 Agent。"
        )
    }

    // MARK: - Helpers

    private static func chatCompletionsURL(baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/chat/completions") else {
            throw OpenAICompatibleAgentClientError.invalidBaseURL
        }
        return url
    }

    private static func providerErrorMessage(from data: Data, decoder: JSONDecoder) -> String? {
        if let envelope = try? decoder.decode(AgentProviderErrorEnvelope.self, from: data) {
            let parts = [envelope.error.code, envelope.error.type, envelope.error.message]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty {
                return parts.joined(separator: " · ")
            }
        }
        return responseSnippet(data)
    }

    private static func decodingSummary(_ error: Error, data: Data) -> String {
        var parts: [String] = []
        if let decodingError = error as? DecodingError {
            parts.append(describe(decodingError))
        } else {
            parts.append(error.localizedDescription)
        }
        if let snippet = responseSnippet(data) {
            parts.append("返回片段：\(snippet)")
        }
        return parts.joined(separator: " ")
    }

    private static func responseSnippet(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(220))
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "缺少字段 \(key.stringValue)\(codingPathSuffix(context.codingPath))。"
        case .valueNotFound(_, let context):
            return "缺少必要值\(codingPathSuffix(context.codingPath))。"
        case .typeMismatch(_, let context):
            return "字段类型不匹配\(codingPathSuffix(context.codingPath))。"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func codingPathSuffix(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else { return "" }
        return "（路径：\(path.map(\.stringValue).joined(separator: "."))）"
    }

    private static func nowTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

// MARK: - 请求 / 响应封装

private struct AgentChatCompletionRequest: Encodable {
    let model: String
    let messages: [AgentChatMessage]
    let tools: [AgentToolDefinition]?
    let toolChoice: AgentToolChoice?
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case tools
        case toolChoice = "tool_choice"
        case temperature
    }
}

private struct AgentChatCompletionResponse: Decodable {
    let choices: [AgentChatChoice]
}

private struct AgentChatChoice: Decodable {
    let message: AgentChatMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct AgentProviderErrorEnvelope: Decodable {
    let error: AgentProviderError
}

private struct AgentProviderError: Decodable {
    let message: String?
    let type: String?
    let code: String?
}
