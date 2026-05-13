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
            VStack(alignment: .leading, spacing: 16) {
                OverviewHeroCard()

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
            .padding(16)
        }
    }

    private func openPortfolio() {
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
            model.selectedSection = .portfolio
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
            .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                    .stroke(AppPalette.line.opacity(0.32), lineWidth: 1)
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
            HStack(alignment: .center, spacing: 24) {
                heroCopy
                    .frame(minWidth: 480, maxWidth: .infinity, alignment: .leading)
                heroSummaryCard(fixedWidth: 540)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                heroCopy
                heroSummaryCard(fixedWidth: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppPalette.heroGradient, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("资产主屏")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.ink)
            Text("这页现在先看你的资产全貌，再看主理人动态。每个标的会把「已持有、买入中、定投计划」聚合到同一个原生视图里，避免来回切页面对账。")
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
                        .font(.system(size: 24, weight: .bold, design: .rounded))
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
        .padding(16)
        .frame(minHeight: 136, alignment: .topLeading)
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
