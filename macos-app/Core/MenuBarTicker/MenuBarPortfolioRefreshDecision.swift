import Foundation

enum MenuBarPortfolioRefreshAction: Equatable {
    case refreshPortfolio
    case refreshMarketIndicesIfNeeded
}

enum MenuBarPortfolioRefreshDecision {
    static func onAppear(
        hasPortfolioSnapshot: Bool,
        hasPersonalPortfolio: Bool,
        hasIncompletePortfolioValuation: Bool,
        lastPortfolioRefreshAt: Date?,
        now: Date = Date()
    ) -> [MenuBarPortfolioRefreshAction] {
        guard hasPersonalPortfolio else {
            return [.refreshMarketIndicesIfNeeded]
        }

        if !hasPortfolioSnapshot {
            return [.refreshPortfolio]
        }

        guard hasIncompletePortfolioValuation else {
            return [.refreshMarketIndicesIfNeeded]
        }

        if isFresh(lastPortfolioRefreshAt, now: now) {
            return [.refreshMarketIndicesIfNeeded]
        }

        return [.refreshPortfolio]
    }

    private static func isFresh(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) < RefreshDecision.portfolioFreshnessInterval
    }
}
