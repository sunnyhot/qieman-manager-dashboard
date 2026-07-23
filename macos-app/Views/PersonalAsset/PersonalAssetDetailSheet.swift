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

private enum AssetDetailLayout {
    static let sheetWidth: CGFloat = 760
    static let minimumHeight: CGFloat = 620
    static let idealHeight: CGFloat = 720
    static let maximumHeight: CGFloat = 780
    static let secondaryColumnWidth: CGFloat = 292
    static let metricColumns = Array(
        repeating: GridItem(.flexible(minimum: 112), spacing: 10),
        count: 5
    )
}

struct PersonalAssetDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let row: PersonalAssetAggregateRow
    var trendSummary: TrendAssetTagSummary?

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
                    LazyVGrid(columns: AssetDetailLayout.metricColumns, spacing: 10) {
                        ForEach(summary.metrics) { metric in
                            detailMetricCard(metric)
                        }
                    }

                    PersonalAssetPriceTrendChart(row: row)

                    if let trendSummary {
                        trendAnalysisSection(trendSummary)
                    }
                    supportingSections(summary.attentionItems)
                }
                .padding(16)
            }
        }
        .frame(width: AssetDetailLayout.sheetWidth)
        .frame(
            minHeight: AssetDetailLayout.minimumHeight,
            idealHeight: AssetDetailLayout.idealHeight,
            maxHeight: AssetDetailLayout.maximumHeight
        )
        .background(AppPalette.surface)
    }

    private func header(_ summary: PersonalAssetDetailSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: row.assetType == .stock ? "chart.line.uptrend.xyaxis" : "chart.pie")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(row.assetType == .stock ? AppPalette.info : AppPalette.brand)
                    .frame(width: 44, height: 44)
                    .background((row.assetType == .stock ? AppPalette.info : AppPalette.brand).opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.title)
                        .font(.system(size: 20, weight: .bold))
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
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppPalette.muted)
                    .help("关闭")
                    .accessibilityLabel("关闭资产详情")

                    Text(summary.effectiveAmountText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
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
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
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

    private func supportingSections(_ items: [PersonalAssetDetailAttentionItem]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    attentionSection(items)
                    sourceSection
                }
                .frame(width: AssetDetailLayout.secondaryColumnWidth, alignment: .top)

                priceSection
                    .frame(minWidth: 360, maxWidth: .infinity, alignment: .top)
            }

            VStack(spacing: 14) {
                attentionSection(items)
                priceSection
                sourceSection
            }
        }
    }

    private func trendAnalysisSection(_ summary: TrendAssetTagSummary) -> some View {
        detailSection(title: "AI 观点", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                trendDecisionHeader(summary)

                Divider()
                    .overlay(AppPalette.line.opacity(0.46))

                HStack(alignment: .top, spacing: 14) {
                    trendActionBlock(summary.tradePlan)
                    trendEvidenceBlock(summary)
                }

                let invalidationConditions = trendInvalidationConditions(summary)
                if !invalidationConditions.isEmpty {
                    Divider()
                        .overlay(AppPalette.line.opacity(0.46))
                    trendInvalidationBlock(invalidationConditions)
                }
            }
        }
    }

    private func trendDecisionHeader(_ summary: TrendAssetTagSummary) -> some View {
        let tone = summary.primaryDirection?.assetTagTone ?? summary.tradePlan.tone

        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tone.color)
                .frame(width: 3, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text("当前判断")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                HStack(spacing: 7) {
                    Text(summary.primaryDirection?.assetTagText ?? summary.tradePlan.label)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tone.color)
                    Text("\(summary.primaryConfidence.label)信心")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.badgeRadius))
                }
                Text(summary.impactText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("数据截至 \(summary.dataAsOf)")
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
        }
    }

    private func trendActionBlock(_ plan: TrendAssetTradePlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("操作建议", systemImage: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(plan.tone.color)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(plan.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(plan.tone.color)
                Text("·")
                    .foregroundStyle(AppPalette.muted)
                Text(plan.method)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
            }

            Text(plan.detail)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !plan.triggerConditions.isEmpty {
                Divider()
                    .overlay(AppPalette.line.opacity(0.38))
                trendConditionList(
                    title: "执行前确认",
                    items: Array(plan.triggerConditions.prefix(3)),
                    tint: plan.tone.color
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(12)
        .background(plan.tone.color.opacity(0.07), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(plan.tone.color.opacity(0.18), lineWidth: 1)
        )
    }

    private func trendEvidenceBlock(_ summary: TrendAssetTagSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("判断依据", systemImage: "list.bullet.clipboard")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppPalette.info)

            if !summary.horizons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.horizons, id: \.horizon) { horizon in
                        trendHorizonRow(horizon)
                    }
                }
            }

            if !summary.rationale.isEmpty {
                if !summary.horizons.isEmpty {
                    Divider()
                        .overlay(AppPalette.line.opacity(0.38))
                }
                Text(summary.rationale)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(12)
        .background(AppPalette.cardStrong.opacity(0.52), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }

    private func trendHorizonRow(_ horizon: TrendHorizonView) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(horizon.horizon.assetTagText)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(horizon.direction.assetTagTone.color)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(horizon.direction.assetTagText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(horizon.direction.assetTagTone.color)
                    Text("\(horizon.confidence.label)信心")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                }
                Text(horizon.rationale)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func trendConditionList(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(tint)
                        .frame(width: 4, height: 4)
                        .padding(.top, 5)
                    Text(item)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trendInvalidationBlock(_ conditions: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.warning)
                .frame(width: 28, height: 28)
                .background(AppPalette.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

            VStack(alignment: .leading, spacing: 7) {
                Text("什么情况下改变判断")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.warning)
                Text("出现以下任一情况，需要重新评估上面的结论。")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.muted)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: 8)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(conditions, id: \.self) { condition in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(AppPalette.warning)
                                .frame(width: 4, height: 4)
                                .padding(.top, 5)
                            Text(condition)
                                .font(.system(size: 10))
                                .foregroundStyle(AppPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .background(AppPalette.warning.opacity(0.06), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }

    private func trendInvalidationConditions(_ summary: TrendAssetTagSummary) -> [String] {
        var seen = Set<String>()
        return (summary.tradePlan.invalidatingConditions + summary.counterSignals).compactMap { rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = value.replacingOccurrences(of: "。", with: "")
            guard !value.isEmpty, seen.insert(key).inserted else { return nil }
            return value
        }
        .prefix(4)
        .map(\.self)
    }

    private var priceSection: some View {
        detailSection(title: "价格与收益", icon: "chart.xyaxis.line") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], spacing: 10) {
                compactFact(title: row.usesMarketTradeColumns ? "现价" : "净值", value: row.currentPrice.map(decimalText) ?? "—", tint: AppPalette.ink)
                compactFact(title: "估值", value: row.currentEstimatePrice.map(decimalText) ?? "—", tint: changeTint)
                compactFact(title: "成本", value: row.costPrice.map(decimalText) ?? "—", tint: AppPalette.ink)
                compactFact(title: "总收益率", value: percentOptional(row.profitPct), tint: profitTint)
                compactFact(title: "今日涨跌幅", value: dailyChangePercentText(row.estimateChangePct), tint: changeTint)
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

private extension TrendAssetTagTone {
    var color: Color {
        switch self {
        case .brand:
            return AppPalette.brand
        case .positive:
            return AppPalette.positive
        case .info:
            return AppPalette.info
        case .warning:
            return AppPalette.warning
        case .danger:
            return AppPalette.danger
        case .muted:
            return AppPalette.muted
        }
    }
}
