import Foundation

extension QiemanPlatformNativeClient {
    func fetchMarketIndexQuotes(kinds: [MarketIndexKind]) async -> [MarketIndexKind: MarketIndexQuote] {
        let uniqueKinds = Array(Set(kinds)).sorted { $0.rawValue < $1.rawValue }
        guard !uniqueKinds.isEmpty else { return [:] }

        var results: [MarketIndexKind: MarketIndexQuote] = [:]
        await withTaskGroup(of: (MarketIndexKind, MarketIndexQuote?).self) { group in
            var nextIndex = 0

            func enqueue(_ kind: MarketIndexKind) {
                group.addTask {
                    if let cached = await self.cache.marketIndexQuote(for: kind, ttl: self.quoteTTL) {
                        return (kind, cached)
                    }
                    guard let quote = try? await self.fetchMarketIndexQuote(kind) else {
                        return (kind, nil)
                    }
                    await self.cache.store(marketIndexQuote: quote, for: kind)
                    return (kind, quote)
                }
            }

            while nextIndex < Swift.min(uniqueKinds.count, Self.preloadConcurrencyLimit) {
                enqueue(uniqueKinds[nextIndex])
                nextIndex += 1
            }

            while let (kind, quote) = await group.next() {
                if let quote {
                    results[kind] = quote
                }
                if nextIndex < uniqueKinds.count {
                    enqueue(uniqueKinds[nextIndex])
                    nextIndex += 1
                }
            }
        }
        return results
    }

    func fetchMarketIndexQuote(_ kind: MarketIndexKind) async throws -> MarketIndexQuote? {
        let quote = try await fetchSingleTencentQuote(symbol: kind.tencentSymbol, stockCode: kind.rawValue)
        guard quote.hasUsableData, quote.price > 0 else { return nil }
        let changeAmount = quote.previousClose.map { quote.price - $0 }

        return MarketIndexQuote(
            kind: kind,
            name: kind.label,
            price: round(quote.price, digits: 2),
            previousClose: quote.previousClose.map { round($0, digits: 2) },
            changeAmount: changeAmount.map { round($0, digits: 2) },
            changePct: quote.changePct.map { round($0, digits: 2) },
            quotedAt: quote.priceTime,
            sourceLabel: quote.priceSourceLabel.nilIfEmpty ?? "大盘行情"
        )
    }
}
