import XCTest
@testable import QiemanDashboard

final class ProfitAttributionTests: XCTestCase {
    func testMakeSummaryRanksGainAndDragByAbsoluteImpact() {
        let rows = [
            row(key: "wide", name: "核心宽基", code: "000001", marketValue: 12_000, costValue: 10_800, profitAmount: 1_200, profitPct: 11.11),
            row(key: "theme", name: "行业主题", code: "000002", marketValue: 7_000, costValue: 7_300, profitAmount: -300, profitPct: -4.11),
            row(key: "bond", name: "债券底仓", code: "000003", marketValue: 5_000, costValue: 5_000, profitAmount: 0, profitPct: 0, pendingAmount: 500)
        ]

        let summary = ProfitAttributionSummary.make(rows: rows)

        XCTAssertEqual(summary.headline, "收益主要由 核心宽基 贡献")
        XCTAssertEqual(summary.totalProfitText, "¥+900.00")
        XCTAssertEqual(summary.entries.map(\.id), ["wide", "theme", "bond"])
        XCTAssertEqual(summary.entries[0].impactShareText, "80.0%")
        XCTAssertEqual(summary.entries[1].kind, .drag)
        XCTAssertEqual(summary.pendingExposureText, "¥500.00")
    }

    func testMakeSummaryElevatesLargestDragWhenTotalProfitIsNegative() {
        let rows = [
            row(key: "wide", name: "核心宽基", code: "000001", marketValue: 12_000, costValue: 11_900, profitAmount: 100, profitPct: 0.84),
            row(key: "theme", name: "行业主题", code: "000002", marketValue: 7_000, costValue: 7_500, profitAmount: -500, profitPct: -6.67)
        ]

        let summary = ProfitAttributionSummary.make(rows: rows)

        XCTAssertEqual(summary.headline, "回撤主要来自 行业主题")
        XCTAssertEqual(summary.totalProfitText, "¥-400.00")
        XCTAssertEqual(summary.entries.first?.id, "theme")
        XCTAssertEqual(summary.totalProfitRateText, "-2.06%")
    }

    private func row(
        key: String,
        name: String,
        code: String,
        marketValue: Double,
        costValue: Double,
        profitAmount: Double?,
        profitPct: Double?,
        pendingAmount: Double = 0
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
            costValue: costValue,
            profitAmount: profitAmount,
            profitPct: profitPct,
            estimateChangePct: nil
        )
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
        return PersonalAssetAggregateRow(
            key: key,
            assetType: .fund,
            fundName: name,
            fundCode: code,
            holdingRow: valuationRow,
            rawHolding: holding,
            archivedHolding: nil,
            pendingTrades: pendingTrades,
            plans: []
        )
    }
}
