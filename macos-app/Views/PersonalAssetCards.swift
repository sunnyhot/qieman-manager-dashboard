import SwiftUI

struct PersonalAssetOverviewCard: View {
    let row: PersonalAssetAggregateRow

    private var profitTint: Color {
        AppPalette.marketTint(for: row.profitAmount)
    }

    private var changeTint: Color {
        AppPalette.marketTint(for: row.estimateChangePct)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.fundName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if let fundCode = row.fundCode, !fundCode.isEmpty {
                            Text(fundCode)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(AppPalette.muted)
                        }
                        if let marketLabel = row.rawHolding?.marketLabel ?? row.holdingRow?.holding.marketLabel ?? row.archivedHolding?.marketLabel {
                            ToolbarBadge(title: marketLabel, tint: AppPalette.info)
                        }
                        ToolbarBadge(title: row.combinedStatusText, tint: row.hasPending ? AppPalette.warning : (row.hasArchivedHolding && !row.hasHolding ? AppPalette.muted : AppPalette.brand))
                        if row.hasDrawdownPlan {
                            ToolbarBadge(title: "涨跌幅 \(row.drawdownPlanCount)", tint: AppPalette.info)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(currencyText(row.effectiveHoldingAmount))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("总持仓")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                    if row.marketValue != nil {
                        Text(percentOptional(row.profitPct))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(profitTint)
                            .lineLimit(1)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                AssetMiniStat(title: row.usesMarketTradeColumns ? "实时估值" : "最新净值", value: row.marketValue.map { currencyText($0, market: row.detectedMarket) } ?? "—", tint: AppPalette.brand)
                if let estimateValue = row.currentEstimateMarketValue {
                    AssetMiniStat(title: "当前估值", value: currencyText(estimateValue, market: row.detectedMarket), tint: changeTint)
                }
                AssetMiniStat(title: "总收益", value: signedCurrencyText(row.profitAmount, market: row.detectedMarket), tint: profitTint)
                AssetMiniStat(title: "今日涨跌", value: signedCurrencyText(row.estimateChangeAmount, market: row.detectedMarket), tint: changeTint)
                AssetMiniStat(
                    title: "待确认",
                    value: row.pendingCashAmount > 0 ? currencyText(row.pendingCashAmount, market: row.detectedMarket) : (row.pendingUnitAmount > 0 ? "\(unitsText(row.pendingUnitAmount)) 份" : "—"),
                    tint: AppPalette.warning
                )
            }

            HStack(spacing: 18) {
                LabeledValue(title: "份额", value: row.holdingUnits.map { "\(unitsText($0)) 份" } ?? "—")
                LabeledValue(title: row.usesMarketTradeColumns ? "现价" : "净值", value: decimalOptional(row.currentPrice))
                if let estimatePrice = row.currentEstimatePrice {
                    LabeledValue(title: "估值", value: decimalText(estimatePrice), tint: changeTint)
                }
                LabeledValue(title: "成本", value: row.costPrice.map(decimalText) ?? "—")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                if let archivedUnits = row.archivedUnits, !row.hasHolding {
                    Text("归档份额 \(unitsText(archivedUnits)) 份")
                }
                if row.pendingTradeCount > 0 {
                    Text("待确认 \(row.pendingTradeCount) 笔")
                }
                if row.totalPlanCount > 0 {
                    Text("下次计划 \(currencyText(row.estimatedNextPlanAmount))")
                }
                if row.hasDrawdownPlan {
                    Text("涨跌幅 \(percentOptional(row.estimateChangePct))")
                }
                if let nextExecutionDate = row.nextExecutionDate {
                    Text("下次 \(nextExecutionDate)")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(row.hasDrawdownPlan ? changeTint : AppPalette.muted)
            .lineLimit(1)
        }
        .padding(14)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .cardStroke(opacity: 0.30)
        .frame(minHeight: 246, alignment: .top)
    }
}

struct PersonalAssetAddButtons: View {
    @State private var isPresentingAddHoldingSheet = false
    @State private var isPresentingAddPendingTradeSheet = false
    @State private var isPresentingAddInvestmentPlanSheet = false

    var body: some View {
        Menu {
            Button {
                isPresentingAddHoldingSheet = true
            } label: {
                Label("添加持仓", systemImage: "briefcase")
            }

            Button {
                isPresentingAddPendingTradeSheet = true
            } label: {
                Label("添加买入中", systemImage: "clock.badge.exclamationmark")
            }

            Button {
                isPresentingAddInvestmentPlanSheet = true
            } label: {
                Label("添加计划档案", systemImage: "calendar.badge.clock")
            }
        } label: {
            Label("添加", systemImage: "plus.circle")
                .font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .sheet(isPresented: $isPresentingAddHoldingSheet) {
            PersonalAssetAddHoldingSheet()
        }
        .sheet(isPresented: $isPresentingAddPendingTradeSheet) {
            PersonalPendingTradeEditSheet()
        }
        .sheet(isPresented: $isPresentingAddInvestmentPlanSheet) {
            PersonalInvestmentPlanAddSheet()
        }
    }
}

struct PersonalAssetAddHoldingSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var codeText = ""
    @State private var unitsText = ""
    @State private var costPriceText = ""
    @State private var codeResolution: PersonalAssetCodeResolution?
    @State private var isResolvingName = false
    @State private var hasResolvedName = false

    private var lookupKey: String {
        codeText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: codeResolution?.assetType == .stock ? "chart.line.uptrend.xyaxis" : "chart.pie")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(codeResolution?.assetType == .stock ? AppPalette.info : AppPalette.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加持仓")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text("填写代码、份额和成本，系统会按代码自动判断场外基金、场内基金或股票。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                addHoldingField("代码", text: $codeText, placeholder: "例如 021550 / 600519 / SH600519")
                addHoldingField("份额", text: $unitsText, placeholder: "例如 100.00")
                addHoldingField("成本", text: $costPriceText, placeholder: "例如 1.2345")
            }

            nameLookupStatus

            HStack(spacing: 10) {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("添加") {
                    guard let codeResolution else { return }
                    if model.addPersonalAssetHolding(
                        assetType: codeResolution.assetType,
                        codeText: codeResolution.code,
                        unitsText: unitsText,
                        costPriceText: costPriceText,
                        displayName: codeResolution.displayName,
                        stockMarket: codeResolution.stockMarket,
                        fundMarket: codeResolution.fundMarket
                    ) {
                        dismiss()
                    }
                }
                .disabled(codeResolution == nil || isResolvingName)
                .buttonStyle(.borderedProminent)
                .tint(codeResolution?.assetType == .stock ? AppPalette.info : AppPalette.brand)
            }
        }
        .padding(18)
        .frame(width: 400)
        .task(id: lookupKey) {
            await resolveName(for: codeText)
        }
    }

