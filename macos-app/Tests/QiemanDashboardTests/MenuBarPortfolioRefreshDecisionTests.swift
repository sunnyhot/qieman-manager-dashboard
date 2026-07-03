import XCTest
@testable import QiemanDashboard

final class MenuBarPortfolioRefreshDecisionTests: XCTestCase {
    func testPopoverAppearRefreshesPortfolioOnlyWhenSnapshotIsMissing() {
        let actions = MenuBarPortfolioRefreshDecision.onAppear(
            hasPortfolioSnapshot: false,
            hasPersonalPortfolio: true,
            hasIncompletePortfolioValuation: false,
            lastPortfolioRefreshAt: nil
        )

        XCTAssertEqual(actions, [.refreshPortfolio])
    }

    func testPopoverAppearRefreshesMarketIndicesWhenCompleteSnapshotIsStale() {
        let now = Date(timeIntervalSince1970: 1_000)
        let actions = MenuBarPortfolioRefreshDecision.onAppear(
            hasPortfolioSnapshot: true,
            hasPersonalPortfolio: true,
            hasIncompletePortfolioValuation: false,
            lastPortfolioRefreshAt: now.addingTimeInterval(-600),
            now: now
        )

        XCTAssertEqual(actions, [.refreshMarketIndicesIfNeeded])
    }

    func testPopoverAppearRefreshesPortfolioWhenExistingSnapshotHasIncompleteValuation() {
        let now = Date(timeIntervalSince1970: 1_000)
        let actions = MenuBarPortfolioRefreshDecision.onAppear(
            hasPortfolioSnapshot: true,
            hasPersonalPortfolio: true,
            hasIncompletePortfolioValuation: true,
            lastPortfolioRefreshAt: now.addingTimeInterval(-600),
            now: now
        )

        XCTAssertEqual(actions, [.refreshPortfolio])
    }

    func testPopoverAppearDoesNotImmediatelyRetryIncompleteValuation() {
        let now = Date(timeIntervalSince1970: 1_000)
        let actions = MenuBarPortfolioRefreshDecision.onAppear(
            hasPortfolioSnapshot: true,
            hasPersonalPortfolio: true,
            hasIncompletePortfolioValuation: true,
            lastPortfolioRefreshAt: now.addingTimeInterval(-20),
            now: now
        )

        XCTAssertEqual(actions, [.refreshMarketIndicesIfNeeded])
    }

    func testPopoverAppearRefreshesMarketIndicesWhenCompleteSnapshotIsFresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        let actions = MenuBarPortfolioRefreshDecision.onAppear(
            hasPortfolioSnapshot: true,
            hasPersonalPortfolio: true,
            hasIncompletePortfolioValuation: false,
            lastPortfolioRefreshAt: now.addingTimeInterval(-20),
            now: now
        )

        XCTAssertEqual(actions, [.refreshMarketIndicesIfNeeded])
    }

    func testPopoverAppearStillRefreshesMarketIndicesWithoutPortfolio() {
        let actions = MenuBarPortfolioRefreshDecision.onAppear(
            hasPortfolioSnapshot: false,
            hasPersonalPortfolio: false,
            hasIncompletePortfolioValuation: false,
            lastPortfolioRefreshAt: nil
        )

        XCTAssertEqual(actions, [.refreshMarketIndicesIfNeeded])
    }
}
