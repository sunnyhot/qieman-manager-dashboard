import SwiftUI

// MARK: - Overview

private struct OverviewAssetTypeSummaryStats {
    let totalMarketValue: Double
    let totalPending: Double
    let totalProfit: Double
    let totalChange: Double
    let holdingCount: Int
    let pendingCount: Int
    let planCount: Int
}

private struct OverviewAssetTypeSummaryGroup: Identifiable {
    let id: String
    let title: String
    let rows: [PersonalAssetAggregateRow]
    let stats: OverviewAssetTypeSummaryStats
    let tint: Color

    init(title: String, rows: [PersonalAssetAggregateRow], tint: Color) {
        self.id = title
        self.title = title
        self.rows = rows
        self.stats = Self.makeStats(rows: rows)
        self.tint = tint
    }

    private static func makeStats(rows: [PersonalAssetAggregateRow]) -> OverviewAssetTypeSummaryStats {
        var totalMarketValue = 0.0
        var totalPending = 0.0
        var totalProfit = 0.0
        var totalChange = 0.0
        var holdingCount = 0
        var pendingCount = 0
        var planCount = 0

        for row in rows {
            totalMarketValue += row.marketValue ?? 0
            totalPending += row.pendingCashAmount
            totalProfit += row.profitAmount ?? 0
            totalChange += row.estimateChangeAmount ?? 0
            if row.hasHolding { holdingCount += 1 }
            if row.hasPending { pendingCount += 1 }
            if row.activePlanCount > 0 { planCount += 1 }
        }

        return OverviewAssetTypeSummaryStats(
            totalMarketValue: totalMarketValue,
            totalPending: totalPending,
            totalProfit: totalProfit,
            totalChange: totalChange,
            holdingCount: holdingCount,
            pendingCount: pendingCount,
            planCount: planCount
        )
    }
}

