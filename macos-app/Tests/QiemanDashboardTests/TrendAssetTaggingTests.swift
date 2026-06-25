import XCTest
@testable import QiemanDashboard

final class TrendAssetTaggingTests: XCTestCase {
    func testIndexMatchesByCodeAndBuildsMultiDimensionTags() {
        let report = TrendAnalysisReport
            .fixture(generatedAt: "2026-06-24 10:00:00", externalSignalStatus: .available)
            .replacingKeyAssets([
                TrendAssetView(
                    id: "asset-510300",
                    name: "沪深300ETF",
                    code: "510300",
                    sector: "场内基金",
                    impactText: "核心宽基仓位，短期跟随A股风险偏好。",
                    horizons: [
                        TrendHorizonView(
                            horizon: .short,
                            direction: .neutralPositive,
                            confidence: TrendConfidence(score: 68, label: "中"),
                            rationale: "短期估值修复但量能仍需确认。",
                            counterSignals: ["跌破上周低点"]
                        ),
                        TrendHorizonView(
                            horizon: .medium,
                            direction: .neutral,
                            confidence: TrendConfidence(score: 55, label: "中"),
                            rationale: "中期等待盈利修复。",
                            counterSignals: []
                        )
                    ],
                    rationale: "组合底仓，影响组合波动中等。",
                    counterSignals: ["成交缩量", "北向流出"]
                )
            ])
            .replacingActions([
                TrendActionCandidate(
                    id: "watch-510300",
                    kind: .considerIncrease,
                    title: "分批加仓沪深300ETF",
                    detail: "若量能放大且未跌破上周低点，可按预算分批加仓。",
                    targetName: "沪深300ETF",
                    confidence: TrendConfidence(score: 62, label: "中"),
                    triggerConditions: ["放量站回均线"],
                    invalidatingConditions: ["跌破上周低点"]
                )
            ])
        let row = aggregateRow(key: "fund:510300", name: "沪深300ETF", code: "510300")

        let summary = TrendAssetTagIndex(report: report).summary(for: row)

        XCTAssertEqual(summary?.impactText, "核心宽基仓位，短期跟随A股风险偏好。")
        XCTAssertEqual(summary?.primaryDirection, .neutralPositive)
        XCTAssertEqual(summary?.primaryConfidence.normalizedScore, 68)
        XCTAssertEqual(summary?.relatedActions.map(\.id), ["watch-510300"])
        XCTAssertEqual(summary?.tradePlan.label, "买入/加仓")
        XCTAssertEqual(summary?.tradePlan.method, "分批买入")
        XCTAssertEqual(summary?.tradePlan.triggerConditions, ["放量站回均线"])
        XCTAssertEqual(summary?.tags.map(\.dimension), ["板块", "动作", "方式", "短期", "中期", "信心", "反证"])
        XCTAssertEqual(summary?.tags.map(\.text), ["场内基金", "买入/加仓", "分批买入", "中性偏强", "中性", "中信心", "3 条"])
    }

    func testIndexFallsBackToNameWhenCodeIsMissingFromReport() {
        let report = TrendAnalysisReport
            .fixture(generatedAt: "2026-06-24 10:00:00", externalSignalStatus: .available)
            .replacingKeyAssets([
                TrendAssetView(
                    id: "asset-dividend",
                    name: "红利低波",
                    code: nil,
                    sector: "场外基金",
                    impactText: "防守属性较强，但短期弹性有限。",
                    horizons: [],
                    rationale: "偏稳定器。",
                    counterSignals: []
                )
            ])
        let row = aggregateRow(key: "fund:000922", name: "红利低波", code: "000922")

        let summary = TrendAssetTagIndex(report: report).summary(for: row)

        XCTAssertEqual(summary?.assetName, "红利低波")
        XCTAssertEqual(summary?.tags.first?.dimension, "板块")
        XCTAssertEqual(summary?.tags.first?.text, "场外基金")
        XCTAssertEqual(summary?.tradePlan.label, "持有观察")
    }

