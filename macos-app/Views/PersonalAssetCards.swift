import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

struct PersonalAssetOverviewCard: View {
    let row: PersonalAssetAggregateRow

    private var profitTint: Color {
        (row.profitAmount ?? 0) >= 0 ? AppPalette.positive : AppPalette.danger
    }

    private var changeTint: Color {
        let value = row.estimateChangePct ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
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
                        ToolbarBadge(title: row.assetTypeLabel, tint: row.assetType == .stock ? AppPalette.info : AppPalette.brand)
                        if let marketLabel = row.rawHolding?.marketLabel ?? row.holdingRow?.holding.marketLabel {
                            ToolbarBadge(title: marketLabel, tint: AppPalette.info)
                        }
                        ToolbarBadge(title: row.combinedStatusText, tint: row.hasPending ? AppPalette.warning : AppPalette.brand)
                        if row.hasDrawdownPlan {
                            ToolbarBadge(title: "涨跌幅 \(row.drawdownPlanCount)", tint: AppPalette.info)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(currencyText(row.effectiveHoldingAmount))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppPalette.ink)
                        .monospacedDigit()
                    Text("总持仓")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                    if row.marketValue != nil {
                        Text(percentOptional(row.profitPct))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(profitTint)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                AssetMiniStat(title: "实时估值", value: row.marketValue.map { currencyText($0, market: row.detectedMarket) } ?? "—", tint: AppPalette.brand)
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
                LabeledValue(title: "现价", value: decimalOptional(row.currentPrice))
                LabeledValue(title: "成本", value: row.costPrice.map(decimalText) ?? "—")
            }

            HStack(spacing: 12) {
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
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 14))
        .frame(minHeight: 246, alignment: .top)
    }
}

struct PersonalAssetAddButtons: View {
    @State private var isPresentingAddSheet = false

    var body: some View {
        Button {
            isPresentingAddSheet = true
        } label: {
            Label("添加持仓", systemImage: "plus.circle")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .sheet(isPresented: $isPresentingAddSheet) {
            PersonalAssetAddHoldingSheet()
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
                    Text("填写代码、份额和成本，系统会按代码自动判断基金或股票。")
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
                        displayName: codeResolution.displayName
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
        .background(nameStatusTint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
                return "判断为：\(codeResolution.assetType.displayName) · \(displayName)"
            }
            return "判断为：\(codeResolution.assetType.displayName)，暂未识别到名称"
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

    private func addHoldingField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
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
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
        }
    }
}

struct PlanArchiveGroup: View {
    let title: String
    let tint: Color
    let plans: [PersonalInvestmentPlan]

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
                    InvestmentPlanCard(plan: plan)
                }
            }
        }
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
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

