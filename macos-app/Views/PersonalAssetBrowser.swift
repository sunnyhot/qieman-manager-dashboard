import SwiftUI

private struct PersonalAssetBrowserPresentation {
    let visibleRows: [PersonalAssetAggregateRow]
    let filterCounts: [PersonalAssetFilterScope: Int]
}

private struct PersonalAssetGroupStats {
    let latestTime: String?
    let totalMarketValue: Double
}

struct PersonalAssetBrowser: View {
    let rows: [PersonalAssetAggregateRow]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var filterScope: PersonalAssetFilterScope = .all
    @State private var sortOption: PersonalAssetSortOption = .defaultOption

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        let presentation = makePresentation(keyword: debouncedSearchText)

        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    browserSearchField
                    Spacer()
                    PersonalAssetAddButtons()
                    browserSortMenu
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        browserSearchField
                        browserSortMenu
                    }
                    PersonalAssetAddButtons()
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(PersonalAssetFilterScope.allCases) { scope in
                        filterChip(scope: scope, counts: presentation.filterCounts)
                    }
                }
                .padding(.vertical, 2)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(PersonalAssetFilterScope.allCases) { scope in
                        filterChip(scope: scope, counts: presentation.filterCounts)
                    }
                }
                .padding(.vertical, 2)
            }

            if presentation.visibleRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前筛选下没有标的。")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("可以试试切换筛选条件，或者清空搜索词。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            } else {
                PersonalAssetGroupedTable(rows: presentation.visibleRows)
            }
        }
        .task(id: searchText) {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private var browserSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppPalette.muted)
            TextField("搜索名称或代码", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
        )
        .frame(maxWidth: 320)
    }

    private var browserSortMenu: some View {
        Menu {
            ForEach(PersonalAssetSortOption.allCases) { option in
                Button {
                    sortOption = option
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("排序：\(sortOption.rawValue)", systemImage: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
    }

    private func filterChip(scope: PersonalAssetFilterScope, counts: [PersonalAssetFilterScope: Int]) -> some View {
        let isSelected = filterScope == scope
        let count = counts[scope, default: 0]
        return Button {
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                filterScope = scope
            }
        } label: {
            HStack(spacing: 8) {
                Text(scope.rawValue)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? AppPalette.onBrand.opacity(0.88) : AppPalette.muted)
            }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? AppPalette.onBrand : AppPalette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? AppPalette.brand : AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                        .stroke(isSelected ? AppPalette.brand.opacity(0.40) : AppPalette.line.opacity(0.42), lineWidth: 1)
                )
        }
        .buttonStyle(PressResponsiveButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: AppPalette.controlRadius))
    }

    private func makePresentation(keyword: String) -> PersonalAssetBrowserPresentation {
        var counts: [PersonalAssetFilterScope: Int] = [:]
        var visibleRows: [PersonalAssetAggregateRow] = []

        for row in rows {
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
            if matchesSearch(row, keyword: keyword) && filterScopeMatch(filterScope, row: row) {
                visibleRows.append(row)
            }
        }

        return PersonalAssetBrowserPresentation(
            visibleRows: PersonalAssetRowSorter.sorted(visibleRows, by: sortOption),
            filterCounts: counts
        )
    }

    private func matchesSearch(_ row: PersonalAssetAggregateRow, keyword: String) -> Bool {
        guard !keyword.isEmpty else { return true }
        return row.fundName.lowercased().contains(keyword)
            || (row.fundCode?.lowercased().contains(keyword) ?? false)
    }

    private func filterScopeMatch(_ scope: PersonalAssetFilterScope, row: PersonalAssetAggregateRow) -> Bool {
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

struct PersonalAssetGroupedTable: View {
    let offExchangeFundRows: [PersonalAssetAggregateRow]
    private let offExchangeFundStats: PersonalAssetGroupStats
    let onExchangeFundRows: [PersonalAssetAggregateRow]
    private let onExchangeFundStats: PersonalAssetGroupStats
    let stockRows: [PersonalAssetAggregateRow]
    private let stockStats: PersonalAssetGroupStats

    init(rows: [PersonalAssetAggregateRow]) {
        var offExchangeFundRows: [PersonalAssetAggregateRow] = []
        var onExchangeFundRows: [PersonalAssetAggregateRow] = []
        var stockRows: [PersonalAssetAggregateRow] = []

        for row in rows {
            if row.assetType == .stock {
                stockRows.append(row)
            } else if row.isOnExchangeFund {
                onExchangeFundRows.append(row)
            } else if row.assetType == .fund {
                offExchangeFundRows.append(row)
            }
        }

        self.offExchangeFundRows = offExchangeFundRows
        self.offExchangeFundStats = Self.groupStats(rows: offExchangeFundRows)
        self.onExchangeFundRows = onExchangeFundRows
        self.onExchangeFundStats = Self.groupStats(rows: onExchangeFundRows)
        self.stockRows = stockRows
        self.stockStats = Self.groupStats(rows: stockRows)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            if !offExchangeFundRows.isEmpty {
                group(title: "场外基金", rows: offExchangeFundRows, stats: offExchangeFundStats, tint: AppPalette.brand, usesMarketTradeColumns: false)
            }
            if !onExchangeFundRows.isEmpty {
                group(title: "场内基金", rows: onExchangeFundRows, stats: onExchangeFundStats, tint: AppPalette.accentWarm, usesMarketTradeColumns: true)
            }
            if !stockRows.isEmpty {
                group(title: "股票", rows: stockRows, stats: stockStats, tint: AppPalette.info, usesMarketTradeColumns: true)
            }
        }
    }

    private func group(title: String, rows: [PersonalAssetAggregateRow], stats: PersonalAssetGroupStats, tint: Color, usesMarketTradeColumns: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── Group header bar with colored accent ──
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 3, height: 18)

                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)

                ToolbarBadge(title: "\(rows.count) 只", tint: tint)

                Spacer()

                Text("市值 \(currencyText(stats.totalMarketValue))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)

                if let time = stats.latestTime {
                    Text("估值 \(time)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(tint.opacity(0.06))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(tint.opacity(0.18))
                    .frame(height: 1)
            }

            PersonalAssetTable(rows: rows, usesMarketTradeColumns: usesMarketTradeColumns)
        }
    }

    private static func groupStats(rows: [PersonalAssetAggregateRow]) -> PersonalAssetGroupStats {
        var latestTime: String?
        var totalMarketValue = 0.0

        for row in rows {
            totalMarketValue += row.marketValue ?? 0
            if let time = row.holdingRow?.resolvedPriceTime,
               latestTime.map({ time > $0 }) ?? true {
                latestTime = time
            }
        }

        return PersonalAssetGroupStats(latestTime: latestTime, totalMarketValue: totalMarketValue)
    }
}

