import Foundation

// MARK: - Platform Filter Computed Properties

extension AppModel {
    /// Filtered platform actions using the centralized filter state
    var filteredPlatformActions: [PlatformActionPayload] {
        var actions = platformPayload?.actions ?? []
        let telemetryStart = PerformanceTelemetry.start()
        let originalCount = actions.count
        defer {
            PerformanceTelemetry.record(
                "platform.actions.filter",
                startedAt: telemetryStart,
                metadata: [
                    "inputCount": "\(originalCount)",
                    "outputCount": "\(actions.count)",
                    "sideFilter": filterState.sideFilter.rawValue,
                    "hasQuery": "\(!filterState.debouncedSearchText.trimmingCharacters(in: .whitespaces).isEmpty)"
                ]
            )
        }

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
        let telemetryStart = PerformanceTelemetry.start()
        let filtered = filteredPlatformActions
        let start = filterState.currentPage * filterState.pageSize
        let end = min(start + filterState.pageSize, filtered.count)
        let pageActions: [PlatformActionPayload]
        if start < filtered.count {
            pageActions = Array(filtered[start ..< end])
        } else {
            pageActions = []
        }
        PerformanceTelemetry.record(
            "platform.actions.paginate",
            startedAt: telemetryStart,
            metadata: [
                "filteredCount": "\(filtered.count)",
                "page": "\(filterState.currentPage)",
                "pageSize": "\(filterState.pageSize)",
                "pageCount": "\(pageActions.count)"
            ]
        )
        return pageActions
    }

    /// Total number of pages
    var totalPlatformPages: Int {
        let count = filteredPlatformActions.count
        return max(1, (count + filterState.pageSize - 1) / filterState.pageSize)
    }
}
