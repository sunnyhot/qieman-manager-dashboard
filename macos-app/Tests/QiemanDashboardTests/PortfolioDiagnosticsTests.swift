import XCTest
@testable import QiemanDashboard

final class PortfolioDiagnosticsTests: XCTestCase {
    func testMakeSummaryElevatesConcentrationAndPendingExposure() {
        let rows = [
            row(name: "核心宽基", code: "000001", marketValue: 60_000, pendingAmount: 0, activePlans: 1, dailyChangeAmount: 600),
            row(name: "行业主题", code: "000002", marketValue: 15_000, pendingAmount: 25_000, activePlans: 0, dailyChangeAmount: -300),
            row(name: "债券底仓", code: "000003", marketValue: 0, pendingAmount: 0, activePlans: 0, dailyChangeAmount: nil)
        ]

        let summary = PortfolioDiagnosticsSummary.make(rows: rows)

        XCTAssertEqual(summary.headline, "2 项风险待处理")
        XCTAssertEqual(summary.items.prefix(2).map(\.kind), [.concentration, .pendingExposure])
        XCTAssertEqual(summary.items.first?.metric, "60.0%")
        XCTAssertEqual(summary.items.first?.level, .risk)
    }

    func testMakeSummaryReportsHealthyDiversifiedPortfolio() {
        let rows = [
            row(name: "宽基 A", code: "000001", marketValue: 20_000, pendingAmount: 0, activePlans: 1, dailyChangeAmount: 120),
            row(name: "宽基 B", code: "000002", marketValue: 20_000, pendingAmount: 0, activePlans: 1, dailyChangeAmount: -90),
            row(name: "债券 C", code: "000003", marketValue: 20_000, pendingAmount: 0, activePlans: 0, dailyChangeAmount: 10),
            row(name: "现金替代 D", code: "000004", marketValue: 20_000, pendingAmount: 0, activePlans: 0, dailyChangeAmount: nil)
        ]

        let summary = PortfolioDiagnosticsSummary.make(rows: rows)

        XCTAssertEqual(summary.headline, "组合结构较均衡")
        XCTAssertEqual(summary.items.first?.kind, .concentration)
        XCTAssertEqual(summary.items.first?.level, .good)
    }

    private func row(
        name: String,
        code: String,
        marketValue: Double,
        pendingAmount: Double,
        activePlans: Int,
        dailyChangeAmount: Double?
    ) -> PersonalAssetAggregateRow {
        let holding = marketValue > 0
            ? UserPortfolioHolding(fundCode: code, assetType: .fund, units: 10_000, costPrice: 1, displayName: name)
            : nil
        let valuationRow = holding.map {
            UserPortfolioValuationRow(
                holding: $0,
                fundName: name,
                currentPrice: nil,
                priceTime: "2026-06-05 15:00",
                priceSource: nil,
                officialNav: nil,
                officialNavDate: nil,
                estimatePrice: nil,
                estimatePriceTime: nil,
                marketValue: marketValue,
                costValue: nil,
                profitAmount: nil,
                profitPct: nil,
                estimateChangePct: dailyChangeAmount.map { $0 / max(marketValue, 1) * 100 }
            )
        }
        let pendingTrades = pendingAmount > 0
            ? [
                PersonalPendingTrade(
                    occurredAt: "2026-06-05",
                    actionLabel: "买入",
                    fundName: name,
                    fundCode: code,
                    amountText: "\(pendingAmount)",
                    amountValue: pendingAmount,
                    status: "待确认"
                )
            ]
            : []
        let plans = (0..<activePlans).map { index in
            PersonalInvestmentPlan(
                planTypeLabel: "定投",
                fundName: name,
                fundCode: code,
                scheduleText: "每周三",
                amountText: "100.00",
                nextExecutionDate: "2026-06-\(10 + index)",
                status: "进行中"
            )
        }
        return PersonalAssetAggregateRow(
            key: code,
            assetType: .fund,
            fundName: name,
            fundCode: code,
            holdingRow: valuationRow,
            rawHolding: holding,
            archivedHolding: nil,
            pendingTrades: pendingTrades,
            plans: plans
        )
    }
}
