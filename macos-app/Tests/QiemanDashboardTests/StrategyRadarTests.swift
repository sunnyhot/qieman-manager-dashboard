import XCTest
@testable import QiemanDashboard

final class StrategyRadarTests: XCTestCase {
    func testMakeSummaryClassifiesAggressiveBuyTiltAndDiversity() {
        let actions = [
            action(id: "a1", side: "buy", strategyType: "网格", valuationChangePct: 1.2),
            action(id: "a2", side: "buy", strategyType: "定投", valuationChangePct: 0.4),
            action(id: "a3", side: "buy", strategyType: "网格", valuationChangePct: -0.3),
            action(id: "a4", side: "sell", strategyType: "网格", valuationChangePct: 2.0)
        ]
        let holdings = [
            holding(id: "h1", strategyType: "网格"),
            holding(id: "h2", strategyType: "定投"),
            holding(id: "h3", strategyType: nil)
        ]

        let summary = StrategyRadarSummary.make(actions: actions, holdings: holdings)

        XCTAssertEqual(summary.headline, "策略偏进攻")
        XCTAssertEqual(summary.buyCount, 3)
        XCTAssertEqual(summary.sellCount, 1)
        XCTAssertEqual(summary.strategyTypeCount, 2)
        XCTAssertEqual(summary.holdingCount, 3)
        XCTAssertEqual(summary.item(for: .balance)?.metric, "买 3 / 卖 1")
        XCTAssertEqual(summary.item(for: .diversity)?.metric, "2 类")
    }

    func testMakeSummaryReportsEmptyState() {
        let summary = StrategyRadarSummary.make(actions: [], holdings: [])

        XCTAssertEqual(summary.headline, "等待平台数据")
        XCTAssertEqual(summary.items.count, 5)
        XCTAssertEqual(summary.item(for: .activity)?.score, 0)
    }

    private func action(
        id: String,
        side: String,
        strategyType: String?,
        valuationChangePct: Double?
    ) -> PlatformActionPayload {
        PlatformActionPayload(
            actionKey: id,
            adjustmentId: nil,
            adjustmentTitle: nil,
            title: nil,
            actionTitle: side == "buy" ? "买入" : "卖出",
            fundName: "测试基金",
            fundCode: id,
            side: side,
            action: nil,
            tradeUnit: nil,
            postPlanUnit: nil,
            createdAt: "2026-06-05 10:00",
            txnDate: "2026-06-05",
            createdTs: nil,
            txnTs: nil,
            articleUrl: nil,
            comment: nil,
            strategyType: strategyType,
            largeClass: nil,
            buyDate: nil,
            nav: nil,
            navDate: nil,
            orderCountInAdjustment: nil,
            tradeValuation: nil,
            tradeValuationDate: nil,
            tradeValuationSource: nil,
            currentValuation: nil,
            currentValuationTime: nil,
            currentValuationSource: nil,
            valuationChangeAmount: nil,
            valuationChangePct: valuationChangePct
        )
    }

    private func holding(id: String, strategyType: String?) -> HoldingItemPayload {
        HoldingItemPayload(
            assetKey: id,
            label: "测试持仓",
            fundName: "测试基金",
            fundCode: id,
            currentUnits: 1,
            latestAction: nil,
            latestActionTitle: nil,
            latestTime: nil,
            latestTs: nil,
            strategyType: strategyType,
            largeClass: nil,
            buyDate: nil,
            avgCost: nil,
            positionCost: nil,
            currentPrice: nil,
            priceSource: nil,
            priceSourceLabel: nil,
            priceTime: nil,
            officialNav: nil,
            officialNavDate: nil,
            estimateChangePct: nil,
            positionValue: nil,
            profitRatio: nil,
            costMethod: nil,
            costCoveredActions: nil,
            costMissingActions: nil,
            costReady: nil,
            quoteReady: nil,
            estimatedValue: nil,
            profitAmount: nil,
            profitPct: nil
        )
    }
}
