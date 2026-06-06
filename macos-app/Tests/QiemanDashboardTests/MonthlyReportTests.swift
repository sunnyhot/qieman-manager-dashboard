import XCTest
@testable import QiemanDashboard

final class MonthlyReportTests: XCTestCase {
    func testMakeSummaryBuildsMarkdownFromPortfolioInsights() {
        let rows = [
            row(name: "核心宽基", code: "000001", marketValue: 20_000, profitAmount: 1_200, profitPct: 6, pendingAmount: 500, activePlanAmount: 100),
            row(name: "红利策略", code: "000002", marketValue: 12_000, profitAmount: -200, profitPct: -1.6, pendingAmount: 0, activePlanAmount: nil)
        ]
        let diagnostics = PortfolioDiagnosticsSummary.make(rows: rows)
        let reminders = PortfolioReminderSummary.make(rows: rows, diagnostics: diagnostics)
        let attribution = ProfitAttributionSummary.make(rows: rows)
        let simulation = PlanSimulationSummary.make(rows: rows, executionCount: 12)

        let report = MonthlyReportSummary.make(
            rows: rows,
            diagnostics: diagnostics,
            reminders: reminders,
            attribution: attribution,
            simulation: simulation,
            generatedAt: "2026-06-06 10:30:00"
        )

        XCTAssertEqual(report.title, "且慢主理人看板月报 2026-06")
        XCTAssertEqual(report.monthText, "2026-06")
        XCTAssertTrue(report.markdown.contains("## 组合概览"))
        XCTAssertTrue(report.markdown.contains("- 总占用：¥32,600.00"))
        XCTAssertTrue(report.markdown.contains("## 收益归因"))
        XCTAssertTrue(report.markdown.contains("收益主要由 核心宽基 贡献"))
        XCTAssertTrue(report.markdown.contains("## 计划模拟"))
        XCTAssertTrue(report.markdown.contains("未来 12 次计划约投入 ¥1,200.00"))
    }

    func testMakeSummaryUsesGeneratedDateWhenMonthIsMissing() {
        let report = MonthlyReportSummary.make(
            rows: [],
            diagnostics: PortfolioDiagnosticsSummary.make(rows: []),
            reminders: PortfolioReminderSummary.make(rows: [], diagnostics: PortfolioDiagnosticsSummary.make(rows: [])),
            attribution: ProfitAttributionSummary.make(rows: []),
            simulation: PlanSimulationSummary.make(rows: []),
            generatedAt: "invalid"
        )

        XCTAssertEqual(report.monthText, "本月")
        XCTAssertTrue(report.markdown.contains("等待资产数据"))
    }

    private func row(
        name: String,
        code: String,
        marketValue: Double,
        profitAmount: Double?,
        profitPct: Double?,
        pendingAmount: Double,
        activePlanAmount: Double?
    ) -> PersonalAssetAggregateRow {
        let holding = UserPortfolioHolding(fundCode: code, assetType: .fund, units: 10_000, costPrice: 1, displayName: name)
        let valuationRow = UserPortfolioValuationRow(
            holding: holding,
            fundName: name,
            currentPrice: nil,
            priceTime: "2026-06-05 15:00",
            priceSource: nil,
            officialNav: nil,
            officialNavDate: nil,
            estimatePrice: nil,
            estimatePriceTime: nil,
            marketValue: marketValue,
            costValue: marketValue - (profitAmount ?? 0),
            profitAmount: profitAmount,
            profitPct: profitPct,
            estimateChangePct: 0.2
        )
        let pendingTrades = pendingAmount > 0
            ? [
                PersonalPendingTrade(
                    occurredAt: "2026-06-05",
                    actionLabel: "买入",
                    fundName: name,
                    fundCode: code,
                    amountText: "\(pendingAmount)",
                    amountValue: pendingAmount,
                    status: "待确认"
                )
            ]
            : []
        let plans = activePlanAmount.map {
            [
                PersonalInvestmentPlan(
                    planTypeLabel: "定投",
                    fundName: name,
                    fundCode: code,
                    scheduleText: "每周三",
                    amountText: String(format: "%.2f", $0),
                    nextExecutionDate: "2026-06-12",
                    status: "进行中"
                )
            ]
        } ?? []
        return PersonalAssetAggregateRow(
            key: code,
            assetType: .fund,
            fundName: name,
            fundCode: code,
            holdingRow: valuationRow,
            rawHolding: holding,
            archivedHolding: nil,
            pendingTrades: pendingTrades,
            plans: plans
        )
    }
}
