import CryptoKit
import Foundation

struct TavilyWebSearchTool: TrendResearchTool {
    let client: any TavilySearchClientProtocol

    let name = "web_search"
    let description = "通过 Tavily 搜索最新网页信息，用于行业变化、宏观环境、监管政策和重要市场事件。查询中不得包含用户姓名、组合名称、金额或其他个人信息。优先使用近期、权威和可追溯来源。"
    let parameters: AgentJSONValue = [
        "type": "object",
        "properties": [
            "query": [
                "type": "string",
                "minLength": 2,
                "maxLength": 400,
                "description": "搜索关键词。只包含通用行业、政策或资产类别，不得包含个人组合和金额信息。"
            ],
            "topic": [
                "type": "string",
                "enum": ["general", "news", "finance"],
                "description": "搜索类别，默认 news。政策和行业动态优先使用 news，市场数据可使用 finance。"
            ],
            "time_range": [
                "type": "string",
                "enum": ["day", "week", "month", "year"],
                "description": "发布时间范围，默认 month。"
            ],
            "max_results": [
                "type": "integer",
                "minimum": 1,
                "maximum": 8,
                "description": "返回条数，默认 5，范围 1...8。"
            ],
            "include_domains": [
                "type": "array",
                "maxItems": 8,
                "items": ["type": "string"],
                "description": "可选域名白名单，例如 gov.cn、pbc.gov.cn、csrc.gov.cn。不要包含协议或路径。"
            ]
        ],
        "required": ["query"],
        "additionalProperties": false
    ]

    private struct Params: Decodable {
        let query: String
        let topic: String?
        let time_range: String?
        let max_results: Int?
        let include_domains: [String]?
    }

    func execute(argumentsJSON: String, context: TrendResearchToolContext) async -> TrendResearchToolResult {
        guard context.webSearchSettings.isConfigured else {
            return .content(
                TrendResearchToolEnvelope.error(
                    code: "web_search_not_configured",
                    message: TavilySearchClientError.missingAPIKey.localizedDescription
                ),
                isError: true
            )
        }

        let params: Params
        do {
            params = try JSONDecoder().decode(Params.self, from: Data(argumentsJSON.utf8))
        } catch {
            return invalidArguments("参数不是合法 JSON：\(error.localizedDescription)")
        }

        let query = params.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...400).contains(query.count) else {
            return invalidArguments("query 长度必须在 2...400 个字符之间")
        }

        let topic = params.topic ?? "news"
        guard ["general", "news", "finance"].contains(topic) else {
            return invalidArguments("topic 只能是 general/news/finance")
        }

        let timeRange = params.time_range ?? "month"
        guard ["day", "week", "month", "year"].contains(timeRange) else {
            return invalidArguments("time_range 只能是 day/week/month/year")
        }

        let maxResults = params.max_results ?? 5
        guard (1...8).contains(maxResults) else {
            return invalidArguments("max_results 必须在 1...8 之间")
        }

        let domains: [String]?
        do {
            domains = try normalizedDomains(params.include_domains)
        } catch {
            return invalidArguments(error.localizedDescription)
        }

        let request = TavilySearchRequest(
            query: query,
            topic: topic,
            searchDepth: "basic",
            maxResults: maxResults,
            timeRange: timeRange,
            includeDomains: domains,
            includeAnswer: false,
            includeRawContent: false,
            includeImages: false
        )

        do {
            let response = try await client.search(
                request,
                apiKey: context.webSearchSettings.apiKey,
                timeoutSeconds: 30
            )
            return await makeResult(response: response, query: query, context: context)
        } catch is CancellationError {
            return .content(
                TrendResearchToolEnvelope.error(code: "web_search_cancelled", message: "Tavily 搜索已取消"),
                isError: true
            )
        } catch {
            return .content(
                TrendResearchToolEnvelope.error(code: "web_search_failed", message: error.localizedDescription),
                isError: true
            )
        }
    }

    private func makeResult(
        response: TavilySearchResponse,
        query: String,
        context: TrendResearchToolContext
    ) async -> TrendResearchToolResult {
        var seenURLs = Set<String>()
        let results = response.results.compactMap { result -> SearchResult? in
            let normalizedURL = result.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: normalizedURL),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  !seenURLs.contains(normalizedURL) else {
                return nil
            }
            seenURLs.insert(normalizedURL)
            let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !content.isEmpty else { return nil }
            return SearchResult(
                evidenceID: Self.evidenceID(for: normalizedURL),
                title: title,
                url: normalizedURL,
                source: Self.sourceName(for: url),
                publishedAt: result.publishedDate,
                summary: String(content.prefix(1_200)),
                score: result.score
            )
        }

        let retrievedAt = ISO8601DateFormatter().string(from: Date())
        await context.evidenceLedger.record(
            results.map {
                TrendEvidence(
                    id: $0.evidenceID,
                    sourceName: $0.source,
                    title: $0.title,
                    url: $0.url,
                    publishedAt: $0.publishedAt,
                    retrievedAt: retrievedAt,
                    summary: $0.summary
                )
            }
        )

        let payload: [[String: Any]] = results.map {
            [
                "evidence_id": $0.evidenceID,
                "title": $0.title,
                "url": $0.url,
                "source": $0.source,
                "published_at": $0.publishedAt ?? NSNull(),
                "summary": $0.summary,
                "score": $0.score ?? NSNull()
            ]
        }
        let warnings = results.isEmpty ? ["Tavily 未返回可用结果，请调整关键词、时间范围或域名限制。"] : []
        return .content(
            TrendResearchToolEnvelope.success(
                [
                    "query": query,
                    "results": payload,
                    "count": results.count,
                    "request_id": response.requestID ?? NSNull()
                ],
                warnings: warnings,
                evidenceIDs: results.map(\.evidenceID)
            )
        )
    }

    private func normalizedDomains(_ values: [String]?) throws -> [String]? {
        guard let values, !values.isEmpty else { return nil }
        guard values.count <= 8 else {
            throw ValidationError(message: "include_domains 最多包含 8 个域名")
        }
        let domains = values.map {
            $0.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "www.", with: "", options: [.anchored])
        }
        guard domains.allSatisfy({
            !$0.isEmpty
                && !$0.contains("://")
                && !$0.contains("/")
                && !$0.contains(" ")
                && $0.contains(".")
        }) else {
            throw ValidationError(message: "include_domains 只能填写不带协议和路径的域名")
        }
        var seen = Set<String>()
        return domains.filter { seen.insert($0).inserted }
    }

    private func invalidArguments(_ message: String) -> TrendResearchToolResult {
        .content(
            TrendResearchToolEnvelope.error(code: "invalid_arguments", message: message),
            isError: true
        )
    }

    private static func evidenceID(for url: String) -> String {
        let digest = SHA256.hash(data: Data(url.lowercased().utf8))
        let value = digest.map { String(format: "%02x", $0) }.joined()
        return "web:tavily:\(value.prefix(20))"
    }

    private static func sourceName(for url: URL) -> String {
        let host = url.host?.replacingOccurrences(of: "www.", with: "", options: [.anchored]) ?? "网页"
        return "Tavily · \(host)"
    }

    private struct SearchResult {
        let evidenceID: String
        let title: String
        let url: String
        let source: String
        let publishedAt: String?
        let summary: String
        let score: Double?
    }

    private struct ValidationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
