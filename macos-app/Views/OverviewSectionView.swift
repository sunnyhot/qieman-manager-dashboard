import SwiftUI

// MARK: - Overview

struct TodayBriefSummaryItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color
}

struct OverviewSectionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                TodayBriefPanel(
                    items: model.todayBriefItems,
                    summaryItems: overviewBriefSummaryItems,
                    action: openBrief,
                    summaryAction: openPortfolio
                )
                AITrendSummaryPanel(
                    summary: model.trendDashboardSummary,
                    action: handleTrendDashboardAction
                )

                SectionCard(title: "最近调仓", subtitle: "原生卡片直接消费平台接口", icon: "arrow.left.arrow.right", trailing: {
                    Spacer()
                    Button("查看全部") {
                        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
                            model.selectedSection = .platform
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }) {
                    if model.latestPlatformActions.isEmpty {
                        EmptySectionState(
                            title: "最近调仓暂时为空",
                            subtitle: "平台接口现在会和论坛分开刷新；点一次刷新后，这里会优先恢复可用数据。",
                            actionTitle: "刷新"
                        ) {
                            Task { try? await model.refreshLatest(persist: false) }
                        }
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(model.latestPlatformActions.prefix(3))) { action in
                                Button {
                                    openPlatform(action)
                                } label: {
                                    PlatformActionRow(action: action)
                                }
                                .buttonStyle(PressResponsiveButtonStyle())
                                .help("打开平台调仓详情")
                            }
                        }
                    }
                }

                // Recent posts
                SectionCard(
                    title: model.currentSnapshot?.snapshotType == "posts" ? "最近发言" : "最近记录",
                    subtitle: model.currentSnapshot?.kindLabel == "帖子" ? "主理人发言摘要" : "当前模式下的最新原生结果",
                    icon: "text.bubble",
                    trailing: {
                        Spacer()
                        Button("查看全部") {
                            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
                                model.selectedSection = .forum
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                ) {
                    if model.hasForumPosts {
                        VStack(spacing: 8) {
                            ForEach(Array(model.forumRecords.prefix(3))) { record in
                                Button {
                                    openForum(record)
                                } label: {
                                    ForumRecordRow(record: record)
                                }
                                .buttonStyle(PressResponsiveButtonStyle())
                                .help("打开论坛发言详情")
                            }
                        }
                    } else {
                        EmptySectionState(
                            title: "最近发言暂时为空",
                            subtitle: "论坛页会自动补拉帖子流；这里也会跟着恢复到最新发言。",
                            actionTitle: "刷新"
                        ) {
                            Task { try? await model.refreshLatest(persist: false) }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func openPortfolio() {
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
            model.selectedSection = .portfolio
        }
    }

    private func handleTrendDashboardAction(_ action: TrendDashboardAction) {
        guard !action.isDisabled else { return }
        switch action.kind {
        case .configure:
            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
                model.selectedSection = .settings
            }
        case .generate, .refresh:
            Task {
                await model.generateTrendAnalysis(userInitiated: true)
            }
        case .openReport:
            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
                model.selectedEnhancementTab = .trend
                model.selectedSection = .enhancement
            }
        case .wait:
            break
        }
    }

    private func openBrief(_ item: TodayBriefItem) {
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
            switch item.destination {
            case .portfolio:
                model.selectedSection = .portfolio
            case .platform:
                if let action = model.latestPlatformActions.first {
                    model.selectPlatformAction(action.id)
                }
                model.selectedSection = .platform
            case .forum:
                if let record = model.forumRecords.first {
                    model.selectedPostID = record.id
                }
                model.selectedSection = .forum
            case .settings:
                model.selectedSection = .settings
            }
        }
    }

    private var overviewBriefSummaryItems: [TodayBriefSummaryItem] {
        [
            TodayBriefSummaryItem(
                id: "total",
                title: "总持仓",
                value: model.personalAssetSummary.map { currencyText($0.totalEffectiveHoldingAmount) } ?? "—",
                detail: model.personalAssetSummary.map {
                    "已持有 \(currencyText($0.totalMarketValue)) + 待确认 \(currencyText($0.totalPendingCashAmount)) + 下次计划 \(currencyText($0.totalEstimatedNextPlanAmount))"
                } ?? "个人资产还未导入完整",
                icon: "wallet.bifold",
                tint: AppPalette.brand
            ),
            TodayBriefSummaryItem(
                id: "pending",
                title: "待确认买入",
                value: model.personalAssetSummary.map { currencyText($0.totalPendingCashAmount) } ?? "—",
                detail: model.pendingTradeSummary.map { "\($0.actionCount) 笔交易进行中" } ?? "暂无买入中",
                icon: "clock.badge.exclamationmark",
                tint: AppPalette.warning
            ),
            TodayBriefSummaryItem(
                id: "plans",
                title: "计划档案",
                value: model.investmentPlanSummary.map { "\($0.activePlanCount) / \($0.pausedPlanCount) / \($0.endedPlanCount)" } ?? "—",
                detail: model.investmentPlanSummary.map { "进行中 / 暂停 / 终止 · 共 \($0.planCount) 条" } ?? "还没有计划档案",
                icon: "calendar.badge.clock",
                tint: AppPalette.info
            ),
            TodayBriefSummaryItem(
                id: "coverage",
                title: "覆盖标的",
                value: model.personalAssetSummary.map { "\($0.fundCount)" } ?? "0",
                detail: model.personalAssetSummary.map { "持有 \($0.holdingFundCount) · 待确认 \($0.pendingFundCount) · 有计划 \($0.activePlanFundCount)" } ?? "先导入你的个人资产",
                icon: "square.grid.3x2",
                tint: AppPalette.accentWarm
            )
        ]
    }

    private func openPlatform(_ action: PlatformActionPayload) {
        model.selectPlatformAction(action.id)
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
            model.selectedSection = .platform
        }
    }

    private func openForum(_ record: SnapshotRecordPayload) {
        model.selectedPostID = record.id
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
            model.selectedSection = .forum
        }
    }
}

