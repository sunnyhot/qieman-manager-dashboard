import Foundation

enum PersonalAssetRowSorter {
    static func sorted(
        _ rows: [PersonalAssetAggregateRow],
        by sortOption: PersonalAssetSortOption
    ) -> [PersonalAssetAggregateRow] {
        rows.sorted { left, right in
            compare(left, right, by: sortOption)
        }
    }

    static func compare(
        _ left: PersonalAssetAggregateRow,
        _ right: PersonalAssetAggregateRow,
        by sortOption: PersonalAssetSortOption
    ) -> Bool {
        switch sortOption {
        case .dailyChange:
            if let ordered = compareOptionalDescending(left.estimateChangeAmount, right.estimateChangeAmount) {
                return ordered
            }
        case .dailyChangePct:
            if let ordered = compareOptionalDescending(left.estimateChangePct, right.estimateChangePct) {
                return ordered
            }
        case .exposure:
            if abs(left.effectiveHoldingAmount - right.effectiveHoldingAmount) > 0.001 {
                return left.effectiveHoldingAmount > right.effectiveHoldingAmount
            }
        case .marketValue:
            if abs((left.marketValue ?? 0) - (right.marketValue ?? 0)) > 0.001 {
                return (left.marketValue ?? 0) > (right.marketValue ?? 0)
            }
        case .pendingAmount:
            if abs(left.pendingCashAmount - right.pendingCashAmount) > 0.001 {
                return left.pendingCashAmount > right.pendingCashAmount
            }
        case .nextExecution:
            let leftDate = sortableExecutionDate(left.nextExecutionDate)
            let rightDate = sortableExecutionDate(right.nextExecutionDate)
            switch (leftDate, rightDate) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs < rhs
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                break
            }
        case .planCumulative:
            if abs(left.totalCumulativePlanAmount - right.totalCumulativePlanAmount) > 0.001 {
                return left.totalCumulativePlanAmount > right.totalCumulativePlanAmount
            }
        case .name:
            let result = left.fundName.localizedStandardCompare(right.fundName)
            if result != .orderedSame {
                return result == .orderedAscending
            }
        }

        return left.fundName.localizedStandardCompare(right.fundName) == .orderedAscending
    }

    private static func compareOptionalDescending(_ left: Double?, _ right: Double?) -> Bool? {
        switch (left, right) {
        case let (lhs?, rhs?):
            if abs(lhs - rhs) > 0.001 {
                return lhs > rhs
            }
            return nil
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return nil
        }
    }

    private static func sortableExecutionDate(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(10))
    }
}
