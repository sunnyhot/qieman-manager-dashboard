import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

struct ForumRecordRow: View {
    let record: SnapshotRecordPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.titleText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
            Text(record.bodyText)
                .font(.system(size: 12))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(3)
            HStack(spacing: 8) {
                if let meta = record.metaText {
                    Text(meta)
                } else {
                    Text(record.createdAt ?? "无附加信息")
                }
                Spacer()
                if let interaction = record.interactionText {
                    Text(interaction)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ForumSelectableRow: View {
    let record: SnapshotRecordPayload
    let isSelected: Bool
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 5 : 4) {
            Text(record.titleText)
                .font(.system(size: isCompact ? 12 : 13, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(isCompact ? 1 : 2)

            Text(record.metaText ?? record.createdAt ?? "无附加信息")
                .font(.system(size: isCompact ? 10 : 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let interaction = record.interactionText {
                HStack(spacing: 6) {
                    if let createdAt = record.createdAt, createdAt != record.metaText {
                        Text(createdAt)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(interaction)
                        .lineLimit(1)
                }
                .font(.system(size: isCompact ? 9 : 10))
                .foregroundStyle(.tertiary)
            }
        }
        .padding(isCompact ? 9 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AppPalette.brand.opacity(0.12) : AppPalette.cardStrong.opacity(0.22))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? AppPalette.brand.opacity(0.55) : AppPalette.line.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PlatformActionRow: View {
    let action: PlatformActionPayload
    var isSelected: Bool = false
    var isCompact: Bool = false

    private var isBuy: Bool { action.side == "buy" }
    private var sideColor: Color { isBuy ? AppPalette.positive : AppPalette.warning }
    private var changeTint: Color {
        let value = action.valuationChangePct ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(sideColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: isCompact ? 8 : 6) {
                if isCompact {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(action.displayTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppPalette.ink)
                                .lineLimit(1)
                            Text("\(action.fundName ?? action.title ?? "未命名标的") · \(action.fundCode ?? "无代码")")
                                .font(.system(size: 10))
                                .foregroundStyle(AppPalette.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(isBuy ? "买入" : "卖出")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(sideColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(sideColor.opacity(0.10))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 10) {
                        compactMetricPill(title: "时间", value: action.txnDate ?? action.createdAt ?? "未知", tint: AppPalette.muted)
                        compactMetricPill(title: "调仓", value: decimalText(action.tradeValuation), tint: AppPalette.ink)
                        compactMetricPill(title: "当前", value: decimalText(action.currentValuation), tint: AppPalette.ink)
                        compactMetricPill(title: "变化", value: percentText(action.valuationChangePct), tint: changeTint)
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.displayTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppPalette.ink)
                            Text("\(action.fundName ?? action.title ?? "未命名标的") · \(action.fundCode ?? "无代码")")
                                .font(.system(size: 11))
                                .foregroundStyle(AppPalette.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(isBuy ? "买入" : "卖出")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(sideColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(sideColor.opacity(0.10))
                                .clipShape(Capsule())
                            if let article = action.articleUrl, let url = URL(string: article) {
                                Link("打开平台原文", destination: url)
                                    .font(.system(size: 10))
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], spacing: 10) {
                        LabeledValue(title: "调仓时间", value: action.txnDate ?? action.createdAt ?? "未知")
                        LabeledValue(title: "调仓估值", value: decimalText(action.tradeValuation))
                        LabeledValue(title: "当前估值", value: decimalText(action.currentValuation))
                        LabeledValue(title: "变化", value: percentText(action.valuationChangePct), tint: changeTint)
                    }
                }
            }
        }
        .padding(isCompact ? 10 : 12)
        .background(isSelected ? AppPalette.brand.opacity(0.14) : AppPalette.card)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? AppPalette.brand.opacity(0.6) : AppPalette.line.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func decimalText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.4f", value)
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%+.2f%%", value)
    }

    @ViewBuilder
    private func compactMetricPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct PlatformActionDetailCard: View {
    let action: PlatformActionPayload

    private var isBuy: Bool {
        let raw = (action.side ?? action.action ?? action.actionTitle ?? "").lowercased()
        return raw.contains("buy") || raw.contains("买")
    }

    private var sideText: String { isBuy ? "买入" : "卖出" }
    private var sideColor: Color { isBuy ? AppPalette.positive : AppPalette.warning }

    private var changeTint: Color {
        let value = action.valuationChangePct ?? action.valuationChangeAmount ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(sideColor)
                    .frame(width: 4, height: 52)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(action.displayTitle)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(sideText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(sideColor)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(sideColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text("\(action.fundName ?? action.title ?? "未命名标的") · \(action.fundCode ?? "无代码")")
                        .font(.system(size: 12))
                        .foregroundStyle(AppPalette.muted)
                }

                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                detailMetric("调仓时间", action.txnDate ?? action.createdAt ?? "未知", tint: AppPalette.ink)
                detailMetric("调仓估值", decimalOptional(action.tradeValuation), tint: AppPalette.ink)
                detailMetric("当前估值", decimalOptional(action.currentValuation), tint: AppPalette.ink)
                detailMetric("估值变化", percentOptional(action.valuationChangePct), tint: changeTint)
                detailMetric("变化金额", signedCurrencyText(action.valuationChangeAmount), tint: changeTint)
                detailMetric("计划份数", action.postPlanUnit.map(String.init) ?? "—", tint: AppPalette.ink)
                detailMetric("交易份数", action.tradeUnit.map(String.init) ?? "—", tint: AppPalette.ink)
                detailMetric("净值", decimalOptional(action.nav), tint: AppPalette.ink)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let comment = action.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.system(size: 12))
                        .foregroundStyle(AppPalette.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                WrapLine(items: [
                    sourceText("调仓估值", source: action.tradeValuationSource, date: action.tradeValuationDate),
                    sourceText("当前估值", source: action.currentValuationSource, date: action.currentValuationTime),
                    action.navDate.map { "净值日期 \($0)" },
                    action.adjustmentId.map { "调仓单 \($0)" },
                    action.orderCountInAdjustment.map { "同单动作 \($0)" }
                ].compactMap { $0 })

                if let article = action.articleUrl, let url = URL(string: article) {
                    Link(destination: url) {
                        Label("打开平台原文", systemImage: "arrow.up.right.square")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppPalette.line.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func detailMetric(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func sourceText(_ title: String, source: String?, date: String?) -> String? {
        let parts = [source, date].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !parts.isEmpty else { return nil }
        return "\(title)：\(parts.joined(separator: " · "))"
    }
}

struct WrapLine: View {
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    chips
                }

                VStack(alignment: .leading, spacing: 6) {
                    chips
                }
            }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(items, id: \.self) { item in
            Text(item)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppPalette.cardStrong)
                .clipShape(Capsule())
        }
    }
}

struct HoldingCard: View {
    let holding: HoldingItemPayload

    private var profitTint: Color {
        let value = holding.displayProfitPct ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            compactLayout
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppPalette.cardStrong.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppPalette.line.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var horizontalLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            accentBar

            identityBlock
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            metricsRow
                .frame(minWidth: 268, alignment: .leading)

            trailingSummary
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                accentBar
                identityBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailingSummary
            }

            ViewThatFits(in: .horizontal) {
                metricsRow
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    metricViews
                }
            }
            .padding(.leading, 13)
        }
    }

    private var accentBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(profitTint.opacity(0.9))
            .frame(width: 3, height: 42)
    }

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(holding.label ?? holding.fundName ?? "未命名标的")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)

            Text("\(holding.fundCode ?? "无代码") · \(holding.largeClass ?? "未分类")")
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)

            Text("最近 \(holding.latestActionTitle ?? holding.latestAction ?? "未知动作") · \(holding.latestTime ?? "未知时间")")
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted.opacity(0.88))
                .lineLimit(1)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 14) {
            metricViews
        }
    }

    @ViewBuilder
    private var metricViews: some View {
        HoldingCardMetric(title: "均价", value: decimalText(holding.avgCost))
        HoldingCardMetric(title: "现价", value: decimalText(holding.currentPrice))
        HoldingCardMetric(title: "市值", value: amountText(holding.displayPositionValue))
        HoldingCardMetric(title: "收益率", value: percentText(holding.displayProfitPct), tint: profitTint)
    }

    private var trailingSummary: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(holding.currentUnits ?? 0) 份")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.ink)
                .monospacedDigit()
                .lineLimit(1)

            Text(holding.priceSourceLabel ?? holding.priceSource ?? "估值来源未知")
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
        }
        .frame(minWidth: 74, alignment: .trailing)
    }

