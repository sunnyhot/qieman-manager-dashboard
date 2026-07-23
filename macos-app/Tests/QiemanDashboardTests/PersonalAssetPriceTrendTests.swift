import XCTest
@testable import QiemanDashboard

final class PersonalAssetPriceTrendTests: XCTestCase {
    func testSeriesNormalizesSortsAndDeduplicatesDailyPoints() {
        let series = PersonalAssetPriceTrendSeries(
            dailyPoints: [
                PersonalWatchlistDailyPoint(date: "2026-07-03", price: 1.03),
                PersonalWatchlistDailyPoint(date: "not-a-date", price: 9.99),
                PersonalWatchlistDailyPoint(date: "2026-07-01", price: 1.01),
                PersonalWatchlistDailyPoint(date: "2026-07-03", price: 1.04),
                PersonalWatchlistDailyPoint(date: "2026-07-02", price: -1)
            ]
        )

        XCTAssertEqual(series.points.map(\.dateText), ["2026-07-01", "2026-07-03"])
        XCTAssertEqual(series.points.map(\.price), [1.01, 1.04])
    }

    func testRangeReturnsLatestTradingDaysAndCalculatesChange() throws {
        let points: [PersonalWatchlistDailyPoint] = (1...120).map { day in
            let month = ((day - 1) / 28) + 1
            let dayOfMonth = ((day - 1) % 28) + 1
            let date = String(format: "2026-%02d-%02d", month, dayOfMonth)
            return PersonalWatchlistDailyPoint(date: date, price: Double(day))
        }
        let series = PersonalAssetPriceTrendSeries(dailyPoints: points)

        XCTAssertEqual(series.points(for: .thirty).count, 30)
        XCTAssertEqual(series.points(for: .ninety).count, 90)
        XCTAssertEqual(series.points(for: .oneEighty).count, 120)
        XCTAssertEqual(series.points(for: .all).count, 120)
        XCTAssertEqual(series.points(for: .thirty).first?.price, 91)
        let changePct = try XCTUnwrap(series.changePct(for: .thirty))
        XCTAssertEqual(changePct, (120.0 / 91.0 - 1) * 100, accuracy: 0.000_001)
    }
}
