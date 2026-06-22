import XCTest
@testable import QiemanDashboard

final class TrendAnalysisContextBuilderTests: XCTestCase {
    func testSanitizedContextExcludesRealAmounts() {
        let rows = [
            aggregateRow(
                code: "510300",
                name: "沪深300ETF",
                marketValue: 120_000,
                costValue: 100_000,
                profitAmount: 20_000,
                profitPct: 20,
                estimateChangePct: 1.2
            ),
            aggregateRow(
                code: "513100",
                name: "纳指ETF",
                marketValue: 80_000,
                costValue: 90_000,
                profitAmount: -10_000,
                profitPct: -11.1,
                estimateChangePct: -0.8
            )
        ]

        let context = TrendAnalysisContextBuilder().build(
            rows: rows,
            summary: PersonalAssetAggregateSummary(
                fundCount: 2,
                holdingFundCount: 2,
                pendingFundCount: 0,
                activePlanFundCount: 0,
                totalMarketValue: 200_000,
                totalPendingCashAmount: 0,
                totalActivePlanCount: 0,
                totalPausedPlanCount: 0,
                totalEndedPlanCount: 0,
                totalCumulativePlanAmount: 0,
                totalEstimatedNextPlanAmount: 0,
                totalEffectiveHoldingAmount: 200_000
            ),
            platformActions: [],
            watchSummary: ManagerWatchTimelineSummary.make(events: []),
            insightSummary: PortfolioSnapshotInsightSummary(headline: "已记录快照", hasEnoughHistory: true, cards: []),
            privacyMode: .sanitized,
            createdAt: "2026-06-22 11:00:00"
        )

        let encoded = context.debugJSONString()
        XCTAssertFalse(encoded.contains("120000"))
        XCTAssertFalse(encoded.contains("100000"))
        XCTAssertFalse(encoded.contains("20000"))
        XCTAssertTrue(encoded.contains("60.00%"))
        XCTAssertTrue(encoded.contains("510300"))
    }

    func testFullDetailContextIncludesRealAmountsAfterSelection() {
        let row = aggregateRow(
            code: "510300",
            name: "沪深300ETF",
            marketValue: 120_000,
            costValue: 100_000,
            profitAmount: 20_000,
            profitPct: 20,
            estimateChangePct: 1.2
        )

        let context = TrendAnalysisContextBuilder().build(
            rows: [row],
            summary: nil,
            platformActions: [],
            watchSummary: ManagerWatchTimelineSummary.make(events: []),
            insightSummary: PortfolioSnapshotInsightSummary(headline: "等待组合快照", hasEnoughHistory: false, cards: []),
            privacyMode: .fullDetail,
            createdAt: "2026-06-22 11:00:00"
        )

        let encoded = context.debugJSONString()
        XCTAssertTrue(encoded.contains("120000"))
        XCTAssertTrue(encoded.contains("100000"))
        XCTAssertTrue(encoded.contains("20000"))
    }

    func testSectorGroupingUsesAssetTypeAndMarketHints() {
        let rows = [
            aggregateRow(
                code: "510300",
                name: "沪深300ETF",
                marketValue: 120_000,
                costValue: 100_000,
                profitAmount: 20_000,
                profitPct: 20,
                estimateChangePct: 1.2
            ),
            aggregateRow(
                code: "AAPL",
                name: "Apple",
                assetType: .stock,
                stockMarket: .us,
                fundMarket: nil,
                marketValue: 50_000,
                costValue: 40_000,
                profitAmount: 10_000,
                profitPct: 25,
                estimateChangePct: 0.4
            )
        ]

        let context = TrendAnalysisContextBuilder().build(
            rows: rows,
            summary: nil,
            platformActions: [],
            watchSummary: ManagerWatchTimelineSummary.make(events: []),
            insightSummary: PortfolioSnapshotInsightSummary(headline: "等待组合快照", hasEnoughHistory: false, cards: []),
            privacyMode: .sanitized,
            createdAt: "2026-06-22 11:00:00"
        )

        XCTAssertTrue(context.sectors.contains { $0.name == "场内基金" })
        XCTAssertTrue(context.sectors.contains { $0.name == "美股" })
    }
}

private func aggregateRow(
    code: String,
    name: String,
    assetType: PersonalAssetType = .fund,
    stockMarket: StockMarket? = nil,
    fundMarket: FundMarket? = .onExchange,
    marketValue: Double,
    costValue: Double,
    profitAmount: Double,
    profitPct: Double,
    estimateChangePct: Double
) -> PersonalAssetAggregateRow {
    let units = 100.0
    let holding = UserPortfolioHolding(
        fundCode: code,
        assetType: assetType,
        units: units,
        costPrice: costValue / units,
        displayName: name,
        stockMarket: stockMarket,
        fundMarket: assetType == .fund ? fundMarket : nil
    )
    let valuation = UserPortfolioValuationRow(
        holding: holding,
        fundName: name,
        currentPrice: marketValue / units,
        priceTime: "2026-06-22 10:00:00",
        priceSource: "测试估值",
        officialNav: nil,
        officialNavDate: nil,
        estimatePrice: marketValue / units,
        estimatePriceTime: "2026-06-22 10:00:00",
        marketValue: marketValue,
        costValue: costValue,
        profitAmount: profitAmount,
        profitPct: profitPct,
        estimateChangePct: estimateChangePct
    )
    return PersonalAssetAggregateRow(
        key: "\(assetType.rawValue)-\(code)",
        assetType: assetType,
        fundName: name,
        fundCode: code,
        holdingRow: valuation,
        rawHolding: holding,
        archivedHolding: nil,
        pendingTrades: [],
        plans: []
    )
}
