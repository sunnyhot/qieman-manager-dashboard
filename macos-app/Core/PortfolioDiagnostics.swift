import Foundation

enum PortfolioDiagnosticKind: Hashable {
    case concentration
    case pendingExposure
    case planCoverage
    case dailyMovement
    case quoteCoverage
}

enum PortfolioDiagnosticLevel: Int, Hashable {
    case risk = 0
    case watch = 1
    case info = 2
    case good = 3
}

struct PortfolioDiagnosticItem: Identifiable, Hashable {
    let kind: PortfolioDiagnosticKind
    let title: String
    let detail: String
    let metric: String
    let level: PortfolioDiagnosticLevel
    let priority: Int

    var id: PortfolioDiagnosticKind { kind }
}

struct PortfolioDiagnosticsSummary: Hashable {
    let headline: String
    let items: [PortfolioDiagnosticItem]

    static func make(rows: [PersonalAssetAggregateRow]) -> PortfolioDiagnosticsSummary {
        let totalExposure = rows.reduce(0) { $0 + $1.effectiveHoldingAmount }
        guard totalExposure > 0 else {
            return PortfolioDiagnosticsSummary(
                headline: "等待资产数据",
                items: [
                    PortfolioDiagnosticItem(
                        kind: .quoteCoverage,
                        title: "资产数据",
                        detail: "添加持仓、买入中或计划后生成组合诊断",
                        metric: "待录入",
                        level: .info,
                        priority: 10
                    )
                ]
            )
        }

        let holdingRows = rows.filter { $0.effectiveHoldingAmount > 0 }
        let topRow = holdingRows.max { $0.effectiveHoldingAmount < $1.effectiveHoldingAmount }
        let topShare = topRow.map { $0.effectiveHoldingAmount / totalExposure * 100 } ?? 0
        let pendingAmount = rows.reduce(0) { $0 + $1.pendingCashAmount }
        let pendingShare = pendingAmount / totalExposure * 100
        let holdingCount = max(rows.filter(\.hasHolding).count, 1)
        let planCoverage = Double(rows.filter { $0.activePlanCount > 0 }.count) / Double(holdingCount) * 100
        let dailyChangeAmount = rows.reduce(0) { $0 + ($1.estimateChangeAmount ?? 0) }
        let marketValue = rows.reduce(0) { $0 + ($1.marketValue ?? 0) }
        let dailyChangePct = marketValue > 0 ? dailyChangeAmount / marketValue * 100 : nil
        let quoteEligibleRows = rows.filter { $0.hasHolding }
        let quotedRows = quoteEligibleRows.filter { $0.marketValue != nil }
        let quoteCoverage = quoteEligibleRows.isEmpty ? 100 : Double(quotedRows.count) / Double(quoteEligibleRows.count) * 100

        let items = [
            concentrationItem(topRow: topRow, topShare: topShare),
            pendingExposureItem(pendingAmount: pendingAmount, pendingShare: pendingShare),
            planCoverageItem(planCoverage: planCoverage, activePlanRows: rows.filter { $0.activePlanCount > 0 }.count, holdingCount: holdingCount),
            dailyMovementItem(amount: dailyChangeAmount, pct: dailyChangePct),
            quoteCoverageItem(coverage: quoteCoverage, quotedCount: quotedRows.count, totalCount: quoteEligibleRows.count)
        ]
        .sorted { left, right in
            if left.level != right.level {
                return left.level.rawValue < right.level.rawValue
            }
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }

        let riskCount = items.filter { $0.level == .risk }.count
        let watchCount = items.filter { $0.level == .watch }.count
        let headline: String
        if riskCount > 0 {
            headline = "\(riskCount) 项风险待处理"
        } else if watchCount > 0 {
            headline = "\(watchCount) 项需要留意"
        } else {
            headline = "组合结构较均衡"
        }

        return PortfolioDiagnosticsSummary(
            headline: headline,
            items: items
        )
    }

