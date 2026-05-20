import Foundation

extension QiemanPlatformNativeClient {
    func preloadQuotes(_ fundCodes: [String], histories: [String: NativeFundHistory]) async -> [String: NativeFundQuote] {
        var results: [String: NativeFundQuote] = [:]
        let uniqueCodes = uniqueNonEmptyCodes(fundCodes)
        await withTaskGroup(of: (String, NativeFundQuote).self) { group in
            var nextIndex = 0
            func enqueue(_ code: String) {
                group.addTask {
                    if let cached = await self.cache.quote(for: code, ttl: self.quoteTTL) {
                        return (code, cached)
                    }
                    let quote = (try? await self.fetchFundQuote(code, history: histories[code])) ?? NativeFundQuote.empty(code)
                    await self.cache.store(quote: quote, for: code)
                    return (code, quote)
                }
            }

            while nextIndex < Swift.min(uniqueCodes.count, Self.preloadConcurrencyLimit) {
                enqueue(uniqueCodes[nextIndex])
                nextIndex += 1
            }

            while let (code, quote) = await group.next() {
                results[code] = quote
                if nextIndex < uniqueCodes.count {
                    enqueue(uniqueCodes[nextIndex])
                    nextIndex += 1
                }
            }
        }
        return results
    }

    func fetchFundQuote(_ fundCode: String, history: NativeFundHistory?) async throws -> NativeFundQuote {
        let now = Int(Date().timeIntervalSince1970)
        let url = URL(string: "https://fundgz.1234567.com.cn/js/\(fundCode).js?rt=\(now)")!
        let text = (try? await requestText(hostURL: url.deletingLastPathComponent().deletingLastPathComponent(), absoluteURL: url, headers: [
            "Referer": "https://fund.eastmoney.com/",
        ])) ?? ""

        if let payloadText = firstMatch(in: text, pattern: #"jsonpgz\((\{[\s\S]*\})\);"#),
           let data = payloadText.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let officialNav = doubleValue(object["dwjz"])
            let officialNavDate = normalizedString(object["jzrq"])
            if let officialNav, officialNav > 0 {
                return NativeFundQuote(
                    fundCode: fundCode,
                    fundName: normalizedString(object["name"]),
                    price: officialNav,
                    priceTime: officialNavDate,
                    priceSource: "official_nav",
                    priceSourceLabel: "最新净值",
                    officialNav: officialNav,
                    officialNavDate: officialNavDate,
                    estimatePrice: doubleValue(object["gsz"]),
                    estimateTime: normalizedString(object["gztime"]),
                    estimateChangePct: doubleValue(object["gszzl"])
                )
            }

            if let estimatePrice = doubleValue(object["gsz"]), estimatePrice > 0 {
                return NativeFundQuote(
                    fundCode: fundCode,
                    fundName: normalizedString(object["name"]),
                    price: estimatePrice,
                    priceTime: normalizedString(object["gztime"]),
                    priceSource: "estimate",
                    priceSourceLabel: "盘中估值",
                    officialNav: nil,
                    officialNavDate: "",
                    estimatePrice: estimatePrice,
                    estimateTime: normalizedString(object["gztime"]),
                    estimateChangePct: doubleValue(object["gszzl"])
                )
            }
        }

        if let latest = history?.series.last {
            return NativeFundQuote(
                fundCode: fundCode,
                fundName: history?.fundName ?? "",
                price: latest.nav,
                priceTime: latest.date,
                priceSource: "official_nav",
                priceSourceLabel: "最近净值",
                officialNav: latest.nav,
                officialNavDate: latest.date,
                estimatePrice: nil,
                estimateTime: "",
                estimateChangePct: nil
            )
        }
        return .empty(fundCode)
    }
}
