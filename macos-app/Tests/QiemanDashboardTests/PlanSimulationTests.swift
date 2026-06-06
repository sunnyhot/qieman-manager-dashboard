import XCTest
@testable import QiemanDashboard

final class PlanSimulationTests: XCTestCase {
    func testMakeSummaryProjectsFutureExecutionsFromActivePlans() {
        let rows = [
            row(name: "核心宽基", code: "000001", marketValue: 20_000, activePlanAmounts: [100, 200]),
            row(name: "红利策略", code: "000002", marketValue: 10_000, activePlanAmounts: [300]),
            row(name: "债券底仓", code: "000003", marketValue: 15_000, activePlanAmounts: [])
        ]

        let summary = PlanSimulationSummary.make(rows: rows, executionCount: 12)

        XCTAssertEqual(summary.headline, "未来 12 次计划约投入 ¥7,200.00")
        XCTAssertEqual(summary.totalPerExecutionText, "¥600.00")
        XCTAssertEqual(summary.projectedAmountText, "¥7,200.00")
        XCTAssertEqual(summary.activePlanCount, 3)
        XCTAssertEqual(summary.items.map(\.id), ["000001", "000002"])
        XCTAssertEqual(summary.items.first?.perExecutionText, "¥300.00")
        XCTAssertEqual(summary.items.first?.projectedAmountText, "¥3,600.00")
    }

    func testMakeSummaryReportsEmptyStateWhenNoActivePlanExists() {
        let summary = PlanSimulationSummary.make(
            rows: [
                row(name: "核心宽基", code: "000001", marketValue: 20_000, activePlanAmounts: [])
            ],
            executionCount: 12
        )

        XCTAssertEqual(summary.headline, "暂无进行中计划")
        XCTAssertEqual(summary.totalPerExecutionText, "—")
        XCTAssertTrue(summary.items.isEmpty)
    }

    private func row(
        name: String,
        code: String,
        marketValue: Double,
        activePlanAmounts: [Double]
    ) -> PersonalAssetAggregateRow {
        let holding = UserPortfolioHolding(fundCode: code, assetType: .fund, units: 10_000, costPrice: 1, displayName: name)
        let valuationRow = UserPortfolioValuationRow(
            holding: holding,
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
            estimateChangePct: nil
        )
        let plans = activePlanAmounts.enumerated().map { index, amount in
            PersonalInvestmentPlan(
                planTypeLabel: "定投",
                fundName: name,
                fundCode: code,
                scheduleText: "每周三",
                amountText: String(format: "%.2f", amount),
                nextExecutionDate: "2026-06-\(12 + index)",
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
            pendingTrades: [],
            plans: plans
        )
    }
}