struct PersonalAssetTable: View {
    let rows: [PersonalAssetAggregateRow]
    let usesMarketTradeColumns: Bool

    /// Compact threshold — below this width we switch to responsive column widths
    static let compactThreshold: CGFloat = 780

    init(rows: [PersonalAssetAggregateRow], usesMarketTradeColumns: Bool = false) {
        self.rows = rows
        self.usesMarketTradeColumns = usesMarketTradeColumns
    }

    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let isCompact = availableWidth < Self.compactThreshold

            ScrollView(.horizontal, showsIndicators: isCompact) {
                tableContent(availableWidth: availableWidth, isCompact: isCompact)
            }
        }
        .frame(minHeight: 44)
    }

    private var tableHeightEstimate: CGFloat {
        CGFloat(rows.count) * 80 + 44
    }

    // MARK: - Column widths adapt to available space

    private func valuationColWidth(isCompact: Bool) -> CGFloat {
        isCompact ? 200 : 260
    }

    private func unitsColWidth(isCompact: Bool) -> CGFloat {
        isCompact ? 80 : 100
    }

    private func priceColWidth(isCompact: Bool) -> CGFloat {
        isCompact ? 100 : 120
    }

    private func fifthColWidth(isCompact: Bool) -> CGFloat {
        isCompact ? 110 : 150
    }

    private func sixthColWidth(isCompact: Bool) -> CGFloat {
        isCompact ? 130 : 190
    }

    private func actionColWidth(isCompact: Bool) -> CGFloat {
        isCompact ? 40 : 52
    }

    @ViewBuilder
    private func tableContent(availableWidth: CGFloat, isCompact: Bool) -> some View {
        let colSpacing: CGFloat = isCompact ? 8 : 12
        let visibleColumnCount = isCompact ? 6 : 7
        let totalFixedWidth = valuationColWidth(isCompact: isCompact)
            + (isCompact ? 0 : unitsColWidth(isCompact: isCompact))
            + priceColWidth(isCompact: isCompact)
            + fifthColWidth(isCompact: isCompact)
            + sixthColWidth(isCompact: isCompact)
            + actionColWidth(isCompact: isCompact)
            + colSpacing * CGFloat(visibleColumnCount - 1)
            + 24              // horizontal padding (12*2)

        VStack(spacing: 0) {
            HStack(spacing: colSpacing) {
                Text("标的")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isCompact ? "估值/收益" : "实时估值 / 收益")
                    .frame(width: valuationColWidth(isCompact: isCompact), alignment: .leading)
                if !isCompact {
                    Text("持有份额")
                        .frame(width: unitsColWidth(isCompact: isCompact), alignment: .leading)
                }
                Text(isCompact ? "价格" : "现价 / 成本")
                    .frame(width: priceColWidth(isCompact: isCompact), alignment: .leading)
                if usesMarketTradeColumns {
                    Text("涨跌幅")
                        .frame(width: fifthColWidth(isCompact: isCompact), alignment: .leading)
                    Text("涨跌额")
                        .frame(width: sixthColWidth(isCompact: isCompact), alignment: .leading)
                } else {
                    Text("待确认")
                        .frame(width: fifthColWidth(isCompact: isCompact), alignment: .leading)
                    Text("计划档案")
                        .frame(width: sixthColWidth(isCompact: isCompact), alignment: .leading)
                }
                Text("操作")
                    .frame(width: actionColWidth(isCompact: isCompact), alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppPalette.line.opacity(0.42))
                    .frame(height: 1)
            }

            LazyVStack(spacing: 8) {
                ForEach(rows) { row in
                    PersonalAssetTableRow(
                        row: row,
                        isCompact: isCompact,
                        colSpacing: colSpacing,
                        valuationWidth: valuationColWidth(isCompact: isCompact),
                        unitsWidth: unitsColWidth(isCompact: isCompact),
                        priceWidth: priceColWidth(isCompact: isCompact),
                        fifthWidth: fifthColWidth(isCompact: isCompact),
                        sixthWidth: sixthColWidth(isCompact: isCompact),
                        actionWidth: actionColWidth(isCompact: isCompact)
                    )
                }
            }
            .padding(.top, 10)
        }
        .frame(minWidth: max(availableWidth, totalFixedWidth + 100))
    }
}