    func testIndexMatchesCombinedCodesFromModelOutput() {
        let report = TrendAnalysisReport
            .fixture(generatedAt: "2026-06-24 10:00:00", externalSignalStatus: .available)
            .replacingKeyAssets([
                TrendAssetView(
                    id: "asset-consume",
                    name: "富国消费主题混合A/C",
                    code: "519915/011309",
                    sector: "消费",
                    impactText: "消费主题对组合波动影响较高。",
                    horizons: [
                        TrendHorizonView(
                            horizon: .short,
                            direction: .neutralNegative,
                            confidence: TrendConfidence(score: 58, label: "中"),
                            rationale: "短期仍受消费情绪拖累。",
                            counterSignals: []
                        )
                    ],
                    rationale: "消费仓位需要观察。",
                    counterSignals: []
                )
            ])
        let row = aggregateRow(key: "fund:011309", name: "富国消费主题混合C", code: "011309")

        let summary = TrendAssetTagIndex(report: report).summary(for: row)

        XCTAssertEqual(summary?.assetName, "富国消费主题混合A/C")
        XCTAssertEqual(summary?.primaryDirection, .neutralNegative)
    }

    func testIndexDerivesBuyPlanForPositiveAssetWithoutModelAction() {
        let report = TrendAnalysisReport
            .fixture(generatedAt: "2026-06-24 10:00:00", externalSignalStatus: .available)
            .replacingKeyAssets([
                TrendAssetView(
                    id: "asset-tech",
                    name: "易方达科技创新混合A",
                    code: "007346",
                    sector: "科技创新",
                    impactText: "科技方向弹性较高，适合按条件分批处理。",
                    horizons: [
                        TrendHorizonView(
                            horizon: .short,
                            direction: .bullish,
                            confidence: TrendConfidence(score: 72, label: "中"),
                            rationale: "短期动量改善。",
                            counterSignals: ["放量失败"]
                        )
                    ],
                    rationale: "趋势偏强但波动较大。",
                    counterSignals: []
                )
            ])
        let row = aggregateRow(key: "fund:007346", name: "易方达科技创新混合A", code: "007346")

        let summary = TrendAssetTagIndex(report: report).summary(for: row)

        XCTAssertEqual(summary?.tradePlan.label, "买入观察")
        XCTAssertEqual(summary?.tradePlan.method, "分批买入")
        XCTAssertTrue(summary?.tradePlan.detail.contains("避免一次性追高") == true)
        XCTAssertTrue(summary?.tags.contains { $0.dimension == "动作" && $0.text == "买入观察" } == true)
        XCTAssertTrue(summary?.tags.contains { $0.dimension == "方式" && $0.text == "分批买入" } == true)
    }

    func testIndexUsesSectorFallbackForUncoveredAsset() {
        let report = TrendAnalysisReport
            .fixture(generatedAt: "2026-06-24 10:00:00", externalSignalStatus: .available)
            .replacingSectors([
                TrendSectorView(
                    id: "consumer",
                    name: "消费",
                    exposureText: "组合主要暴露",
                    direction: .neutralNegative,
                    confidence: TrendConfidence(score: 61, label: "中"),
                    rationale: "消费板块仍在弱修复中。",
                    evidenceIDs: [],
                    counterSignals: ["白酒成交放量"]
                )
            ])
        let row = aggregateRow(key: "fund:000248", name: "汇添富中证主要消费ETF联接A", code: "000248")

        let summary = TrendAssetTagIndex(report: report).summary(for: row)

        XCTAssertEqual(summary?.sector, "消费")
        XCTAssertEqual(summary?.impactText, "消费板块仍在弱修复中。")
        XCTAssertEqual(summary?.primaryDirection, .neutralNegative)
        XCTAssertEqual(summary?.tags.map(\.dimension).prefix(5), ["板块", "动作", "方式", "板块趋势", "信心"])
        XCTAssertEqual(summary?.tradePlan.label, "减仓复核")
        XCTAssertEqual(summary?.tradePlan.method, "暂停追买")
    }

