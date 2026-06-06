import AppKit
import SwiftUI

// MARK: - Personal Portfolio

struct PortfolioSectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isPresentingAddPendingTrade = false
    @State private var editingPendingTrade: PersonalPendingTrade?
    @State private var deletingPendingTrade: PersonalPendingTrade?
    @State private var isPresentingAddInvestmentPlan = false
    @State private var didCopyMonthlyReport = false

    private var totalProfitAmount: Double? {
        model.userPortfolioSnapshot?.totalProfitAmount
    }

    private var totalProfitPct: Double? {
        model.userPortfolioSnapshot?.totalProfitPct
    }

    private var totalProfitTint: Color {
        AppPalette.marketTint(for: totalProfitAmount)
    }

    var body: some View {
        let dailyChange = model.userPortfolioSnapshot?.dailyChangeSummary
        let dailyChangeTint = AppPalette.marketTint(for: dailyChange?.amount)

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    MetricCard(
                        title: "总持仓",
                        value: model.personalAssetSummary.map { currencyText($0.totalEffectiveHoldingAmount) } ?? "—",
                        subtitle: model.personalAssetSummary.map {
                            "已持有 \(currencyText($0.totalMarketValue)) + 待确认 \(currencyText($0.totalPendingCashAmount)) + 下次计划 \(currencyText($0.totalEstimatedNextPlanAmount))"
                        } ?? "自动聚合你的已持有、买入中和计划档案",
                        icon: "yensign.circle",
                        accent: AppPalette.brand
                    )
                    MetricCard(
                        title: "总收益",
                        value: signedCurrencyText(totalProfitAmount),
                        subtitle: "收益率 \(percentOptional(totalProfitPct))",
                        icon: "plusminus.circle",
                        accent: totalProfitTint,
                        valueTint: totalProfitTint
                    )
                    MetricCard(
                        title: "今日涨跌",
                        value: signedCurrencyText(dailyChange?.amount),
                        subtitle: "今日涨跌率 \(percentOptional(dailyChange?.pct))",
                        icon: "waveform.path.ecg",
                        accent: dailyChangeTint,
                        valueTint: dailyChangeTint
                    )
                    MetricCard(
                        title: "待确认金额",
                        value: model.personalAssetSummary.map { currencyText($0.totalPendingCashAmount) } ?? "—",
                        subtitle: model.pendingTradeSummary.map { "\($0.actionCount) 笔交易进行中" } ?? "暂无待确认交易",
                        icon: "clock.badge.exclamationmark",
                        accent: AppPalette.warning
                    )
                    MetricCard(
                        title: "计划档案",
                        value: model.investmentPlanSummary.map { "\($0.activePlanCount) / \($0.pausedPlanCount) / \($0.endedPlanCount)" } ?? "—",
                        subtitle: model.investmentPlanSummary.map { "进行中 / 暂停 / 终止 · 共 \($0.planCount)" } ?? "支持完整计划档案",
                        icon: "calendar.badge.clock",
                        accent: AppPalette.info
                    )
                    MetricCard(
                        title: "覆盖标的",
                        value: model.personalAssetSummary.map { "\($0.fundCount)" } ?? "0",
                        subtitle: model.personalAssetSummary.map { "持有 \($0.holdingFundCount) · 待确认 \($0.pendingFundCount) · 有计划 \($0.activePlanFundCount)" } ?? "支持手动、图片和表格导入",
                        icon: "square.grid.3x2",
                        accent: AppPalette.accentWarm
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        statusLineContent
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        statusLineContent
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)

                PortfolioDiagnosticsPanel(summary: model.portfolioDiagnosticsSummary)
                ProfitAttributionPanel(summary: model.profitAttributionSummary)
                PortfolioReminderPanel(summary: model.portfolioReminderSummary)
                PlanSimulationPanel(summary: model.planSimulationSummary)
                MonthlyReportPanel(summary: model.monthlyReportSummary, didCopy: didCopyMonthlyReport) {
                    copyMonthlyReport(model.monthlyReportSummary)
                }

                SectionCard(title: "资产全貌总表", subtitle: "把「已持有 + 待确认 + 计划档案」聚合到同一行", icon: "tablecells", trailing: {
                    Spacer()
                    Text(hasAnyPersonalData ? "已导入" : "未导入")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(hasAnyPersonalData ? AppPalette.positive : AppPalette.warning)
                    Button("打开设置") {
                        model.selectedSection = .settings
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.brand)
                    .controlSize(.small)
                }) {
                    if model.personalAssetRows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有可聚合的资产数据。先导入持仓、买入中或定投计划。")
                                .font(.system(size: 12))
                                .foregroundStyle(AppPalette.muted)
                            PersonalAssetAddButtons()
                        }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                    } else {
                        PersonalAssetBrowser(rows: model.personalAssetRows)
                    }
                }

                SectionCard(title: "买入中", subtitle: "待确认交易单独展示，不并入已成交持仓收益", icon: "clock.badge.exclamationmark", trailing: {
                    Spacer()
                    Button {
                        isPresentingAddPendingTrade = true
                    } label: {
                        Label("添加买入中", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }) {
                    if let summary = model.pendingTradeSummary, !model.pendingTrades.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                                StatChip(title: "待确认金额", value: currencyText(summary.totalCashAmount))
                                StatChip(title: "现金单", value: "\(summary.cashTradeCount)")
                                if summary.unitTradeCount > 0 {
                                    StatChip(title: "份额单", value: "\(summary.unitTradeCount)")
                                }
                            }

                            VStack(spacing: 10) {
                                ForEach(model.pendingTrades) { trade in
                                    PendingTradeCard(
                                        trade: trade,
                                        onEdit: { editingPendingTrade = trade },
                                        onDelete: { deletingPendingTrade = trade }
                                    )
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有买入中记录。可以直接手动添加待确认买入、定投或转换。")
                                .font(.system(size: 12))
                                .foregroundStyle(AppPalette.muted)
                            Button {
                                isPresentingAddPendingTrade = true
                            } label: {
                                Label("添加买入中", systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppPalette.warning)
                            .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                    }
                }

                SectionCard(title: "计划档案", subtitle: "按进行中、已暂停、已终止完整归档", icon: "calendar.badge.clock", trailing: {
                    Spacer()
                    Button {
                        isPresentingAddInvestmentPlan = true
                    } label: {
                        Label("添加计划", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }) {
                    if let summary = model.investmentPlanSummary, !model.investmentPlans.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                                    StatChip(title: "累计投入", value: currencyText(summary.totalCumulativeInvestedAmount))
                                    StatChip(title: "最近执行", value: summary.nextExecutionDate ?? "—")
                                    StatChip(title: "计划状态", value: "进行中 \(summary.activePlanCount) · 暂停 \(summary.pausedPlanCount) · 终止 \(summary.endedPlanCount) · 总数 \(summary.planCount)")
                                }

                            if !model.activeInvestmentPlans.isEmpty {
                                PlanArchiveGroup(title: "进行中", tint: AppPalette.positive, plans: model.activeInvestmentPlans)
                            }

                            if !model.pausedInvestmentPlans.isEmpty {
                                PlanArchiveGroup(title: "已暂停", tint: AppPalette.warning, plans: model.pausedInvestmentPlans)
                            }

                            if !model.endedInvestmentPlans.isEmpty {
                                PlanArchiveGroup(title: "已终止", tint: AppPalette.muted, plans: model.endedInvestmentPlans)
                            }

                            if model.pausedInvestmentPlans.isEmpty && model.endedInvestmentPlans.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("当前还没有已暂停或已终止的计划明细。")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(AppPalette.muted)
                                    Text("后续把这些计划的截图、表格或手工文本导入到「定投计划」草稿区，并把最后一列状态写成「已暂停」或「已终止」，这里就会自动归档。")
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppPalette.muted)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有定投计划记录。可以直接手动添加计划档案。")
                                .font(.system(size: 12))
                                .foregroundStyle(AppPalette.muted)
                            Button {
                                isPresentingAddInvestmentPlan = true
                            } label: {
                                Label("添加计划", systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppPalette.info)
                            .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                    }
                }
            }
            .padding(14)
        }
        .sheet(isPresented: $isPresentingAddPendingTrade) {
            PersonalPendingTradeEditSheet()
        }
        .sheet(item: $editingPendingTrade) { trade in
            PersonalPendingTradeEditSheet(trade: trade)
        }
        .sheet(isPresented: $isPresentingAddInvestmentPlan) {
            PersonalInvestmentPlanAddSheet()
        }
        .alert("删除买入中记录？", isPresented: deletePendingConfirmationBinding) {
            Button("删除", role: .destructive) {
                if let deletingPendingTrade {
                    model.deletePendingTrade(deletingPendingTrade.id)
                }
                deletingPendingTrade = nil
            }
            Button("取消", role: .cancel) {
                deletingPendingTrade = nil
            }
        } message: {
            Text(deletePendingConfirmationMessage)
        }
    }

    @ViewBuilder
    private var statusLineContent: some View {
        Text(model.portfolioAutoRefreshStatusText)
        if let latestTime = model.pendingTradeSummary?.latestTime {
            Text("待确认最新：\(latestTime)")
        }
        if let nextDate = model.investmentPlanSummary?.nextExecutionDate {
            Text("下次定投：\(nextDate)")
        }
    }

    private var hasAnyPersonalData: Bool {
        model.hasAnyPortfolioRecords || model.hasPendingTrades || model.hasInvestmentPlans
    }

    private var deletePendingConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletingPendingTrade != nil },
            set: { isPresented in
                if !isPresented {
                    deletingPendingTrade = nil
                }
            }
        )
    }

    private var deletePendingConfirmationMessage: String {
        guard let deletingPendingTrade else { return "" }
        return "会从本地保存的数据中删除 \(deletingPendingTrade.displayTitle) 的这条买入中记录。"
    }

    private func copyMonthlyReport(_ report: MonthlyReportSummary) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report.markdown, forType: .string)
        didCopyMonthlyReport = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            didCopyMonthlyReport = false
        }
    }
}

