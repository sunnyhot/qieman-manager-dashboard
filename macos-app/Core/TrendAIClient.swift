import Foundation

protocol TrendAIClientProtocol {
    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport
    func checkConnection(settings: TrendAIProviderSettings) async throws -> TrendConnectionCheckResult
}

struct TrendConnectionCheckResult: Hashable {
    let endpoint: String
    let model: String
    let preview: String
}

enum TrendAIClientError: LocalizedError {
    case invalidBaseURL
    case missingConfiguration
    case requestFailed(Int?, String?)
    case timedOut(Double)
    case emptyContent(finishReason: String?, reasoningPreview: String?)
    case invalidOpenAICompatibleResponse(String)
    case invalidReportResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "趋势分析模型地址无效。"
        case .missingConfiguration:
            return "尚未配置趋势分析模型。请填写模型地址、模型名称和 API Key。"
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
            return "趋势分析模型请求超时：\(Int(seconds)) 秒内未返回。GLM-5.2 正式分析会先推理再输出，建议稍后重试或减少明细范围。"
        case .emptyContent(let finishReason, let reasoningPreview):
            let finishText = finishReason.map { "finish_reason=\($0)" } ?? "finish_reason 为空"
            if let reasoningPreview, !reasoningPreview.isEmpty {
                return "趋势分析模型只返回了 reasoning_content，没有返回 content（\(finishText)）。通常是 max_tokens 太小或模型先输出思考内容；已保留返回片段：\(reasoningPreview)"
            }
            return "趋势分析模型没有返回可解析内容（\(finishText)）。"
        case .invalidOpenAICompatibleResponse(let detail):
            return "模型接口返回格式不符合 OpenAI-compatible chat/completions：\(detail)"
        case .invalidReportResponse(let detail):
            return "模型已连通，但趋势分析 JSON 不完整或格式不对：\(detail)"
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

struct TrendAIClient: TrendAIClientProtocol {
    let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport {
        guard settings.isConfigured else { throw TrendAIClientError.missingConfiguration }
        let content = try await chatCompletionContent(
            settings: settings,
            messages: [
                TrendChatMessage(role: "system", content: prompt.system),
                TrendChatMessage(role: "user", content: prompt.user)
            ],
            temperature: 0.2,
            maxTokens: nil
        ).content

        guard let reportData = normalizedReportJSONData(from: content) else {
            throw TrendAIClientError.emptyContent(finishReason: nil, reasoningPreview: nil)
        }
        do {
            return try decodeReport(from: reportData)
        } catch {
            throw TrendAIClientError.invalidReportResponse(decodingSummary(error, data: reportData))
        }
    }

    func checkConnection(settings: TrendAIProviderSettings) async throws -> TrendConnectionCheckResult {
        guard settings.isConfigured else { throw TrendAIClientError.missingConfiguration }
        let result = try await chatCompletionContent(
            settings: settings,
            messages: [
                TrendChatMessage(role: "system", content: "你是连通性检测器。只回复 OK。"),
                TrendChatMessage(role: "user", content: "ping")
            ],
            temperature: 0,
            maxTokens: 128
        )

        return TrendConnectionCheckResult(
            endpoint: result.endpoint.absoluteString,
            model: settings.model,
            preview: String(result.content.prefix(120))
        )
    }

    private func chatCompletionContent(
        settings: TrendAIProviderSettings,
        messages: [TrendChatMessage],
        temperature: Double,
        maxTokens: Int?
    ) async throws -> (content: String, endpoint: URL) {
        let url = try chatCompletionsURL(baseURL: settings.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.timeoutSeconds
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TrendChatCompletionRequest(
            model: settings.model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw TrendAIClientError.timedOut(settings.timeoutSeconds)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TrendAIClientError.requestFailed(nil, nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TrendAIClientError.requestFailed(http.statusCode, providerErrorMessage(from: data))
        }

        let completion: TrendChatCompletionResponse
        do {
            completion = try decoder.decode(TrendChatCompletionResponse.self, from: data)
        } catch {
            throw TrendAIClientError.invalidOpenAICompatibleResponse(decodingSummary(error, data: data))
        }

        let firstChoice = completion.choices.first
        let message = firstChoice?.message
        if let content = message?.content, !content.isEmpty {
            return (content, url)
        }
        throw TrendAIClientError.emptyContent(
            finishReason: firstChoice?.finishReason,
            reasoningPreview: message?.reasoningContent.map { String($0.prefix(140)) }
        )
    }

    private func chatCompletionsURL(baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/chat/completions") else {
            throw TrendAIClientError.invalidBaseURL
        }
        return url
    }

    private func providerErrorMessage(from data: Data) -> String? {
        if let envelope = try? decoder.decode(TrendProviderErrorEnvelope.self, from: data) {
            let parts = [envelope.error.code, envelope.error.type, envelope.error.message]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty {
                return parts.joined(separator: " · ")
            }
        }
        return responseSnippet(data)
    }

    private func decodingSummary(_ error: Error, data: Data) -> String {
        var parts: [String] = []
        if let decodingError = error as? DecodingError {
            parts.append(Self.describe(decodingError))
        } else {
            parts.append(error.localizedDescription)
        }
        if let snippet = responseSnippet(data) {
            parts.append("返回片段：\(snippet)")
        }
        return parts.joined(separator: " ")
    }

    private func responseSnippet(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(220))
    }

    private func decodeReport(from data: Data) throws -> TrendAnalysisReport {
        do {
            return try decoder.decode(TrendAnalysisReport.self, from: data)
        } catch {
            let envelope = try decoder.decode(TrendReportEnvelope.self, from: data)
            if let report = envelope.trendAnalysisReport ?? envelope.report {
                return report
            }
            throw error
        }
    }

    private func normalizedReportJSONData(from content: String) -> Data? {
        let stripped = stripMarkdownCodeFence(content)
        guard let jsonText = extractJSONObject(from: stripped) else {
            return stripped.data(using: .utf8)
        }
        return jsonText.data(using: .utf8)
    }

    private func stripMarkdownCodeFence(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return trimmed }
        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractJSONObject(from content: String) -> String? {
        guard
            let start = content.firstIndex(of: "{"),
            let end = content.lastIndex(of: "}"),
            start <= end
        else {
            return nil
        }
        return String(content[start...end])
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

}

private struct TrendChatCompletionRequest: Encodable {
    let model: String
    let messages: [TrendChatMessage]
    let temperature: Double
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct TrendChatMessage: Codable {
    let role: String?
    let content: String?
    let reasoningContent: String?

    init(role: String?, content: String, reasoningContent: String? = nil) {
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case reasoningContent = "reasoning_content"
    }
}

private struct TrendChatCompletionResponse: Decodable {
    let choices: [TrendChatChoice]
}

private struct TrendChatChoice: Decodable {
    let message: TrendChatMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct TrendProviderErrorEnvelope: Decodable {
    let error: TrendProviderError
}

private struct TrendProviderError: Decodable {
    let message: String?
    let type: String?
    let code: String?
}

private struct TrendReportEnvelope: Decodable {
    let trendAnalysisReport: TrendAnalysisReport?
    let report: TrendAnalysisReport?
}
