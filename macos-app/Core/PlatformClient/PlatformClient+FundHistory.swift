import Foundation

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
