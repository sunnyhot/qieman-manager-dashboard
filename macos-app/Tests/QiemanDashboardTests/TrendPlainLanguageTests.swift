import XCTest
@testable import QiemanDashboard

final class TrendPlainLanguageTests: XCTestCase {
    func testDirectionAndConfidenceUseEverydayChinese() {
        XCTAssertEqual(TrendPlainLanguage.direction(.neutralPositive), "走势偏强")
        XCTAssertEqual(
            TrendPlainLanguage.confidence(TrendConfidence(score: 60, label: "中")),
            "把握一般"
        )
        XCTAssertEqual(TrendPlainLanguage.actionLabel("买入观察"), "先观察，等机会")
        XCTAssertEqual(TrendPlainLanguage.actionMethod("暂停追买"), "暂时不再买入")
    }

    func testCachedReportJargonBecomesCompleteSentences() {
        XCTAssertEqual(
            TrendPlainLanguage.sentence("AI产业周期"),
            "AI 行业仍在增长。"
        )
        XCTAssertEqual(
            TrendPlainLanguage.sentence("纳斯达克科技巨头盈利动能强劲。"),
            "纳斯达克大型科技公司的盈利增长较快。"
        )
        XCTAssertEqual(
            TrendPlainLanguage.sentence("行业 Beta 向下"),
            "行业整体走势偏弱。"
        )
        XCTAssertEqual(
            TrendPlainLanguage.sentence("短期趋势维持偏强"),
            "短期走势仍然较强。"
        )
        XCTAssertEqual(
            TrendPlainLanguage.sentence("未触发反证条件"),
            "没有出现相反信号。"
        )
        XCTAssertEqual(
            TrendPlainLanguage.headline("AI产业周期"),
            "AI 行业仍在增长"
        )
        XCTAssertEqual(
            TrendPlainLanguage.outlookSentence(
                horizon: .medium,
                direction: .neutralPositive,
                confidence: TrendConfidence(score: 60, label: "中")
            ),
            "从中期看，目前走势偏强，这项判断把握一般。"
        )
    }
}
