import Foundation

enum ProfitAttributionKind: Hashable {
    case gain
    case drag
    case neutral
}

struct ProfitAttributionEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let codeText: String
    let amountValue: Double
    let rateValue: Double?
    let amountText: String
    let rateText: String
    let impactShareText: String
    let marketValueText: String
    let kind: ProfitAttributionKind
}

struct ProfitAttributionSummary: Hashable {
    let headline: String
    let totalProfitValue: Double?
    let totalProfitText: String
    let totalProfitRateText: String
    let coverageText: String
    let pendingExposureText: String
    let plannedExposureText: String
    let entries: [ProfitAttributionEntry]

    static func make(rows: [PersonalAssetAggregateRow]) -> ProfitAttributionSummary {
        let holdingRows = rows.filter(\.hasHolding)
        let rowsWithProfit = rows.filter { $0.profitAmount != nil }
        let totalProfit = rowsWithProfit.reduce(0) { $0 + ($1.profitAmount ?? 0) }
        let totalCost = rowsWithProfit.reduce(0) { partial, row in
            partial + (row.holdingRow?.costValue ?? inferredCostValue(row) ?? 0)
        }
        let totalAbsImpact = rowsWithProfit.reduce(0) { $0 + abs($1.profitAmount ?? 0) }
        let pendingExposure = rows.reduce(0) { $0 + $1.pendingCashAmount }
        let plannedExposure = rows.reduce(0) { $0 + $1.estimatedNextPlanAmount }

        let rawEntries = rowsWithProfit.map { row in
            let amount = row.profitAmount ?? 0
            let kind: ProfitAttributionKind
            if amount > 0 {
                kind = .gain
            } else if amount < 0 {
                kind = .drag
            } else {
                kind = .neutral
            }
            let impactShare = totalAbsImpact > 0 ? abs(amount) / totalAbsImpact * 100 : 0
            return ProfitAttributionEntry(
                id: row.id,
                title: row.fundName,
                codeText: row.fundCode?.isEmpty == false ? row.fundCode! : "—",
                amountValue: amount,
                rateValue: row.profitPct,
                amountText: signedCurrencyText(amount, market: row.detectedMarket),
                rateText: percentOptional(row.profitPct),
                impactShareText: percentText(impactShare),
                marketValueText: row.marketValue.map { currencyText($0, market: row.detectedMarket) } ?? "—",
                kind: kind
            )
        }

        let entries = sortedEntries(rawEntries, totalProfit: totalProfit)
        let headline = headline(entries: entries, rowCount: rowsWithProfit.count, totalProfit: totalProfit)
        let totalProfitRate = totalCost > 0 ? totalProfit / totalCost * 100 : nil

        return ProfitAttributionSummary(
            headline: headline,
            totalProfitValue: rowsWithProfit.isEmpty ? nil : totalProfit,
            totalProfitText: rowsWithProfit.isEmpty ? "—" : signedCurrencyText(totalProfit),
            totalProfitRateText: percentOptional(totalProfitRate),
            coverageText: "\(rowsWithProfit.count) / \(holdingRows.count) 个已持有标的有收益数据",
            pendingExposureText: currencyText(pendingExposure),
            plannedExposureText: currencyText(plannedExposure),
            entries: entries
        )
    }

    private static func sortedEntries(_ entries: [ProfitAttributionEntry], totalProfit: Double) -> [ProfitAttributionEntry] {
        entries.sorted { left, right in
            let leftRank = rank(left.kind, totalProfit: totalProfit)
            let rightRank = rank(right.kind, totalProfit: totalProfit)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            if abs(left.amountValue - right.amountValue) > 0.0001 {
                switch left.kind {
                case .drag:
                    return left.amountValue < right.amountValue
                case .gain, .neutral:
                    return left.amountValue > right.amountValue
                }
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
    }

    private static func rank(_ kind: ProfitAttributionKind, totalProfit: Double) -> Int {
        if totalProfit < 0 {
            switch kind {
            case .drag: return 0
            case .gain: return 1
            case .neutral: return 2
            }
        }
        switch kind {
        case .gain: return 0
        case .drag: return 1
        case .neutral: return 2
        }
    }

    private static func headline(entries: [ProfitAttributionEntry], rowCount: Int, totalProfit: Double) -> String {
        guard rowCount > 0 else { return "等待收益数据" }
        if totalProfit > 0, let topGain = entries.first(where: { $0.kind == .gain }) {
            return "收益主要由 \(topGain.title) 贡献"
        }
        if totalProfit < 0, let topDrag = entries.first(where: { $0.kind == .drag }) {
            return "回撤主要来自 \(topDrag.title)"
        }
        return "收益基本持平"
    }

    private static func inferredCostValue(_ row: PersonalAssetAggregateRow) -> Double? {
        guard let marketValue = row.marketValue, let profitAmount = row.profitAmount else {
            return nil
        }
        return marketValue - profitAmount
    }

    private static func percentText(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}

extension AppModel {
    var profitAttributionSummary: ProfitAttributionSummary {
        ProfitAttributionSummary.make(rows: personalAssetRows)
    }
}
