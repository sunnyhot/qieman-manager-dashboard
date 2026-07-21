import Foundation
import XCTest
@testable import QiemanDashboard

final class PersonalWatchlistTests: XCTestCase {
    func testCategoriesPreserveOffExchangeOnExchangeAndStock() {
        XCTAssertEqual(item(code: "021550", assetType: .fund, fundMarket: .offExchange).category, .offExchangeFund)
        XCTAssertEqual(item(code: "510300", assetType: .fund, fundMarket: .onExchange).category, .onExchangeFund)
        XCTAssertEqual(item(code: "600519", assetType: .stock, stockMarket: .aShare).category, .stock)
    }

    func testBaselineIsImmutableAndDailyPointsUpsertByTradingDate() throws {
        let originalBaseline = PersonalWatchlistBaseline(
            price: 1.0,
            quotedAt: "2026-07-20",
            capturedAt: "2026-07-20T10:00:00Z",
            sourceLabel: "关注起点"
        )
        let record = PersonalWatchlistRecord(
            item: item(code: "021550", assetType: .fund, fundMarket: .offExchange),
            baseline: originalBaseline,
            dailyPoints: [
                PersonalWatchlistDailyPoint(date: "2026-07-20", price: 1.00),
                PersonalWatchlistDailyPoint(date: "2026-07-21", price: 1.01),
            ]
        )
        let proposedReplacement = PersonalWatchlistBaseline(
            price: 9.9,
            quotedAt: "2026-07-21",
            capturedAt: "2026-07-21T10:00:00Z",
            sourceLabel: "错误覆盖"
        )

        let updated = record.updating(
            baseline: proposedReplacement,
            appending: [
                PersonalWatchlistDailyPoint(date: "2026-07-21 15:00:00", price: 1.02),
                PersonalWatchlistDailyPoint(date: "2026-07-22", price: 1.03),
            ]
        )

        XCTAssertEqual(updated.baseline, originalBaseline)
        XCTAssertEqual(updated.dailyPoints.map(\.date), ["2026-07-20", "2026-07-21", "2026-07-22"])
        XCTAssertEqual(updated.dailyPoints[1].price, 1.02)
    }

    func testQuoteRowCalculatesChangeAgainstFollowBaseline() throws {
        let record = PersonalWatchlistRecord(
            item: item(code: "510300", assetType: .fund, fundMarket: .onExchange),
            baseline: PersonalWatchlistBaseline(
                price: 4.0,
                quotedAt: "2026-07-20 15:00:00",
                capturedAt: "2026-07-20T15:00:00Z",
                sourceLabel: "股票行情"
            )
        )
        let row = PersonalWatchlistQuoteRow(
            record: record,
            assetName: "沪深300ETF",
            currentPrice: 4.4,
            quotedAt: "2026-07-21 15:00:00",
            sourceLabel: "股票行情",
            dailyChangePct: 1.2,
            dailyPoints: []
        )

        XCTAssertEqual(try XCTUnwrap(row.changeSinceFollowAmount), 0.4, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(row.changeSinceFollowPct), 10, accuracy: 0.0001)
    }

    func testStoreRoundTripsBaselineAndNormalizedHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("personal-watchlist-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("user-watchlist.json")
        let store = PersonalWatchlistStore()
        let record = PersonalWatchlistRecord(
            item: item(code: "AAPL", assetType: .stock, stockMarket: .us),
            baseline: PersonalWatchlistBaseline(
                price: 210,
                quotedAt: "2026-07-20 16:00:00",
                capturedAt: "2026-07-20T20:00:00Z",
                sourceLabel: "股票行情"
            ),
            dailyPoints: [
                PersonalWatchlistDailyPoint(date: "2026-07-20", price: 210),
                PersonalWatchlistDailyPoint(date: "2026-07-20", price: 211),
            ]
        )

        try store.save([record], to: fileURL)
        let loaded = try store.load(from: fileURL)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.baseline?.price, 210)
        XCTAssertEqual(loaded.first?.dailyPoints, [PersonalWatchlistDailyPoint(date: "2026-07-20", price: 211)])
    }

    private func item(
        code: String,
        assetType: PersonalAssetType,
        stockMarket: StockMarket? = nil,
        fundMarket: FundMarket? = nil
    ) -> PersonalWatchlistItem {
        PersonalWatchlistItem(
            code: code,
            displayName: nil,
            assetType: assetType,
            stockMarket: stockMarket,
            fundMarket: fundMarket,
            followedAt: "2026-07-20T10:00:00Z"
        )
    }
}
