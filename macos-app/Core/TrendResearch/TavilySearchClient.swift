import Foundation

protocol TavilySearchClientProtocol: Sendable {
    func search(
        _ searchRequest: TavilySearchRequest,
        apiKey: String,
        timeoutSeconds: Double
    ) async throws -> TavilySearchResponse
}

struct TavilySearchRequest: Encodable, Hashable, Sendable {
    let query: String
    let topic: String
    let searchDepth: String
    let maxResults: Int
    let timeRange: String?
    let includeDomains: [String]?
    let includeAnswer: Bool
    let includeRawContent: Bool
    let includeImages: Bool

    enum CodingKeys: String, CodingKey {
        case query
        case topic
        case searchDepth = "search_depth"
        case maxResults = "max_results"
        case timeRange = "time_range"
        case includeDomains = "include_domains"
        case includeAnswer = "include_answer"
        case includeRawContent = "include_raw_content"
        case includeImages = "include_images"
    }
}

struct TavilySearchResponse: Decodable, Hashable, Sendable {
    let query: String?
    let results: [TavilySearchResult]
    let responseTime: String?
    let requestID: String?

    enum CodingKeys: String, CodingKey {
        case query
        case results
        case responseTime = "response_time"
        case requestID = "request_id"
    }
}

struct TavilySearchResult: Decodable, Hashable, Sendable {
    let title: String
    let url: String
    let content: String
    let score: Double?
    let publishedDate: String?

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case content
        case score
        case publishedDate = "published_date"
    }
}

enum TavilySearchClientError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse(String)
    case requestFailed(statusCode: Int, detail: String?)
    case timedOut(Double)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "尚未配置 Tavily API Key。请在「设置 > AI 研判 > 联网搜索」中填写。"
        case .invalidResponse(let detail):
            return "Tavily 返回格式无效：\(detail)"
        case .requestFailed(let statusCode, let detail):
            let suffix = detail.map { " \($0)" } ?? ""
            if statusCode == 401 {
                return "Tavily API Key 无效或无权访问搜索服务。\(suffix)"
            }
            if [429, 432, 433].contains(statusCode) {
                return "Tavily 搜索额度或请求频率已达上限，请稍后重试。\(suffix)"
            }
            return "Tavily 搜索失败：HTTP \(statusCode)。\(suffix)"
        case .timedOut(let seconds):
            return "Tavily 搜索超时：\(Int(seconds)) 秒内未返回。"
        }
    }
}

struct TavilySearchClient: TavilySearchClientProtocol, Sendable {
    static let endpoint = URL(string: "https://api.tavily.com/search")!

    let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(
        _ searchRequest: TavilySearchRequest,
        apiKey: String,
        timeoutSeconds: Double = 30
    ) async throws -> TavilySearchResponse {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw TavilySearchClientError.missingAPIKey
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(searchRequest)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw TavilySearchClientError.timedOut(timeoutSeconds)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TavilySearchClientError.invalidResponse("缺少 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TavilySearchClientError.requestFailed(
                statusCode: http.statusCode,
                detail: Self.errorMessage(from: data)
            )
        }

        do {
            return try decoder.decode(TavilySearchResponse.self, from: data)
        } catch {
            throw TavilySearchClientError.invalidResponse(error.localizedDescription)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8).map { String($0.prefix(220)) }
        }
        if let detail = object["detail"] as? String { return detail }
        if let detail = object["detail"] as? [String: Any],
           let error = detail["error"] as? String {
            return error
        }
        if let message = object["message"] as? String { return message }
        return nil
    }
}
