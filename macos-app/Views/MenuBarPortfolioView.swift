import AppKit
import SwiftUI

private enum MenuBarHoldingSortOption: String, CaseIterable, Identifiable {
    case dailyChange = "今日涨跌"
    case totalProfit = "总收益"
    case marketValue = "市值"

    var id: String { rawValue }
}

struct MenuBarPortfolioView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("menu.bar.holdings.sort") private var holdingSortRawValue = MenuBarHoldingSortOption.marketValue.rawValue

    private var holdingSort: MenuBarHoldingSortOption {
        MenuBarHoldingSortOption(rawValue: holdingSortRawValue) ?? .marketValue
    }

    private var hasMarketIndexTickerSelection: Bool {
        model.menuBarTickerSettings.enabledKinds.contains { $0.marketIndexRequest != nil }
    }

    var body: some View {
        let tickerEntries = model.menuBarTickerVisibleEntries

        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !tickerEntries.isEmpty {
                        MenuBarTickerPreviewCard(entries: tickerEntries)
                    }

                    if let snapshot = model.userPortfolioSnapshot, !snapshot.rows.isEmpty {
                        MenuBarSummaryCard(
                            snapshot: snapshot,
                            personalSummary: model.personalAssetSummary
                        )

                        holdingsPanel(snapshot: snapshot)
                    } else if model.hasPersonalPortfolio {
                        MenuBarEmptyState(
                            icon: "waveform.path.ecg",
                            title: "还没有估值结果",
                            subtitle: "点一次刷新，就会拉到每只标的的实时估值和总收益。"
                        )
                    } else {
                        MenuBarEmptyState(
                            icon: "briefcase",
                            title: model.hasInvestmentPlans ? "已导入计划，但还没持仓估值" : "还没配置持仓",
                            subtitle: "去主界面的“我的持仓”录入后，这里会直接显示每只标的的实时估值和总收益。"
                        )
                    }
                }
                .padding(.trailing, 2)
            }

            Divider()

            HStack {
                Button("打开主界面") {
                    model.selectedSection = .portfolio
                    openWindow(id: "main-window")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.link)

                Button("配置菜单栏") {
                    model.selectedSection = .settings
                    openWindow(id: "main-window")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.link)

                Spacer()

                Button("数据目录") {
                    model.openDataDirectory()
                }
                .buttonStyle(.link)
            }
        }
        .padding(14)
        .frame(width: 392, height: 720)
        .background(AppPalette.canvasGradient)
        .task {
            if model.userPortfolioSnapshot == nil, model.hasPersonalPortfolio {
                try? await model.refreshUserPortfolio(updateNotice: false)
            }
            await model.refreshMarketIndicesIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("我的持仓")
                    .font(.system(size: 15, weight: .bold))
                Text(model.userPortfolioSnapshot?.refreshedAt ?? "点击刷新获取最新估值")
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
            }
            Spacer()
            Button((model.isRefreshingPortfolio || model.isRefreshingMarketIndices) ? "刷新中…" : "刷新") {
                Task {
                    if model.hasPersonalPortfolio {
                        try? await model.refreshUserPortfolio()
                    } else {
                        await model.refreshMarketIndices(kinds: MarketIndexKind.allCases, updateNotice: true)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.isRefreshingPortfolio || model.isRefreshingMarketIndices || (!model.hasPersonalPortfolio && !hasMarketIndexTickerSelection))
        }
    }

    private func holdingsPanel(snapshot: UserPortfolioSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("持仓列表")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text("\(snapshot.holdingCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppPalette.cardStrong)
                    .clipShape(Capsule())
                Spacer()
                Text("按\(holdingSort.rawValue)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
            }

            Picker("持仓排序", selection: holdingSortBinding) {
                ForEach(MenuBarHoldingSortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            LazyVStack(spacing: 8) {
                ForEach(sortedHoldingRows(snapshot.rows)) { row in
                    MenuBarHoldingRow(row: row)
                }
            }
        }
    }

    private func sortedHoldingRows(_ rows: [UserPortfolioValuationRow]) -> [UserPortfolioValuationRow] {
        switch holdingSort {
        case .dailyChange:
            return rows.map { ($0, $0.estimatedDailyChangeAmount ?? -.greatestFiniteMagnitude) }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        case .totalProfit:
            return rows.map { ($0, $0.profitAmount ?? -.greatestFiniteMagnitude) }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        case .marketValue:
            return rows.map { ($0, $0.marketValue ?? -.greatestFiniteMagnitude) }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
    }

    private var holdingSortBinding: Binding<MenuBarHoldingSortOption> {
        Binding(
            get: { holdingSort },
            set: { holdingSortRawValue = $0.rawValue }
        )
    }
}

private struct MenuBarTickerPreviewCard: View {
    let entries: [MenuBarTickerEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.info)
                Text("菜单栏正在显示")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Spacer()
                Text("\(entries.count) 项")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppPalette.muted)
                            .lineLimit(1)
                        Text(entry.value)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(toneColor(entry.tone))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(toneColor(entry.tone).opacity(0.08), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                }
            }
        }
        .padding(12)
        .background(AppPalette.cardStrong.opacity(0.82), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.line.opacity(0.42), lineWidth: 1)
        )
    }

    private func toneColor(_ tone: MenuBarTickerTone) -> Color {
        switch tone {
        case .positive:
            return AppPalette.marketGain
        case .negative:
            return AppPalette.marketLoss
        case .neutral:
            return AppPalette.ink
        }
    }
}

