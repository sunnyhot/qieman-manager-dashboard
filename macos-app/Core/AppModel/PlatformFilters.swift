import Foundation

// MARK: - Platform Filter Computed Properties

extension AppModel {
    /// Filtered platform actions using the centralized filter state
    var filteredPlatformActions: [PlatformActionPayload] {
        var actions = platformPayload?.actions ?? []

        // Side filter (check if side string contains "buy")
        switch filterState.sideFilter {
        case .all: break
        case .buy:
            actions = actions.filter { ($0.side ?? "").lowercased().contains("buy") }
        case .sell:
            actions = actions.filter { !($0.side ?? "").lowercased().contains("buy") }
        }

        // Search filter using debounced value
        let query = filterState.debouncedSearchText
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        if !query.isEmpty {
            actions = actions.filter { action in
                (action.fundName ?? "").lowercased().contains(query)
                    || (action.fundCode ?? "").lowercased().contains(query)
                    || action.displayTitle.lowercased().contains(query)
                    || (action.adjustmentTitle ?? "").lowercased().contains(query)
            }
        }

        return actions
    }

    /// Per-side counts from payload (avoids repeated filtering)
    var platformActionCounts: (all: Int, buy: Int, sell: Int) {
        let all = platformPayload?.actions ?? []
        return (
            all: all.count,
            buy: platformPayload?.buyCount
                ?? all.filter { ($0.side ?? "").lowercased().contains("buy") }.count,
            sell: platformPayload?.sellCount
                ?? all.filter { !($0.side ?? "").lowercased().contains("buy") }.count
        )
    }

    /// Page-sliced filtered actions
    var paginatedPlatformActions: [PlatformActionPayload] {
        let filtered = filteredPlatformActions
        let start = filterState.currentPage * filterState.pageSize
        let end = min(start + filterState.pageSize, filtered.count)
        guard start < filtered.count else { return [] }
        return Array(filtered[start ..< end])
    }

    /// Total number of pages
    var totalPlatformPages: Int {
        let count = filteredPlatformActions.count
        return max(1, (count + filterState.pageSize - 1) / filterState.pageSize)
    }
}
