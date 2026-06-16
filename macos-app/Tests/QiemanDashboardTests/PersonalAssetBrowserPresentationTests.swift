import XCTest
@testable import QiemanDashboard

final class PersonalAssetBrowserPresentationTests: XCTestCase {
    func testPresentationBuildsCountsAndVisibleRowsFromScopeSearchAndSort() {
        let rows = [
            row(key: "wide", name: "沪深300", code: "000300", marketValue: 30_000, pendingAmount: 0),
            row(key: "dividend", name: "红利低波", code: "000922", marketValue: 10_000, pendingAmount: 500),
            row(key: "pending", name: "等待确认", code: "000001", marketValue: nil, pendingAmount: 800)
        ]

        let presentation = PersonalAssetBrowserPresentationModel.make(
            rows: rows,
            keyword: "000",
            filterScope: .pending,
            sortOption: .pendingAmount,
            comparisonSelection: ["pending", "wide"],
            comparisonMaxCount: 4
        )

        XCTAssertEqual(presentation.filterCounts[.all], 3)
        XCTAssertEqual(presentation.filterCounts[.holding], 2)
        XCTAssertEqual(presentation.filterCounts[.pending], 2)
        XCTAssertEqual(presentation.visibleRows.map(\.id), ["pending", "dividend"])
        XCTAssertEqual(presentation.comparisonSummary.items.map(\.id), ["pending", "wide"])
    }

    func testPresentationPrunesInvalidComparisonSelection() {
        let rows = [
            row(key: "wide", name: "沪深300", code: "000300", marketValue: 30_000, pendingAmount: 0)
        ]

        let presentation = PersonalAssetBrowserPresentationModel.make(
            rows: rows,
            keyword: "",
            filterScope: .all,
            sortOption: .name,
            comparisonSelection: ["missing", "wide"],
            comparisonMaxCount: 4
        )

        XCTAssertEqual(presentation.validComparisonSelection, ["wide"])
        XCTAssertEqual(presentation.comparisonSummary.items.map(\.id), ["wide"])
    }

    private func row(
        key: String,
        name: String,
        code: String,
        marketValue: Double?,
        pendingAmount: Double
    ) -> PersonalAssetAggregateRow {
        let holding = marketValue.map { _ in
            UserPortfolioHolding(fundCode: code, assetType: .fund, units: 10_000, costPrice: 1, displayName: name)
        }
        let valuationRow = holding.map {
            UserPortfolioValuationRow(
                holding: $0,
                fundName: name,
                currentPrice: nil,
                priceTime: nil,
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
