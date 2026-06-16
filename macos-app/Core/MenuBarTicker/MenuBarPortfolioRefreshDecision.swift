import Foundation

enum MenuBarPortfolioRefreshAction: Equatable {
    case refreshPortfolio
    case refreshMarketIndicesIfNeeded
}

enum MenuBarPortfolioRefreshDecision {
    static func onAppear(
        hasPortfolioSnapshot: Bool,
        hasPersonalPortfolio: Bool
    ) -> [MenuBarPortfolioRefreshAction] {
        if hasPersonalPortfolio, !hasPortfolioSnapshot {
            return [.refreshPortfolio]
        }
        return [.refreshMarketIndicesIfNeeded]
    }
}