    private func decimalText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.4f", value)
    }

    private func amountText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%+.2f%%", value)
    }
}

private struct HoldingCardMetric: View {
    let title: String
    let value: String
    var tint: Color = AppPalette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(minWidth: 54, alignment: .leading)
    }
}

struct PlatformHoldingsPieChart: View {
    let holdings: [HoldingItemPayload]

    private var slices: [HoldingAllocationSlice] {
        let grouped = Dictionary(grouping: holdings.filter { ($0.currentUnits ?? 0) > 0 }, by: categoryLabel)
        var buckets = grouped.map { label, items in
            HoldingAllocationBucket(
                label: label,
                units: items.compactMap(\.currentUnits).reduce(0, +),
                assetCount: items.count
            )
        }
        .filter { $0.units > 0 }
        .sorted {
            if $0.units != $1.units {
                return $0.units > $1.units
            }
            return $0.label < $1.label
        }

        if buckets.count > 6 {
            let remainder = buckets.dropFirst(5).reduce(HoldingAllocationBucket(label: "其他", units: 0, assetCount: 0)) { partial, bucket in
                HoldingAllocationBucket(
                    label: partial.label,
                    units: partial.units + bucket.units,
                    assetCount: partial.assetCount + bucket.assetCount
                )
            }
            buckets = Array(buckets.prefix(5)) + [remainder]
        }

        let total = buckets.map(\.units).reduce(0, +)
        return buckets.enumerated().map { index, bucket in
            HoldingAllocationSlice(
                label: bucket.label,
                units: bucket.units,
                assetCount: bucket.assetCount,
                ratio: total > 0 ? Double(bucket.units) / Double(total) : 0,
                tint: allocationPalette[index % allocationPalette.count]
            )
        }
    }

