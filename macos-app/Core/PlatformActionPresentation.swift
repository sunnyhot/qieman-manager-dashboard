import Foundation

struct PlatformActionCounts: Equatable {
    let all: Int
    let buy: Int
    let sell: Int
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
        let computedBuyCount = actions.filter { isBuy($0) }.count
        let computedSellCount = actions.count - computedBuyCount
        let counts = PlatformActionCounts(
            all: actions.count,
            buy: buyCount ?? computedBuyCount,
            sell: sellCount ?? computedSellCount
        )

        var filtered = actions
        switch sideFilter {
        case .all:
            break
        case .buy:
            filtered = filtered.filter { isBuy($0) }
        case .sell:
            filtered = filtered.filter { !isBuy($0) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            filtered = filtered.filter { action in
                (action.fundName ?? "").lowercased().contains(query)
                    || (action.fundCode ?? "").lowercased().contains(query)
                    || action.displayTitle.lowercased().contains(query)
                    || (action.adjustmentTitle ?? "").lowercased().contains(query)
            }
        }

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

    private static func isBuy(_ action: PlatformActionPayload) -> Bool {
        (action.side ?? "").lowercased().contains("buy")
    }
}
