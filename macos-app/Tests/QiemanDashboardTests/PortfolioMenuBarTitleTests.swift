import XCTest
@testable import QiemanDashboard

final class PortfolioMenuBarTitleTests: XCTestCase {
    func testFallbackUsesCompactTotalValueWhenAvailable() {
        XCTAssertEqual(
            PortfolioMenuBarTitle.fallback(
                totalEffectiveHoldingAmount: 12_345,
                hasPersonalPortfolio: true,
                hasPendingTrades: false,
                hasInvestmentPlans: false,
                hasArchivedPortfolio: false
            ),
            "1.2万"
        )

        XCTAssertEqual(
            PortfolioMenuBarTitle.fallback(
                totalEffectiveHoldingAmount: 9_876,
                hasPersonalPortfolio: true,
                hasPendingTrades: false,
                hasInvestmentPlans: false,
                hasArchivedPortfolio: false
            ),
            "9876"
        )
    }

    func testFallbackKeepsExistingPriorityWithoutTickerTitle() {
        XCTAssertEqual(
            PortfolioMenuBarTitle.fallback(
                totalEffectiveHoldingAmount: nil,
                hasPersonalPortfolio: true,
                hasPendingTrades: true,
                hasInvestmentPlans: true,
                hasArchivedPortfolio: true
            ),
            "持仓"
        )

        XCTAssertEqual(
            PortfolioMenuBarTitle.fallback(
                totalEffectiveHoldingAmount: nil,
                hasPersonalPortfolio: false,
                hasPendingTrades: true,
                hasInvestmentPlans: true,
                hasArchivedPortfolio: true
            ),
            "待确认"
        )

        XCTAssertEqual(
            PortfolioMenuBarTitle.fallback(
                totalEffectiveHoldingAmount: nil,
                hasPersonalPortfolio: false,
                hasPendingTrades: false,
                hasInvestmentPlans: true,
                hasArchivedPortfolio: true
            ),
            "计划"
        )

        XCTAssertEqual(
            PortfolioMenuBarTitle.fallback(
                totalEffectiveHoldingAmount: nil,
                hasPersonalPortfolio: false,
                hasPendingTrades: false,
                hasInvestmentPlans: false,
                hasArchivedPortfolio: true
            ),
            "归档"
        )
    }
}
