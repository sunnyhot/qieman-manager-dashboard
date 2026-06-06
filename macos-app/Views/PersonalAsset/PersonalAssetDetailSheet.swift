import SwiftUI

private extension PersonalAssetDetailTone {
    var color: Color {
        switch self {
        case .brand:
            return AppPalette.brand
        case .info:
            return AppPalette.info
        case .warning:
            return AppPalette.warning
        case .muted:
            return AppPalette.muted
        case .marketGain:
            return AppPalette.marketGain
        case .marketLoss:
            return AppPalette.marketLoss
        }
    }
}

struct PersonalAssetDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let row: PersonalAssetAggregateRow

    private var summary: PersonalAssetDetailSummary {
        PersonalAssetDetailSummary.make(row: row)
    }

    private var changeTint: Color {
        AppPalette.marketTint(for: row.estimateChangeAmount)
    }

    private var profitTint: Color {
        AppPalette.marketTint(for: row.profitAmount)
    }

    var body: some View {
        let summary = summary

        VStack(spacing: 0) {
            header(summary)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
                        ForEach(summary.metrics) { metric in
                            detailMetricCard(metric)
                        }
                    }

                    attentionSection(summary.attentionItems)
                    priceSection
                    sourceSection
                }
                .padding(16)
            }
        }
        .frame(width: 560)
        .frame(minHeight: 560)
        .background(AppPalette.surface)
    }

    private func header(_ summary: PersonalAssetDetailSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: row.assetType == .stock ? "chart.line.uptrend.xyaxis" : "chart.pie")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(row.assetType == .stock ? AppPalette.info : AppPalette.brand)
                    .frame(width: 40, height: 40)
                    .background((row.assetType == .stock ? AppPalette.info : AppPalette.brand).opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        if let codeText = summary.codeText, !codeText.isEmpty {
                            Text(codeText)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(AppPalette.muted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.badgeRadius))
                        }
                        if let marketText = summary.marketText {
                            ToolbarBadge(title: marketText, tint: AppPalette.info)
                        }
                        ToolbarBadge(title: summary.statusText, tint: row.hasPending ? AppPalette.warning : AppPalette.brand)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppPalette.muted)
                    .help("关闭")

                    Text(summary.effectiveAmountText)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("总持仓")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
            }
        }
        .padding(16)
        .background(AppPalette.card, in: Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppPalette.line.opacity(0.42))
                .frame(height: 1)
        }
    }

    private func detailMetricCard(_ metric: PersonalAssetDetailMetric) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            Text(metric.value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(metric.tone.color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if let detail = metric.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(metric.tone.color.opacity(0.16), lineWidth: 1)
        )
    }

    private func attentionSection(_ items: [PersonalAssetDetailAttentionItem]) -> some View {
        detailSection(title: "待处理事项", icon: "list.bullet.rectangle") {
            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppPalette.positive)
                    Text("暂无买入中、进行中计划或归档提醒")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .padding(12)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        HStack(alignment: .center, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(item.tone.color)
                                .frame(width: 3, height: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppPalette.ink)
                                Text(item.detail.isEmpty ? "暂无附加信息" : item.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppPalette.muted)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(item.metric)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(item.tone.color)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .padding(12)
                        .background(AppPalette.cardStrong.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                    }
                }
            }
        }
    }

    private var priceSection: some View {
        detailSection(title: "价格与收益", icon: "chart.xyaxis.line") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], spacing: 10) {
                compactFact(title: row.usesMarketTradeColumns ? "现价" : "净值", value: row.currentPrice.map(decimalText) ?? "—", tint: AppPalette.ink)
                compactFact(title: "估值", value: row.currentEstimatePrice.map(decimalText) ?? "—", tint: changeTint)
                compactFact(title: "成本", value: row.costPrice.map(decimalText) ?? "—", tint: AppPalette.ink)
                compactFact(title: "总收益率", value: percentOptional(row.profitPct), tint: profitTint)
                compactFact(title: "今日涨跌幅", value: percentOptional(row.estimateChangePct), tint: changeTint)
                compactFact(title: "估值时间", value: row.holdingRow?.resolvedPriceTime ?? "—", tint: AppPalette.muted)
            }
        }
    }

    private var sourceSection: some View {
        detailSection(title: "本地记录", icon: "tray.full") {
            HStack(spacing: 10) {
                compactFact(title: "持仓", value: row.hasHolding ? "已记录" : (row.hasArchivedHolding ? "已归档" : "暂无"), tint: row.hasHolding ? AppPalette.brand : AppPalette.muted)
                compactFact(title: "买入中", value: "\(row.pendingTradeCount) 笔", tint: row.pendingTradeCount > 0 ? AppPalette.warning : AppPalette.muted)
                compactFact(title: "计划", value: "\(row.activePlanCount) / \(row.pausedPlanCount) / \(row.endedPlanCount)", tint: row.totalPlanCount > 0 ? AppPalette.info : AppPalette.muted)
            }
        }
    }

    private func compactFact(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .cardStroke(opacity: 0.28)
    }

    private func detailSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                    .accentIconStyle(tint: AppPalette.brand, size: 22)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Spacer()
            }
            content()
        }
        .padding(14)
        .background(AppPalette.card.opacity(0.82), in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .panelStroke(opacity: 0.36)
    }
}