struct OverviewSectionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                OverviewHeroCard()
                TodayBriefPanel(items: model.todayBriefItems, action: openBrief)
                DashboardInsightPanel(
                    managerSummary: model.managerActivitySummary,
                    freshnessSummary: model.dashboardFreshnessSummary,
                    managerAction: openManagerActivity,
                    freshnessAction: openFreshness
                )

                ViewThatFits {
                    LazyVGrid(columns: overviewMetricWideColumns, spacing: 12) {
                        overviewJumpMetricCards
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        overviewJumpMetricCards
                    }
                }

                SectionCard(title: "资产总览", subtitle: "按类型汇总已持有、待确认、定投计划", icon: "rectangle.grid.2x2") {
                    if model.personalAssetRows.isEmpty {
                        Text("还没有可展示的个人资产。去「我的持仓」里导入持仓、买入中或定投计划后，这里会自动聚合。")
                            .font(.system(size: 12))
                            .foregroundStyle(AppPalette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                    } else {
                        let groups = assetTypeSummaryGroups
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 12) {
                                assetTypeSummaryCards(groups)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                                assetTypeSummaryCards(groups)
                            }
                        }
                    }
                }

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

    private func openManagerActivity(_ item: ManagerActivityItem) {
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
            switch item.kind {
            case .platformAction:
                if let action = model.latestPlatformActions.first {
                    model.selectPlatformAction(action.id)
                }
                model.selectedSection = .platform
            case .forumRecord:
                if let record = model.forumRecords.first {
                    model.selectedPostID = record.id
                }
                model.selectedSection = .forum
            case .watchStatus:
                model.selectedSection = .settings
            }
        }
    }

    private func openFreshness(_ item: DashboardFreshnessItem) {
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
            switch item.kind {
            case .portfolio:
                model.selectedSection = .portfolio
            case .platform:
                model.selectedSection = .platform
            case .forum:
                model.selectedSection = .forum
            case .auth, .managerWatch, .system:
                model.selectedSection = .settings
            }
        }
    }

    private var overviewMetricWideColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220), spacing: 12)]
    }

    @ViewBuilder
    private var overviewJumpMetricCards: some View {
        OverviewJumpMetricCard(
            title: "总持仓",
            value: model.personalAssetSummary.map { currencyText($0.totalEffectiveHoldingAmount) } ?? "—",
            subtitle: model.personalAssetSummary.map {
                "已持有 \(currencyText($0.totalMarketValue)) + 待确认 \(currencyText($0.totalPendingCashAmount)) + 下次计划 \(currencyText($0.totalEstimatedNextPlanAmount))"
            } ?? "个人资产还未导入完整",
            icon: "wallet.bifold",
            accent: AppPalette.brand,
            destination: "我的持仓"
        ) {
            openPortfolio()
        }
        .frame(minWidth: 220, maxWidth: .infinity)

        OverviewJumpMetricCard(
            title: "待确认买入",
            value: model.personalAssetSummary.map { currencyText($0.totalPendingCashAmount) } ?? "—",
            subtitle: model.pendingTradeSummary.map { "\($0.actionCount) 笔交易进行中" } ?? "暂无买入中",
            icon: "clock.badge.exclamationmark",
            accent: AppPalette.warning,
            destination: "我的持仓"
        ) {
            openPortfolio()
        }
        .frame(minWidth: 220, maxWidth: .infinity)

        OverviewJumpMetricCard(
            title: "计划档案",
            value: model.investmentPlanSummary.map { "\($0.activePlanCount) / \($0.pausedPlanCount) / \($0.endedPlanCount)" } ?? "—",
            subtitle: model.investmentPlanSummary.map { "进行中 / 暂停 / 终止 · 共 \($0.planCount) 条" } ?? "还没有计划档案",
            icon: "calendar.badge.clock",
            accent: AppPalette.info,
            destination: "我的持仓"
        ) {
            openPortfolio()
        }
        .frame(minWidth: 220, maxWidth: .infinity)

        OverviewJumpMetricCard(
            title: "覆盖标的",
            value: model.personalAssetSummary.map { "\($0.fundCount)" } ?? "0",
            subtitle: model.personalAssetSummary.map { "持有 \($0.holdingFundCount) · 待确认 \($0.pendingFundCount) · 有计划 \($0.activePlanFundCount)" } ?? "先导入你的个人资产",
            icon: "square.grid.3x2",
            accent: AppPalette.accentWarm,
            destination: "我的持仓"
        ) {
            openPortfolio()
        }
        .frame(minWidth: 220, maxWidth: .infinity)
    }

    private var assetTypeSummaryGroups: [OverviewAssetTypeSummaryGroup] {
        var offExchangeFundRows: [PersonalAssetAggregateRow] = []
        var onExchangeFundRows: [PersonalAssetAggregateRow] = []
        var stockRows: [PersonalAssetAggregateRow] = []

        for row in model.personalAssetRows {
            if row.assetType == .stock {
                stockRows.append(row)
            } else if row.isOnExchangeFund {
                onExchangeFundRows.append(row)
            } else if row.assetType == .fund {
                offExchangeFundRows.append(row)
            }
        }

        return [
            OverviewAssetTypeSummaryGroup(
                title: "场外基金",
                rows: offExchangeFundRows,
                tint: AppPalette.brand
            ),
            OverviewAssetTypeSummaryGroup(
                title: "场内基金",
                rows: onExchangeFundRows,
                tint: AppPalette.accentWarm
            ),
            OverviewAssetTypeSummaryGroup(
                title: "股票",
                rows: stockRows,
                tint: AppPalette.info
            )
        ].filter { !$0.rows.isEmpty }
    }

    @ViewBuilder
    private func assetTypeSummaryCards(_ groups: [OverviewAssetTypeSummaryGroup]) -> some View {
        ForEach(groups) { group in
            assetTypeSummaryCard(group)
            .frame(minWidth: 260, maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func assetTypeSummaryCard(_ group: OverviewAssetTypeSummaryGroup) -> some View {
        let stats = group.stats
        Button { openPortfolio() } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(group.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    ToolbarBadge(title: "\(group.rows.count) 只", tint: group.tint)
                    Spacer()
                    Text(currencyText(stats.totalMarketValue))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                let profitTint = AppPalette.marketTint(for: stats.totalProfit)
                let changeTint = AppPalette.marketTint(for: stats.totalChange)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("总收益")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                        Text(signedCurrencyText(stats.totalProfit))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(profitTint)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今日涨跌")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                        Text(signedCurrencyText(stats.totalChange))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(changeTint)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    if stats.totalPending > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("待确认")
                                .font(.system(size: 10))
                                .foregroundStyle(AppPalette.muted)
                            Text(currencyText(stats.totalPending))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppPalette.ink)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Text("持有 \(stats.holdingCount)")
                    Text("待确认 \(stats.pendingCount)")
                    Text("有计划 \(stats.planCount)")
                }
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .interactiveSurface(
                tint: AppPalette.brand,
                fill: AppPalette.card,
                hoverFill: AppPalette.cardHover,
                strokeOpacity: AppPalette.borderLight,
                activeStrokeOpacity: 0.52,
                lift: 0.8
            )
        }
        .buttonStyle(PressResponsiveButtonStyle())
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
    let action: (TodayBriefItem) -> Void

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
                    Text("优先级看板")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ToolbarBadge(title: items.isEmpty ? "暂无" : "\(items.count) 项", tint: items.isEmpty ? AppPalette.muted : AppPalette.brand)
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
                        Text("持仓、计划和主理人动态刷新后会自动出现在这里")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .padding(12)
                .background(AppPalette.cardStrong.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                .cardStroke(opacity: 0.28)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                    ForEach(items) { item in
                        TodayBriefItemButton(item: item) {
                            action(item)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .panelStroke()
        .sectionShadow()
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
                        .lineLimit(2)
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
        .help(item.title)
    }
}

private extension DashboardInsightTone {
    var overviewTint: Color {
        switch self {
        case .brand:
            return AppPalette.brand
        case .info:
            return AppPalette.info
        case .warning:
            return AppPalette.warning
        case .error:
            return AppPalette.danger
        case .positive:
            return AppPalette.positive
        case .muted:
            return AppPalette.muted
        }
    }
}

struct DashboardInsightPanel: View {
    let managerSummary: ManagerActivitySummary
    let freshnessSummary: DashboardFreshnessSummary
    let managerAction: (ManagerActivityItem) -> Void
    let freshnessAction: (DashboardFreshnessItem) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ManagerActivityPanel(summary: managerSummary, action: managerAction)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                FreshnessStatusPanel(summary: freshnessSummary, action: freshnessAction)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 12) {
                ManagerActivityPanel(summary: managerSummary, action: managerAction)
                FreshnessStatusPanel(summary: freshnessSummary, action: freshnessAction)
            }
        }
    }
}

