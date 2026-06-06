import XCTest
@testable import QiemanDashboard

final class PortfolioReminderTests: XCTestCase {
    func testMakeSummaryPrioritizesPendingTradeAndRiskDiagnostics() {
        let rows = [
            row(name: "核心宽基", code: "000001", marketValue: 60_000, pendingAmount: 0, activePlans: 1, nextDate: "2026-06-12"),
            row(name: "行业主题", code: "000002", marketValue: 15_000, pendingAmount: 25_000, activePlans: 0, nextDate: nil)
        ]
        let diagnostics = PortfolioDiagnosticsSummary.make(rows: rows)

        let summary = PortfolioReminderSummary.make(rows: rows, diagnostics: diagnostics)

        XCTAssertEqual(summary.headline, "2 项需要处理")
        XCTAssertEqual(summary.items.prefix(2).map(\.kind), [.pendingTrade, .concentration])
        XCTAssertEqual(summary.items.first?.metric, "¥25,000.00")
        XCTAssertEqual(summary.items.first?.urgency, .high)
    }

    func testMakeSummaryReportsQuietState() {
        let rows = [
            row(name: "宽基 A", code: "000001", marketValue: 20_000, pendingAmount: 0, activePlans: 1, nextDate: "2026-06-12"),
            row(name: "宽基 B", code: "000002", marketValue: 20_000, pendingAmount: 0, activePlans: 0, nextDate: nil),
            row(name: "债券 C", code: "000003", marketValue: 20_000, pendingAmount: 0, activePlans: 0, nextDate: nil),
            row(name: "现金 D", code: "000004", marketValue: 20_000, pendingAmount: 0, activePlans: 0, nextDate: nil)
        ]
        let diagnostics = PortfolioDiagnosticsSummary.make(rows: rows)

        let summary = PortfolioReminderSummary.make(rows: rows, diagnostics: diagnostics)

        XCTAssertEqual(summary.headline, "1 项提醒")
        XCTAssertEqual(summary.items.map(\.kind), [.investmentPlan])
        XCTAssertEqual(summary.items.first?.urgency, .medium)
    }

    private func row(
        name: String,
        code: String,
        marketValue: Double,
        pendingAmount: Double,
        activePlans: Int,
        nextDate: String?
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
            costValue: nil,
            profitAmount: nil,
            profitPct: nil,
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
        let plans = (0..<activePlans).map { index in
            PersonalInvestmentPlan(
                planTypeLabel: "定投",
                fundName: name,
                fundCode: code,
                scheduleText: "每周三",
                amountText: "100.00",
                nextExecutionDate: nextDate ?? "2026-06-\(12 + index)",
                status: "进行中"
            )
        }
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
