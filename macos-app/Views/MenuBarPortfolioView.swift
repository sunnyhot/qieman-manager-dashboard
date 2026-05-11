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
    @AppStorage("menu.bar.holdings.sort") private var holdingSortRawValue = MenuBarHoldingSortOption.marketValue.rawValue

    private var holdingSort: MenuBarHoldingSortOption {
        MenuBarHoldingSortOption(rawValue: holdingSortRawValue) ?? .marketValue
    }

    private var hasMarketIndexTickerSelection: Bool {
        model.menuBarTickerSettings.selections.contains {
            $0.kindValue?.marketIndexRequest != nil
        }
    }

    var body: some View {
        let tickerEntries = model.menuBarTickerVisibleEntries

        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
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
                    model.showMainWindow(section: .portfolio)
                }
                .buttonStyle(.link)

                Button("配置菜单栏") {
                    model.showMainWindow(section: .settings)
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
                Picker("排序", selection: holdingSortBinding) {
                    ForEach(MenuBarHoldingSortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
            }

            LazyVStack(spacing: 6) {
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
        VStack(alignment: .leading, spacing: 6) {
            Text(currencyText(personalSummary?.totalEffectiveHoldingAmount ?? snapshot.totalMarketValue))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.ink)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                SummaryPill(title: "今日涨跌", value: signedCurrencyOptional(totalDailyChangeAmount), tint: dailyTint)
                SummaryPill(title: "今日涨跌率", value: percentOptional(totalDailyChangePct), tint: dailyTint)
                SummaryPill(title: "总收益", value: signedCurrencyOptional(snapshot.totalProfitAmount), tint: profitTint)
                SummaryPill(title: "总收益率", value: percentOptional(snapshot.totalProfitPct), tint: profitTint)
            }
        }
        .padding(10)
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
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .leading)
        .padding(.horizontal, 8)
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

    private var marketTint: Color {
        if let market = row.holding.detectedMarket {
            switch market {
            case .aShare: return AppPalette.info
            case .hk: return AppPalette.brand
            case .us: return AppPalette.positive
            }
        }
        if let fundMarket = row.holding.detectedFundMarket {
            switch fundMarket {
            case .offExchange: return Color.purple
            case .onExchange: return AppPalette.warning
            }
        }
        return AppPalette.muted
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.fundName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                Text(row.holding.normalizedFundCode)
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.muted)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1) {
                Text(currencyOptional(row.marketValue, market: row.holding.detectedMarket))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.ink)
                    .monospacedDigit()
                Text("\(unitsText(row.holding.units)) 份")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.muted)
                    .monospacedDigit()
            }
            .frame(width: 96, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 1) {
                Text(signedCurrencyOptional(row.estimatedDailyChangeAmount, market: row.holding.detectedMarket))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(dailyTint)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(percentOptional(row.estimateChangePct))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(dailyTint)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(marketTint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(marketTint.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct HoldingMetricPill: View {
    let title: String
    let amount: String
    let pct: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                Text(amount)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .monospacedDigit()
                Text(pct)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48, alignment: .leading)
        .padding(.horizontal, 7)
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
