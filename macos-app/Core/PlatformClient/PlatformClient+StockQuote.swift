import Foundation

extension QiemanPlatformNativeClient {
    func preloadStockQuotes(_ stockCodes: [String]) async -> [String: NativeStockQuote] {
        var results: [String: NativeStockQuote] = [:]
        let uniqueCodes = uniqueNonEmptyCodes(stockCodes)
        await withTaskGroup(of: (String, NativeStockQuote).self) { group in
            var nextIndex = 0
            func enqueue(_ code: String) {
                group.addTask {
                    if let cached = await self.cache.stockQuote(for: code, ttl: self.quoteTTL) {
                        return (code, cached)
                    }
                    let quote = (try? await self.fetchStockQuote(code)) ?? NativeStockQuote.empty(code)
                    await self.cache.store(stockQuote: quote, for: code)
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

    func fetchStockQuote(_ stockCode: String) async throws -> NativeStockQuote {
        if let quote = try? await fetchEastmoneyStockQuote(stockCode), quote.hasUsableData {
            return quote
        }
        if let quote = try? await fetchTencentStockQuote(stockCode), quote.hasUsableData {
            return quote
        }
        return .empty(stockCode)
    }

    func fetchEastmoneyStockQuote(_ stockCode: String) async throws -> NativeStockQuote {
        guard let secid = stockSecID(for: stockCode) else {
            return .empty(stockCode)
        }
        let url = URL(string: "https://push2.eastmoney.com/api/qt/stock/get?secid=\(secid)&fields=f43,f57,f58,f59,f60,f169,f170")!
        let text = try await requestText(hostURL: url, absoluteURL: url, headers: [
            "Accept": "application/json",
            "Referer": "https://quote.eastmoney.com/",
        ])
        let payload = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) ?? [:]
        guard let object = payload as? [String: Any],
              let data = object["data"] as? [String: Any],
              let code = normalizedString(data["f57"]).nilIfEmpty else {
            return .empty(stockCode)
        }

        let scale = pow(10.0, Double(intValue(data["f59"]) ?? 2))
        let price = scaledQuoteValue(data["f43"], scale: scale)
        let previousClose = scaledQuoteValue(data["f60"], scale: scale)
        let changePct = scaledQuoteValue(data["f170"], scale: 100)

        return NativeStockQuote(
            stockCode: code,
            stockName: normalizedString(data["f58"]),
            price: price ?? 0,
            priceTime: isoTimestampNow(),
            priceSource: "stock_quote",
            priceSourceLabel: "股票行情",
            previousClose: previousClose,
            changePct: changePct
        )
    }

    func fetchTencentStockQuote(_ stockCode: String) async throws -> NativeStockQuote {
        let market = UserPortfolioHolding.detectStockMarket(from: stockCode)

        guard let symbol = tencentStockSymbol(for: stockCode, market: market) else {
            return .empty(stockCode)
        }

        let quote = try await fetchSingleTencentQuote(symbol: symbol, stockCode: stockCode)
        if quote.hasUsableData { return quote }

        if market == .us {
            for suffix in [".O", ".N", ".A"] {
                let altSymbol = "\(symbol)\(suffix)"
                let altQuote = try? await fetchSingleTencentQuote(symbol: altSymbol, stockCode: stockCode)
                if let altQuote, altQuote.hasUsableData { return altQuote }
            }
        }

        return quote
    }

    func fetchSingleTencentQuote(symbol: String, stockCode: String) async throws -> NativeStockQuote {
        let url = URL(string: "https://qt.gtimg.cn/q=\(symbol)")!
        let text = try await requestText(hostURL: url, absoluteURL: url, headers: [
            "Accept": "text/plain,*/*",
            "Referer": "https://gu.qq.com/",
        ])
        guard let quoted = firstMatch(in: text, pattern: #"="([^"]*)";"#) else {
            return .empty(stockCode)
        }
        let parts = quoted.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 32 else {
            return .empty(stockCode)
        }
        let code = normalizedString(parts[safe: 2]).nilIfEmpty ?? stockCode
        let price = doubleValue(parts[safe: 3]) ?? 0
        let previousClose = doubleValue(parts[safe: 4])
        let changePct = doubleValue(parts[safe: 32])

        return NativeStockQuote(
            stockCode: code,
            stockName: normalizedString(parts[safe: 1]),
            price: price,
            priceTime: formattedTencentQuoteTime(parts[safe: 30]),
            priceSource: "tencent_stock_quote",
            priceSourceLabel: "股票行情",
            previousClose: previousClose,
            changePct: changePct
        )
    }
}
