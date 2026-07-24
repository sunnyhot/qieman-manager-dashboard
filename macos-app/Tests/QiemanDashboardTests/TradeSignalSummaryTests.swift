import XCTest
@testable import QiemanDashboard

final class TradeSignalSummaryTests: XCTestCase {
    func testMakeBuildsWorkbenchSignalsFromTrendActions() {
        let report = makeReport(
            generatedAt: "2026-07-03 09:30:00",
            actions: [
                TrendActionCandidate(
                    id: "buy-000001",
                    kind: .considerIncrease,
                    title: "关注买入红利低波",
                    detail: "回撤未破坏中期逻辑，可小额分批观察。",
                    targetName: "红利低波",
                    confidence: TrendConfidence(score: 78, label: "中"),
                    triggerConditions: ["继续回撤且量能缩小"],
                    invalidatingConditions: ["红利板块跌破趋势支撑"]
                ),
                TrendActionCandidate(
                    id: "sell-000002",
                    kind: .considerReduce,
                    title: "复核纳指仓位",
                    detail: "冲高回落时复核再平衡。",
                    targetName: "纳斯达克100",
                    confidence: TrendConfidence(score: 71, label: "中"),
                    triggerConditions: ["放量冲高回落"],
                    invalidatingConditions: ["盈利预期继续上修"]
                )
            ],
            assetTrends: []
        )
        let rows = [
            row(name: "红利低波", code: "000001", estimateChangePct: -1.2),
            row(name: "纳斯达克100", code: "000002", estimateChangePct: 1.6)
        ]

        let summary = TradeSignalSummary.make(
            report: report,
            rows: rows,
            settings: .default,
            now: "2026-07-03 15:00:00"
        )

        XCTAssertEqual(summary.headline, "2 条 AI 操作建议")
        XCTAssertEqual(summary.triggeredCount, 2)
        XCTAssertFalse(summary.staleAnalysis)
        XCTAssertEqual(summary.items.map(\.action), [.watchBuy, .watchSell])
        XCTAssertEqual(summary.items.first?.assetKey, "000001")
        XCTAssertEqual(summary.items.first?.status, .approaching)
        XCTAssertEqual(summary.items.first?.triggerSummary, "继续回撤且量能缩小")
        XCTAssertEqual(summary.items.first?.invalidatingSummary, "红利板块跌破趋势支撑")
    }

    func testMakeMarksStaleAnalysisButKeepsSignalsWhenAllowed() {
        let report = makeReport(
            generatedAt: "2026-07-02 09:30:00",
            actions: [
                TrendActionCandidate(
                    id: "buy-000001",
                    kind: .considerIncrease,
                    title: "关注买入红利低波",
                    detail: "回撤未破坏中期逻辑。",
                    targetName: "红利低波",
                    confidence: TrendConfidence(score: 78, label: "中"),
                    triggerConditions: ["继续回撤"],
                    invalidatingConditions: ["趋势破位"]
                )
            ],
            assetTrends: []
        )

        let summary = TradeSignalSummary.make(
            report: report,
            rows: [row(name: "红利低波", code: "000001", estimateChangePct: -0.8)],
            settings: .default,
            now: "2026-07-03 15:00:00"
        )

        XCTAssertTrue(summary.staleAnalysis)
        XCTAssertTrue(summary.items.first?.isBasedOnStaleAnalysis == true)
        XCTAssertEqual(summary.items.first?.status, .approaching)
        XCTAssertTrue(summary.items.first?.reason.contains("基于上次 AI 分析") == true)
    }

    func testMakeFiltersDisabledOrLowConfidenceSignals() {
        let report = makeReport(
            generatedAt: "2026-07-03 09:30:00",
            actions: [
                TrendActionCandidate(
                    id: "low-buy",
                    kind: .considerIncrease,
                    title: "低置信买入",
                    detail: "信号不足。",
                    targetName: "红利低波",
                    confidence: TrendConfidence(score: 40, label: "低"),
                    triggerConditions: ["回撤"],
                    invalidatingConditions: ["破位"]
                ),
                TrendActionCandidate(
                    id: "sell",
                    kind: .considerReduce,
                    title: "卖出观察",
                    detail: "仓位偏高。",
                    targetName: "纳斯达克100",
                    confidence: TrendConfidence(score: 80, label: "高"),
                    triggerConditions: ["冲高"],
                    invalidatingConditions: ["继续走强"]
                )
            ],
            assetTrends: []
        )
        let settings = TradeSignalSettings(
            enabled: true,
            localNotificationsEnabled: false,
            riskPreference: .balanced,
            primaryHorizon: .medium,
            minimumConfidence: 60,
            allowBuySignals: true,
            allowSellSignals: false,
            useStaleAnalysis: true,
            assetPreferences: []
        )

        let summary = TradeSignalSummary.make(
            report: report,
            rows: [row(name: "红利低波", code: "000001", estimateChangePct: -1)],
            settings: settings,
            now: "2026-07-03 15:00:00"
        )

        XCTAssertTrue(summary.items.isEmpty)
        XCTAssertEqual(summary.headline, "暂无 AI 操作建议")
    }

    private func makeReport(
        generatedAt: String,
        actions: [TrendActionCandidate],
        assetTrends: [TrendAssetView]
    ) -> TrendAnalysisReport {
        TrendAnalysisReport(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            generatedAt: generatedAt,
            dataAsOf: generatedAt,
            privacyMode: .sanitized,
            externalSignalStatus: .partial,
            portfolio: TrendPortfolioSummary(
                headline: "组合保持观察",
                riskLevel: .medium,
                summary: "等待信号确认。"
            ),
            horizons: [],
            marketOutlook: [],
            sectors: [],
            opportunities: [],
            keyAssets: [],
            assetTrends: assetTrends,
            actions: actions,
            evidence: [],
            warnings: [],
            disclaimer: "仅供研究，不构成投资建议。"
        )
    }

    private func row(name: String, code: String, estimateChangePct: Double?) -> PersonalAssetAggregateRow {
        let holding = UserPortfolioHolding(fundCode: code, assetType: .fund, units: 1_000, costPrice: 1, displayName: name)
        let valuationRow = UserPortfolioValuationRow(
            holding: holding,
            fundName: name,
            currentPrice: nil,
            priceTime: "2026-07-03 15:00",
            priceSource: nil,
            officialNav: nil,
            officialNavDate: nil,
            estimatePrice: nil,
            estimatePriceTime: nil,
            marketValue: 1_000,
            costValue: 900,
            profitAmount: 100,
            profitPct: 11.11,
            estimateChangePct: estimateChangePct
        )
        return PersonalAssetAggregateRow(
            key: code,
            assetType: .fund,
            fundName: name,
            fundCode: code,
            holdingRow: valuationRow,
            rawHolding: holding,
            archivedHolding: nil,
            pendingTrades: [],
            plans: []
        )
    }
}
