import Foundation

extension QiemanPlatformNativeClient {
    func uniqueNonEmptyCodes(_ codes: [String]) -> [String] {
        Array(Set(codes.map(normalizedString).filter { !$0.isEmpty })).sorted()
    }

    func lookupNav(history: NativeFundHistory?, dateText: String) -> NativeFundHistoryEntry? {
        guard let history else { return nil }
        let targetKey = dateKey(dateText)
        guard targetKey > 0, !history.series.isEmpty else { return nil }
        var low = 0
        var high = history.series.count
        while low < high {
            let mid = (low + high) / 2
            if history.series[mid].dateKey <= targetKey {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let index = low - 1
        guard index >= 0, index < history.series.count else { return nil }
        return history.series[index]
    }

    func normalizePlatformOrder(_ order: [String: Any], adjustmentID: Int) -> NativePlatformOrder {
        let orderCode = normalizedString(order["orderCode"])
        let side: String
        let label: String
        switch orderCode {
        case "022":
            side = "buy"
            label = "买入"
        case "024":
            side = "sell"
            label = "卖出"
        default:
            side = "unknown"
            label = orderCode.isEmpty ? "未知" : orderCode
        }
        let fund = order["fund"] as? [String: Any] ?? [:]
        let title = firstNonEmpty([
            normalizedString(order["variety"]),
            normalizedString(fund["fundName"]),
            normalizedString(fund["fundCode"]),
            "未命名标的",
        ])
        return NativePlatformOrder(
            adjustmentID: adjustmentID,
            side: side,
            label: label,
            fundCode: normalizedString(fund["fundCode"]),
            fundName: normalizedString(fund["fundName"]),
            title: title,
            tradeUnit: intValue(order["tradeUnit"]) ?? 0,
            postPlanUnit: intValue(order["postPlanUnit"]) ?? 0,
            strategyType: normalizedString(order["strategyType"]),
            largeClass: normalizedString(order["largeClass"]),
            nav: doubleValue(order["nav"]) ?? 0,
            navDate: formatTime(firstNonEmpty([formatTimestampMs(order["navDate"]), normalizedString(order["navDate"])])),
            buyDate: formatTime(formatTimestampMs(((order["gridDetail"] as? [String: Any])?["buyDate"]))),
            orderCountInAdjustment: 0
        )
    }
}
