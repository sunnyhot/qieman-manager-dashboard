import Foundation

protocol TrendAIClientProtocol {
    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport
    func checkConnection(settings: TrendAIProviderSettings) async throws -> TrendConnectionCheckResult
}

enum TrendAIClientError: LocalizedError {
    case invalidBaseURL
    case requestFailed(Int?, String?)
    case emptyContent(finishReason: String?, reasoningPreview: String?)
    case invalidOpenAICompatibleResponse(String)
    case invalidReportResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "趋势分析模型地址无效。"
        case .requestFailed(let statusCode, let detail):
            let suffix = detail.map { " \($0)" } ?? ""
            if let statusCode {
                return "趋势分析模型请求失败：HTTP \(statusCode)。\(suffix)"
            }
            return "趋势分析模型请求失败。\(suffix)"
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
}

struct TrendAIClient: TrendAIClientProtocol {
    let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport {
        let content = try await chatCompletionContent(
            settings: settings,
            messages: [
                TrendChatMessage(role: "system", content: prompt.system),
                TrendChatMessage(role: "user", content: prompt.user)
            ],
            temperature: 0.2,
            maxTokens: nil
        ).content

        guard let reportData = content.data(using: .utf8) else {
            throw TrendAIClientError.emptyContent(finishReason: nil, reasoningPreview: nil)
        }
        do {
            return try decoder.decode(TrendAnalysisReport.self, from: reportData)
        } catch {
            throw TrendAIClientError.invalidReportResponse(decodingSummary(error, data: reportData))
        }
    }

    func checkConnection(settings: TrendAIProviderSettings) async throws -> TrendConnectionCheckResult {
        let result = try await chatCompletionContent(
            settings: settings,
            messages: [
                TrendChatMessage(role: "system", content: "你是连通性检测器。只回复 OK。"),
                TrendChatMessage(role: "user", content: "ping")
            ],
            temperature: 0,
            maxTokens: 1024
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

        let (data, response) = try await session.data(for: request)
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
