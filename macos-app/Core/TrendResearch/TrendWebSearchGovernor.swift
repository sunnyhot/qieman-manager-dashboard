import CryptoKit
import Foundation

/// 单次 web_search 的执行结果。`cacheHit` 用于区分模型工具调用与真实 Tavily 请求，
/// 只有后者消耗本次运行的联网搜索预算。
struct TrendWebSearchOutcome: Sendable {
    let response: TavilySearchResponse
    let cacheHit: Bool
    let remainingNetworkSearches: Int
}

struct TrendWebSearchGovernorStatus: Sendable, Equatable {
    let networkSearchesUsed: Int
    let cacheHits: Int
    let maxNetworkSearches: Int

    var remainingNetworkSearches: Int {
        max(0, maxNetworkSearches - networkSearchesUsed)
    }
}

enum TrendWebSearchGovernorError: Error, LocalizedError {
    case budgetExhausted(limit: Int)

    var errorDescription: String? {
        switch self {
        case .budgetExhausted(let limit):
            return "本次分析的 Tavily 实际请求已达到 \(limit) 次上限。已有证据应优先用于形成结论；如仍缺少本地数据，可继续调用持仓或行情工具，随后提交报告。"
        }
    }
}

/// App 生命周期内共享的 Tavily 响应缓存。
///
/// Key 会规范化查询文本、域名顺序和 API Key 指纹；不持久化 API Key，也不把它写入日志。
/// 缓存只减少重复请求，不替代 Agent 对搜索主题和后续工具的自主选择。
actor TrendWebSearchResponseCache {
    private struct Key: Hashable, Sendable {
        let apiKeyDigest: String
        let query: String
        let topic: String
        let searchDepth: String
        let maxResults: Int
        let timeRange: String?
        let includeDomains: [String]
        let includeAnswer: Bool
        let includeRawContent: Bool
        let includeImages: Bool
    }

    private struct Entry: Sendable {
        let response: TavilySearchResponse
        let expiresAt: Date
        let insertedAt: Date
    }

    private var entries: [Key: Entry] = [:]
    private let ttlSeconds: TimeInterval
    private let maxEntries: Int

    init(ttlSeconds: TimeInterval = 6 * 60 * 60, maxEntries: Int = 64) {
        self.ttlSeconds = max(60, ttlSeconds)
        self.maxEntries = max(8, maxEntries)
    }

    func value(
        for request: TavilySearchRequest,
        apiKey: String,
        now: Date = Date()
    ) -> TavilySearchResponse? {
        pruneExpired(now: now)
        return entries[Self.key(for: request, apiKey: apiKey)]?.response
    }

    func store(
        _ response: TavilySearchResponse,
        for request: TavilySearchRequest,
        apiKey: String,
        now: Date = Date()
    ) {
        pruneExpired(now: now)
        if entries.count >= maxEntries,
           let oldest = entries.min(by: { $0.value.insertedAt < $1.value.insertedAt })?.key {
            entries.removeValue(forKey: oldest)
        }
        entries[Self.key(for: request, apiKey: apiKey)] = Entry(
            response: response,
            expiresAt: now.addingTimeInterval(ttlSeconds),
            insertedAt: now
        )
    }

    private func pruneExpired(now: Date) {
        entries = entries.filter { $0.value.expiresAt > now }
    }

    private static func key(for request: TavilySearchRequest, apiKey: String) -> Key {
        Key(
            apiKeyDigest: digest(apiKey),
            query: normalizedText(request.query),
            topic: request.topic.lowercased(),
            searchDepth: request.searchDepth.lowercased(),
            maxResults: request.maxResults,
            timeRange: request.timeRange?.lowercased(),
            includeDomains: (request.includeDomains ?? [])
                .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .sorted(),
            includeAnswer: request.includeAnswer,
            includeRawContent: request.includeRawContent,
            includeImages: request.includeImages
        )
    }

    private static func normalizedText(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "zh_CN")
        )
        let allowed = CharacterSet.alphanumerics
        let separated = folded.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : " "
        }.joined()
        return separated
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// 单次 Agent 运行的 Tavily 治理器：共享缓存，但独立统计真实网络请求额度。
actor TrendWebSearchGovernor {
    private let maxNetworkSearches: Int
    private let cache: TrendWebSearchResponseCache
    private var networkSearchesUsed = 0
    private var cacheHits = 0

    init(
        maxNetworkSearches: Int,
        cache: TrendWebSearchResponseCache = TrendWebSearchResponseCache()
    ) {
        self.maxNetworkSearches = max(1, maxNetworkSearches)
        self.cache = cache
    }

    func search(
        _ request: TavilySearchRequest,
        apiKey: String,
        timeoutSeconds: Double,
        client: any TavilySearchClientProtocol
    ) async throws -> TrendWebSearchOutcome {
        if let response = await cache.value(for: request, apiKey: apiKey) {
            cacheHits += 1
            return TrendWebSearchOutcome(
                response: response,
                cacheHit: true,
                remainingNetworkSearches: max(0, maxNetworkSearches - networkSearchesUsed)
            )
        }

        guard networkSearchesUsed < maxNetworkSearches else {
            throw TrendWebSearchGovernorError.budgetExhausted(limit: maxNetworkSearches)
        }

        // 发起请求即计入预算；网络失败也会消耗一次实际尝试，防止故障时无限重试。
        networkSearchesUsed += 1
        let response = try await client.search(
            request,
            apiKey: apiKey,
            timeoutSeconds: timeoutSeconds
        )
        await cache.store(response, for: request, apiKey: apiKey)
        return TrendWebSearchOutcome(
            response: response,
            cacheHit: false,
            remainingNetworkSearches: max(0, maxNetworkSearches - networkSearchesUsed)
        )
    }

    func status() -> TrendWebSearchGovernorStatus {
        TrendWebSearchGovernorStatus(
            networkSearchesUsed: networkSearchesUsed,
            cacheHits: cacheHits,
            maxNetworkSearches: maxNetworkSearches
        )
    }
}
