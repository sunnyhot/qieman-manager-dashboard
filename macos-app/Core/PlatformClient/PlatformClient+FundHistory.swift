import Foundation

private enum PreloadResult {
    case history(code: String, data: NativeFundHistory)
    case quote(code: String, data: NativeFundQuote)
}

extension QiemanPlatformNativeClient {
    func preloadHistories(_ fundCodes: [String]) async -> [String: NativeFundHistory] {
        var results: [String: NativeFundHistory] = [:]
        let uniqueCodes = uniqueNonEmptyCodes(fundCodes)
        await withTaskGroup(of: (String, NativeFundHistory).self) { group in
            var nextIndex = 0
            func enqueue(_ code: String) {
                group.addTask {
                    if let cached = await self.cache.history(for: code, ttl: self.historyTTL) {
                        return (code, cached)
                    }
                    let history = (try? await self.fetchFundHistorySeries(code)) ?? NativeFundHistory(fundCode: code, fundName: "", series: [])
                    await self.cache.store(history: history, for: code)
                    return (code, history)
                }
            }

            while nextIndex < Swift.min(uniqueCodes.count, Self.preloadConcurrencyLimit) {
                enqueue(uniqueCodes[nextIndex])
                nextIndex += 1
            }

            while let (code, history) = await group.next() {
                results[code] = history
                if nextIndex < uniqueCodes.count {
                    enqueue(uniqueCodes[nextIndex])
                    nextIndex += 1
                }
            }
        }
        return results
    }

    /// Pipelined preload: quotes start as soon as their corresponding history completes,
    /// overlapping the two phases instead of running them sequentially.
    func preloadHistoriesAndQuotes(_ fundCodes: [String]) async -> (histories: [String: NativeFundHistory], quotes: [String: NativeFundQuote]) {
        var histories: [String: NativeFundHistory] = [:]
        var quotes: [String: NativeFundQuote] = [:]
        let uniqueCodes = uniqueNonEmptyCodes(fundCodes)
        guard !uniqueCodes.isEmpty else { return (histories, quotes) }

        await withTaskGroup(of: PreloadResult.self) { group in
            var nextHistoryIndex = 0
            let limit = Self.preloadConcurrencyLimit

            func enqueueHistory(_ code: String) {
                group.addTask {
                    let history: NativeFundHistory
                    if let cached = await self.cache.history(for: code, ttl: self.historyTTL) {
                        history = cached
                    } else {
                        history = (try? await self.fetchFundHistorySeries(code)) ?? NativeFundHistory(fundCode: code, fundName: "", series: [])
                        await self.cache.store(history: history, for: code)
                    }
                    return .history(code: code, data: history)
                }
            }

            func enqueueQuote(_ code: String, history: NativeFundHistory?) {
                group.addTask {
                    let quote: NativeFundQuote
                    if let cached = await self.cache.quote(for: code, ttl: self.quoteTTL) {
                        quote = cached
                    } else {
                        quote = (try? await self.fetchFundQuote(code, history: history)) ?? NativeFundQuote.empty(code)
                        await self.cache.store(quote: quote, for: code)
                    }
                    return .quote(code: code, data: quote)
                }
            }

            while nextHistoryIndex < Swift.min(uniqueCodes.count, limit) {
                enqueueHistory(uniqueCodes[nextHistoryIndex])
                nextHistoryIndex += 1
            }

            while let result = await group.next() {
                switch result {
                case .history(let code, let data):
                    histories[code] = data
                    enqueueQuote(code, history: data)
                    if nextHistoryIndex < uniqueCodes.count {
                        enqueueHistory(uniqueCodes[nextHistoryIndex])
                        nextHistoryIndex += 1
                    }
                case .quote(let code, let data):
                    quotes[code] = data
                }
            }
        }

        return (histories, quotes)
    }

    func fetchFundHistorySeries(_ fundCode: String) async throws -> NativeFundHistory {
        let now = Int(Date().timeIntervalSince1970)
        let url = URL(string: "https://fund.eastmoney.com/pingzhongdata/\(fundCode).js?v=\(now)")!
        let text = try await requestText(hostURL: url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(), absoluteURL: url, headers: [
            "Referer": "https://fund.eastmoney.com/",
        ])

        let name = firstMatch(in: text, pattern: #"var\s+fS_name\s*=\s*"([^"]*)";"#) ?? ""
        guard let trendText = firstMatch(in: text, pattern: #"var\s+Data_netWorthTrend\s*=\s*(\[[\s\S]*?\]);"#),
              let data = trendText.data(using: .utf8),
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return NativeFundHistory(fundCode: fundCode, fundName: name, series: [])
        }

        let series = rows.compactMap { row -> NativeFundHistoryEntry? in
            guard let nav = doubleValue(row["y"]), nav > 0,
                  let ts = intValue(row["x"]), ts > 0 else {
                return nil
            }
            let date = dateTextFromTimestampMs(ts)
            guard !date.isEmpty else { return nil }
            return NativeFundHistoryEntry(date: date, dateKey: dateKey(date), nav: nav, ts: ts)
        }
        return NativeFundHistory(fundCode: fundCode, fundName: name, series: series)
    }
}