    private var nameLookupStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: nameStatusIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(nameStatusTint)
            Text(nameStatusText)
                .font(.system(size: 11))
                .foregroundStyle(nameStatusTint)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(nameStatusTint.opacity(AppPalette.accentSubtle), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }

    private var nameStatusIcon: String {
        if codeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "magnifyingglass"
        }
        if isResolvingName {
            return "arrow.clockwise"
        }
        if codeResolution?.displayName != nil {
            return "checkmark.circle"
        }
        if codeResolution != nil {
            return "checkmark.circle"
        }
        return "exclamationmark.circle"
    }

    private var nameStatusText: String {
        if codeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "输入代码后自动判断类型并识别名称"
        }
        if isResolvingName {
            return "正在判断类型和识别名称…"
        }
        if let codeResolution {
            if let displayName = codeResolution.displayName, !displayName.isEmpty {
                return "判断为：\(resolutionTypeLabel(codeResolution)) · \(displayName)"
            }
            return "判断为：\(resolutionTypeLabel(codeResolution))，暂未识别到名称"
        }
        if hasResolvedName {
            return "暂时无法判断类型，请检查代码"
        }
        return "输入代码后自动判断类型并识别名称"
    }

    private var nameStatusTint: Color {
        if isResolvingName {
            return AppPalette.info
        }
        if codeResolution?.displayName != nil {
            return AppPalette.positive
        }
        if codeResolution != nil {
            return AppPalette.info
        }
        if hasResolvedName {
            return AppPalette.warning
        }
        return AppPalette.muted
    }

    private func resolutionTypeLabel(_ resolution: PersonalAssetCodeResolution) -> String {
        if resolution.assetType == .stock {
            return resolution.stockMarket?.displayName ?? resolution.assetType.displayName
        }
        return resolution.fundMarket?.displayName ?? resolution.assetType.displayName
    }

    private func addHoldingField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .inputFieldStyle()
        }
    }

    private func resolveName(for rawCode: String) async {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        codeResolution = nil
        hasResolvedName = false
        guard !code.isEmpty else {
            isResolvingName = false
            return
        }

        isResolvingName = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }

        let resolution = await model.resolvePersonalAssetCode(code)
        if Task.isCancelled { return }

        codeResolution = resolution
        hasResolvedName = true
        isResolvingName = false
    }
}

struct PersonalAssetEditHoldingSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let row: PersonalAssetAggregateRow

    @State private var codeText: String
    @State private var nameText: String
    @State private var unitsText: String
    @State private var costPriceText: String

    private var holding: UserPortfolioHolding? {
        row.rawHolding ?? row.holdingRow?.holding
    }

    init(row: PersonalAssetAggregateRow) {
        self.row = row
        let holding = row.rawHolding ?? row.holdingRow?.holding
        _codeText = State(initialValue: holding?.normalizedFundCode ?? row.fundCode ?? "")
        _nameText = State(initialValue: holding?.normalizedName ?? row.fundName)
        _unitsText = State(initialValue: holding.map { Self.formattedUnitsText($0.units) } ?? "")
        _costPriceText = State(initialValue: holding?.costPrice.map(decimalText) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text("编辑持仓")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text(holdingMarketLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }

            if holding == nil {
                Text("这条资产没有已持有记录。")
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.muted)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    editField("名称", text: $nameText, placeholder: "可留空，按代码自动补全")
                    editField("代码", text: $codeText, placeholder: "例如 021550 / ETF:510300 / HK:00700 / US:AAPL")
                    editField("份额", text: $unitsText, placeholder: "例如 100.00")
                    editField("成本价", text: $costPriceText, placeholder: "可留空")
                }
            }

            HStack(spacing: 10) {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("保存") {
                    if model.updatePersonalAssetHolding(
                        row,
                        codeText: codeText,
                        unitsText: unitsText,
                        costPriceText: costPriceText,
                        displayNameText: nameText
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.brand)
                .disabled(holding == nil)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private var holdingMarketLabel: String {
        if row.assetType == .stock {
            return holding?.detectedMarket?.displayName ?? row.detectedMarket?.displayName ?? row.assetType.displayName
        }
        return holding?.detectedFundMarket?.displayName ?? row.detectedFundMarket?.displayName ?? row.assetType.displayName
    }

    private func editField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .inputFieldStyle()
        }
    }

    private static func formattedUnitsText(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0000001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.4f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

struct PersonalAssetUnitAdjustmentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let row: PersonalAssetAggregateRow
    let mode: PersonalAssetUnitAdjustmentMode
    let onSubmit: (String, String) -> Bool

    @State private var adjustmentUnitsText: String
    @State private var adjustmentUnitNetValueText: String

    init(
        row: PersonalAssetAggregateRow,
        mode: PersonalAssetUnitAdjustmentMode,
        onSubmit: @escaping (String, String) -> Bool
    ) {
        self.row = row
        self.mode = mode
        self.onSubmit = onSubmit
        _adjustmentUnitsText = State(initialValue: "")
        _adjustmentUnitNetValueText = State(initialValue: row.currentPrice.map(decimalText) ?? row.costPrice.map(decimalText) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: mode == .add ? "plus.circle" : "minus.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(mode == .add ? AppPalette.positive : AppPalette.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode == .add ? "添加份额" : "删除份额")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text(row.fundCode.map { "\(row.fundName)（\($0)）" } ?? row.fundName)
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                adjustmentField("份额", text: $adjustmentUnitsText, placeholder: "例如 100.00")
                adjustmentField("单位净值", text: $adjustmentUnitNetValueText, placeholder: "例如 1.2345")
            }

            if mode == .remove, let holdingUnits = row.holdingUnits {
                Text("当前份额 \(unitsText(holdingUnits))。删除份额会按填写的单位净值扣减成本金额。")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
            } else {
                Text("添加份额会用填写的单位净值和现有成本加权重算成本价。")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(mode == .add ? "添加" : "删除") {
                    if onSubmit(adjustmentUnitsText, adjustmentUnitNetValueText) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(mode == .add ? AppPalette.positive : AppPalette.warning)
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private func adjustmentField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .inputFieldStyle()
        }
    }
}

struct PlanArchiveGroup: View {
    @EnvironmentObject private var model: AppModel

    let title: String
    let tint: Color
    let plans: [PersonalInvestmentPlan]

    @State private var editingPlan: PersonalInvestmentPlan?
    @State private var deletingPlan: PersonalInvestmentPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text("\(plans.count) 条")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
            }

            LazyVStack(spacing: 10) {
                ForEach(plans) { plan in
                    InvestmentPlanCard(
                        plan: plan,
                        onEdit: { editingPlan = plan },
                        onDelete: { deletingPlan = plan }
                    )
                }
            }
        }
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
        return "会从本地保存的数据中删除 \(itemText) 的这条计划档案。"
    }
}

struct AssetMiniStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(AppPalette.accentSubtle), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }
}