struct ManagerActivityPanel: View {
    let summary: ManagerActivitySummary
    let action: (ManagerActivityItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(
                title: "主理人动态",
                subtitle: summary.title,
                icon: "person.crop.circle.badge.clock",
                badge: summary.items.isEmpty ? "暂无动态" : "\(summary.items.count) 项",
                tint: AppPalette.brand
            )

            if summary.items.isEmpty {
                emptyInsight(title: "暂无调仓或发言摘要", detail: summary.subtitle, icon: "text.bubble")
            } else {
                VStack(spacing: 8) {
                    ForEach(summary.items) { item in
                        Button {
                            action(item)
                        } label: {
                            insightRow(
                                icon: managerIcon(for: item.kind),
                                title: item.title,
                                detail: item.detail,
                                metric: item.metric,
                                tint: item.tone.overviewTint
                            )
                        }
                        .buttonStyle(PressResponsiveButtonStyle())
                    }
                }
            }
        }
        .padding(14)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .panelStroke()
        .sectionShadow()
    }

    private func managerIcon(for kind: ManagerActivityKind) -> String {
        switch kind {
        case .platformAction:
            return "arrow.left.arrow.right"
        case .forumRecord:
            return "text.bubble"
        case .watchStatus:
            return "bell.and.waves.left.and.right"
        }
    }
}

struct FreshnessStatusPanel: View {
    let summary: DashboardFreshnessSummary
    let action: (DashboardFreshnessItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(
                title: "数据状态",
                subtitle: summary.headline,
                icon: "dot.radiowaves.left.and.right",
                badge: summary.headline,
                tint: summary.headline == "数据状态正常" ? AppPalette.positive : AppPalette.warning
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(Array(summary.items.prefix(6))) { item in
                    Button {
                        action(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(item.tone.overviewTint)
                                    .frame(width: 7, height: 7)
                                Text(item.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppPalette.muted)
                                    .lineLimit(1)
                            }

                            Text(item.status)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(item.tone.overviewTint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(item.detail)
                                .font(.system(size: 9))
                                .foregroundStyle(AppPalette.muted)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                        .padding(10)
                        .interactiveSurface(
                            tint: item.tone.overviewTint,
                            fill: AppPalette.cardStrong.opacity(0.72),
                            hoverFill: AppPalette.cardHover,
                            strokeOpacity: 0.16,
                            activeStrokeOpacity: 0.36,
                            lift: 0.6
                        )
                    }
                    .buttonStyle(PressResponsiveButtonStyle())
                    .help(item.detail)
                }
            }
        }
        .padding(14)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .panelStroke()
        .sectionShadow()
    }
}