    private var totalUnits: Int {
        slices.map(\.units).reduce(0, +)
    }

    private var largestSlice: HoldingAllocationSlice? {
        slices.first
    }

    private let allocationPalette: [Color] = [
        AppPalette.brand,
        AppPalette.info,
        AppPalette.accentWarm,
        AppPalette.positive,
        AppPalette.warning,
        AppPalette.danger,
        AppPalette.muted,
    ]

    var body: some View {
        if !slices.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.brand)
                    Text("当前持仓分布")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Spacer()
                    Text("按当前份数")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 18) {
                        pieVisual
                            .frame(width: 220, height: 176)
                        legend
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        pieVisual
                            .frame(maxWidth: .infinity)
                            .frame(height: 176)
                        legend
                    }
                }
            }
            .padding(14)
            .background(AppPalette.card.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppPalette.line.opacity(0.32), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var pieVisual: some View {
        ZStack {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("份数", slice.units),
                    innerRadius: .ratio(0.58),
                    angularInset: 1.2
                )
                .foregroundStyle(slice.tint)
            }
            .chartLegend(.hidden)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)

            VStack(spacing: 1) {
                Text("\(totalUnits)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.ink)
                Text("当前份数")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                if let largestSlice {
                    Text("最大 \(largestSlice.label)")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.muted.opacity(0.9))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(slices) { slice in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(slice.tint)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(slice.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                            .lineLimit(1)
                        Text("\(slice.assetCount) 只 · \(percentText(slice.ratio))")
                            .font(.system(size: 9))
                            .foregroundStyle(AppPalette.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 10)

                    Text("\(slice.units) 份")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryLabel(for holding: HoldingItemPayload) -> String {
        let largeClass = (holding.largeClass ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !largeClass.isEmpty {
            return largeClass
        }

        let strategyType = (holding.strategyType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !strategyType.isEmpty {
            return strategyType
        }

        return "未分类"
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}

private struct HoldingAllocationBucket {
    let label: String
    let units: Int
    let assetCount: Int
}

private struct HoldingAllocationSlice: Identifiable {
    let label: String
    let units: Int
    let assetCount: Int
    let ratio: Double
    let tint: Color

    var id: String { label }
}

struct PlatformMonthlyOverview: View {
    let months: [PlatformMonthSummary]

    private var totalCount: Int {
        months.map(\.totalCount).reduce(0, +)
    }

    private var buyCount: Int {
        months.map(\.buyCount).reduce(0, +)
    }

    private var sellCount: Int {
        months.map(\.sellCount).reduce(0, +)
    }

    private var activeDays: Int {
        months.map(\.activeDays).reduce(0, +)
    }

    private var busiestMonth: PlatformMonthSummary? {
        months.max { left, right in
            if left.totalCount != right.totalCount {
                return left.totalCount < right.totalCount
            }
            return left.month < right.month
        }
    }

    private var averagePerMonthText: String {
        guard !months.isEmpty else { return "0.0" }
        return String(format: "%.1f", Double(totalCount) / Double(months.count))
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                summaryPanel
                    .frame(width: 270)
                monthChart
            }

            VStack(alignment: .leading, spacing: 12) {
                summaryPanel
                monthChart
            }
        }
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 18))
                    .foregroundStyle(AppPalette.brand)
                    .frame(width: 38, height: 38)
                    .background(AppPalette.brand.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("近 12 个月")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text(months.first.map { "\($0.month) 起" } ?? "暂无月份")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(totalCount)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.ink)
                Text("笔")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
            }

            VStack(spacing: 8) {
                rhythmLine(title: "买入", value: buyCount, tint: AppPalette.positive)
                rhythmLine(title: "卖出", value: sellCount, tint: AppPalette.warning)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                SnapshotMiniBadge(text: "活跃 \(activeDays) 天", tint: AppPalette.info)
                SnapshotMiniBadge(text: "月均 \(averagePerMonthText) 笔", tint: AppPalette.brand)
                if let busiestMonth {
                    SnapshotMiniBadge(text: "最密 \(busiestMonth.month)", tint: AppPalette.accentWarm)
                    SnapshotMiniBadge(text: "\(busiestMonth.totalCount) 笔", tint: AppPalette.accentWarm)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppPalette.card.opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppPalette.line.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @State private var selectedMonth: PlatformMonthSummary?
    @State private var hoverLocation: CGPoint = .zero

    private var monthChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            chartLegend
            chartBody
                .overlay { chartTooltip }
                .frame(height: 200)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.card.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppPalette.line.opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var chartLegend: some View {
        HStack(spacing: 12) {
            Label("买入", systemImage: "square.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppPalette.positive)
            Label("卖出", systemImage: "square.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppPalette.warning)
        }
    }

    private var chartBody: some View {
        Chart {
            ForEach(months) { month in
                BarMark(
                    x: .value("月", String(month.month.suffix(2))),
                    y: .value("买入", month.buyCount)
                )
                .foregroundStyle(AppPalette.positive)
                .position(by: .value("类型", "买入"))

                BarMark(
                    x: .value("月", String(month.month.suffix(2))),
                    y: .value("卖出", month.sellCount)
                )
                .foregroundStyle(AppPalette.warning)
                .position(by: .value("类型", "卖出"))
            }

            if let selectedMonth {
                RuleMark(x: .value("月", String(selectedMonth.month.suffix(2))))
                    .foregroundStyle(AppPalette.line.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let frame = proxy.plotFrame else { return }
                            let plotRect = geo[frame]
                            let relX = location.x - plotRect.origin.x
                            let relY = location.y - plotRect.origin.y
                            guard relX >= 0, relX <= plotRect.width, relY >= 0, relY <= plotRect.height else {
                                selectedMonth = nil
                                return
                            }
                            hoverLocation = location
                            if let xVal: String = proxy.value(atX: relX) {
                                selectedMonth = months.first { String($0.month.suffix(2)) == xVal }
                            }
                        case .ended:
                            selectedMonth = nil
                        }
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                    .font(.system(size: 9, design: .rounded))
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(AppPalette.line.opacity(0.4))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
        }
    }

    private var chartTooltip: some View {
        GeometryReader { geo in
            if let m = selectedMonth {
                let tooltipWidth: CGFloat = 160
                let tooltipHeight: CGFloat = 60
                let tipX = min(max(hoverLocation.x + 12, 0), geo.size.width - tooltipWidth)
                let tipY = min(max(hoverLocation.y - tooltipHeight - 8, 0), geo.size.height - tooltipHeight)
                tooltipContent(month: m)
                    .frame(width: tooltipWidth, alignment: .leading)
                    .position(x: tipX + tooltipWidth / 2, y: tipY + tooltipHeight / 2)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.12), value: selectedMonth?.id)
            }
        }
    }

    @ViewBuilder
    private func tooltipContent(month m: PlatformMonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(m.month)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            HStack(spacing: 8) {
                Text("买入 \(m.buyCount)")
                    .foregroundStyle(AppPalette.positive)
                Text("卖出 \(m.sellCount)")
                    .foregroundStyle(AppPalette.warning)
            }
            .font(.system(size: 10, weight: .semibold))
            Text("共 \(m.totalCount) 笔 · 活跃 \(m.activeDays) 天")
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(8)
        .background(AppPalette.cardStrong)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }

    private func rhythmLine(title: String, value: Int, tint: Color) -> some View {
        let ratio = totalCount > 0 ? Double(value) / Double(totalCount) : 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)")
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppPalette.muted)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppPalette.cardStrong)
                    Capsule()
                        .fill(tint.opacity(0.78))
                        .frame(width: max(6, proxy.size.width * ratio))
                }
            }
            .frame(height: 7)
        }
    }
}
