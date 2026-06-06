import XCTest
@testable import QiemanDashboard

final class PersonalAssetComparisonTests: XCTestCase {
    func testMakeSummaryPreservesSelectionOrderAndFlagsHighlights() {
        let rows = [
            row(key: "wide", name: "核心宽基", code: "000001", marketValue: 12_000, profitAmount: 1_200, profitPct: 12, dailyChangePct: 0.2),
            row(key: "dividend", name: "红利策略", code: "000002", marketValue: 24_000, profitAmount: 900, profitPct: 4, dailyChangePct: -1.8, pendingAmount: 500),
            row(key: "bond", name: "债券底仓", code: "000003", marketValue: 8_000, profitAmount: 80, profitPct: 1, dailyChangePct: 0.05)
        ]

        let summary = PersonalAssetComparisonSummary.make(
            rows: rows,
            selectedIDs: ["dividend", "wide", "missing"]
        )

        XCTAssertEqual(summary.headline, "正在对比 2 只标的")
        XCTAssertEqual(summary.items.map(\.id), ["dividend", "wide"])
        XCTAssertTrue(summary.items[0].isLargestExposure)
        XCTAssertTrue(summary.items[1].isBestProfitRate)
        XCTAssertTrue(summary.items[0].isLargestDailyMover)
        XCTAssertEqual(summary.items[0].pendingText, "¥500.00")
    }

    func testMakeSummaryCapsSelectionAndPromptsForSecondAsset() {
        let rows = (0..<5).map { index in
            row(
                key: "fund-\(index)",
                name: "基金 \(index)",
                code: "00000\(index)",
                marketValue: Double(index + 1) * 1_000,
                profitAmount: nil,
                profitPct: nil,
                dailyChangePct: nil
            )
        }

        let summary = PersonalAssetComparisonSummary.make(
            rows: rows,
            selectedIDs: ["fund-0", "fund-1", "fund-2", "fund-3", "fund-4"],
            maxCount: 4
        )

        XCTAssertEqual(summary.items.count, 4)
        XCTAssertEqual(summary.items.map(\.id), ["fund-0", "fund-1", "fund-2", "fund-3"])

        let single = PersonalAssetComparisonSummary.make(rows: rows, selectedIDs: ["fund-0"])
        XCTAssertEqual(single.headline, "再选 1 只标的")
        XCTAssertEqual(single.items.first?.profitText, "—")
    }

    private func row(
        key: String,
        name: String,
        code: String,
        marketValue: Double?,
        profitAmount: Double?,
        profitPct: Double?,
        dailyChangePct: Double?,
        pendingAmount: Double = 0
    ) -> PersonalAssetAggregateRow {
        let holding = UserPortfolioHolding(fundCode: code, assetType: .fund, units: 10_000, costPrice: 1, displayName: name)
        let valuationRow = marketValue.map {
            UserPortfolioValuationRow(
                holding: holding,
                fundName: name,
                currentPrice: nil,
                priceTime: "2026-06-05 15:00",
                priceSource: nil,
                officialNav: nil,
                officialNavDate: nil,
                estimatePrice: nil,
                estimatePriceTime: nil,
                marketValue: $0,
                costValue: nil,
                profitAmount: profitAmount,
                profitPct: profitPct,
                estimateChangePct: dailyChangePct
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
