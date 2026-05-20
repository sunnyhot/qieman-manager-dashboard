import CryptoKit
import Foundation

enum NativePlatformError: LocalizedError {
    case missingProdCode
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingProdCode:
            return "没有产品代码，无法直拉平台调仓记录。"
        case .invalidResponse:
            return "平台调仓接口返回结构异常。"
        case .api(let message):
            return message
        }
    }
}

actor QiemanPlatformCache {
    private var payloads: [String: (Date, PlatformPayload)] = [:]
    private var histories: [String: (Date, NativeFundHistory)] = [:]
    private var quotes: [String: (Date, NativeFundQuote)] = [:]
    private var stockQuotes: [String: (Date, NativeStockQuote)] = [:]
    private var marketIndexQuotes: [MarketIndexKind: (Date, MarketIndexQuote)] = [:]

    func payload(for prodCode: String, ttl: TimeInterval) -> PlatformPayload? {
        guard let (loadedAt, payload) = payloads[prodCode], Date().timeIntervalSince(loadedAt) < ttl else {
            return nil
        }
        return payload
    }

    func store(payload: PlatformPayload, for prodCode: String) {
        payloads[prodCode] = (Date(), payload)
    }

    func history(for fundCode: String, ttl: TimeInterval) -> NativeFundHistory? {
        guard let (loadedAt, history) = histories[fundCode], Date().timeIntervalSince(loadedAt) < ttl else {
            return nil
        }
        return history
    }

    func store(history: NativeFundHistory, for fundCode: String) {
        histories[fundCode] = (Date(), history)
    }

    func quote(for fundCode: String, ttl: TimeInterval) -> NativeFundQuote? {
        guard let (loadedAt, quote) = quotes[fundCode], Date().timeIntervalSince(loadedAt) < ttl else {
            return nil
        }
        return quote
    }

    func store(quote: NativeFundQuote, for fundCode: String) {
        quotes[fundCode] = (Date(), quote)
    }

    func stockQuote(for stockCode: String, ttl: TimeInterval) -> NativeStockQuote? {
        guard let (loadedAt, quote) = stockQuotes[stockCode], Date().timeIntervalSince(loadedAt) < ttl else {
            return nil
        }
        return quote
    }

    func store(stockQuote: NativeStockQuote, for stockCode: String) {
        stockQuotes[stockCode] = (Date(), stockQuote)
    }

    func marketIndexQuote(for kind: MarketIndexKind, ttl: TimeInterval) -> MarketIndexQuote? {
        guard let (loadedAt, quote) = marketIndexQuotes[kind], Date().timeIntervalSince(loadedAt) < ttl else {
            return nil
        }
        return quote
    }

    func store(marketIndexQuote: MarketIndexQuote, for kind: MarketIndexKind) {
        marketIndexQuotes[kind] = (Date(), marketIndexQuote)
    }
}

struct NativePlatformOrder {
    let adjustmentID: Int
    let side: String
    let label: String
    let fundCode: String
    let fundName: String
    let title: String
    let tradeUnit: Int
    let postPlanUnit: Int
    let strategyType: String
    let largeClass: String
    let nav: Double
    let navDate: String
    let buyDate: String
    let orderCountInAdjustment: Int
}

struct NativePlatformActionSeed {
    let actionKey: String
    let adjustmentID: Int
    let adjustmentTitle: String
    let title: String
    let actionTitle: String
    let fundName: String
    let fundCode: String
    let side: String
    let action: String
    let tradeUnit: Int
    let postPlanUnit: Int
    let createdAt: String
    let txnDate: String
    let createdTs: Int
    let txnTs: Int
    let articleURL: String
    let comment: String
    let strategyType: String
    let largeClass: String
    let buyDate: String
    let nav: Double
    let navDate: String
    let orderCountInAdjustment: Int
}

struct NativePlatformAdjustment {
    let adjustmentID: Int
    let title: String
    let createdTs: Int
    let txnTs: Int
    let orderCount: Int
}

struct NativeFundHistoryEntry {
    let date: String
    let dateKey: Int
    let nav: Double
    let ts: Int
}

struct NativeFundHistory {
    let fundCode: String
    let fundName: String
    let series: [NativeFundHistoryEntry]
}

struct NativeFundQuote {
    let fundCode: String
    let fundName: String
    let price: Double
    let priceTime: String
    let priceSource: String
    let priceSourceLabel: String
    let officialNav: Double?
    let officialNavDate: String
    let estimatePrice: Double?
    let estimateTime: String
    let estimateChangePct: Double?

