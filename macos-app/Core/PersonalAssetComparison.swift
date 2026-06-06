import Foundation

struct PersonalAssetComparisonItem: Identifiable, Hashable {
    let id: String
    let title: String
    let codeText: String
    let statusText: String
    let exposureValue: Double
    let marketValueText: String
    let exposureText: String
    let profitValue: Double?
    let profitRateValue: Double?
    let profitText: String
    let profitRateText: String
    let dailyChangeValue: Double?
    let dailyChangeRateValue: Double?
    let dailyChangeText: String
    let dailyChangeRateText: String
    let pendingText: String
    let planText: String
    let isLargestExposure: Bool
    let isBestProfitRate: Bool
    let isLargestDailyMover: Bool
}

struct PersonalAssetComparisonSummary: Hashable {
    let headline: String
    let detail: String
    let maxCount: Int
    let items: [PersonalAssetComparisonItem]

    static func make(
        rows: [PersonalAssetAggregateRow],
        selectedIDs: [String],
        maxCount: Int = 4
    ) -> PersonalAssetComparisonSummary {
        let rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let selectedRows = selectedIDs
            .prefix(maxCount)
            .compactMap { rowsByID[$0] }

        let maxExposure = selectedRows.map(\.effectiveHoldingAmount).max()
        let maxProfitRate = selectedRows.compactMap(\.profitPct).max()
        let maxDailyMove = selectedRows
            .compactMap { row -> Double? in
                if let pct = row.estimateChangePct {
                    return abs(pct)
                }
                if let amount = row.estimateChangeAmount {
                    return abs(amount)
                }
                return nil
            }
            .max()

        let items = selectedRows.map { row in
            let dailyMoveValue = row.estimateChangePct.map(abs) ?? row.estimateChangeAmount.map(abs)
            return PersonalAssetComparisonItem(
                id: row.id,
                title: row.fundName,
                codeText: row.fundCode?.isEmpty == false ? row.fundCode! : "—",
                statusText: row.combinedStatusText,
                exposureValue: row.effectiveHoldingAmount,
                marketValueText: row.marketValue.map { currencyText($0, market: row.detectedMarket) } ?? "—",
                exposureText: currencyText(row.effectiveHoldingAmount, market: row.detectedMarket),
                profitValue: row.profitAmount,
                profitRateValue: row.profitPct,
                profitText: row.profitAmount.map { signedCurrencyText($0, market: row.detectedMarket) } ?? "—",
                profitRateText: percentOptional(row.profitPct),
                dailyChangeValue: row.estimateChangeAmount,
                dailyChangeRateValue: row.estimateChangePct,
                dailyChangeText: row.estimateChangeAmount.map { signedCurrencyText($0, market: row.detectedMarket) } ?? "—",
                dailyChangeRateText: percentOptional(row.estimateChangePct),
                pendingText: pendingText(for: row),
                planText: row.totalPlanCount > 0 ? "进行中 \(row.activePlanCount) / 共 \(row.totalPlanCount)" : "—",
                isLargestExposure: maxExposure.map { approximatelyEqual(row.effectiveHoldingAmount, $0) } ?? false,
                isBestProfitRate: row.profitPct.flatMap { profitRate in maxProfitRate.map { approximatelyEqual(profitRate, $0) } } ?? false,
                isLargestDailyMover: dailyMoveValue.flatMap { move in maxDailyMove.map { approximatelyEqual(move, $0) } } ?? false
            )
        }

        let headline: String
        switch items.count {
        case 0:
            headline = "选择标的开始对比"
        case 1:
            headline = "再选 1 只标的"
        default:
            headline = "正在对比 \(items.count) 只标的"
        }

        return PersonalAssetComparisonSummary(
            headline: headline,
            detail: items.count >= 2 ? "市值、收益、今日涨跌、待确认和计划档案" : "最多可同时对比 \(maxCount) 只标的",
            maxCount: maxCount,
            items: items
        )
    }

    private static func pendingText(for row: PersonalAssetAggregateRow) -> String {
        if row.pendingCashAmount > 0 {
            return currencyText(row.pendingCashAmount, market: row.detectedMarket)
        }
        if row.pendingUnitAmount > 0 {
            return "\(unitsText(row.pendingUnitAmount)) 份"
        }
        return "—"
    }

    private static func approximatelyEqual(_ left: Double, _ right: Double) -> Bool {
        abs(left - right) < 0.0001
    }
}