private extension PortfolioDiagnosticLevel {
    var color: Color {
        switch self {
        case .risk:
            return AppPalette.danger
        case .watch:
            return AppPalette.warning
        case .info:
            return AppPalette.info
        case .good:
            return AppPalette.positive
        }
    }

    var label: String {
        switch self {
        case .risk:
            return "风险"
        case .watch:
            return "留意"
        case .info:
            return "观察"
        case .good:
            return "正常"
        }
    }
}

struct PortfolioDiagnosticsPanel: View {
    let summary: PortfolioDiagnosticsSummary

    var body: some View {
        SectionCard(title: "组合诊断", subtitle: summary.headline, icon: "stethoscope") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(summary.headline)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    ToolbarBadge(title: summary.totalExposureText, tint: AppPalette.brand)
                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 10)], spacing: 10) {
                    ForEach(summary.items) { item in
                        PortfolioDiagnosticTile(item: item)
                    }
                }
            }
        }
    }
}

struct PortfolioDiagnosticTile: View {
    let item: PortfolioDiagnosticItem

    private var iconName: String {
        switch item.kind {
        case .concentration:
            return "scope"
        case .pendingExposure:
            return "clock.badge.exclamationmark"
        case .planCoverage:
            return "calendar.badge.clock"
        case .dailyMovement:
            return "waveform.path.ecg"
        case .quoteCoverage:
            return "dot.radiowaves.left.and.right"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.level.color)
                    .frame(width: 28, height: 28)
                    .background(item.level.color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(item.level.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(item.level.color)
                }

                Spacer(minLength: 4)

                Text(item.metric)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(item.level.color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Text(item.detail)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .background(AppPalette.cardStrong.opacity(0.74), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(item.level.color.opacity(0.18), lineWidth: 1)
        )
    }
}

private extension ProfitAttributionKind {
    var color: Color {
        switch self {
        case .gain:
            return AppPalette.marketGain
        case .drag:
            return AppPalette.marketLoss
        case .neutral:
            return AppPalette.muted
        }
    }

    var label: String {
        switch self {
        case .gain:
            return "贡献"
        case .drag:
            return "拖累"
        case .neutral:
            return "持平"
        }
    }
}

struct ProfitAttributionPanel: View {
    let summary: ProfitAttributionSummary

    private var totalTint: Color {
        AppPalette.marketTint(for: summary.totalProfitValue)
    }

    var body: some View {
        SectionCard(title: "收益归因", subtitle: summary.headline, icon: "chart.pie") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 10)], spacing: 10) {
                    ProfitAttributionMetric(title: "总收益", value: summary.totalProfitText, tint: totalTint)
                    ProfitAttributionMetric(title: "总收益率", value: summary.totalProfitRateText, tint: totalTint)
                    ProfitAttributionMetric(title: "收益覆盖", value: summary.coverageText, tint: AppPalette.info)
                    ProfitAttributionMetric(title: "待确认", value: summary.pendingExposureText, tint: AppPalette.warning)
                    ProfitAttributionMetric(title: "下次计划", value: summary.plannedExposureText, tint: AppPalette.info)
                }