    static func empty(_ fundCode: String) -> NativeFundQuote {
        NativeFundQuote(
            fundCode: fundCode,
            fundName: "",
            price: 0,
            priceTime: "",
            priceSource: "",
            priceSourceLabel: "",
            officialNav: nil,
            officialNavDate: "",
            estimatePrice: nil,
            estimateTime: "",
            estimateChangePct: nil
        )
    }
}

struct NativeStockQuote {
    let stockCode: String
    let stockName: String
    let price: Double
    let priceTime: String
    let priceSource: String
    let priceSourceLabel: String
    let previousClose: Double?
    let changePct: Double?

    var hasUsableData: Bool {
        price > 0 || !stockName.isEmpty
    }

    static func empty(_ stockCode: String) -> NativeStockQuote {
        NativeStockQuote(
            stockCode: stockCode,
            stockName: "",
            price: 0,
            priceTime: "",
            priceSource: "",
            priceSourceLabel: "",
            previousClose: nil,
            changePct: nil
        )
    }
}

struct NativeUserPortfolioPricePayload {
    let assetName: String
    let currentPrice: Double?
    let priceTime: String
    let priceSource: String
    let officialNav: Double?
    let officialNavDate: String
    let estimatePrice: Double?
    let estimatePriceTime: String
    let estimateChangePct: Double?
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func prefixString(_ length: Int) -> String {
        String(prefix(length))
    }
}

final class QiemanPlatformNativeClient {
    let baseURL = URL(string: "https://qieman.com")!
    private let apiBase = "/pmdj/v2"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private let anonymousID = "anon-\(QiemanPlatformNativeClient.sha256Hex(UUID().uuidString).prefix(16))"
    let payloadTTL: TimeInterval = 120
    let historyTTL: TimeInterval = 12 * 60 * 60
    let quoteTTL: TimeInterval = 45
    let cache = QiemanPlatformCache()
    static let preloadConcurrencyLimit = 6

    // MARK: - Networking

