import XCTest
@testable import QiemanDashboard

final class TrendAnalysisValidatorTests: XCTestCase {
    func testRejectsMandatoryBuySellLanguage() {
        let report = TrendAnalysisReport
            .fixture(generatedAt: "2026-06-22 12:00:00", externalSignalStatus: .available)
            .replacingActions([
                TrendActionCandidate(
                    id: "buy-now",
                    kind: .considerIncrease,
                    title: "必须买入沪深300",
                    detail: "保证上涨。",
                    targetName: "沪深300ETF",
                    confidence: TrendConfidence(score: 90, label: "高"),
                    triggerConditions: ["放量突破"],
                    invalidatingConditions: ["跌破均线"]
                )
            ])

        let result = TrendAnalysisValidator().validate(report)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.messages.contains { $0.contains("absolute") || $0.contains("强制") })
    }

    func testRejectsActionWithoutConditions() {
        let report = TrendAnalysisReport
            .fixture(generatedAt: "2026-06-22 12:00:00", externalSignalStatus: .available)
            .replacingActions([
                TrendActionCandidate(
                    id: "watch",
                    kind: .watch,
                    title: "关注纳指",
                    detail: "波动加大。",
                    targetName: "纳指ETF",
                    confidence: TrendConfidence(score: 60, label: "中"),
                    triggerConditions: [],
                    invalidatingConditions: ["美元流动性改善"]
                )
            ])

        let result = TrendAnalysisValidator().validate(report)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.messages.contains { $0.contains("trigger") || $0.contains("触发") })
    }

    func testRejectsTopLevelHorizonWithoutRationale() {
        let report = TrendAnalysisReport
            .fixture(generatedAt: "2026-06-22 12:00:00", externalSignalStatus: .available)
            .replacingHorizons([
                TrendHorizonView(
                    horizon: .short,
                    direction: .neutral,
                    confidence: TrendConfidence(score: 60, label: "中"),
                    rationale: "",
                    counterSignals: []
                )
            ])

        let result = TrendAnalysisValidator().validate(report)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.messages.contains { $0.contains("判断依据") || $0.contains("rationale") })
    }

    func testAcceptsFixtureReport() {
        let report = TrendAnalysisReport.fixture(
            generatedAt: "2026-06-22 12:00:00",
            externalSignalStatus: .available
        )

        let result = TrendAnalysisValidator().validate(report)

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.messages.isEmpty)
    }
}

private extension TrendAnalysisReport {
    func replacingHorizons(_ horizons: [TrendHorizonView]) -> TrendAnalysisReport {
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
