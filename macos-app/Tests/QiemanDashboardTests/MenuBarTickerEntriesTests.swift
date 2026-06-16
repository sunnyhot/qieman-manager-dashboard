import XCTest
@testable import QiemanDashboard

@MainActor
final class MenuBarTickerEntriesTests: XCTestCase {
    func testVisibleEntriesStopsBuildingAfterMaxVisibleItems() {
        let model = AppModel()
        model.menuBarTickerSettings = MenuBarTickerSettings(
            isEnabled: true,
            maxVisibleItems: 2,
            selections: [
                .kind(.sseIndexLevel),
                .kind(.csi300IndexLevel),
                .kind(.chinextIndexLevel)
            ]
        )
        model.marketIndexQuotes = [
            .sseComposite: quote(kind: .sseComposite, price: 3_000),
            .csi300: quote(kind: .csi300, price: 4_000),
            .chinext: quote(kind: .chinext, price: 2_000)
        ]
        var events: [PerformanceTelemetryEvent] = []

        let entries = PerformanceTelemetry.withSink({ events.append($0) }) {
            model.menuBarTickerVisibleEntries
        }

        XCTAssertEqual(entries.map(\.id), ["sseIndexLevel", "csi300IndexLevel"])
        let buildEvent = events.last { $0.name == "menuBar.entries.build" }
        XCTAssertEqual(buildEvent?.metadata["selectionCount"], "3")
        XCTAssertEqual(buildEvent?.metadata["entryCount"], "2")
        XCTAssertEqual(buildEvent?.metadata["aggregateBuilt"], "false")
    }

    func testAggregateSelectionsBuildAggregatesOnDemand() {
        let model = AppModel()
        model.menuBarTickerSettings = MenuBarTickerSettings(
            isEnabled: true,
            maxVisibleItems: 2,
            selections: [.kind(.overallDailyPct)]
        )
        model.userPortfolioSnapshot = UserPortfolioSnapshot(
            rows: [valuationRow(marketValue: 110, estimateChangePct: 10)],
            refreshedAt: "2026-06-16 15:00",
            totalMarketValue: 110,
            totalCostValue: nil,
            totalProfitAmount: nil,
            totalProfitPct: nil
        )
        var events: [PerformanceTelemetryEvent] = []

        let entries = PerformanceTelemetry.withSink({ events.append($0) }) {
            model.menuBarTickerVisibleEntries
        }

        XCTAssertEqual(entries.map(\.id), ["overallDailyPct"])
        let buildEvent = events.last { $0.name == "menuBar.entries.build" }
        XCTAssertEqual(buildEvent?.metadata["entryCount"], "1")
        XCTAssertEqual(buildEvent?.metadata["aggregateBuilt"], "true")
    }

    private func quote(kind: MarketIndexKind, price: Double) -> MarketIndexQuote {
        MarketIndexQuote(
            kind: kind,
            name: kind.label,
            price: price,
            previousClose: price,
            changeAmount: 0,
            changePct: 0,
            quotedAt: "2026-06-16 15:00",
            sourceLabel: "测试"
        )
    }

    private func valuationRow(marketValue: Double, estimateChangePct: Double) -> UserPortfolioValuationRow {
        let holding = UserPortfolioHolding(
            fundCode: "000001",
            assetType: .fund,
            units: 100,
            costPrice: 1,
            displayName: "测试基金"
        )
        return UserPortfolioValuationRow(
            holding: holding,
            fundName: "测试基金",
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
            estimateChangePct: estimateChangePct
        )
    }
}
