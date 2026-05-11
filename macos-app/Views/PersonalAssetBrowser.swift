import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

private struct PersonalAssetBrowserPresentation {
    let visibleRows: [PersonalAssetAggregateRow]
    let filterCounts: [PersonalAssetFilterScope: Int]
}

struct PersonalAssetBrowser: View {
    let rows: [PersonalAssetAggregateRow]

    @State private var searchText = ""
    @State private var filterScope: PersonalAssetFilterScope = .all
    @State private var sortOption: PersonalAssetSortOption = .defaultOption

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        let presentation = makePresentation()

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
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

                Spacer()

                PersonalAssetAddButtons()

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

    private func makePresentation() -> PersonalAssetBrowserPresentation {
        let keyword = normalizedSearchText
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
    let onExchangeFundRows: [PersonalAssetAggregateRow]
    let stockRows: [PersonalAssetAggregateRow]

    init(rows: [PersonalAssetAggregateRow]) {
        self.offExchangeFundRows = rows.filter { $0.assetType == .fund && !$0.isOnExchangeFund }
        self.onExchangeFundRows = rows.filter(\.isOnExchangeFund)
        self.stockRows = rows.filter { $0.assetType == .stock }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !offExchangeFundRows.isEmpty {
                group(title: "场外基金", rows: offExchangeFundRows, tint: AppPalette.brand, usesMarketTradeColumns: false)
            }
            if !onExchangeFundRows.isEmpty {
                group(title: "场内基金", rows: onExchangeFundRows, tint: AppPalette.accentWarm, usesMarketTradeColumns: true)
            }
            if !stockRows.isEmpty {
                group(title: "股票", rows: stockRows, tint: AppPalette.info, usesMarketTradeColumns: true)
            }
        }
    }

    private func group(title: String, rows: [PersonalAssetAggregateRow], tint: Color, usesMarketTradeColumns: Bool) -> some View {
        let latestTime = rows.compactMap(\.holdingRow?.resolvedPriceTime).max()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                ToolbarBadge(title: "\(rows.count) 只", tint: tint)
                Text("市值 \(currencyText(rows.compactMap(\.marketValue).reduce(0, +)))")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                if let time = latestTime {
                    Text("估值 \(time)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted.opacity(0.7))
                }
            }
            PersonalAssetTable(rows: rows, usesMarketTradeColumns: usesMarketTradeColumns)
        }
    }
}

struct PersonalAssetTable: View {
    let rows: [PersonalAssetAggregateRow]
    let usesMarketTradeColumns: Bool

    init(rows: [PersonalAssetAggregateRow], usesMarketTradeColumns: Bool = false) {
        self.rows = rows
        self.usesMarketTradeColumns = usesMarketTradeColumns
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("标的")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("实时估值 / 收益")
                    .frame(width: 260, alignment: .leading)
                Text("持有份额")
                    .frame(width: 100, alignment: .leading)
                Text("现价 / 成本")
                    .frame(width: 120, alignment: .leading)
                if usesMarketTradeColumns {
                    Text("涨跌幅")
                        .frame(width: 150, alignment: .leading)
                    Text("涨跌额")
                        .frame(width: 190, alignment: .leading)
                } else {
                    Text("待确认")
                        .frame(width: 150, alignment: .leading)
                    Text("计划档案")
                        .frame(width: 190, alignment: .leading)
                }
                Text("操作")
                    .frame(width: 52, alignment: .trailing)
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

            VStack(spacing: 8) {
                ForEach(rows) { row in
                    PersonalAssetTableRow(row: row)
                }
            }
            .padding(.top, 10)
        }
    }
}

struct PersonalAssetTableRow: View {
    @EnvironmentObject private var model: AppModel

    let row: PersonalAssetAggregateRow

    @State private var pendingDeleteScope: PersonalAssetDeleteScope?
    @State private var pendingUnitAdjustmentMode: PersonalAssetUnitAdjustmentMode?
    @State private var isPresentingHoldingEditor = false
    @State private var isPresentingPlanManager = false

    private var profitTint: Color {
        AppPalette.marketTint(for: row.profitAmount)
    }

