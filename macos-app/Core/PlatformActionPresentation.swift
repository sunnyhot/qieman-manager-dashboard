import Foundation

struct PlatformActionCounts: Equatable {
    let all: Int
    let buy: Int
    let sell: Int

    static func make(
        actions: [PlatformActionPayload],
        buyCount: Int?,
        sellCount: Int?
    ) -> PlatformActionCounts {
        if let buyCount, let sellCount {
            return PlatformActionCounts(all: actions.count, buy: buyCount, sell: sellCount)
        }
        let computedBuyCount = actions.filter { PlatformActionPresentation.isBuy($0) }.count
        return PlatformActionCounts(
            all: actions.count,
            buy: buyCount ?? computedBuyCount,
            sell: sellCount ?? actions.count - computedBuyCount
        )
    }
}

struct PlatformActionPresentation: Equatable {
    let counts: PlatformActionCounts
    let filteredActions: [PlatformActionPayload]
    let pageActions: [PlatformActionPayload]
    let totalPages: Int
    let currentPage: Int

    static func make(
        actions: [PlatformActionPayload],
        sideFilter: PlatformSideFilter,
        searchText: String,
        currentPage: Int,
        pageSize: Int,
        buyCount: Int? = nil,
        sellCount: Int? = nil
    ) -> PlatformActionPresentation {
        let counts = PlatformActionCounts.make(actions: actions, buyCount: buyCount, sellCount: sellCount)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = filteredActions(actions: actions, sideFilter: sideFilter, query: query)

        let safePageSize = max(1, pageSize)
        let totalPages = max(1, (filtered.count + safePageSize - 1) / safePageSize)
        let clampedPage = min(max(0, currentPage), totalPages - 1)
        let start = clampedPage * safePageSize
        let end = min(start + safePageSize, filtered.count)
        let pageActions = start < filtered.count ? Array(filtered[start ..< end]) : []

        return PlatformActionPresentation(
            counts: counts,
            filteredActions: filtered,
            pageActions: pageActions,
            totalPages: totalPages,
            currentPage: clampedPage
        )
    }

    static func isBuy(_ action: PlatformActionPayload) -> Bool {
        (action.side ?? "").lowercased().contains("buy")
    }

    private static func filteredActions(
        actions: [PlatformActionPayload],
        sideFilter: PlatformSideFilter,
        query: String
    ) -> [PlatformActionPayload] {
        guard sideFilter != .all || !query.isEmpty else {
            return actions
        }
        return actions.filter { action in
            switch sideFilter {
            case .all:
                break
            case .buy:
                guard isBuy(action) else { return false }
            case .sell:
                guard !isBuy(action) else { return false }
            }
            guard !query.isEmpty else { return true }
            return (action.fundName ?? "").lowercased().contains(query)
                || (action.fundCode ?? "").lowercased().contains(query)
                || action.displayTitle.lowercased().contains(query)
                || (action.adjustmentTitle ?? "").lowercased().contains(query)
        }
    }
}
