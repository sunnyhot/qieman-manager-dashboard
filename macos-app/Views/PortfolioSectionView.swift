import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Personal Portfolio

struct PortfolioSectionView: View {
    @EnvironmentObject private var model: AppModel

    private var totalProfitAmount: Double? {
        model.userPortfolioSnapshot?.totalProfitAmount
    }

    private var totalProfitPct: Double? {
        model.userPortfolioSnapshot?.totalProfitPct
    }

    private var totalDailyChangeAmount: Double? {
        let values = model.userPortfolioSnapshot?.rows.compactMap(\.estimatedDailyChangeAmount) ?? []
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var totalDailyChangePct: Double? {
        guard let snapshot = model.userPortfolioSnapshot else { return nil }
        let pairs = snapshot.rows.compactMap { row -> (Double, Double)? in
            guard
                let change = row.estimatedDailyChangeAmount,
                let previous = row.previousMarketValue,
                previous > 0
            else {
                return nil
            }
            return (change, previous)
        }
        guard !pairs.isEmpty else { return nil }
        let totalChange = pairs.reduce(0) { $0 + $1.0 }
        let totalPrevious = pairs.reduce(0) { $0 + $1.1 }
        guard totalPrevious > 0 else { return nil }
        return totalChange / totalPrevious * 100
    }

    private var totalProfitTint: Color {
        let value = totalProfitAmount ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    private var totalDailyChangeTint: Color {
        let value = totalDailyChangeAmount ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
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
                        value: signedCurrencyText(totalDailyChangeAmount),
                        subtitle: "今日涨跌率 \(percentOptional(totalDailyChangePct))",
                        icon: "waveform.path.ecg",
                        accent: totalDailyChangeTint,
                        valueTint: totalDailyChangeTint
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

                HStack(spacing: 10) {
                    if let latestTime = model.pendingTradeSummary?.latestTime {
                        Text("待确认最新：\(latestTime)")
                    }
                    if let nextDate = model.investmentPlanSummary?.nextExecutionDate {
                        Text("下次定投：\(nextDate)")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)

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
                            .background(AppPalette.cardStrong)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        PersonalAssetBrowser(rows: model.personalAssetRows)
                    }
                }

                SectionCard(title: "买入中", subtitle: "待确认交易单独展示，不并入已成交持仓收益", icon: "clock.badge.exclamationmark") {
                    if let summary = model.pendingTradeSummary, !model.pendingTrades.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                StatChip(title: "待确认金额", value: currencyText(summary.totalCashAmount))
                                StatChip(title: "现金单", value: "\(summary.cashTradeCount)")
                                if summary.unitTradeCount > 0 {
                                    StatChip(title: "份额单", value: "\(summary.unitTradeCount)")
                                }
                            }

                            LazyVStack(spacing: 10) {
                                ForEach(model.pendingTrades) { trade in
                                    PendingTradeCard(trade: trade)
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有买入中记录。可以直接手动录入，或在导入中心上传图片、表格。")
                                .font(.system(size: 12))
                                .foregroundStyle(AppPalette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppPalette.cardStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                SectionCard(title: "计划档案", subtitle: "按进行中、已暂停、已终止完整归档", icon: "calendar.badge.clock") {
                    if let summary = model.investmentPlanSummary, !model.investmentPlans.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                StatChip(title: "进行中", value: "\(summary.activePlanCount)")
                                StatChip(title: "已暂停", value: "\(summary.pausedPlanCount)")
                                StatChip(title: "已终止", value: "\(summary.endedPlanCount)")
                                StatChip(title: "总数", value: "\(summary.planCount)")
                            }

                            HStack(spacing: 10) {
                                StatChip(title: "智能定投", value: "\(summary.smartPlanCount)")
                                StatChip(title: "日定投", value: "\(summary.dailyPlanCount)")
                                StatChip(title: "周定投", value: "\(summary.weeklyPlanCount)")
                                StatChip(title: "涨跌幅模式", value: "\(model.investmentPlans.filter(\.isDrawdownMode).count)")
                            }

                            HStack(spacing: 10) {
                                StatChip(title: "累计投入", value: currencyText(summary.totalCumulativeInvestedAmount))
                                if let nextDate = summary.nextExecutionDate {
                                    StatChip(title: "最近执行", value: nextDate)
                                }
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
                                .background(AppPalette.cardStrong)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有定投计划记录。可以直接手动录入，或在导入中心上传图片、表格。")
                                .font(.system(size: 12))
                                .foregroundStyle(AppPalette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppPalette.cardStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(16)
        }
    }

    private var hasAnyPersonalData: Bool {
        model.hasPersonalPortfolio || model.hasPendingTrades || model.hasInvestmentPlans
    }
}

