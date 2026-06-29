import XCTest
@testable import QiemanDashboard

final class TrendPromptBuilderTests: XCTestCase {
    func testPromptRequiresStructuredSafeJSONOutput() {
        let context = makeTrendPromptContext()

        let prompt = TrendPromptBuilder().build(
            context: context,
            settings: TrendAnalysisSettings.default
        )

        XCTAssertTrue(prompt.system.contains("Return valid JSON only"))
        XCTAssertTrue(prompt.system.contains("Do not guarantee returns"))
        XCTAssertTrue(prompt.system.contains("Do not use mandatory buy/sell language"))
        XCTAssertTrue(prompt.system.contains("counterSignals"))
        XCTAssertTrue(prompt.system.contains("Do not add fields outside this schema"))
        XCTAssertTrue(prompt.system.contains("\"headline\""))
        XCTAssertTrue(prompt.system.contains("\"riskLevel\""))
        XCTAssertTrue(prompt.system.contains("\"externalSignalStatus\""))
        XCTAssertTrue(prompt.system.contains("Do not perform exhaustive online searches for every asset"))
        XCTAssertTrue(prompt.system.contains("Keep actions and evidence concise"))
        XCTAssertTrue(prompt.system.contains("keyAssets should focus on portfolio-relevant assets"))
        XCTAssertTrue(prompt.system.contains("Do not force every Context JSON asset into keyAssets"))
        XCTAssertTrue(prompt.system.contains("marketOutlook"))
        XCTAssertTrue(prompt.system.contains("opportunities"))
        XCTAssertTrue(prompt.system.contains("assetTrends"))
        XCTAssertTrue(prompt.system.contains("gold"))
        XCTAssertTrue(prompt.system.contains("每个已持有基金"))
        XCTAssertTrue(prompt.system.contains("buy/hold/sell execution guidance"))
        XCTAssertTrue(prompt.system.contains("keyAssets.horizons"))
        XCTAssertTrue(prompt.system.contains("Follow the embedded Qieman investment trend analysis skill rules"))
        XCTAssertTrue(prompt.system.contains("configured without online search"))
        XCTAssertTrue(prompt.user.contains("\"privacyMode\":\"脱敏摘要\""))
    }

    func testChunkPromptRequiresSectorFirstAnalysis() {
        let context = makeTrendPromptContext()

        let prompt = TrendPromptBuilder().buildChunk(
            context: context,
            chunkIndex: 1,
            chunkCount: 3,
            settings: TrendAnalysisSettings.default
        )

        XCTAssertTrue(prompt.system.contains("先判断板块趋势"))
        XCTAssertTrue(prompt.system.contains("Include every material asset in this chunk in keyAssets"))
        XCTAssertTrue(prompt.system.contains("assetTrends"))
        XCTAssertTrue(prompt.user.contains("逐个覆盖本分块资产"))
        XCTAssertTrue(prompt.user.contains("分块 1/3"))
    }

    private func makeTrendPromptContext() -> TrendAnalysisContext {
        TrendAnalysisContext(
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
    }
}