    private var changeTint: Color {
        AppPalette.marketTint(for: row.estimateChangeAmount)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.fundName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    if let marketLabel = row.rawHolding?.marketLabel ?? row.holdingRow?.holding.marketLabel ?? row.archivedHolding?.marketLabel {
                        ToolbarBadge(title: marketLabel, tint: AppPalette.info)
                    }
                    ToolbarBadge(title: row.combinedStatusText, tint: row.hasPending ? AppPalette.warning : (row.hasArchivedHolding && !row.hasHolding ? AppPalette.muted : AppPalette.brand))
                    if row.hasDrawdownPlan {
                        ToolbarBadge(title: "涨跌幅 \(row.drawdownPlanCount)", tint: AppPalette.info)
                    }
                }
                HStack(spacing: 8) {
                    if let fundCode = row.fundCode, !fundCode.isEmpty {
                        Text(fundCode)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    if row.pendingTradeCount > 0, let latest = row.pendingTrades.first?.occurredAt {
                        Text("最新待确认 \(latest)")
                    }
                    if row.hasDrawdownPlan {
                        Text("含 \(row.drawdownPlanCount) 条涨跌幅计划")
                    }
                    if let archivedAt = row.archivedHolding?.archivedAt {
                        Text("归档 \(archivedAt.prefix(10))")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.marketValue.map { currencyText($0, market: row.detectedMarket) } ?? "—")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text("总收益 \(signedCurrencyText(row.profitAmount, market: row.detectedMarket)) · \(percentOptional(row.profitPct))")
                    .font(.system(size: 10))
                    .foregroundStyle(profitTint)
                Text("今日涨跌 \(signedCurrencyText(row.estimateChangeAmount, market: row.detectedMarket)) · \(percentOptional(row.estimateChangePct))")
                    .font(.system(size: 10))
                    .foregroundStyle(changeTint)
            }
            .frame(width: 260, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(unitsColumnValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                if let unitsColumnCaption {
                    Text(unitsColumnCaption)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
            }
            .frame(width: 100, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(row.usesMarketTradeColumns ? "现价" : "净值") \(row.currentPrice.map(decimalText) ?? "—")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                if let estimatePrice = row.currentEstimatePrice {
                    Text("估值 \(decimalText(estimatePrice)) · \(percentOptional(row.estimateChangePct))")
                        .font(.system(size: 10))
                        .foregroundStyle(changeTint)
                }
                Text("成本 \(row.costPrice.map(decimalText) ?? "—")")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
            }
            .frame(width: 120, alignment: .leading)

            if row.usesMarketTradeColumns {
                Group {
                    if let changePct = row.estimateChangePct {
                        Text(String(format: "%+.2f%%", changePct))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.marketTint(for: changePct))
                    } else {
                        Text("—")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                    }
                }
                .frame(width: 150, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if row.pendingTradeCount > 0 {
                        Text(row.pendingCashAmount > 0 ? currencyText(row.pendingCashAmount, market: row.detectedMarket) : "\(unitsText(row.pendingUnitAmount)) 份")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                        Text("\(row.pendingTradeCount) 笔 · \(row.pendingTrades.first?.actionLabel ?? "待确认")")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                    } else {
                        Text("—")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                        Text("暂无")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
                .frame(width: 150, alignment: .leading)
            }

            if row.usesMarketTradeColumns {
                Group {
                    if let changeAmt = row.estimateChangeAmount {
                        Text(signedCurrencyText(changeAmt, market: row.detectedMarket))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.marketTint(for: changeAmt))
                    } else {
                        Text("—")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                    }
                }
                .frame(width: 190, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                if row.totalPlanCount > 0 {
                    Text("进行中 \(row.activePlanCount) · 暂停 \(row.pausedPlanCount) · 终止 \(row.endedPlanCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("下次估算 \(currencyText(row.estimatedNextPlanAmount, market: row.detectedMarket)) · 累计 \(currencyText(row.totalCumulativePlanAmount, market: row.detectedMarket))\(row.hasDrawdownPlan ? " · 涨跌幅 \(row.drawdownPlanCount)" : "")")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                } else {
                    Text("—")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("暂无")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
            }
            .frame(width: 190, alignment: .leading)
            }

            HStack {
                Spacer()
                if hasRowActions {
                    actionMenu
                }
            }
            .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.line.opacity(0.28), lineWidth: 1)
        )
        .alert(deleteConfirmationTitle, isPresented: deleteConfirmationBinding) {
            Button("删除", role: .destructive) {
                if let pendingDeleteScope {
                    model.deletePersonalAssetEntry(row, scope: pendingDeleteScope)
                }
                pendingDeleteScope = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteScope = nil
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .sheet(item: $pendingUnitAdjustmentMode) { mode in
            PersonalAssetUnitAdjustmentSheet(row: row, mode: mode) { unitsText, unitNetValueText in
                model.adjustPersonalAssetHoldingUnits(
                    row,
                    mode: mode,
                    unitsText: unitsText,
                    unitNetValueText: unitNetValueText
                )
            }
        }
        .sheet(isPresented: $isPresentingHoldingEditor) {
            PersonalAssetEditHoldingSheet(row: row)
        }
        .sheet(isPresented: $isPresentingPlanManager) {
            PersonalInvestmentPlanManagementSheet(row: row)
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteScope != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteScope = nil
                }
            }
        )
    }

    private var sourceDeleteScopes: [PersonalAssetDeleteScope] {
        var scopes: [PersonalAssetDeleteScope] = []
        if row.rawHolding != nil || row.holdingRow != nil {
            scopes.append(.holding)
        } else if row.archivedHolding != nil {
            scopes.append(.holding)
        }
        if !row.pendingTrades.isEmpty {
            scopes.append(.pendingTrades)
        }
        if !row.plans.isEmpty {
            scopes.append(.investmentPlans)
        }
        return scopes
    }

    private var canAddHoldingUnits: Bool {
        guard let fundCode = row.fundCode else { return false }
        return !fundCode.isEmpty
    }

    private var canEditHolding: Bool {
        row.rawHolding != nil || row.holdingRow != nil
    }

    private var canArchiveHolding: Bool {
        canEditHolding
    }

    private var canRestoreArchivedHolding: Bool {
        row.archivedHolding != nil && !row.hasHolding
    }

    private var canRemoveHoldingUnits: Bool {
        (row.holdingUnits ?? 0) > 0 && (row.rawHolding != nil || row.holdingRow != nil)
    }

    private var canArchivePlans: Bool {
        row.totalPlanCount > 0
    }

    private var hasRowActions: Bool {
        canEditHolding || canArchiveHolding || canRestoreArchivedHolding || canAddHoldingUnits || canRemoveHoldingUnits || canArchivePlans || !sourceDeleteScopes.isEmpty
    }

    private var unitsColumnValue: String {
        if let holdingUnits = row.holdingUnits {
            return unitsText(holdingUnits)
        }
        if let archivedUnits = row.archivedHolding?.units {
            return unitsText(archivedUnits)
        }
        return "—"
    }

    private var unitsColumnCaption: String? {
        if row.holdingUnits != nil {
            return "持有份额"
        }
        if row.archivedHolding != nil {
            return "归档份额"
        }
        return nil
    }

    private var actionMenu: some View {
        Menu {
            if canEditHolding {
                Button {
                    isPresentingHoldingEditor = true
                } label: {
                    Label("编辑持仓", systemImage: "square.and.pencil")
                }
            }

            if canAddHoldingUnits {
                Button {
                    pendingUnitAdjustmentMode = .add
                } label: {
                    Label("添加份额", systemImage: "plus.circle")
                }
            }

            if canRemoveHoldingUnits {
                Button {
                    pendingUnitAdjustmentMode = .remove
                } label: {
                    Label("删除份额", systemImage: "minus.circle")
                }
            }

            if canArchiveHolding {
                Button {
                    model.archivePersonalAssetHolding(row)
                } label: {
                    Label("归档持仓", systemImage: "archivebox")
                }
            }

            if canRestoreArchivedHolding {
                Button {
                    model.restorePersonalAssetHolding(row)
                } label: {
                    Label("恢复归档持仓", systemImage: "arrow.uturn.backward.circle")
                }
            }

            if (canEditHolding || canAddHoldingUnits || canRemoveHoldingUnits || canArchiveHolding || canRestoreArchivedHolding) && canArchivePlans {
                Divider()
            }

            if canArchivePlans {
                Button {
                    isPresentingPlanManager = true
                } label: {
                    Label("管理定投计划", systemImage: "calendar.badge.clock")
                }

                if row.activePlanCount > 0 {
                    Button {
                        model.updateInvestmentPlansStatus(row, status: "已暂停", activeOnly: true)
                    } label: {
                        Label("暂停进行中计划", systemImage: "pause.circle")
                    }
                    Button {
                        model.updateInvestmentPlansStatus(row, status: "已终止", activeOnly: true)
                    } label: {
                        Label("终止进行中计划", systemImage: "archivebox")
                    }
                }
                if row.pausedPlanCount > 0 || row.endedPlanCount > 0 {
                    Button {
                        model.updateInvestmentPlansStatus(row, status: "进行中", archivedOnly: true)
                    } label: {
                        Label("恢复归档计划", systemImage: "arrow.uturn.backward.circle")
                    }
                }
            }

            if (canAddHoldingUnits || canRemoveHoldingUnits || canArchiveHolding || canRestoreArchivedHolding || canArchivePlans) && !sourceDeleteScopes.isEmpty {
                Divider()
            }

            ForEach(sourceDeleteScopes) { scope in
                Button(role: .destructive) {
                    pendingDeleteScope = scope
                } label: {
                    Label(deleteTitle(for: scope), systemImage: deleteIcon(for: scope))
                }
            }

            if sourceDeleteScopes.count > 1 {
                Divider()
                Button(role: .destructive) {
                    pendingDeleteScope = .all
                } label: {
                    Label(deleteTitle(for: .all), systemImage: deleteIcon(for: .all))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(AppPalette.brand)
            .frame(width: 42, height: 28)
            .background(AppPalette.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("调整条目")
    }

    private var deleteConfirmationTitle: String {
        guard let pendingDeleteScope else { return "删除条目" }
        return "\(deleteTitle(for: pendingDeleteScope))？"
    }

    private var deleteConfirmationMessage: String {
        guard let pendingDeleteScope else { return "" }
        let itemText = row.fundCode.map { "\(row.fundName)（\($0)）" } ?? row.fundName
        return "会从本地保存的数据中删除 \(itemText) 的\(deleteDescription(for: pendingDeleteScope))。这个操作不会影响且慢账户。"
    }

    private func deleteTitle(for scope: PersonalAssetDeleteScope) -> String {
        switch scope {
        case .holding:
            return row.hasArchivedHolding && !row.hasHolding ? "删除归档持仓" : "删除已持有"
        case .pendingTrades:
            return row.pendingTradeCount > 1 ? "删除买入中 \(row.pendingTradeCount) 条" : "删除买入中"
        case .investmentPlans:
            return row.totalPlanCount > 1 ? "删除计划档案 \(row.totalPlanCount) 条" : "删除计划档案"
        case .all:
            return "删除整条明细"
        }
    }

    private func deleteDescription(for scope: PersonalAssetDeleteScope) -> String {
        switch scope {
        case .holding:
            return row.hasArchivedHolding && !row.hasHolding ? "归档持仓记录" : "已持有记录"
        case .pendingTrades:
            return row.pendingTradeCount > 1 ? "\(row.pendingTradeCount) 条买入中记录" : "买入中记录"
        case .investmentPlans:
            return row.totalPlanCount > 1 ? "\(row.totalPlanCount) 条计划档案" : "计划档案"
        case .all:
            return "所有本地明细记录"
        }
    }

    private func deleteIcon(for scope: PersonalAssetDeleteScope) -> String {
        switch scope {
        case .holding:
            return "briefcase"
        case .pendingTrades:
            return "clock"
        case .investmentPlans:
            return "calendar"
        case .all:
            return "trash"
        }
    }
}

struct PersonalPendingTradeEditSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let trade: PersonalPendingTrade?

    @State private var occurredAtText: String
    @State private var actionText: String
    @State private var fundNameText: String
    @State private var fundCodeText: String
    @State private var targetFundNameText: String
    @State private var targetFundCodeText: String
    @State private var amountText: String
    @State private var statusText: String
    @State private var noteText: String

    init(trade: PersonalPendingTrade? = nil) {
        self.trade = trade
        _occurredAtText = State(initialValue: trade?.occurredAt ?? "")
        _actionText = State(initialValue: trade?.actionLabel ?? "买入")
        _fundNameText = State(initialValue: trade?.fundName ?? "")
        _fundCodeText = State(initialValue: trade?.fundCode ?? "")
        _targetFundNameText = State(initialValue: trade?.targetFundName ?? "")
        _targetFundCodeText = State(initialValue: trade?.targetFundCode ?? "")
        _amountText = State(initialValue: trade?.amountText ?? "")
        _statusText = State(initialValue: trade?.status ?? "交易进行中")
        _noteText = State(initialValue: trade?.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trade == nil ? "添加买入中" : "修改买入中")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text("记录待确认买入、定投或转换，后续可继续修改或删除。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 10) {
                formField("发生时间", text: $occurredAtText, placeholder: "留空则使用当前时间")
                formField("动作", text: $actionText, placeholder: "买入 / 定投 / 转换")
                formField("基金名称", text: $fundNameText, placeholder: "可填名称或只填代码")
                formField("基金代码", text: $fundCodeText, placeholder: "例如 019524")
                formField("目标名称", text: $targetFundNameText, placeholder: "转换目标，可留空")
                formField("目标代码", text: $targetFundCodeText, placeholder: "转换目标代码，可留空")
                formField("金额/份额", text: $amountText, placeholder: "例如 10元 或 100份")
                formField("状态", text: $statusText, placeholder: "交易进行中")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("备注")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                TextField("可留空", text: $noteText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                            .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(trade == nil ? "添加" : "保存") {
                    let didSave: Bool
                    if let trade {
                        didSave = model.updatePendingTrade(
                            trade.id,
                            occurredAt: occurredAtText,
                            actionLabel: actionText,
                            fundName: fundNameText,
                            fundCode: fundCodeText,
                            targetFundName: targetFundNameText,
                            targetFundCode: targetFundCodeText,
                            amountText: amountText,
                            status: statusText,
                            note: noteText
                        )
                    } else {
                        didSave = model.addPendingTrade(
                            occurredAt: occurredAtText,
                            actionLabel: actionText,
                            fundName: fundNameText,
                            fundCode: fundCodeText,
                            targetFundName: targetFundNameText,
                            targetFundCode: targetFundCodeText,
                            amountText: amountText,
                            status: statusText,
                            note: noteText
                        )
                    }
                    if didSave {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.warning)
            }
        }
        .padding(18)
        .frame(width: 620)
    }

    private func formField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
        }
    }
}

private enum PersonalInvestmentPlanStatusOption: String, CaseIterable, Identifiable {
    case active = "进行中"
    case paused = "已暂停"
    case ended = "已终止"

    var id: String { rawValue }

    init(status: String) {
        if status.contains("终止") {
            self = .ended
        } else if status.contains("暂停") {
            self = .paused
        } else {
            self = .active
        }
    }

    var tint: Color {
        switch self {
        case .active:
            return AppPalette.positive
        case .paused:
            return AppPalette.warning
        case .ended:
            return AppPalette.muted
        }
    }
}

struct PersonalInvestmentPlanManagementSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let row: PersonalAssetAggregateRow

    @State private var editingPlan: PersonalInvestmentPlan?
    @State private var deletingPlan: PersonalInvestmentPlan?

    private let planIDs: Set<UUID>

    init(row: PersonalAssetAggregateRow) {
        self.row = row
        self.planIDs = Set(row.plans.map(\.id))
    }

    private var plans: [PersonalInvestmentPlan] {
        model.investmentPlans
            .filter { planIDs.contains($0.id) }
            .sorted(by: comparePlans)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text("管理定投计划")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text(row.fundCode.map { "\(row.fundName)（\($0)）" } ?? row.fundName)
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            if plans.isEmpty {
                Text("这条资产当前没有定投计划。")
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(plans) { plan in
                            PersonalInvestmentPlanManageRow(
                                plan: plan,
                                onEdit: { editingPlan = plan },
                                onStatusChange: { status in
                                    model.updateInvestmentPlanStatus(plan.id, status: status.rawValue)
                                },
                                onDelete: { deletingPlan = plan }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 520)
            }
        }
        .padding(18)
        .frame(width: 720)
        .frame(minHeight: 360)
        .sheet(item: $editingPlan) { plan in
            PersonalInvestmentPlanEditSheet(plan: plan)
        }
        .alert("删除定投计划？", isPresented: deleteConfirmationBinding) {
            Button("删除", role: .destructive) {
                if let deletingPlan {
                    model.deleteInvestmentPlan(deletingPlan.id)
                }
                deletingPlan = nil
            }
            Button("取消", role: .cancel) {
                deletingPlan = nil
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletingPlan != nil },
            set: { isPresented in
                if !isPresented {
                    deletingPlan = nil
                }
            }
        )
    }

    private var deleteConfirmationMessage: String {
        guard let deletingPlan else { return "" }
        let itemText = deletingPlan.fundCode.map { "\(deletingPlan.fundName)（\($0)）" } ?? deletingPlan.fundName
        return "会从本地保存的数据中删除 \(itemText) 的这条定投计划。这个操作不会影响支付宝或且慢账户。"
    }

    private func comparePlans(_ lhs: PersonalInvestmentPlan, _ rhs: PersonalInvestmentPlan) -> Bool {
        let lhsRank = statusRank(lhs)
        let rhsRank = statusRank(rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.nextExecutionDate != rhs.nextExecutionDate {
            return lhs.nextExecutionDate < rhs.nextExecutionDate
        }
        return lhs.fundName.localizedStandardCompare(rhs.fundName) == .orderedAscending
    }

    private func statusRank(_ plan: PersonalInvestmentPlan) -> Int {
        if plan.isActivePlan { return 0 }
        if plan.isPausedPlan { return 1 }
        return 2
    }
}

private struct PersonalInvestmentPlanManageRow: View {
    let plan: PersonalInvestmentPlan
    let onEdit: () -> Void
    let onStatusChange: (PersonalInvestmentPlanStatusOption) -> Void
    let onDelete: () -> Void

    private var statusOption: PersonalInvestmentPlanStatusOption {
        PersonalInvestmentPlanStatusOption(status: plan.normalizedStatus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.planTypeLabel)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(plan.isDrawdownMode ? AppPalette.info : AppPalette.brand)
                        Text(plan.fundName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                            .lineLimit(1)
                        ToolbarBadge(title: plan.normalizedStatus, tint: statusOption.tint)
                        if plan.isDrawdownMode {
                            ToolbarBadge(title: "涨跌幅模式", tint: AppPalette.info)
                        }
                    }
                    HStack(spacing: 8) {
                        if let fundCode = plan.fundCode, !fundCode.isEmpty {
                            Text(fundCode)
                        }
                        Text(plan.scheduleText)
                        Text(plan.nextExecutionDate.isEmpty ? "无下次时间" : plan.nextExecutionDate)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.amountRangeText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                    Text(plan.cumulativeInvestedAmount.map(currencyText) ?? "累计 —")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
            }

            HStack(spacing: 8) {
                Button {
                    onEdit()
                } label: {
                    Label("编辑", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)

                Menu {
                    ForEach(PersonalInvestmentPlanStatusOption.allCases) { option in
                        Button {
                            onStatusChange(option)
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                if option == statusOption {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("状态", systemImage: "archivebox")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(12)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.line.opacity(0.55), lineWidth: 1)
        )
    }
}

struct PersonalInvestmentPlanAddSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var planTypeText = "定投"
    @State private var fundNameText = ""
    @State private var fundCodeText = ""
    @State private var scheduleText = ""
    @State private var amountText = ""
    @State private var investedPeriodsText = ""
    @State private var cumulativeAmountText = ""
    @State private var paymentMethodText = ""
    @State private var nextExecutionDateText = ""
    @State private var status: PersonalInvestmentPlanStatusOption = .active
    @State private var noteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加计划档案")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text("手动补录定投、智能定投或涨跌幅计划，保存后可继续修改状态。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 10) {
                planField("计划类型", text: $planTypeText, placeholder: "定投 / 智能定投")
                planField("基金名称", text: $fundNameText, placeholder: "基金名称")
                planField("基金代码", text: $fundCodeText, placeholder: "例如 013308")
                planField("计划说明", text: $scheduleText, placeholder: "每周三定投 / 每周五定投-涨跌幅模式")
                planField("金额", text: $amountText, placeholder: "500.00元 / 250.00~1,000.00元")
                planField("已投期数", text: $investedPeriodsText, placeholder: "可留空")
                planField("累计投入", text: $cumulativeAmountText, placeholder: "可留空")
                planField("支付方式", text: $paymentMethodText, placeholder: "可留空")
                planField("下次执行", text: $nextExecutionDateText, placeholder: "进行中计划必填")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("状态")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                Picker("状态", selection: $status) {
                    ForEach(PersonalInvestmentPlanStatusOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("备注")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                TextField("可留空", text: $noteText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                            .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("添加") {
                    if model.addInvestmentPlan(
                        planTypeLabel: planTypeText,
                        fundName: fundNameText,
                        fundCode: fundCodeText,
                        scheduleText: scheduleText,
                        amountText: amountText,
                        investedPeriodsText: investedPeriodsText,
                        cumulativeInvestedAmountText: cumulativeAmountText,
                        paymentMethod: paymentMethodText,
                        nextExecutionDate: nextExecutionDateText,
                        status: status.rawValue,
                        note: noteText
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.info)
            }
        }
        .padding(18)
        .frame(width: 620)
    }

    private func planField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
        }
    }
}

struct PersonalInvestmentPlanEditSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let plan: PersonalInvestmentPlan

    @State private var planTypeText: String
    @State private var fundNameText: String
    @State private var fundCodeText: String
    @State private var scheduleText: String
    @State private var amountText: String
    @State private var investedPeriodsText: String
    @State private var cumulativeAmountText: String
    @State private var paymentMethodText: String
    @State private var nextExecutionDateText: String
    @State private var status: PersonalInvestmentPlanStatusOption
    @State private var noteText: String

    init(plan: PersonalInvestmentPlan) {
        self.plan = plan
        _planTypeText = State(initialValue: plan.planTypeLabel)
        _fundNameText = State(initialValue: plan.fundName)
        _fundCodeText = State(initialValue: plan.fundCode ?? "")
        _scheduleText = State(initialValue: plan.scheduleText)
        _amountText = State(initialValue: plan.amountText)
        _investedPeriodsText = State(initialValue: plan.investedPeriods.map(String.init) ?? "")
        _cumulativeAmountText = State(initialValue: plan.cumulativeInvestedAmount.map { Self.amountFieldText($0) } ?? "")
        _paymentMethodText = State(initialValue: plan.paymentMethod ?? "")
        _nextExecutionDateText = State(initialValue: plan.nextExecutionDate)
        _status = State(initialValue: PersonalInvestmentPlanStatusOption(status: plan.normalizedStatus))
        _noteText = State(initialValue: plan.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text("编辑定投计划")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text(plan.fundCode.map { "\(plan.fundName)（\($0)）" } ?? plan.fundName)
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 10) {
                planField("计划类型", text: $planTypeText, placeholder: "定投 / 智能定投")
                planField("基金名称", text: $fundNameText, placeholder: "基金名称")
                planField("基金代码", text: $fundCodeText, placeholder: "例如 013308")
                planField("计划说明", text: $scheduleText, placeholder: "每周三定投 / 每周五定投-涨跌幅模式")
                planField("金额", text: $amountText, placeholder: "500.00元 / 250.00~1,000.00元")
                planField("已投期数", text: $investedPeriodsText, placeholder: "例如 12")
                planField("累计投入", text: $cumulativeAmountText, placeholder: "例如 6000.00")
                planField("支付方式", text: $paymentMethodText, placeholder: "余额宝")
                planField("下次执行", text: $nextExecutionDateText, placeholder: "2026-05-01(星期五)")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("状态")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                Picker("状态", selection: $status) {
                    ForEach(PersonalInvestmentPlanStatusOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("备注")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                TextField("可留空", text: $noteText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                            .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("保存") {
                    if model.updateInvestmentPlan(
                        plan.id,
                        planTypeLabel: planTypeText,
                        fundName: fundNameText,
                        fundCode: fundCodeText,
                        scheduleText: scheduleText,
                        amountText: amountText,
                        investedPeriodsText: investedPeriodsText,
                        cumulativeInvestedAmountText: cumulativeAmountText,
                        paymentMethod: paymentMethodText,
                        nextExecutionDate: nextExecutionDateText,
                        status: status.rawValue,
                        note: noteText
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.brand)
            }
        }
        .padding(18)
        .frame(width: 620)
    }

    private func planField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
        }
    }

    private static func amountFieldText(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0000001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}
