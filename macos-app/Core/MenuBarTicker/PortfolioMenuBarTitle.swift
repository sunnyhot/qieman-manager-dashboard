import Foundation

enum PortfolioMenuBarTitle {
    static func fallback(
        totalEffectiveHoldingAmount: Double?,
        hasPersonalPortfolio: Bool,
        hasPendingTrades: Bool,
        hasInvestmentPlans: Bool,
        hasArchivedPortfolio: Bool
    ) -> String {
        if let total = totalEffectiveHoldingAmount, total > 0 {
            if total >= 10_000 {
                return String(format: "%.1f万", total / 10_000)
            }
            return String(format: "%.0f", total)
        }
        if hasPersonalPortfolio {
            return "持仓"
        }
        if hasPendingTrades {
            return "待确认"
        }
        if hasInvestmentPlans {
            return "计划"
        }
        return hasArchivedPortfolio ? "归档" : "未配置"
    }
}
