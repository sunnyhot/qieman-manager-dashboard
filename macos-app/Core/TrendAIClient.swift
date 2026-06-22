import Foundation

protocol TrendAIClientProtocol {
    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport
}

enum TrendAIClientError: LocalizedError {
    case invalidBaseURL
    case requestFailed(Int?)
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "趋势分析模型地址无效。"
        case .requestFailed(let statusCode):
            if let statusCode {
                return "趋势分析模型请求失败：HTTP \(statusCode)。"
            }
            return "趋势分析模型请求失败。"
        case .emptyContent:
            return "趋势分析模型没有返回可解析内容。"
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
        let url = try chatCompletionsURL(baseURL: settings.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.timeoutSeconds
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TrendChatCompletionRequest(
            model: settings.model,
            messages: [
                TrendChatMessage(role: "system", content: prompt.system),
                TrendChatMessage(role: "user", content: prompt.user)
            ],
            temperature: 0.2
        ))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TrendAIClientError.requestFailed(nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TrendAIClientError.requestFailed(http.statusCode)
        }

        let completion = try decoder.decode(TrendChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content,
              let reportData = content.data(using: .utf8) else {
            throw TrendAIClientError.emptyContent
        }
        return try decoder.decode(TrendAnalysisReport.self, from: reportData)
    }

    private func chatCompletionsURL(baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/chat/completions") else {
            throw TrendAIClientError.invalidBaseURL
        }
        return url
    }
}

private struct TrendChatCompletionRequest: Encodable {
    let model: String
    let messages: [TrendChatMessage]
    let temperature: Double
}

private struct TrendChatMessage: Codable {
    let role: String?
    let content: String
}

private struct TrendChatCompletionResponse: Decodable {
    let choices: [TrendChatChoice]
}

private struct TrendChatChoice: Decodable {
    let message: TrendChatMessage
}