private func panelHeader(title: String, subtitle: String, icon: String, badge: String, tint: Color) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .accentIconStyle(tint: tint, size: 24)

        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        ToolbarBadge(title: badge, tint: tint)
    }
}

private func emptyInsight(title: String, detail: String, icon: String) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppPalette.muted)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
        }
    }
    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
    .padding(12)
    .background(AppPalette.cardStrong.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
}

private func insightRow(icon: String, title: String, detail: String, metric: String, tint: Color) -> some View {
    HStack(alignment: .center, spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)
            Text(detail.isEmpty ? "暂无附加信息" : detail)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Text(metric)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .padding(10)
    .interactiveSurface(
        tint: tint,
        fill: AppPalette.cardStrong.opacity(0.72),
        hoverFill: AppPalette.cardHover,
        strokeOpacity: 0.16,
        activeStrokeOpacity: 0.36,
        lift: 0.6
    )
}

struct OverviewJumpMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let accent: Color
    let destination: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MetricCard(title: title, value: value, subtitle: subtitle, icon: icon, accent: accent)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        Text(destination)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.10), in: Capsule())
                    .padding(9)
                }
        }
        .buttonStyle(PressResponsiveButtonStyle())
        .help("打开\(destination)")
    }
}

struct OverviewHeroCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                heroCopy
                    .frame(minWidth: 320, maxWidth: .infinity, alignment: .leading)
                heroSummaryCard(fixedWidth: 420)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                heroCopy
                heroSummaryCard(fixedWidth: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppPalette.heroGradient, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(AppPalette.borderHeavy), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日看板")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.ink)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text("今日收益 · 待确认交易 · 定投计划 · 主理人动态")
                .font(.system(size: 13))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ToolbarBadge(title: model.cookieAvailable ? "已登录" : "未登录", tint: model.cookieAvailable ? AppPalette.positive : AppPalette.warning)
                    ToolbarBadge(title: model.liveModeLabel, tint: AppPalette.brand)
                    if model.hasPersonalPortfolio {
                        ToolbarBadge(title: "资产聚合已启用", tint: AppPalette.info)
                    }
                }
            }
        }
    }

    private func heroSummaryCard(fixedWidth: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("总览摘要")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                    Text(model.personalAssetSummary.map { currencyText($0.totalEffectiveHoldingAmount) } ?? (model.hasPersonalPortfolio ? "待刷新" : "未配置"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                Spacer(minLength: 8)
                Button {
                    model.selectedSection = .portfolio
                } label: {
                    Label("我的持仓", systemImage: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.brand)
                .controlSize(.small)
            }

            if let summary = model.personalAssetSummary {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        heroSummaryMetric(title: "已持有", value: currencyText(summary.totalMarketValue), tint: AppPalette.brand)
                        heroSummaryMetric(title: "待确认", value: currencyText(summary.totalPendingCashAmount), tint: AppPalette.warning)
                        heroSummaryMetric(title: "下次计划", value: currencyText(summary.totalEstimatedNextPlanAmount), tint: AppPalette.info)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        heroSummaryMetric(title: "已持有", value: currencyText(summary.totalMarketValue), tint: AppPalette.brand)
                        heroSummaryMetric(title: "待确认", value: currencyText(summary.totalPendingCashAmount), tint: AppPalette.warning)
                        heroSummaryMetric(title: "下次计划", value: currencyText(summary.totalEstimatedNextPlanAmount), tint: AppPalette.info)
                    }
                }
            } else {
                Text(
                    model.investmentPlanSummary.map { "\($0.activePlanCount) 个进行中计划 · 下次 \($0.nextExecutionDate ?? "待定")" }
                    ?? model.pendingTradeSummary.map { "待确认 \(currencyText($0.totalCashAmount)) · \($0.actionCount) 笔" }
                    ?? model.userPortfolioSnapshot.map { "浮盈 \(currencyOptional($0.totalProfitAmount)) · \($0.holdingCount) 个标的" }
                    ?? "去「我的持仓」里粘贴代码和份额"
                )
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(minHeight: 120, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(width: fixedWidth, alignment: .leading)
        .background(AppPalette.cardStrong.opacity(0.90), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.line.opacity(0.42), lineWidth: 1)
        )
    }

    private func heroSummaryMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppPalette.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
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