                if summary.entries.isEmpty {
                    Text("等待收益数据")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppPalette.cardStrong.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                } else {
                    VStack(spacing: 8) {
                        ForEach(summary.entries.prefix(6)) { entry in
                            ProfitAttributionEntryRow(entry: entry)
                        }
                    }
                }
            }
        }
    }
}

struct ProfitAttributionMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppPalette.cardStrong.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
    }
}

struct ProfitAttributionEntryRow: View {
    let entry: ProfitAttributionEntry

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(entry.kind.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(entry.kind.color)
                .frame(width: 36, height: 24)
                .background(entry.kind.color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.badgeRadius))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                    ToolbarBadge(title: entry.codeText, tint: AppPalette.info)
                }
                Text("市值 \(entry.marketValueText) · 影响 \(entry.impactShareText)")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.amountText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.kind.color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(entry.rateText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(entry.kind.color.opacity(0.86))
                    .monospacedDigit()
            }
            .frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppPalette.cardStrong.opacity(0.56), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                .stroke(AppPalette.line.opacity(0.26), lineWidth: 1)
        )
    }
}

private extension PortfolioReminderUrgency {
    var color: Color {
        switch self {
        case .high:
            return AppPalette.danger
        case .medium:
            return AppPalette.warning
        case .low:
            return AppPalette.info
        }
    }

