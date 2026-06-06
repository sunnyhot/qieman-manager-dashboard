import Foundation

struct MonthlyReportSummary: Hashable {
    let title: String
    let monthText: String
    let generatedAt: String
    let markdown: String

    static func make(
        rows: [PersonalAssetAggregateRow],
        diagnostics: PortfolioDiagnosticsSummary,
        reminders: PortfolioReminderSummary,
        attribution: ProfitAttributionSummary,
        simulation: PlanSimulationSummary,
        generatedAt: String
    ) -> MonthlyReportSummary {
        let monthText = reportMonth(from: generatedAt)
        let title = "且慢主理人看板月报 \(monthText)"
        let totalMarketValue = rows.reduce(0) { $0 + ($1.marketValue ?? 0) }
        let totalPending = rows.reduce(0) { $0 + $1.pendingCashAmount }
        let totalNextPlan = rows.reduce(0) { $0 + $1.estimatedNextPlanAmount }
        let totalExposure = rows.reduce(0) { $0 + $1.effectiveHoldingAmount }
        let holdingCount = rows.filter(\.hasHolding).count

        var lines: [String] = [
            "# \(title)",
            "",
            "生成时间：\(generatedAt)",
            "",
            "## 组合概览",
            "- 覆盖标的：\(rows.count) 只",
            "- 已持有标的：\(holdingCount) 只",
            "- 实时市值：\(currencyText(totalMarketValue))",
            "- 待确认金额：\(currencyText(totalPending))",
            "- 下次计划金额：\(currencyText(totalNextPlan))",
            "- 总占用：\(currencyText(totalExposure))",
            "",
            "## 组合诊断",
            "- \(diagnostics.headline)"
        ]

        lines.append(contentsOf: diagnostics.items.prefix(5).map {
            "- \($0.title)：\($0.metric)，\($0.detail)"
        })

        lines.append(contentsOf: [
            "",
            "## 提醒通知"
        ])
        if reminders.items.isEmpty {
            lines.append("- 暂无待处理提醒")
        } else {
            lines.append(contentsOf: reminders.items.prefix(5).map {
                "- \($0.title)：\($0.metric)，\($0.detail)"
            })
        }

        lines.append(contentsOf: [
            "",
            "## 收益归因",
            "- \(attribution.headline)",
            "- 总收益：\(attribution.totalProfitText)",
            "- 总收益率：\(attribution.totalProfitRateText)"
        ])
        lines.append(contentsOf: attribution.entries.prefix(5).map {
            "- \($0.title)：\($0.amountText)，影响 \($0.impactShareText)"
        })

        lines.append(contentsOf: [
            "",
            "## 计划模拟",
            "- \(simulation.headline)",
            "- 单次计划：\(simulation.totalPerExecutionText)",
            "- 覆盖标的：\(simulation.activeAssetCount) 只"
        ])
        lines.append(contentsOf: simulation.items.prefix(5).map {
            "- \($0.title)：未来 \(simulation.executionCount) 次 \($0.projectedAmountText)，单次 \($0.perExecutionText)"
        })

        lines.append(contentsOf: [
            "",
            "## 重点标的"
        ])
        let focusRows = rows
            .sorted { left, right in
                if abs(left.effectiveHoldingAmount - right.effectiveHoldingAmount) > 0.001 {
                    return left.effectiveHoldingAmount > right.effectiveHoldingAmount
                }
                return left.fundName.localizedStandardCompare(right.fundName) == .orderedAscending
            }
            .prefix(6)
        if focusRows.isEmpty {
            lines.append("- 等待资产数据")
        } else {
            lines.append(contentsOf: focusRows.map { row in
                let codeText = row.fundCode?.isEmpty == false ? "（\(row.fundCode!)）" : ""
                return "- \(row.fundName)\(codeText)：占用 \(currencyText(row.effectiveHoldingAmount, market: row.detectedMarket))，收益 \(signedCurrencyText(row.profitAmount, market: row.detectedMarket))，今日 \(signedCurrencyText(row.estimateChangeAmount, market: row.detectedMarket))"
            })
        }

        return MonthlyReportSummary(
            title: title,
            monthText: monthText,
            generatedAt: generatedAt,
            markdown: lines.joined(separator: "\n")
        )
    }

    private static func reportMonth(from generatedAt: String) -> String {
        guard generatedAt.count >= 7 else { return "本月" }
        let prefix = String(generatedAt.prefix(7))
        guard prefix.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil else {
            return "本月"
        }
        return prefix
    }
}

extension AppModel {
    var monthlyReportSummary: MonthlyReportSummary {
        MonthlyReportSummary.make(
            rows: personalAssetRows,
            diagnostics: portfolioDiagnosticsSummary,
            reminders: portfolioReminderSummary,
            attribution: profitAttributionSummary,
            simulation: planSimulationSummary,
            generatedAt: Self.timestampString()
        )
    }
}
