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
        XCTAssertTrue(prompt.system.contains("普通投资者能直接听懂的自然中文"))
        XCTAssertTrue(prompt.system.contains("不要使用或堆砌研报术语"))
        XCTAssertTrue(prompt.system.contains("不要输出“AI产业周期”“行业 Beta 向下”这类名词短语"))
        XCTAssertTrue(prompt.system.contains("纳斯达克大型科技公司的盈利仍在较快增长"))
        XCTAssertTrue(prompt.system.contains("不要写“买入观察”“减仓复核”“暂停追买”"))
        XCTAssertTrue(prompt.system.contains("首个 horizon.rationale 要用一句简短自然中文概括主要原因"))
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

    func testPromptIncludesTradeSignalPreferencesWithoutChangingSchema() {
        let context = makeTrendPromptContext()
        let tradeSettings = TradeSignalSettings(
            enabled: true,
            localNotificationsEnabled: true,
            riskPreference: .conservative,
            primaryHorizon: .long,
            minimumConfidence: 72,
            allowBuySignals: true,
            allowSellSignals: false,
            useStaleAnalysis: true,
            assetPreferences: [
                TradeSignalAssetPreference(
                    assetKey: "000001",
                    mode: .raiseAttention,
                    preferredHorizon: .short,
                    notes: "核心标的"
                )
            ]
        )

        let prompt = TrendPromptBuilder().build(
            context: context,
            settings: TrendAnalysisSettings.default,
            tradeSignalSettings: tradeSettings
        )

        XCTAssertTrue(prompt.system.contains("AI 操作建议偏好"))
        XCTAssertTrue(prompt.system.contains("风险偏好：保守"))
        XCTAssertTrue(prompt.system.contains("主要观察周期：长期"))
        XCTAssertTrue(prompt.system.contains("最低关注置信度：72"))
        XCTAssertTrue(prompt.system.contains("允许关注卖出：否"))
        XCTAssertTrue(prompt.system.contains("000001：提高关注；周期：短期；备注：核心标的"))
        XCTAssertTrue(prompt.system.contains("Do not add fields outside this schema"))
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
