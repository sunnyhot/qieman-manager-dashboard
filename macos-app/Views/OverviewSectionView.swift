import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Overview

struct OverviewSectionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OverviewHeroCard()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
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
                }

                SectionCard(title: "资产总览", subtitle: "按类型汇总已持有、待确认、定投计划", icon: "rectangle.grid.2x2") {
                    if model.personalAssetRows.isEmpty {
                        Text("还没有可展示的个人资产。去「我的持仓」里导入持仓、买入中或定投计划后，这里会自动聚合。")
                            .font(.system(size: 12))
                            .foregroundStyle(AppPalette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(AppPalette.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        let fundRows = model.personalAssetRows.filter { $0.assetType == .fund }
                        let stockRows = model.personalAssetRows.filter { $0.assetType == .stock }
                        HStack(spacing: 12) {
                            assetTypeSummaryCard(
                                title: "基金",
                                rows: fundRows,
                                tint: AppPalette.brand
                            )
                            if !stockRows.isEmpty {
                                assetTypeSummaryCard(
                                    title: "股票",
                                    rows: stockRows,
                                    tint: AppPalette.info
                                )
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

    @ViewBuilder
    private func assetTypeSummaryCard(title: String, rows: [PersonalAssetAggregateRow], tint: Color) -> some View {
        let totalMarketValue = rows.compactMap(\.marketValue).reduce(0, +)
        let totalPending = rows.map(\.pendingCashAmount).reduce(0, +)
        let totalProfit = rows.compactMap(\.profitAmount).reduce(0, +)
        let totalChange = rows.compactMap(\.estimateChangeAmount).reduce(0, +)
        let holdingCount = rows.filter(\.hasHolding).count
        let pendingCount = rows.filter(\.hasPending).count
        let planCount = rows.filter { $0.activePlanCount > 0 }.count

        Button { openPortfolio() } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    ToolbarBadge(title: "\(rows.count) 只", tint: tint)
                    Spacer()
                    Text(currencyText(totalMarketValue))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                }

                let profitTint: Color = totalProfit >= 0 ? AppPalette.positive : AppPalette.danger
                let changeTint: Color = totalChange >= 0 ? AppPalette.positive : AppPalette.danger
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("总收益")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                        Text(signedCurrencyText(totalProfit))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(profitTint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今日涨跌")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                        Text(signedCurrencyText(totalChange))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(changeTint)
                    }
                    if totalPending > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("待确认")
                                .font(.system(size: 10))
                                .foregroundStyle(AppPalette.muted)
                            Text(currencyText(totalPending))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppPalette.ink)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Text("持有 \(holdingCount)")
                    Text("待确认 \(pendingCount)")
                    Text("有计划 \(planCount)")
                }
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    .background(accent.opacity(0.10))
                    .clipShape(Capsule())
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
            HStack(spacing: 18) {
                heroCopy
                Spacer(minLength: 16)
                heroSummaryCard(fixedWidth: 280)
            }

            VStack(alignment: .leading, spacing: 16) {
                heroCopy
                heroSummaryCard(fixedWidth: nil)
            }
        }
        .padding(20)
        .background(AppPalette.heroGradient)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppPalette.line.opacity(0.65), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
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
        VStack(alignment: .leading, spacing: 8) {
            Text("总览摘要")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            Text(model.personalAssetSummary.map { currencyText($0.totalEffectiveHoldingAmount) } ?? (model.hasPersonalPortfolio ? "待刷新" : "未配置"))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(
                model.personalAssetSummary.map { "已持有 \(currencyText($0.totalMarketValue)) · 待确认 \(currencyText($0.totalPendingCashAmount)) · 下次计划 \(currencyText($0.totalEstimatedNextPlanAmount))" }
                ?? model.investmentPlanSummary.map { "\($0.activePlanCount) 个进行中计划 · 下次 \($0.nextExecutionDate ?? "待定")" }
                ?? model.pendingTradeSummary.map { "待确认 \(currencyText($0.totalCashAmount)) · \($0.actionCount) 笔" }
                ?? model.userPortfolioSnapshot.map { "浮盈 \(currencyOptional($0.totalProfitAmount)) · \($0.holdingCount) 个标的" }
                ?? "去「我的持仓」里粘贴代码和份额"
            )
                .font(.system(size: 12))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.selectedSection = .portfolio
            } label: {
                Label("打开我的持仓", systemImage: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.brand)
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(width: fixedWidth, alignment: .leading)
        .background(AppPalette.cardStrong.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
        .background(AppPalette.cardStrong.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
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
                    .background(AppPalette.brandSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

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
                .background(AppPalette.warning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(14)
        .background(AppPalette.card.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
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
                .background(AppPalette.cardStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .background(AppPalette.cardStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

