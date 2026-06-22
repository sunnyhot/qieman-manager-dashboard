import XCTest
@testable import QiemanDashboard

final class TrendPromptBuilderTests: XCTestCase {
    func testPromptRequiresStructuredSafeJSONOutput() {
        let context = TrendAnalysisContext(
            createdAt: "2026-06-22 12:00:00",
            privacyMode: .sanitized,
            portfolio: TrendContextPortfolio(
                assetCount: 1,
                holdingCount: 1,
                activePlanCount: 0,
                pendingAssetCount: 0,
                totalMarketValue: nil,
                totalPendingCashAmount: nil,
                totalEstimatedNextPlanAmount: nil,
                totalEffectiveHoldingAmount: nil
            ),
            assets: [],
            sectors: [],
            platformSignals: [],
            watchSummary: "暂无",
            insightHeadline: "等待组合快照"
        )

        let prompt = TrendPromptBuilder().build(
            context: context,
            settings: TrendAnalysisSettings.default
        )

        XCTAssertTrue(prompt.system.contains("Return valid JSON only"))
        XCTAssertTrue(prompt.system.contains("Do not guarantee returns"))
        XCTAssertTrue(prompt.system.contains("Do not use mandatory buy/sell language"))
        XCTAssertTrue(prompt.system.contains("counterSignals"))
        XCTAssertTrue(prompt.user.contains("\"privacyMode\":\"脱敏摘要\""))
    }
}