private struct MenuBarEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(AppPalette.muted)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(AppPalette.cardStrong)
        .clipShape(RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }
}

private struct MenuBarSummaryCard: View {
    let snapshot: UserPortfolioSnapshot
    let personalSummary: PersonalAssetAggregateSummary?

    private var totalDailyChangeAmount: Double? {
        let values = snapshot.rows.compactMap(\.estimatedDailyChangeAmount)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var totalDailyChangePct: Double? {
        let pairs = snapshot.rows.compactMap { row -> (Double, Double)? in
            guard let change = row.estimatedDailyChangeAmount,
                  let previous = row.previousMarketValue,
                  previous > 0
            else { return nil }
            return (change, previous)
        }
        guard !pairs.isEmpty else { return nil }
        let totalChange = pairs.reduce(0) { $0 + $1.0 }
        let totalPrevious = pairs.reduce(0) { $0 + $1.1 }
        guard totalPrevious > 0 else { return nil }
        return totalChange / totalPrevious * 100
    }

    private var dailyTint: Color {
        AppPalette.marketTint(for: totalDailyChangeAmount)
    }

    private var profitTint: Color {
        AppPalette.marketTint(for: snapshot.totalProfitAmount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("总资产估值")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                Spacer()
                Text("共 \(snapshot.holdingCount) 只标的")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
            }

            Text(currencyText(personalSummary?.totalEffectiveHoldingAmount ?? snapshot.totalMarketValue))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.ink)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                SummaryPill(title: "今日涨跌", value: signedCurrencyOptional(totalDailyChangeAmount), tint: dailyTint)
                SummaryPill(title: "今日涨跌率", value: percentOptional(totalDailyChangePct), tint: dailyTint)
                SummaryPill(title: "总收益", value: signedCurrencyOptional(snapshot.totalProfitAmount), tint: profitTint)
                SummaryPill(title: "总收益率", value: percentOptional(snapshot.totalProfitPct), tint: profitTint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.cardStrong)
        .clipShape(RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
        )
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56, alignment: .leading)
        .padding(.horizontal, 10)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }
}

private struct MenuBarHoldingRow: View {
    let row: UserPortfolioValuationRow

    private var dailyTint: Color {
        AppPalette.marketTint(for: row.estimatedDailyChangeAmount)
    }

    private var profitTint: Color {
        AppPalette.marketTint(for: row.profitAmount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.fundName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                    Text(row.holding.normalizedFundCode)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("实时估值")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.muted)
                    Text(currencyOptional(row.marketValue, market: row.holding.detectedMarket))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                    HStack(spacing: 4) {
                        if let marketLabel = row.holding.marketLabel {
                            Text(marketLabel)
                                .font(.system(size: 9, weight: .medium))
                        }
                        Text("\(unitsText(row.holding.units)) 份")
                    }
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                HoldingMetricPill(
                    title: "总收益",
                    amount: signedCurrencyOptional(row.profitAmount, market: row.holding.detectedMarket),
                    pct: percentOptional(row.profitPct),
                    tint: profitTint
                )
                HoldingMetricPill(
                    title: "今日涨跌",
                    amount: signedCurrencyOptional(row.estimatedDailyChangeAmount, market: row.holding.detectedMarket),
                    pct: percentOptional(row.estimateChangePct),
                    tint: dailyTint
                )
            }

            HStack(spacing: 10) {
                Text("现价 \(decimalOptional(row.resolvedPrice))")
                if let cost = row.holding.costPrice {
                    Text("成本 \(decimalText(cost))")
                }
                if let source = row.resolvedPriceSource {
                    Text(source)
                }
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundStyle(AppPalette.muted)
            .lineLimit(1)
            .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.line.opacity(0.55), lineWidth: 1)
        )
    }
}

private struct HoldingMetricPill: View {
    let title: String
    let amount: String
    let pct: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            Text(amount)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
            Text(pct)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .leading)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }
}

private func signedCurrencyOptional(_ value: Double?, market: StockMarket? = nil) -> String {
    guard let value else { return "—" }
    let sign = value >= 0 ? "+" : "-"
    let symbol = market?.currencySymbol ?? "¥"
    return "\(symbol)\(sign)\(String(format: "%.2f", abs(value)))"
}
