import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

struct PersonalAssetBrowser: View {
    let rows: [PersonalAssetAggregateRow]

    @State private var searchText = ""
    @State private var filterScope: PersonalAssetFilterScope = .all
    @State private var sortOption: PersonalAssetSortOption = .exposure

    private var displayedRows: [PersonalAssetAggregateRow] {
        rows
            .filter(matchesSearch)
            .filter(matchesFilter)
            .sorted(by: compareRows)
    }

    private var totalPendingAmount: Double {
        displayedRows.map(\.pendingCashAmount).reduce(0, +)
    }

    private var totalDisplayedProfit: Double? {
        let values = displayedRows.compactMap(\.profitAmount)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var totalDisplayedChange: Double? {
        let values = displayedRows.compactMap(\.estimateChangeAmount)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var drawdownFundCount: Int {
        displayedRows.filter(\.hasDrawdownPlan).count
    }

    var body: some View {
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
                .background(AppPalette.cardStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        .background(AppPalette.cardStrong)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .menuStyle(.borderlessButton)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PersonalAssetFilterScope.allCases) { scope in
                        filterChip(scope: scope)
                    }
                }
                .padding(.vertical, 2)
            }

            if displayedRows.isEmpty {
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
                .background(AppPalette.cardStrong)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                PersonalAssetGroupedTable(rows: displayedRows)
            }
        }
    }

    private func filterChip(scope: PersonalAssetFilterScope) -> some View {
        let isSelected = filterScope == scope
        let count = rows.filter { row in
            filterScopeMatch(scope, row: row)
        }.count
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
            .background(isSelected ? AppPalette.brand : AppPalette.cardStrong)
            .clipShape(Capsule())
        }
        .buttonStyle(PressResponsiveButtonStyle())
        .contentShape(Capsule())
    }

    private func matchesSearch(_ row: PersonalAssetAggregateRow) -> Bool {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return true }
        return row.fundName.lowercased().contains(keyword)
            || (row.fundCode?.lowercased().contains(keyword) ?? false)
    }

    private func matchesFilter(_ row: PersonalAssetAggregateRow) -> Bool {
        filterScopeMatch(filterScope, row: row)
    }

    private func filterScopeMatch(_ scope: PersonalAssetFilterScope, row: PersonalAssetAggregateRow) -> Bool {
        switch scope {
        case .all:
            return true
        case .holding:
            return row.hasHolding
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

    private func compareRows(_ left: PersonalAssetAggregateRow, _ right: PersonalAssetAggregateRow) -> Bool {
        switch sortOption {
        case .exposure:
            let leftValue = totalExposure(of: left)
            let rightValue = totalExposure(of: right)
            if abs(leftValue - rightValue) > 0.001 {
                return leftValue > rightValue
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

    private func totalExposure(of row: PersonalAssetAggregateRow) -> Double {
        row.effectiveHoldingAmount
    }

    private func sortableExecutionDate(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(10))
    }
}

struct PersonalAssetGroupedTable: View {
    let rows: [PersonalAssetAggregateRow]

    private var fundRows: [PersonalAssetAggregateRow] {
        rows.filter { $0.assetType == .fund }
    }

    private var stockRows: [PersonalAssetAggregateRow] {
        rows.filter { $0.assetType == .stock }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !fundRows.isEmpty {
                group(title: "基金", rows: fundRows)
            }
            if !stockRows.isEmpty {
                group(title: "股票", rows: stockRows)
            }
        }
    }

    private func group(title: String, rows: [PersonalAssetAggregateRow]) -> some View {
        let latestTime = rows.compactMap(\.holdingRow?.resolvedPriceTime).sorted().last
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                ToolbarBadge(title: "\(rows.count) 只", tint: title == "股票" ? AppPalette.info : AppPalette.brand)
                Text("市值 \(currencyText(rows.compactMap(\.marketValue).reduce(0, +)))")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                if let time = latestTime {
                    Text("估值 \(time)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted.opacity(0.7))
                }
            }
            PersonalAssetTable(rows: rows, isStock: title == "股票")
        }
    }
}

struct PersonalAssetTable: View {
    let rows: [PersonalAssetAggregateRow]
    let isStock: Bool

    init(rows: [PersonalAssetAggregateRow], isStock: Bool = false) {
        self.rows = rows
        self.isStock = isStock
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("标的")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("实时估值 / 收益")
                    .frame(width: 260, alignment: .leading)
                Text("现价 / 成本")
                    .frame(width: 120, alignment: .leading)
                if isStock {
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
            .background(AppPalette.cardStrong)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            LazyVStack(spacing: 8) {
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

    private var profitTint: Color {
        (row.profitAmount ?? 0) >= 0 ? AppPalette.positive : AppPalette.danger
    }

    private var changeTint: Color {
        let value = row.estimateChangeAmount ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.fundName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    ToolbarBadge(title: row.assetTypeLabel, tint: row.assetType == .stock ? AppPalette.info : AppPalette.brand)
                    if let marketLabel = row.rawHolding?.marketLabel ?? row.holdingRow?.holding.marketLabel {
                        ToolbarBadge(title: marketLabel, tint: AppPalette.info)
                    }
                    ToolbarBadge(title: row.combinedStatusText, tint: row.hasPending ? AppPalette.warning : AppPalette.brand)
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
                Text("现价 \(row.currentPrice.map(decimalText) ?? "—")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text("成本 \(row.costPrice.map(decimalText) ?? "—")")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
            }
            .frame(width: 120, alignment: .leading)

            if row.assetType == .stock {
                Group {
                    if let changePct = row.estimateChangePct {
                        Text(String(format: "%+.2f%%", changePct))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(changePct >= 0 ? AppPalette.positive : AppPalette.danger)
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

            if row.assetType == .stock {
                Group {
                    if let changeAmt = row.estimateChangeAmount {
                        Text(signedCurrencyText(changeAmt, market: row.detectedMarket))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(changeAmt >= 0 ? AppPalette.positive : AppPalette.danger)
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
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private var canRemoveHoldingUnits: Bool {
        (row.holdingUnits ?? 0) > 0 && (row.rawHolding != nil || row.holdingRow != nil)
    }

    private var hasRowActions: Bool {
        canAddHoldingUnits || canRemoveHoldingUnits || !sourceDeleteScopes.isEmpty
    }

    private var actionMenu: some View {
        Menu {
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

            if (canAddHoldingUnits || canRemoveHoldingUnits) && !sourceDeleteScopes.isEmpty {
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
            .background(AppPalette.brand.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
            return "删除已持有"
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
            return "已持有记录"
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