    private static func concentrationItem(topRow: PersonalAssetAggregateRow?, topShare: Double) -> PortfolioDiagnosticItem {
        let level: PortfolioDiagnosticLevel
        let title: String
        if topShare >= 50 {
            level = .risk
            title = "单一标的过重"
        } else if topShare >= 30 {
            level = .watch
            title = "集中度偏高"
        } else {
            level = .good
            title = "集中度可控"
        }
        let name = topRow?.fundName ?? "暂无标的"
        return PortfolioDiagnosticItem(
            kind: .concentration,
            title: title,
            detail: "第一大标的 \(name)",
            metric: percentText(topShare),
            level: level,
            priority: 10
        )
    }

    private static func pendingExposureItem(pendingAmount: Double, pendingShare: Double) -> PortfolioDiagnosticItem {
        let level: PortfolioDiagnosticLevel
        let title: String
        if pendingShare >= 20 {
            level = .risk
            title = "待确认占比过高"
        } else if pendingShare >= 10 {
            level = .watch
            title = "待确认占比较高"
        } else if pendingShare > 0 {
            level = .info
            title = "存在待确认交易"
        } else {
            level = .good
            title = "无待确认压力"
        }
        return PortfolioDiagnosticItem(
            kind: .pendingExposure,
            title: title,
            detail: pendingAmount > 0 ? "待确认金额 \(currencyText(pendingAmount))" : "没有买入中交易",
            metric: percentText(pendingShare),
            level: level,
            priority: 20
        )
    }

    private static func planCoverageItem(planCoverage: Double, activePlanRows: Int, holdingCount: Int) -> PortfolioDiagnosticItem {
        let level: PortfolioDiagnosticLevel
        let title: String
        if activePlanRows == 0 {
            level = .watch
            title = "缺少进行中计划"
        } else if planCoverage < 30 {
            level = .info
            title = "计划覆盖较低"
        } else {
            level = .good
            title = "计划覆盖正常"
        }
        return PortfolioDiagnosticItem(
            kind: .planCoverage,
            title: title,
            detail: "\(activePlanRows) / \(holdingCount) 个已持有标的有进行中计划",
            metric: percentText(planCoverage),
            level: level,
            priority: 30
        )
    }

    private static func dailyMovementItem(amount: Double, pct: Double?) -> PortfolioDiagnosticItem {
        let absolutePct = abs(pct ?? 0)
        let level: PortfolioDiagnosticLevel
        let title: String
        if absolutePct >= 2.5 {
            level = .watch
            title = "今日波动较大"
        } else if pct != nil {
            level = .good
            title = "今日波动可控"
        } else {
            level = .info
            title = "今日波动待估"
        }
        return PortfolioDiagnosticItem(
            kind: .dailyMovement,
            title: title,
            detail: "组合今日涨跌 \(signedCurrencyText(amount))",
            metric: pct.map(percentText) ?? "—",
            level: level,
            priority: 40
        )
    }

    private static func quoteCoverageItem(coverage: Double, quotedCount: Int, totalCount: Int) -> PortfolioDiagnosticItem {
        let level: PortfolioDiagnosticLevel
        let title: String
        if totalCount == 0 {
            level = .info
            title = "暂无估值标的"
        } else if coverage < 80 {
            level = .watch
            title = "估值覆盖不足"
        } else {
            level = .good
            title = "估值覆盖正常"
        }
        return PortfolioDiagnosticItem(
            kind: .quoteCoverage,
            title: title,
            detail: "\(quotedCount) / \(totalCount) 个已持有标的有估值",
            metric: percentText(coverage),
            level: level,
            priority: 50
        )
    }

    private static func percentText(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}

extension AppModel {
    var portfolioDiagnosticsSummary: PortfolioDiagnosticsSummary {
        PortfolioDiagnosticsSummary.make(rows: personalAssetRows)
    }
}
