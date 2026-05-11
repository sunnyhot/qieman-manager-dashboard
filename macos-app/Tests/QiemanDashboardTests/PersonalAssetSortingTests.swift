import XCTest
@testable import QiemanDashboard

final class PersonalAssetSortingTests: XCTestCase {
    func testDefaultSortOptionUsesDailyChange() {
        XCTAssertEqual(PersonalAssetSortOption.defaultOption, .dailyChange)
    }

    func testDailyChangeSortOrdersByEstimatedAmountDescending() {
        let rows = [
            row(name: "Beta", code: "000002", marketValue: 1_000, units: 100, estimatePrice: 10.10, estimateChangePct: 1.0),
            row(name: "No Quote", code: "000004", marketValue: 1_000, units: 100, estimatePrice: nil, estimateChangePct: nil),
            row(name: "Alpha", code: "000001", marketValue: 1_000, units: 100, estimatePrice: 12.00, estimateChangePct: 20.0),
            row(name: "Gamma", code: "000003", marketValue: 1_000, units: 100, estimatePrice: 9.80, estimateChangePct: -2.0)
        ]

        let sorted = PersonalAssetRowSorter.sorted(rows, by: .dailyChange)

        XCTAssertEqual(sorted.map(\.fundName), ["Alpha", "Beta", "Gamma", "No Quote"])
    }

    func testDailyChangePctSortOrdersByPercentDescending() {
        let rows = [
            row(name: "Two Percent", code: "000002", marketValue: 1_000, units: 100, estimatePrice: 10.20, estimateChangePct: 2.0),
            row(name: "Missing", code: "000004", marketValue: 1_000, units: 100, estimatePrice: 10.00, estimateChangePct: nil),
            row(name: "Five Percent", code: "000001", marketValue: 1_000, units: 100, estimatePrice: 10.50, estimateChangePct: 5.0),
            row(name: "Negative", code: "000003", marketValue: 1_000, units: 100, estimatePrice: 9.90, estimateChangePct: -1.0)
        ]

        let sorted = PersonalAssetRowSorter.sorted(rows, by: .dailyChangePct)

        XCTAssertEqual(sorted.map(\.fundName), ["Five Percent", "Two Percent", "Negative", "Missing"])
    }

    private func row(
        name: String,
        code: String,
        marketValue: Double,
        units: Double,
        estimatePrice: Double?,
        estimateChangePct: Double?
    ) -> PersonalAssetAggregateRow {
        let holding = UserPortfolioHolding(
            fundCode: code,
            assetType: .fund,
            units: units,
            costPrice: 1,
            displayName: name
        )
        let valuationRow = UserPortfolioValuationRow(
            holding: holding,
            fundName: name,
            currentPrice: nil,
            priceTime: nil,
            priceSource: nil,
            officialNav: nil,
            officialNavDate: nil,
            estimatePrice: estimatePrice,
            estimatePriceTime: nil,
            marketValue: marketValue,
            costValue: nil,
            profitAmount: nil,
            profitPct: nil,
            estimateChangePct: estimateChangePct
        )
        return PersonalAssetAggregateRow(
            key: code,
            assetType: .fund,
            fundName: name,
            fundCode: code,
            holdingRow: valuationRow,
            rawHolding: holding,
            archivedHolding: nil,
            pendingTrades: [],
            plans: []
        )
    }
}
