import Foundation

struct PersonalAssetBrowserPresentationModel: Equatable {
    let visibleRows: [PersonalAssetAggregateRow]
    let filterCounts: [PersonalAssetFilterScope: Int]
    let comparisonSummary: PersonalAssetComparisonSummary
    let validComparisonSelection: [String]

    static func make(
        rows: [PersonalAssetAggregateRow],
        keyword: String,
        filterScope: PersonalAssetFilterScope,
        sortOption: PersonalAssetSortOption,
        comparisonSelection: [String],
        comparisonMaxCount: Int
    ) -> PersonalAssetBrowserPresentationModel {
        let normalizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var counts: [PersonalAssetFilterScope: Int] = [:]
        var visibleRows: [PersonalAssetAggregateRow] = []

        for row in rows {
            incrementCounts(for: row, counts: &counts)
            if matchesSearch(row, keyword: normalizedKeyword) && filterScopeMatch(filterScope, row: row) {
                visibleRows.append(row)
            }
        }

        let sortedVisibleRows = PersonalAssetRowSorter.sorted(visibleRows, by: sortOption)
        let validIDs = Set(rows.map(\.id))
        let validSelection = comparisonSelection.filter { validIDs.contains($0) }
        let comparisonSummary = PersonalAssetComparisonSummary.make(
            rows: rows,
            selectedIDs: validSelection,
            maxCount: comparisonMaxCount
        )

        return PersonalAssetBrowserPresentationModel(
            visibleRows: sortedVisibleRows,
            filterCounts: counts,
            comparisonSummary: comparisonSummary,
            validComparisonSelection: validSelection
        )
    }

    private static func incrementCounts(
        for row: PersonalAssetAggregateRow,
        counts: inout [PersonalAssetFilterScope: Int]
    ) {
        counts[.all, default: 0] += 1
        if row.hasHolding {
            counts[.holding, default: 0] += 1
        }
        if row.hasArchivedHolding {
            counts[.archivedHolding, default: 0] += 1
        }
        if row.hasPending {
            counts[.pending, default: 0] += 1
        }
        if row.activePlanCount > 0 {
            counts[.activePlan, default: 0] += 1
        }
        if row.pausedPlanCount > 0 || row.endedPlanCount > 0 {
            counts[.archivedPlan, default: 0] += 1
        }
        if row.hasDrawdownPlan {
            counts[.drawdownMode, default: 0] += 1
        }
    }

    private static func matchesSearch(_ row: PersonalAssetAggregateRow, keyword: String) -> Bool {
        guard !keyword.isEmpty else { return true }
        return row.fundName.lowercased().contains(keyword)
            || (row.fundCode?.lowercased().contains(keyword) ?? false)
    }

    private static func filterScopeMatch(_ scope: PersonalAssetFilterScope, row: PersonalAssetAggregateRow) -> Bool {
        switch scope {
        case .all:
            return true
        case .holding:
            return row.hasHolding
        case .archivedHolding:
            return row.hasArchivedHolding
        case .pending:
            return row.hasPending
        case .activePlan:
            return row.activePlanCount > 0
        case .archivedPlan:
            return row.pausedPlanCount > 0 || row.endedPlanCount > 0
        case .drawdownMode:
            return row.hasDrawdownPlan
        }
    }
}