private extension TodayBriefTone {
    var overviewTint: Color {
        switch self {
        case .brand:
            return AppPalette.brand
        case .info:
            return AppPalette.info
        case .warning:
            return AppPalette.warning
        case .danger:
            return AppPalette.danger
        case .positive:
            return AppPalette.positive
        case .muted:
            return AppPalette.muted
        case .marketGain:
            return AppPalette.marketGain
        case .marketLoss:
            return AppPalette.marketLoss
        }
    }
}

struct TodayBriefPanel: View {
    let items: [TodayBriefItem]
    let summaryItems: [TodayBriefSummaryItem]
    let action: (TodayBriefItem) -> Void
    let summaryAction: () -> Void

    private var todayBriefWideColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 220), spacing: 10, alignment: .top), count: 4)
    }

    private var todayBriefMediumColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 220), spacing: 10, alignment: .top), count: 2)
    }

    private var todayBriefCompactColumns: [GridItem] {
        [GridItem(.flexible(minimum: 220), spacing: 10, alignment: .top)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                    .accentIconStyle(tint: AppPalette.brand, size: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("今日看点")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("资产摘要 + 今日事项")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ToolbarBadge(title: items.isEmpty ? "暂无" : "\(items.count) 项", tint: items.isEmpty ? AppPalette.muted : AppPalette.brand)
            }

            if !summaryItems.isEmpty {
                ViewThatFits(in: .horizontal) {
                    LazyVGrid(columns: todayBriefWideColumns, alignment: .leading, spacing: 10) {
                        ForEach(summaryItems) { item in
                            TodayBriefSummaryCard(item: item, action: summaryAction)
                        }
                    }

                    LazyVGrid(columns: todayBriefMediumColumns, alignment: .leading, spacing: 10) {
                        ForEach(summaryItems) { item in
                            TodayBriefSummaryCard(item: item, action: summaryAction)
                        }
                    }

                    LazyVGrid(columns: todayBriefCompactColumns, alignment: .leading, spacing: 10) {
                        ForEach(summaryItems) { item in
                            TodayBriefSummaryCard(item: item, action: summaryAction)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppPalette.positive)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今天暂无需要处理的事项")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                        Text("持仓、计划和最新记录刷新后会自动出现在这里")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .padding(12)
                .background(AppPalette.cardStrong.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                .cardStroke(opacity: 0.28)
            } else {
                ViewThatFits(in: .horizontal) {
                    LazyVGrid(columns: todayBriefWideColumns, alignment: .leading, spacing: 10) {
                        ForEach(items) { item in
                            TodayBriefItemButton(item: item) {
                                action(item)
                            }
                        }
                    }

                    LazyVGrid(columns: todayBriefMediumColumns, alignment: .leading, spacing: 10) {
                        ForEach(items) { item in
                            TodayBriefItemButton(item: item) {
                                action(item)
                            }
                        }
                    }

                    LazyVGrid(columns: todayBriefCompactColumns, alignment: .leading, spacing: 10) {
                        ForEach(items) { item in
                            TodayBriefItemButton(item: item) {
                                action(item)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .panelStroke()
        .sectionShadow()
    }
}

struct TodayBriefSummaryCard: View {
    let item: TodayBriefSummaryItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: 30, height: 30)
                    .background(item.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                            .stroke(item.tint.opacity(0.18), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(1)
                    Text(item.value)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                    Text(item.detail)
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(item.tint)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .interactiveSurface(
                tint: item.tint,
                fill: AppPalette.cardStrong.opacity(0.72),
                hoverFill: AppPalette.cardHover,
                strokeOpacity: 0.16,
                activeStrokeOpacity: 0.36,
                lift: 0.6
            )
        }
        .buttonStyle(PressResponsiveButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("打开我的持仓")
    }
}

struct TodayBriefItemButton: View {
    let item: TodayBriefItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: item.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.tone.overviewTint)
                    .frame(width: 32, height: 32)
                    .background(item.tone.overviewTint.opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                            .stroke(item.tone.overviewTint.opacity(0.18), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(item.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.metric)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(item.tone.overviewTint)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppPalette.muted)
                }
                .frame(minWidth: 54, alignment: .trailing)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .interactiveSurface(
                tint: item.tone.overviewTint,
                fill: AppPalette.cardStrong.opacity(0.72),
                hoverFill: AppPalette.cardHover,
                strokeOpacity: 0.18,
                activeStrokeOpacity: 0.40,
                lift: 0.8
            )
        }
        .buttonStyle(PressResponsiveButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(item.title)
    }
}

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

struct ManagerWatchControlCard: View {
    @EnvironmentObject private var model: AppModel

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.managerWatchSettings.isEnabled },
            set: { model.updateManagerWatchEnabled($0) }
        )
    }

    private var forumBinding: Binding<Bool> {
        Binding(
            get: { model.managerWatchSettings.watchForum },
            set: { model.updateManagerWatchForumEnabled($0) }
        )
    }

    private var platformBinding: Binding<Bool> {
        Binding(
            get: { model.managerWatchSettings.watchPlatform },
            set: { model.updateManagerWatchPlatformEnabled($0) }
        )
    }

    private var prodCodeBinding: Binding<String> {
        Binding(
            get: { model.managerWatchSettings.prodCode },
            set: { model.managerWatchSettings.prodCode = $0 }
        )
    }

    private var managerNameBinding: Binding<String> {
        Binding(
            get: { model.managerWatchSettings.managerName },
            set: { model.managerWatchSettings.managerName = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLoginEnabled },
            set: { model.updateLaunchAtLoginEnabled($0) }
        )
    }

    var body: some View {
        SectionCard(title: "主理人提醒", subtitle: "App 常驻时自动巡检新调仓和新发言，并通过系统通知推送", icon: "bell.badge") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    managerWatchControls
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    managerWatchStatusPanel
                        .frame(width: 380, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 12) {
                    managerWatchControls
                    managerWatchStatusPanel
                }
            }
        }
    }

    private var managerWatchControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Toggle("开启通知巡检", isOn: enabledBinding)
                    .toggleStyle(.switch)
                ToolbarBadge(
                    title: model.managerWatchStatusText,
                    tint: model.managerWatchSettings.isEnabled ? AppPalette.positive : AppPalette.muted
                )
                ToolbarBadge(title: model.managerWatchSettings.intervalLabel, tint: AppPalette.info)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                compactField("产品", text: prodCodeBinding, minWidth: 220)
                compactField("主理人", text: managerNameBinding, minWidth: 220)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    Toggle("监控平台调仓", isOn: platformBinding)
                        .toggleStyle(.checkbox)
                    Toggle("监控主理人发言", isOn: forumBinding)
                        .toggleStyle(.checkbox)
                    intervalMenu
                        .frame(maxWidth: 240)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("监控平台调仓", isOn: platformBinding)
                        .toggleStyle(.checkbox)
                    Toggle("监控主理人发言", isOn: forumBinding)
                        .toggleStyle(.checkbox)
                    intervalMenu
                }
            }
            .font(.system(size: 12))

            HStack(spacing: 10) {
                Button("保存设置") {
                    model.saveManagerWatchConfiguration()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.brand)

                Button("同步当前查询") {
                    model.syncManagerWatchTargetsFromCurrentForm()
                }
                .buttonStyle(.bordered)

                Button("立即巡检") {
                    model.runManagerWatchNow()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(AppPalette.cardStrong.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.55), lineWidth: 1)
        )
    }

    private var managerWatchStatusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bell.and.waves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                    .frame(width: 34, height: 34)
                    .background(AppPalette.brandSoft, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

                VStack(alignment: .leading, spacing: 2) {
                    Text("巡检状态")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text(model.managerWatchScopeText)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(1)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ManagerWatchStatusTile(title: "巡检目标", value: model.managerWatchScopeText, tint: AppPalette.brand)
                ManagerWatchStatusTile(
                    title: "上次检查",
                    value: model.managerWatchSettings.lastCheckedAt ?? "暂无",
                    tint: AppPalette.muted
                )
                ManagerWatchStatusTile(
                    title: "上次成功",
                    value: model.managerWatchSettings.lastSuccessAt ?? "暂无",
                    tint: AppPalette.positive
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("开机自启", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                HStack(spacing: 8) {
                    ToolbarBadge(title: model.launchAtLoginStatusText, tint: model.launchAtLoginEnabled ? AppPalette.positive : AppPalette.muted)
                    ToolbarBadge(title: "关闭窗口后保留菜单栏", tint: AppPalette.info)
                }
            }
            .font(.system(size: 12))

            if let error = model.managerWatchSettings.lastErrorMessage, !error.isEmpty {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppPalette.warning)
                        .frame(width: 4)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.ink)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            }
        }
        .padding(14)
        .background(AppPalette.card.opacity(0.82), in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.55), lineWidth: 1)
        )
    }

    private var intervalMenu: some View {
        Menu {
            ForEach(ManagerWatchIntervalOption.allCases) { option in
                Button {
                    model.updateManagerWatchInterval(option.rawValue)
                } label: {
                    HStack {
                        Text(option.label)
                        if model.managerWatchSettings.intervalMinutes == option.rawValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("频率：\(model.managerWatchSettings.intervalLabel)", systemImage: "timer")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
    }

    private func compactField(_ label: String, text: Binding<String>, minWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
        }
        .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
    }
}

struct ManagerWatchStatusTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }
}