    func testIndexDerivesSellPlanForBearishSectorFallback() {
        let report = TrendAnalysisReport
            .fixture(generatedAt: "2026-06-24 10:00:00", externalSignalStatus: .available)
            .replacingSectors([
                TrendSectorView(
                    id: "consumer",
                    name: "消费",
                    exposureText: "组合主要暴露",
                    direction: .bearish,
                    confidence: TrendConfidence(score: 70, label: "中"),
                    rationale: "消费板块趋势转弱，需要降低组合拖累。",
                    evidenceIDs: [],
                    counterSignals: ["重新站上关键均线"]
                )
            ])
        let row = aggregateRow(key: "fund:000248", name: "汇添富中证主要消费ETF联接A", code: "000248")

        let summary = TrendAssetTagIndex(report: report).summary(for: row)

        XCTAssertEqual(summary?.tradePlan.label, "卖出/减仓")
        XCTAssertEqual(summary?.tradePlan.method, "分批卖出")
        XCTAssertTrue(summary?.tradePlan.triggerConditions.first?.contains("偏弱") == true)
        XCTAssertTrue(summary?.tags.contains { $0.dimension == "动作" && $0.text == "卖出/减仓" } == true)
        XCTAssertTrue(summary?.tags.contains { $0.dimension == "方式" && $0.text == "分批卖出" } == true)
    }

    func testIndexUsesLocalFallbackWhenReportHasNoMatchingAssetOrSector() {
        let report = TrendAnalysisReport.fixture(
            generatedAt: "2026-06-24 10:00:00",
            externalSignalStatus: .available
        )
        let row = aggregateRow(key: "fund:006327", name: "易方达中概互联网ETF联接A", code: "006327")

        let summary = TrendAssetTagIndex(report: report).summary(for: row)

        XCTAssertEqual(summary?.assetName, "易方达中概互联网ETF联接A")
        XCTAssertEqual(summary?.primaryDirection, .uncertain)
        XCTAssertTrue(summary?.impactText.contains("趋势报告未覆盖该标的") == true)
        XCTAssertTrue(summary?.tags.contains { $0.dimension == "覆盖" && $0.text == "待补齐" } == true)
        XCTAssertTrue(summary?.tags.contains { $0.dimension == "状态" && $0.text == "已持有" } == true)
        XCTAssertEqual(summary?.tradePlan.label, "持有观察")
        XCTAssertEqual(summary?.tradePlan.method, "等信号再动")
        XCTAssertTrue(summary?.tradePlan.detail.contains("暂不新增交易") == true)
    }

    func testEmptyReportProducesNoAssetSummary() {
        let row = aggregateRow(key: "fund:510300", name: "沪深300ETF", code: "510300")

        let summary = TrendAssetTagIndex(report: nil).summary(for: row)

        XCTAssertNil(summary)
    }

    private func aggregateRow(key: String, name: String, code: String) -> PersonalAssetAggregateRow {
        let holding = UserPortfolioHolding(
            fundCode: code,
            assetType: .fund,
            units: 10_000,
            costPrice: 1,
            displayName: name
        )
        let valuation = UserPortfolioValuationRow(
            holding: holding,
            fundName: name,
            currentPrice: 1,
            priceTime: "2026-06-24 10:00:00",
            priceSource: nil,
            officialNav: nil,
            officialNavDate: nil,
            estimatePrice: 1.01,
            estimatePriceTime: "2026-06-24 10:00:00",
            marketValue: 10_000,
            costValue: 9_000,
            profitAmount: 1_000,
            profitPct: 11.11,
            estimateChangePct: 0.5
        )
        return PersonalAssetAggregateRow(
            key: key,
            assetType: .fund,
            fundName: name,
            fundCode: code,
            holdingRow: valuation,
            rawHolding: holding,
            archivedHolding: nil,
            pendingTrades: [],
            plans: []
        )
    }
}

private extension TrendAnalysisReport {
    func replacingKeyAssets(_ keyAssets: [TrendAssetView]) -> TrendAnalysisReport {
        TrendAnalysisReport(
            id: id,
            generatedAt: generatedAt,
            dataAsOf: dataAsOf,
            privacyMode: privacyMode,
            externalSignalStatus: externalSignalStatus,
            portfolio: portfolio,
            horizons: horizons,
            sectors: sectors,
            keyAssets: keyAssets,
            actions: actions,
            evidence: evidence,
            warnings: warnings,
            disclaimer: disclaimer
        )
    }

    func replacingSectors(_ sectors: [TrendSectorView]) -> TrendAnalysisReport {
        TrendAnalysisReport(
            id: id,
            generatedAt: generatedAt,
            dataAsOf: dataAsOf,
            privacyMode: privacyMode,
            externalSignalStatus: externalSignalStatus,
            portfolio: portfolio,
            horizons: horizons,
            sectors: sectors,
            keyAssets: keyAssets,
            actions: actions,
            evidence: evidence,
            warnings: warnings,
            disclaimer: disclaimer
        )
    }
}