    func requestJSON(hostURL: URL, path: String, params: [String: String], headers: [String: String]) async throws -> Any {
        var components = URLComponents(url: hostURL.appendingPathComponent(apiBase + path), resolvingAgainstBaseURL: false)
        components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }.sorted(by: { $0.name < $1.name })
        guard let url = components?.url else {
            throw NativePlatformError.invalidResponse
        }
        let query = components?.percentEncodedQuery.map { "?\($0)" } ?? ""
        let pathWithQuery = apiBase + path + query

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(makeXSign(), forHTTPHeaderField: "x-sign")
        request.setValue(makeXRequestID(pathWithQuery: pathWithQuery), forHTTPHeaderField: "x-request-id")
        request.setValue(anonymousID, forHTTPHeaderField: "sensors-anonymous-id")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NativePlatformError.invalidResponse
        }
        let payload = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        if !(200..<300).contains(http.statusCode) {
            throw NativePlatformError.api(buildErrorMessage(payload, statusCode: http.statusCode))
        }
        if let object = payload as? [String: Any] {
            let code = normalizedString(object["code"])
            if !code.isEmpty, code != "0", code != "200" {
                throw NativePlatformError.api(buildErrorMessage(payload, statusCode: http.statusCode))
            }
        }
        return payload
    }

    func requestText(hostURL: URL, absoluteURL: URL, headers: [String: String]) async throws -> String {
        var request = URLRequest(url: absoluteURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NativePlatformError.invalidResponse
        }
        return decodeResponseText(data)
    }

    private func buildErrorMessage(_ payload: Any, statusCode: Int) -> String {
        if let object = payload as? [String: Any] {
            let detail = object["detail"] as? [String: Any]
            let detailMessage = firstNonEmpty([normalizedString(detail?["msg"]), normalizedString(detail?["message"])])
            let message = firstNonEmpty([normalizedString(object["msg"]), normalizedString(object["message"]), detailMessage, "请求失败"])
            return "HTTP \(statusCode) | \(message)"
        }
        return "HTTP \(statusCode)"
    }

    private func makeXSign() -> String {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let digest = QiemanPlatformNativeClient.sha256Hex(String(Int(Double(now) * 1.01))).uppercased()
        return "\(now)\(digest.prefix(32))"
    }

    private func makeXRequestID(pathWithQuery: String) -> String {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let seed = "\(Double.random(in: 0..<1))\(now)\(pathWithQuery)\(anonymousID)"
        return "albus.\(QiemanPlatformNativeClient.sha256Hex(seed).suffix(20).uppercased())"
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - String / Value Utilities

    func normalizedString(_ value: Any?) -> String {
        guard let value else { return "" }
        if value is NSNull { return "" }
        return String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func firstNonEmpty(_ values: [String]) -> String {
        values.first(where: { !$0.isEmpty }) ?? ""
    }

    func intValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    func doubleValue(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    func scaledQuoteValue(_ value: Any?, scale: Double) -> Double? {
        guard let raw = doubleValue(value), scale > 0 else { return nil }
        return raw / scale
    }

    func stockSecID(for stockCode: String, market: StockMarket? = nil) -> String? {
        let code = stockCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMarket = market ?? UserPortfolioHolding.detectStockMarket(from: code)
        guard resolvedMarket == nil || resolvedMarket == .aShare else { return nil }
        guard code.count == 6, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: code)) else {
            return nil
        }
        if code.hasPrefix("5") || code.hasPrefix("6") || code.hasPrefix("9") {
            return "1.\(code)"
        }
        return "0.\(code)"
    }

    func tencentStockSymbol(for stockCode: String, market: StockMarket? = nil) -> String? {
        let code = stockCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMarket = market ?? UserPortfolioHolding.detectStockMarket(from: code)

        switch resolvedMarket {
        case .aShare:
            guard code.count == 6, code.allSatisfy(\.isNumber) else { return nil }
            if code.hasPrefix("5") || code.hasPrefix("6") || code.hasPrefix("9") {
                return "sh\(code)"
            }
            if code.hasPrefix("4") || code.hasPrefix("8") {
                return "bj\(code)"
            }
            return "sz\(code)"
        case .hk:
            return "hk\(code)"
        case .us:
            return "us\(code.uppercased())"
        case nil:
            return nil
        }
    }

    func formattedTencentQuoteTime(_ value: String?) -> String {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 14 else { return raw }
        let year = raw.prefix(4)
        let month = raw.dropFirst(4).prefix(2)
        let day = raw.dropFirst(6).prefix(2)
        let hour = raw.dropFirst(8).prefix(2)
        let minute = raw.dropFirst(10).prefix(2)
        let second = raw.dropFirst(12).prefix(2)
        return "\(year)-\(month)-\(day) \(hour):\(minute):\(second)"
    }

    func decodeResponseText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let text = String(data: data, encoding: gb18030) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Date / Time Utilities

    func actionTimestamp(_ txnTs: Int?, createdTs: Int?) -> Int {
        (txnTs ?? 0) > 0 ? (txnTs ?? 0) : (createdTs ?? 0)
    }

    func formatTimestampMs(_ value: Any?) -> String {
        guard let ms = intValue(value), ms > 0 else { return "" }
        return isoDateTime(Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }

    static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let isoDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static let displayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func dateTextFromTimestampMs(_ value: Int) -> String {
        Self.dateOnlyFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(value) / 1000))
    }

    func isoDateTime(_ date: Date) -> String {
        Self.isoDateTimeFormatter.string(from: date)
    }

    func formatTime(_ value: String) -> String {
        let text = normalizedString(value)
        guard !text.isEmpty else { return "未记录" }
        return text.replacingOccurrences(of: "T", with: " ").prefixString(19)
    }

    func normalizeDateText(_ value: String) -> String {
        let text = normalizedString(value)
        return text.count >= 10 ? String(text.prefix(10)) : text
    }

    func dateKey(_ value: String) -> Int {
        let text = normalizeDateText(value)
        guard !text.isEmpty else { return 0 }
        return Int(text.replacingOccurrences(of: "-", with: "")) ?? 0
    }

    func round(_ value: Double, digits: Int) -> Double {
        let base = pow(10.0, Double(digits))
        return (value * base).rounded() / base
    }

    func isoTimestampNow() -> String {
        Self.displayTimeFormatter.string(from: Date())
    }

    func zipOptional(_ lhs: Double?, _ rhs: Double?) -> (Double, Double)? {
        guard let lhs, let rhs else { return nil }
        return (lhs, rhs)
    }

    // MARK: - Regex

    static let regexCache: [String: NSRegularExpression] = {
        let patterns = [
            #"var\s+fS_name\s*=\s*"([^"]*)";"#,
            #"var\s+Data_netWorthTrend\s*=\s*(\[[\s\S]*?\]);"#,
            #"jsonpgz\((\{[\s\S]*\})\);"#,
            #"="([^"]*)";"#,
        ]
        return Dictionary(uniqueKeysWithValues: patterns.compactMap { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                return nil
            }
            return (pattern, regex)
        })
    }()

    func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = Self.regexCache[pattern] ?? (try? NSRegularExpression(pattern: pattern, options: [])) else {
            return nil
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let resultRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[resultRange])
    }
}