    var label: String {
        switch self {
        case .high:
            return "处理"
        case .medium:
            return "留意"
        case .low:
            return "记录"
        }
    }
}

private extension PortfolioReminderKind {
    var iconName: String {
        switch self {
        case .pendingTrade:
            return "clock.badge.exclamationmark"
        case .investmentPlan:
            return "calendar.badge.clock"
        case .concentration:
            return "scope"
        case .dailyMovement:
            return "waveform.path.ecg"
        case .quoteCoverage:
            return "dot.radiowaves.left.and.right"
        }
    }
}

struct PortfolioReminderPanel: View {
    let summary: PortfolioReminderSummary

    var body: some View {
        SectionCard(title: "提醒通知", subtitle: summary.headline, icon: "bell.badge") {
            if summary.items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.positive)
                        .accentIconStyle(tint: AppPalette.positive, size: 28)
                    Text("暂无待处理提醒")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                    Spacer()
                }
                .padding(12)
                .background(AppPalette.cardStrong.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 192), spacing: 10)], spacing: 10) {
                    ForEach(summary.items) { item in
                        PortfolioReminderTile(item: item)
                    }
                }
            }
        }
    }
}

struct PortfolioReminderTile: View {
    let item: PortfolioReminderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: item.kind.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.urgency.color)
                    .frame(width: 28, height: 28)
                    .background(item.urgency.color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                    Text(item.urgency.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(item.urgency.color)
                }

                Spacer(minLength: 0)

                Text(item.metric)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(item.urgency.color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }

            Text(item.detail)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(12)
        .background(AppPalette.cardStrong.opacity(0.66), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(item.urgency.color.opacity(0.18), lineWidth: 1)
        )
    }
}

struct PlanSimulationPanel: View {
    let summary: PlanSimulationSummary

    var body: some View {
        SectionCard(title: "计划模拟", subtitle: summary.headline, icon: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 10)], spacing: 10) {
                    ProfitAttributionMetric(title: "单次计划", value: summary.totalPerExecutionText, tint: AppPalette.info)
                    ProfitAttributionMetric(title: "未来 \(summary.executionCount) 次", value: summary.projectedAmountText, tint: AppPalette.brand)
                    ProfitAttributionMetric(title: "进行中计划", value: "\(summary.activePlanCount)", tint: AppPalette.positive)
                    ProfitAttributionMetric(title: "覆盖标的", value: "\(summary.activeAssetCount)", tint: AppPalette.info)
                }

                if summary.items.isEmpty {
                    Text("暂无进行中计划")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppPalette.cardStrong.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                } else {
                    VStack(spacing: 8) {
                        ForEach(summary.items.prefix(5)) { item in
                            PlanSimulationItemRow(item: item)
                        }
                    }
                }
            }
        }
    }
}

struct PlanSimulationItemRow: View {
    let item: PlanSimulationItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.info)
                .frame(width: 30, height: 30)
                .background(AppPalette.info.opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                    ToolbarBadge(title: item.codeText, tint: AppPalette.info)
                }
                Text("\(item.activePlanCount) 条计划 · 下次 \(item.nextExecutionDateText) · 当前占用 \(item.currentExposureText)")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.projectedAmountText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.brand)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("单次 \(item.perExecutionText)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppPalette.info)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: 126, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppPalette.cardStrong.opacity(0.56), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                .stroke(AppPalette.line.opacity(0.26), lineWidth: 1)
        )
    }
}

struct MonthlyReportPanel: View {
    let summary: MonthlyReportSummary
    let didCopy: Bool
    let onCopy: () -> Void

    private var lineCountText: String {
        "\(summary.markdown.split(separator: "\n", omittingEmptySubsequences: false).count) 行"
    }

    var body: some View {
        SectionCard(title: "月报导出", subtitle: summary.title, icon: "doc.text", trailing: {
            Spacer()
            Button(action: onCopy) {
                Label(didCopy ? "已复制" : "复制月报", systemImage: didCopy ? "checkmark.circle" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .tint(didCopy ? AppPalette.positive : AppPalette.brand)
            .controlSize(.small)
        }) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 10)], spacing: 10) {
                    ProfitAttributionMetric(title: "报告月份", value: summary.monthText, tint: AppPalette.brand)
                    ProfitAttributionMetric(title: "生成时间", value: summary.generatedAt, tint: AppPalette.info)
                    ProfitAttributionMetric(title: "Markdown", value: lineCountText, tint: AppPalette.positive)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text(summary.markdown)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppPalette.cardStrong.opacity(0.62), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                        .stroke(AppPalette.line.opacity(0.28), lineWidth: 1)
                )
            }
        }
    }
}
