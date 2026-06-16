import XCTest
@testable import QiemanDashboard

final class MenuBarPortfolioRefreshDecisionTests: XCTestCase {
    func testPopoverAppearRefreshesPortfolioOnlyWhenSnapshotIsMissing() {
        let actions = MenuBarPortfolioRefreshDecision.onAppear(
            hasPortfolioSnapshot: false,
            hasPersonalPortfolio: true
        )

        XCTAssertEqual(actions, [.refreshPortfolio])
    }

    func testPopoverAppearRefreshesMarketIndicesWhenSnapshotExists() {
        let actions = MenuBarPortfolioRefreshDecision.onAppear(
            hasPortfolioSnapshot: true,
            hasPersonalPortfolio: true
        )

        XCTAssertEqual(actions, [.refreshMarketIndicesIfNeeded])
    }

    func testPopoverAppearStillRefreshesMarketIndicesWithoutPortfolio() {
        let actions = MenuBarPortfolioRefreshDecision.onAppear(
            hasPortfolioSnapshot: false,
            hasPersonalPortfolio: false
        )

        XCTAssertEqual(actions, [.refreshMarketIndicesIfNeeded])
    }
}
