import SwiftUI

struct AITrendSummaryPanel: View {
    let summary: TrendDashboardSummary
    let action: (TrendDashboardAction) -> Void

    private func trendHorizonWideColumns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 190), spacing: 10, alignment: .top), count: max(1, min(3, count)))
    }

    private func trendHorizonMediumColumns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 190), spacing: 10, alignment: .top), count: max(1, min(2, count)))
    }

    private var trendHorizonCompactColumns: [GridItem] {
        [GridItem(.flexible(minimum: 190), spacing: 10, alignment: .top)]
    }

    private func trendSectorWideColumns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 220), spacing: 10, alignment: .top), count: max(1, min(4, count)))
    }

    private func trendSectorMediumColumns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 220), spacing: 10, alignment: .top), count: max(1, min(2, count)))
    }

    private var trendSectorCompactColumns: [GridItem] {
        [GridItem(.flexible(minimum: 220), spacing: 10, alignment: .top)]
    }

    var body: some View {
        SectionCard(title: "AI 趋势摘要", subtitle: subtitle, icon: "sparkles", trailing: {
            Spacer()
            ToolbarBadge(title: summary.stateText, tint: summary.status.tint)
            ToolbarBadge(title: summary.riskText, tint: summary.riskTone.color)
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(summary.riskTone.color)
                        .frame(width: 3, height: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary.headline)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(summary.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(AppPalette.muted)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))

                if !summary.horizons.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        LazyVGrid(columns: trendHorizonWideColumns(count: summary.horizons.count), alignment: .leading, spacing: 10) {
                            ForEach(summary.horizons) { horizon in
                                AITrendHorizonCard(item: horizon)
                            }
                        }

                        LazyVGrid(columns: trendHorizonMediumColumns(count: summary.horizons.count), alignment: .leading, spacing: 10) {
                            ForEach(summary.horizons) { horizon in
                                AITrendHorizonCard(item: horizon)
                            }
                        }

                        LazyVGrid(columns: trendHorizonCompactColumns, alignment: .leading, spacing: 10) {
                            ForEach(summary.horizons) { horizon in
                                AITrendHorizonCard(item: horizon)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !summary.sectors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("板块观点")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                        ViewThatFits(in: .horizontal) {
                            LazyVGrid(columns: trendSectorWideColumns(count: summary.sectors.count), alignment: .leading, spacing: 10) {
                                ForEach(summary.sectors) { sector in
                                    AITrendSectorCard(item: sector)
                                }
                            }

                            LazyVGrid(columns: trendSectorMediumColumns(count: summary.sectors.count), alignment: .leading, spacing: 10) {
                                ForEach(summary.sectors) { sector in
                                    AITrendSectorCard(item: sector)
                                }
                            }

                            LazyVGrid(columns: trendSectorCompactColumns, alignment: .leading, spacing: 10) {
                                ForEach(summary.sectors) { sector in
                                    AITrendSectorCard(item: sector)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        trendActionButton(summary.primaryAction)
                        if let secondaryAction = summary.secondaryAction {
                            trendActionButton(secondaryAction)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        trendActionButton(summary.primaryAction)
                        if let secondaryAction = summary.secondaryAction {
                            trendActionButton(secondaryAction)
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let parts = [
            summary.dataAsOf.map { "数据 \($0)" },
            summary.externalSignalText,
            summary.generatedAt.map { "生成 \($0)" }
        ].compactMap { $0 }
        return parts.isEmpty ? "组合级 AI 判断与条件式复核入口" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func trendActionButton(_ item: TrendDashboardAction) -> some View {
        if item.isPrimary {
            Button {
                action(item)
            } label: {
                Label(item.title, systemImage: item.systemImage)
            }
            .buttonStyle(.borderedProminent)
            .tint(item.tone.color)
            .controlSize(.small)
            .disabled(item.isDisabled)
        } else {
            Button {
                action(item)
            } label: {
                Label(item.title, systemImage: item.systemImage)
            }
            .buttonStyle(.bordered)
            .tint(item.tone.color)
            .controlSize(.small)
            .disabled(item.isDisabled)
        }
    }
}

private struct AITrendHorizonCard: View {
    let item: TrendDashboardHorizonItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                Spacer(minLength: 4)
                Text(item.directionText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(item.tone.color)
            }
            Text(item.confidenceText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(item.tone.color)
            Text(item.rationale)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(AppPalette.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(item.tone.color.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct AITrendSectorCard: View {
    let item: TrendDashboardSectorItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(item.exposureText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.info)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(item.directionText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(item.tone.color)
                Text(item.confidenceText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
            }
            Text(item.rationale)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(item.tone.color.opacity(0.14), lineWidth: 1)
        )
    }
}

private extension TrendDashboardStatus {
    var tint: Color {
        switch self {
        case .unconfigured, .stale, .rejected:
            return AppPalette.warning
        case .empty, .generating:
            return AppPalette.info
        case .ready:
            return AppPalette.positive
        case .failed:
            return AppPalette.danger
        }
    }
}

private extension TrendDashboardTone {
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
