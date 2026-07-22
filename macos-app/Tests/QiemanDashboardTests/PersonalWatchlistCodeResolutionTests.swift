import XCTest
@testable import QiemanDashboard

@MainActor
final class PersonalWatchlistCodeResolutionTests: XCTestCase {
    func testPreparesStockCodeWithoutWaitingForRemoteNameLookup() throws {
        let resolution = try XCTUnwrap(
            AppModel().preparePersonalWatchlistCode(category: .stock, codeText: "  SH600519 ")
        )

        XCTAssertEqual(resolution.assetType, .stock)
        XCTAssertEqual(resolution.code, "600519")
        XCTAssertNil(resolution.displayName)
        XCTAssertEqual(resolution.stockMarket, .aShare)
        XCTAssertNil(resolution.fundMarket)
    }

    func testPreparesOffExchangeFundCodeWithoutWaitingForRemoteNameLookup() throws {
        let resolution = try XCTUnwrap(
            AppModel().preparePersonalWatchlistCode(category: .offExchangeFund, codeText: "021550")
        )

        XCTAssertEqual(resolution.assetType, .fund)
        XCTAssertEqual(resolution.code, "021550")
        XCTAssertNil(resolution.displayName)
        XCTAssertNil(resolution.stockMarket)
        XCTAssertEqual(resolution.fundMarket, .offExchange)
    }

    func testPreparesOnExchangeFundCodeWithoutWaitingForRemoteNameLookup() throws {
        let resolution = try XCTUnwrap(
            AppModel().preparePersonalWatchlistCode(category: .onExchangeFund, codeText: "510300")
        )

        XCTAssertEqual(resolution.assetType, .fund)
        XCTAssertEqual(resolution.code, "510300")
        XCTAssertNil(resolution.displayName)
        XCTAssertNil(resolution.stockMarket)
        XCTAssertEqual(resolution.fundMarket, .onExchange)
    }

    func testRejectsEmptyWatchlistCode() {
        XCTAssertNil(
            AppModel().preparePersonalWatchlistCode(category: .stock, codeText: "  \n ")
        )
    }
}
