import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum PersonalAssetFilterScope: String, CaseIterable, Identifiable {
    case all = "全部"
    case holding = "已持有"
    case pending = "待确认"
    case activePlan = "进行中计划"
    case archivedPlan = "已暂停/终止"
    case drawdownMode = "涨跌幅模式"

    var id: String { rawValue }
}

private enum PersonalAssetSortOption: String, CaseIterable, Identifiable {
    case exposure = "综合敞口"
    case marketValue = "市值"
    case pendingAmount = "待确认金额"
    case nextExecution = "下次定投时间"
    case planCumulative = "累计计划金额"
    case name = "基金名"

    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    private let compactSidebarThreshold: CGFloat = 1360

    private var shouldShowQueryToolbar: Bool {
        switch model.selectedSection {
        case .platform, .forum:
            return true
        case .overview, .portfolio, .snapshots, .backupWeb:
            return false
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompactSidebar = proxy.size.width < compactSidebarThreshold

            ZStack {
                AppPalette.canvasGradient
                    .ignoresSafeArea()

                HSplitView {
                    sidebar(isCompact: isCompactSidebar)
                        .frame(
                            minWidth: isCompactSidebar ? 82 : 216,
                            idealWidth: isCompactSidebar ? 90 : 232,
                            maxWidth: isCompactSidebar ? 96 : 252
                        )
                    mainContent
                }
            }
        }
        .frame(minWidth: 1080, minHeight: 780)
        .task {
            await model.start()
            model.refreshDataForSectionIfNeeded(model.selectedSection)
        }
        .onChange(of: model.selectedSection) { _, section in
            model.refreshDataForSectionIfNeeded(section)
        }
        .sheet(isPresented: $model.isPresentingLoginSheet) {
            QiemanLoginView(cookieFileURL: model.cookieFileURL) {
                model.handleCookieSavedFromLoginSheet()
            }
        }
        .sheet(isPresented: $model.isPresentingUpdateSheet) {
            if let update = model.availableUpdate {
                AppUpdateSheet(
                    release: update,
                    isInstalling: model.isInstallingUpdate,
                    installProgress: model.updateInstallProgress,
                    onInstall: {
                        Task { await model.downloadAndInstallAvailableUpdate() }
                    },
                    onReleasePage: {
                        model.openAvailableUpdateReleasePage()
                        model.dismissUpdateSheet()
                    },
                    onDismiss: {
                        model.dismissUpdateSheet()
                    }
                )
            }
        }
    }

    // MARK: - Sidebar

    private func sidebar(isCompact: Bool) -> some View {
        VStack(spacing: 0) {
            // Brand area
            HStack(spacing: isCompact ? 0 : 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                    .frame(width: 36, height: 36)
                    .background(AppPalette.brandSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if !isCompact {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("且慢")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                        Text("投资仪表盘")
                            .font(.system(size: 11))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
            .padding(.horizontal, isCompact ? 10 : 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().padding(.horizontal, isCompact ? 8 : 12)

            // Navigation
            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    sidebarButton(section: section, isCompact: isCompact)
                }
            }
            .padding(.horizontal, isCompact ? 8 : 10)
            .padding(.top, 12)

            Spacer()

            Divider().padding(.horizontal, isCompact ? 8 : 12)

            // Footer status
            VStack(alignment: .leading, spacing: 6) {
                if isCompact {
                    VStack(spacing: 10) {
                        Circle()
                            .fill(model.cookieAvailable ? AppPalette.positive : AppPalette.warning)
                            .frame(width: 7, height: 7)

                        Text("\(model.history.count)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppPalette.muted)

                        VStack(spacing: 10) {
                            Button {
                                model.openDataDirectory()
                            } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppPalette.muted)
                            .help("打开数据目录")

                            Button {
                                model.openWebBackupInBrowser()
                            } label: {
                                Image(systemName: "globe")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppPalette.muted)
                            .help("打开网页备份")
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.cookieAvailable ? AppPalette.positive : AppPalette.warning)
                            .frame(width: 6, height: 6)
                        Text(model.cookieAvailable ? "Cookie 可用" : "Cookie 缺失")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                        Spacer()
                        Text("\(model.history.count) 快照")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                    }

                    HStack(spacing: 8) {
                        Button {
                            model.openDataDirectory()
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppPalette.muted)

                        Button {
                            model.openWebBackupInBrowser()
                        } label: {
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppPalette.muted)

                        Spacer()

                        if let logURL = model.logFileURL {
                            Text(logURL.lastPathComponent)
                                .font(.system(size: 9))
                                .foregroundStyle(AppPalette.muted.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(isCompact ? 10 : 14)
        }
        .background(AppPalette.paper.opacity(0.96))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppPalette.line.opacity(0.7))
                .frame(width: 1)
        }
    }

    private func sidebarButton(section: AppSection, isCompact: Bool) -> some View {
        let isSelected = model.selectedSection == section
        return Button {
            guard model.selectedSection != section else { return }
            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
                model.selectedSection = section
            }
            if section == .backupWeb {
                Task(priority: .utility) { await model.prepareWebBackup() }
            }
        } label: {
            HStack(spacing: isCompact ? 0 : 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                    .foregroundStyle(isSelected ? AppPalette.brand : AppPalette.muted)

                if !isCompact {
                    Text(section.rawValue)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? AppPalette.ink : AppPalette.muted)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 46, alignment: isCompact ? .center : .leading)
            .padding(.horizontal, isCompact ? 8 : 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppPalette.brand.opacity(0.10) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isSelected && !isCompact {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppPalette.brand)
                        .frame(width: 3, height: 18)
                        .offset(x: 0)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PressResponsiveButtonStyle())
        .help(section.rawValue)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            toolbar
            notifications
            detailPanel
        }
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        toolbarTitleBlock
                        Spacer(minLength: 12)
                        toolbarActionRow
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        toolbarTitleBlock
                        ScrollView(.horizontal, showsIndicators: false) {
                            toolbarActionRow
                        }
                    }
                }

                if shouldShowQueryToolbar {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(QueryMode.allCases) { mode in
                                queryModeChip(mode: mode)
                            }
                        }
                    }
                    .padding(.vertical, 2)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        toolbarField("产品", text: $model.form.prodCode, minWidth: 180)
                        toolbarField("主理人", text: $model.form.userName, minWidth: 200)
                        toolbarField("关键词", text: $model.form.keyword, minWidth: 240)
                        toolbarField("页数", text: $model.form.pages, minWidth: 100)
                        toolbarField("每页", text: $model.form.pageSize, minWidth: 100)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        toolbarField("起始", text: $model.form.since, minWidth: 180)
                        toolbarField("结束", text: $model.form.until, minWidth: 180)
                    }

                    if model.showAdvancedParams {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                            toolbarField("groupId", text: $model.form.groupID, minWidth: 180)
                            toolbarField("groupUrl", text: $model.form.groupURL, minWidth: 260)
                            toolbarField("brokerUserId", text: $model.form.brokerUserID, minWidth: 180)
                            toolbarField("spaceUserId", text: $model.form.spaceUserID, minWidth: 180)
                            toolbarField("自动刷新", text: $model.form.autoRefresh, minWidth: 140)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppPalette.paper.opacity(0.92))

            Divider()
        }
        .background(AppPalette.paper.opacity(0.85))
    }

    private var toolbarTitleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.selectedSection.rawValue)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            HStack(spacing: 6) {
                ToolbarBadge(
                    title: model.cookieAvailable ? "Cookie 可用" : "Cookie 缺失",
                    tint: model.cookieAvailable ? AppPalette.positive : AppPalette.warning
                )
                ToolbarBadge(
                    title: model.liveModeLabel,
                    tint: model.hasLiveService ? AppPalette.brand : AppPalette.muted
                )
            }
        }
    }

    private var toolbarActionRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { try? await model.refreshLatest(persist: false) }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(model.isRefreshing || (!model.hasLiveService && !model.canRefreshWithoutLiveService))

            Button("登录且慢") {
                model.presentLoginSheet()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button(model.isCheckingAuth ? "验证中…" : "验证登录态") {
                Task { await model.validateAuth() }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(model.isCheckingAuth)

            Menu {
                Button("刷新并保存") {
                    Task { try? await model.refreshLatest(persist: true) }
                }
                .disabled(model.isRefreshing || (!model.hasLiveService && !model.canRefreshWithoutLiveService))

                Divider()

                Button(model.isCheckingForUpdates ? "检查更新中…" : "检查更新") {
                    Task { await model.checkForUpdates(userInitiated: true) }
                }
                .disabled(model.isCheckingForUpdates)

                if model.availableUpdate != nil {
                    Button(model.isInstallingUpdate ? "安装更新中…" : "下载并重启安装") {
                        Task { await model.downloadAndInstallAvailableUpdate() }
                    }
                    .disabled(model.isInstallingUpdate)

                    Button("打开 Release 页面") {
                        model.openAvailableUpdateReleasePage()
                    }
                }

                Divider()

                Button(model.showAdvancedParams ? "收起高级参数" : "展开高级参数") {
                    model.showAdvancedParams.toggle()
                }
            } label: {
                Label("更多", systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AppPalette.cardStrong)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func toolbarField(_ label: String, text: Binding<String>, minWidth: CGFloat) -> some View {
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
                .controlSize(.regular)
        }
        .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
    }

    private func queryModeChip(mode: QueryMode) -> some View {
        let isSelected = model.form.mode == mode
        return Button {
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                model.form.mode = mode
            }
        } label: {
            Text(mode.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? AppPalette.onBrand : AppPalette.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? AppPalette.brand : AppPalette.cardStrong)
                .clipShape(Capsule())
        }
        .buttonStyle(PressResponsiveButtonStyle())
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var notifications: some View {
        if !model.noticeMessage.isEmpty || !model.errorMessage.isEmpty || (model.authPayload?.ok == true) {
            VStack(spacing: 4) {
                if !model.noticeMessage.isEmpty {
                    ToastBar(text: model.noticeMessage, tint: AppPalette.positive)
                }
                if !model.errorMessage.isEmpty {
                    ToastBar(text: model.errorMessage, tint: AppPalette.danger)
                }
                if let auth = model.authPayload, auth.ok {
                    ToastBar(text: "登录态有效：\(auth.userName) / brokerUserId \(auth.brokerUserId)", tint: AppPalette.info)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        switch model.selectedSection {
        case .overview:
            OverviewSectionView()
        case .portfolio:
            PortfolioSectionView()
        case .platform:
            PlatformSectionView()
        case .forum:
            ForumSectionView()
        case .snapshots:
            SnapshotsSectionView()
        case .backupWeb:
            WebBackupView(url: model.baseURL)
        }
    }
}

private struct AppUpdateSheet: View {
    let release: AppUpdateRelease
    let isInstalling: Bool
    let installProgress: String
    let onInstall: () -> Void
    let onReleasePage: () -> Void
    let onDismiss: () -> Void

    private var releaseNotesPreview: String {
        let trimmed = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "这个版本没有填写更新说明。" : trimmed
    }

    private var publishedText: String? {
        guard let publishedAt = release.publishedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: publishedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                    .frame(width: 48, height: 48)
                    .background(AppPalette.brandSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text("发现新版本")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.positive)
                    Text(release.displayTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text("当前 \(release.currentVersion) · 最新 \(release.version)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let asset = release.asset {
                        ToolbarBadge(title: asset.name, tint: AppPalette.info)
                        ToolbarBadge(title: asset.sizeText, tint: AppPalette.muted)
                    } else {
                        ToolbarBadge(title: "未找到 zip 资产", tint: AppPalette.warning)
                    }

                    if let publishedText {
                        ToolbarBadge(title: publishedText, tint: AppPalette.muted)
                    }
                }

                Text(releaseNotesPreview)
                    .font(.system(size: 13))
                    .foregroundStyle(AppPalette.ink)
                    .lineSpacing(4)
                    .lineLimit(8)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppPalette.cardStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if isInstalling {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(installProgress.isEmpty ? "正在准备更新…" : installProgress)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppPalette.muted)
                    }
                    .padding(.horizontal, 2)
                }
            }

            HStack {
                Button("稍后") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isInstalling)

                Spacer()

                Button("查看发布页") {
                    onReleasePage()
                }
                .disabled(isInstalling)

                Button {
                    onInstall()
                } label: {
                    Label(isInstalling ? "安装中…" : "下载并重启安装", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isInstalling || release.asset == nil)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(AppPalette.paper)
    }
}

// MARK: - Overview

private struct OverviewSectionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OverviewHeroCard()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    MetricCard(
                        title: "总持仓",
                        value: model.personalAssetSummary.map { currencyText($0.totalEffectiveHoldingAmount) } ?? "—",
                        subtitle: model.personalAssetSummary.map {
                            "已持有 \(currencyText($0.totalMarketValue)) + 待确认 \(currencyText($0.totalPendingCashAmount)) + 下次计划 \(currencyText($0.totalEstimatedNextPlanAmount))"
                        } ?? "个人资产还未导入完整",
                        icon: "wallet.bifold",
                        accent: AppPalette.brand
                    )
                    MetricCard(
                        title: "待确认买入",
                        value: model.personalAssetSummary.map { currencyText($0.totalPendingCashAmount) } ?? "—",
                        subtitle: model.pendingTradeSummary.map { "\($0.actionCount) 笔交易进行中" } ?? "暂无买入中",
                        icon: "clock.badge.exclamationmark",
                        accent: AppPalette.warning
                    )
                    MetricCard(
                        title: "计划档案",
                        value: model.investmentPlanSummary.map { "\($0.activePlanCount) / \($0.pausedPlanCount) / \($0.endedPlanCount)" } ?? "—",
                        subtitle: model.investmentPlanSummary.map { "进行中 / 暂停 / 终止 · 共 \($0.planCount) 条" } ?? "还没有计划档案",
                        icon: "calendar.badge.clock",
                        accent: AppPalette.info
                    )
                    MetricCard(
                        title: "覆盖基金",
                        value: model.personalAssetSummary.map { "\($0.fundCount)" } ?? "0",
                        subtitle: model.personalAssetSummary.map { "持有 \($0.holdingFundCount) · 待确认 \($0.pendingFundCount) · 有计划 \($0.activePlanFundCount)" } ?? "先导入你的个人资产",
                        icon: "square.grid.3x2",
                        accent: AppPalette.accentWarm
                    )
                }

                ManagerWatchControlCard()

                SectionCard(title: "资产总览卡片", subtitle: "按基金汇总“已持有 + 待确认 + 定投档案”", icon: "rectangle.grid.2x2") {
                    if model.personalAssetRows.isEmpty {
                        Text("还没有可展示的个人资产。去“我的持仓”里导入持仓、买入中或定投计划后，这里会自动聚合。")
                            .font(.system(size: 12))
                            .foregroundStyle(AppPalette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(AppPalette.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
                            ForEach(model.personalAssetRows) { row in
                                PersonalAssetOverviewCard(row: row)
                            }
                        }
                    }
                }

                SectionCard(title: "基金全貌总表", subtitle: "一行看清每只基金的持仓、待确认和计划状态", icon: "tablecells") {
                    if model.personalAssetRows.isEmpty {
                        Text("导入任一类个人数据后，这里会生成汇总总表。")
                            .font(.system(size: 12))
                            .foregroundStyle(AppPalette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(AppPalette.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        PersonalAssetBrowser(rows: model.personalAssetRows)
                    }
                }

                SectionCard(title: "最近调仓", subtitle: "原生卡片直接消费平台接口", icon: "arrow.left.arrow.right") {
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
                            ForEach(model.latestPlatformActions) { action in
                                PlatformActionRow(action: action)
                            }
                        }
                    }
                }

                // Recent posts
                SectionCard(
                    title: model.currentSnapshot?.snapshotType == "posts" ? "最近发言" : "最近记录",
                    subtitle: model.currentSnapshot?.kindLabel == "帖子" ? "主理人发言摘要" : "当前模式下的最新原生结果",
                    icon: "text.bubble"
                ) {
                    if model.hasForumPosts {
                        VStack(spacing: 8) {
                            ForEach(Array(model.forumRecords.prefix(6))) { record in
                                ForumRecordRow(record: record)
                            }
                        }
                    } else {
                        EmptySectionState(
                            title: "最近发言暂时为空",
                            subtitle: "论坛页会自动补拉帖子流；这里也会跟着恢复，不需要再去历史快照里切换。",
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
}

private struct OverviewHeroCard: View {
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
            Text("这页现在先看你的资产全貌，再看主理人动态。每只基金会把“已持有、买入中、定投计划”聚合到同一个原生视图里，避免来回切页面对账。")
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
                ?? "去“我的持仓”里粘贴代码和份额"
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

private struct ManagerWatchControlCard: View {
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
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Toggle("开启通知巡检", isOn: enabledBinding)
                            .toggleStyle(.switch)
                        ToolbarBadge(
                            title: model.managerWatchStatusText,
                            tint: model.managerWatchSettings.isEnabled ? AppPalette.positive : AppPalette.muted
                        )
                        ToolbarBadge(
                            title: model.managerWatchSettings.watchPlatform && model.managerWatchSettings.watchForum
                                ? "调仓 + 发言"
                                : (model.managerWatchSettings.watchPlatform ? "仅调仓" : (model.managerWatchSettings.watchForum ? "仅发言" : "未选择")),
                            tint: AppPalette.info
                        )
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("开启通知巡检", isOn: enabledBinding)
                            .toggleStyle(.switch)
                        HStack(spacing: 8) {
                            ToolbarBadge(
                                title: model.managerWatchStatusText,
                                tint: model.managerWatchSettings.isEnabled ? AppPalette.positive : AppPalette.muted
                            )
                            ToolbarBadge(
                                title: model.managerWatchSettings.watchPlatform && model.managerWatchSettings.watchForum
                                    ? "调仓 + 发言"
                                    : (model.managerWatchSettings.watchPlatform ? "仅调仓" : (model.managerWatchSettings.watchForum ? "仅发言" : "未选择")),
                                tint: AppPalette.info
                            )
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    compactField("产品", text: prodCodeBinding, minWidth: 220)
                    compactField("主理人", text: managerNameBinding, minWidth: 220)
                    intervalMenu
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        Toggle("监控平台调仓", isOn: platformBinding)
                            .toggleStyle(.checkbox)
                        Toggle("监控主理人发言", isOn: forumBinding)
                            .toggleStyle(.checkbox)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("监控平台调仓", isOn: platformBinding)
                            .toggleStyle(.checkbox)
                        Toggle("监控主理人发言", isOn: forumBinding)
                            .toggleStyle(.checkbox)
                    }
                }
                .font(.system(size: 12))

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Toggle("开机自启", isOn: launchAtLoginBinding)
                            .toggleStyle(.switch)
                        ToolbarBadge(title: model.launchAtLoginStatusText, tint: model.launchAtLoginEnabled ? AppPalette.positive : AppPalette.muted)
                        ToolbarBadge(title: "关闭窗口后仅保留菜单栏", tint: AppPalette.info)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("开机自启", isOn: launchAtLoginBinding)
                            .toggleStyle(.switch)
                        HStack(spacing: 8) {
                            ToolbarBadge(title: model.launchAtLoginStatusText, tint: model.launchAtLoginEnabled ? AppPalette.positive : AppPalette.muted)
                            ToolbarBadge(title: "关闭窗口后仅保留菜单栏", tint: AppPalette.info)
                        }
                    }
                }
                .font(.system(size: 12))

                ViewThatFits(in: .horizontal) {
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

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button("保存设置") {
                            model.saveManagerWatchConfiguration()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppPalette.brand)

                        HStack(spacing: 10) {
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
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                    StatChip(title: "巡检目标", value: model.managerWatchScopeText)
                    if let lastChecked = model.managerWatchSettings.lastCheckedAt {
                        StatChip(title: "上次检查", value: lastChecked)
                    }
                    if let lastSuccess = model.managerWatchSettings.lastSuccessAt {
                        StatChip(title: "上次成功", value: lastSuccess)
                    }
                }
                }

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
        }
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

// MARK: - Platform

private struct PlatformSectionView: View {
    @EnvironmentObject private var model: AppModel
    private let compactThreshold: CGFloat = 1120
    private let detailAnchor = "platform-detail-panel"

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < compactThreshold

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                            MetricCard(title: "调仓动作", value: "\(model.platformPayload?.count ?? 0)", subtitle: "覆盖调仓单 \(model.platformPayload?.adjustmentCount ?? 0)", icon: "arrow.left.arrow.right", accent: AppPalette.info)
                            MetricCard(title: "买入", value: "\(model.platformPayload?.buyCount ?? 0)", subtitle: "本地原生筛选", icon: "arrow.down.circle", accent: AppPalette.positive)
                            MetricCard(title: "卖出", value: "\(model.platformPayload?.sellCount ?? 0)", subtitle: "本地原生筛选", icon: "arrow.up.circle", accent: AppPalette.warning)
                            MetricCard(title: "持仓标的", value: "\(model.platformPayload?.holdings?.assetCount ?? 0)", subtitle: model.platformPayload?.prodCode ?? model.form.prodCode, icon: "bag", accent: AppPalette.accentWarm)
                        }

                        SectionCard(title: "交易时间总览", subtitle: "按月看买卖节奏", icon: "calendar") {
                            if model.monthlyPlatformSummary.isEmpty {
                                EmptySectionState(
                                    title: "还没有平台调仓数据",
                                    subtitle: "右上角点“刷新”后会重新直拉平台调仓；即使论坛抓取失败，调仓也会单独更新。",
                                    actionTitle: "立即刷新"
                                ) {
                                    Task { try? await model.refreshLatest(persist: false) }
                                }
                            } else {
                                PlatformMonthlyOverview(months: model.monthlyPlatformSummary)
                            }
                        }

                        SectionCard(
                            title: "调仓浏览",
                            subtitle: isCompact ? "窄窗口自动切成上下结构，点列表会直接跳到详情" : "宽窗口保持双栏，左边选动作，右边看详情",
                            icon: "square.split.2x1"
                        ) {
                            if model.hasPlatformActions {
                                if isCompact {
                                    VStack(alignment: .leading, spacing: 12) {
                                        platformListPanel(isCompact: true, scrollProxy: scrollProxy)
                                        platformDetailPanel
                                            .id(detailAnchor)
                                    }
                                } else {
                                    HStack(alignment: .top, spacing: 14) {
                                        platformListPanel(isCompact: false, scrollProxy: scrollProxy)
                                            .frame(width: min(max(proxy.size.width * 0.36, 340), 430), alignment: .top)

                                        platformDetailPanel
                                            .frame(maxWidth: .infinity, alignment: .topLeading)
                                    }
                                }
                            } else {
                                EmptySectionState(
                                    title: "平台调仓暂时为空",
                                    subtitle: "我已经把平台和论坛改成了独立刷新。现在点一次刷新，就算其中一项失败，另一项也会照常显示。",
                                    actionTitle: "刷新调仓"
                                ) {
                                    Task { try? await model.refreshLatest(persist: false) }
                                }
                            }
                        }

                        SectionCard(title: "当前持仓", subtitle: "保留原项目的数据口径", icon: "bag") {
                            if model.platformHoldings.isEmpty {
                                EmptySectionState(
                                    title: "当前没有平台持仓",
                                    subtitle: "如果最近没有拉到调仓数据，这里会先留空；刷新后会自动恢复。",
                                    actionTitle: "立即刷新"
                                ) {
                                    Task { try? await model.refreshLatest(persist: false) }
                                }
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(model.platformHoldings) { holding in
                                        HoldingCard(holding: holding)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func platformListPanel(isCompact: Bool, scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("调仓动作列表")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text("\(model.platformPayload?.actions?.count ?? 0)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppPalette.card)
                    .clipShape(Capsule())
                Spacer()
                if isCompact {
                    Text("点一下自动跳到详情")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
            }

            LazyVStack(spacing: 8) {
                ForEach(model.platformPayload?.actions ?? []) { action in
                    Button {
                        model.selectPlatformAction(action.id)
                        if isCompact {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy.scrollTo(detailAnchor, anchor: .top)
                            }
                        }
                    } label: {
                        PlatformActionRow(
                            action: action,
                            isSelected: model.selectedPlatformActionID == action.id,
                            isCompact: true
                        )
                    }
                    .buttonStyle(PressResponsiveButtonStyle())
                    .id(action.id)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.cardStrong)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
        )
    }

    private var platformDetailPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("调仓详情")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Spacer()
                if let action = model.selectedPlatformAction {
                    Text(action.txnDate ?? action.createdAt ?? "未知时间")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
            }

            if let selectedAction = model.selectedPlatformAction {
                PlatformActionDetailCard(action: selectedAction)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("还没有选中的调仓动作")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("从左侧动作列表里点一条，就会在这里展示调仓估值、当前估值和变化。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppPalette.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.cardStrong)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
        )
    }
}

// MARK: - Personal Portfolio

private struct PortfolioSectionView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("portfolio.import.center.expanded") private var isImportCenterExpanded = false
    @State private var importTarget: PersonalDataImportTarget = .holdings
    @State private var isDraftEditorExpanded = false

    private var totalProfitAmount: Double? {
        model.userPortfolioSnapshot?.totalProfitAmount
    }

    private var totalProfitPct: Double? {
        model.userPortfolioSnapshot?.totalProfitPct
    }

    private var totalDailyChangeAmount: Double? {
        let values = model.userPortfolioSnapshot?.rows.compactMap(\.estimatedDailyChangeAmount) ?? []
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var totalDailyChangePct: Double? {
        guard let snapshot = model.userPortfolioSnapshot else { return nil }
        let pairs = snapshot.rows.compactMap { row -> (Double, Double)? in
            guard
                let change = row.estimatedDailyChangeAmount,
                let previous = row.previousMarketValue,
                previous > 0
            else {
                return nil
            }
            return (change, previous)
        }
        guard !pairs.isEmpty else { return nil }
        let totalChange = pairs.reduce(0) { $0 + $1.0 }
        let totalPrevious = pairs.reduce(0) { $0 + $1.1 }
        guard totalPrevious > 0 else { return nil }
        return totalChange / totalPrevious * 100
    }

    private var totalProfitTint: Color {
        let value = totalProfitAmount ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    private var totalDailyChangeTint: Color {
        let value = totalDailyChangeAmount ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    MetricCard(
                        title: "总持仓",
                        value: model.personalAssetSummary.map { currencyText($0.totalEffectiveHoldingAmount) } ?? "—",
                        subtitle: model.personalAssetSummary.map {
                            "已持有 \(currencyText($0.totalMarketValue)) + 待确认 \(currencyText($0.totalPendingCashAmount)) + 下次计划 \(currencyText($0.totalEstimatedNextPlanAmount))"
                        } ?? "自动聚合你的已持有、买入中和计划档案",
                        icon: "yenign.circle",
                        accent: AppPalette.brand
                    )
                    MetricCard(
                        title: "总收益",
                        value: signedCurrencyText(totalProfitAmount),
                        subtitle: "收益率 \(percentOptional(totalProfitPct))",
                        icon: "plusminus.circle",
                        accent: totalProfitTint,
                        valueTint: totalProfitTint
                    )
                    MetricCard(
                        title: "今日涨跌",
                        value: signedCurrencyText(totalDailyChangeAmount),
                        subtitle: "今日涨跌率 \(percentOptional(totalDailyChangePct))",
                        icon: "waveform.path.ecg",
                        accent: totalDailyChangeTint,
                        valueTint: totalDailyChangeTint
                    )
                    MetricCard(
                        title: "待确认金额",
                        value: model.personalAssetSummary.map { currencyText($0.totalPendingCashAmount) } ?? "—",
                        subtitle: model.pendingTradeSummary.map { "\($0.actionCount) 笔交易进行中" } ?? "暂无待确认交易",
                        icon: "clock.badge.exclamationmark",
                        accent: AppPalette.warning
                    )
                    MetricCard(
                        title: "计划档案",
                        value: model.investmentPlanSummary.map { "\($0.activePlanCount) / \($0.pausedPlanCount) / \($0.endedPlanCount)" } ?? "—",
                        subtitle: model.investmentPlanSummary.map { "进行中 / 暂停 / 终止 · 共 \($0.planCount)" } ?? "支持完整计划档案",
                        icon: "calendar.badge.clock",
                        accent: AppPalette.info
                    )
                    MetricCard(
                        title: "覆盖基金",
                        value: model.personalAssetSummary.map { "\($0.fundCount)" } ?? "0",
                        subtitle: model.personalAssetSummary.map { "持有 \($0.holdingFundCount) · 待确认 \($0.pendingFundCount) · 有计划 \($0.activePlanFundCount)" } ?? "支持手动、图片和表格导入",
                        icon: "square.grid.3x2",
                        accent: AppPalette.accentWarm
                    )
                }

                HStack(spacing: 10) {
                    Text("估值更新时间：\(model.userPortfolioSnapshot?.refreshedAt ?? "未刷新")")
                    if let latestTime = model.pendingTradeSummary?.latestTime {
                        Text("待确认最新：\(latestTime)")
                    }
                    if let nextDate = model.investmentPlanSummary?.nextExecutionDate {
                        Text("下次定投：\(nextDate)")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)

                SectionCard(title: "导入中心", subtitle: "支持手动录入、上传图片 OCR、上传表格到三类资产区", icon: "square.and.arrow.down") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ToolbarBadge(
                                title: hasAnyPersonalData ? "已导入资产数据" : "尚未导入",
                                tint: hasAnyPersonalData ? AppPalette.positive : AppPalette.warning
                            )
                            ToolbarBadge(
                                title: hasCurrentDraft
                                ? "草稿 \(currentDraftLineCount) 行 / \(currentDraftCharacterCount) 字"
                                : "草稿为空",
                                tint: hasCurrentDraft ? AppPalette.info : AppPalette.muted
                            )
                            Spacer()
                            Button(isImportCenterExpanded ? "收起导入中心" : "展开导入中心") {
                                withAnimation(.easeInOut(duration: 0.20)) {
                                    isImportCenterExpanded.toggle()
                                    if !isImportCenterExpanded {
                                        isDraftEditorExpanded = false
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppPalette.brand)
                        }

                        if isImportCenterExpanded || !hasAnyPersonalData {
                            Picker("导入对象", selection: $importTarget) {
                                ForEach(PersonalDataImportTarget.allCases) { target in
                                    Text(target.rawValue).tag(target)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 520)

                            Text(importTarget.helpText)
                                .font(.system(size: 11))
                                .foregroundStyle(AppPalette.muted)

                            HStack(spacing: 8) {
                                Spacer()
                                Button(isDraftEditorExpanded ? "收起编辑" : "展开编辑") {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        isDraftEditorExpanded.toggle()
                                    }
                                }
                                .buttonStyle(.bordered)
                            }

                            if isDraftEditorExpanded {
                                TextEditor(text: selectedDraftBinding)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(height: 220)
                                    .padding(10)
                                    .background(AppPalette.cardStrong)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                                    )
                            } else if hasCurrentDraft {
                                ScrollView {
                                    Text(currentDraftPreviewText)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(AppPalette.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                }
                                .frame(height: 122)
                                .background(AppPalette.cardStrong)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                                )
                            }

                            HStack {
                                Text(importTarget.sampleText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppPalette.muted)
                                Spacer()
                            }

                            HStack(spacing: 10) {
                                Button(saveDraftButtonTitle) {
                                    model.saveDraft(for: importTarget)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppPalette.brand)
                                .disabled(importTarget == .holdings && model.isResolvingPortfolioNames)

                                Button("上传图片") {
                                    presentImportPanel(source: .image)
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.isProcessingImport)

                                Button("上传表格") {
                                    presentImportPanel(source: .table)
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.isProcessingImport)

                                Button(reloadButtonTitle) {
                                    model.reloadDraftTargetFromDisk(importTarget)
                                }
                                .buttonStyle(.bordered)

                                if importTarget == .holdings {
                                    Button(model.isRefreshingPortfolio ? "刷新中…" : "刷新估值") {
                                        Task { try? await model.refreshUserPortfolio() }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(model.isRefreshingPortfolio || !model.hasPersonalPortfolio)
                                }

                                Button("清空草稿") {
                                    model.updateDraft("", for: importTarget)
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.draft(for: importTarget).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        } else {
                            Text("导入中心已折叠。需要补录时点“展开导入中心”，不影响下面资产总表和估值浏览。")
                                .font(.system(size: 11))
                                .foregroundStyle(AppPalette.muted)
                                .padding(.horizontal, 2)
                        }
                    }
                }

                SectionCard(title: "基金全貌总表", subtitle: "把“已持有 + 待确认 + 计划档案”聚合到同一行", icon: "tablecells") {
                    if model.personalAssetRows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有可聚合的基金数据。先导入持仓、买入中或定投计划。")
                                .font(.system(size: 12))
                                .foregroundStyle(AppPalette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(AppPalette.cardStrong)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        PersonalAssetBrowser(rows: model.personalAssetRows)
                    }
                }

                SectionCard(title: "实时估值", subtitle: "和平台持仓共用同一套原生估值口径", icon: "waveform.path.ecg.rectangle") {
                    if let snapshot = model.userPortfolioSnapshot, !snapshot.rows.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(snapshot.rows) { row in
                                PersonalHoldingCard(row: row)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.hasPersonalPortfolio ? "持仓已保存，点“刷新估值”即可拉最新价格。" : "还没有个人持仓。先在上面粘贴代码和份额。")
                                .font(.system(size: 12))
                                .foregroundStyle(AppPalette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppPalette.cardStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                SectionCard(title: "买入中", subtitle: "待确认交易单独展示，不并入已成交持仓收益", icon: "clock.badge.exclamationmark") {
                    if let summary = model.pendingTradeSummary, !model.pendingTrades.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                StatChip(title: "待确认金额", value: currencyText(summary.totalCashAmount))
                                StatChip(title: "现金单", value: "\(summary.cashTradeCount)")
                                if summary.unitTradeCount > 0 {
                                    StatChip(title: "份额单", value: "\(summary.unitTradeCount)")
                                }
                            }

                            VStack(spacing: 10) {
                                ForEach(model.pendingTrades) { trade in
                                    PendingTradeCard(trade: trade)
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有买入中记录。可以直接手动录入，或在导入中心上传图片、表格。")
                                .font(.system(size: 12))
                                .foregroundStyle(AppPalette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppPalette.cardStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                SectionCard(title: "计划档案", subtitle: "按进行中、已暂停、已终止完整归档", icon: "calendar.badge.clock") {
                    if let summary = model.investmentPlanSummary, !model.investmentPlans.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                StatChip(title: "进行中", value: "\(summary.activePlanCount)")
                                StatChip(title: "已暂停", value: "\(summary.pausedPlanCount)")
                                StatChip(title: "已终止", value: "\(summary.endedPlanCount)")
                                StatChip(title: "总数", value: "\(summary.planCount)")
                            }

                            HStack(spacing: 10) {
                                StatChip(title: "智能定投", value: "\(summary.smartPlanCount)")
                                StatChip(title: "日定投", value: "\(summary.dailyPlanCount)")
                                StatChip(title: "周定投", value: "\(summary.weeklyPlanCount)")
                                StatChip(title: "涨跌幅模式", value: "\(model.investmentPlans.filter(\.isDrawdownMode).count)")
                            }

                            HStack(spacing: 10) {
                                StatChip(title: "累计投入", value: currencyText(summary.totalCumulativeInvestedAmount))
                                if let nextDate = summary.nextExecutionDate {
                                    StatChip(title: "最近执行", value: nextDate)
                                }
                            }

                            if !model.activeInvestmentPlans.isEmpty {
                                PlanArchiveGroup(title: "进行中", tint: AppPalette.positive, plans: model.activeInvestmentPlans)
                            }

                            if !model.pausedInvestmentPlans.isEmpty {
                                PlanArchiveGroup(title: "已暂停", tint: AppPalette.warning, plans: model.pausedInvestmentPlans)
                            }

                            if !model.endedInvestmentPlans.isEmpty {
                                PlanArchiveGroup(title: "已终止", tint: AppPalette.muted, plans: model.endedInvestmentPlans)
                            }

                            if model.pausedInvestmentPlans.isEmpty && model.endedInvestmentPlans.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("当前还没有已暂停或已终止的计划明细。")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(AppPalette.muted)
                                    Text("后续把这些计划的截图、表格或手工文本导入到“定投计划”草稿区，并把最后一列状态写成“已暂停”或“已终止”，这里就会自动归档。")
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppPalette.muted)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppPalette.cardStrong)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有定投计划记录。可以直接手动录入，或在导入中心上传图片、表格。")
                                .font(.system(size: 12))
                                .foregroundStyle(AppPalette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppPalette.cardStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(16)
        }
        .onChange(of: importTarget) { _, _ in
            isDraftEditorExpanded = false
        }
    }

    private var selectedDraftBinding: Binding<String> {
        Binding(
            get: { model.draft(for: importTarget) },
            set: { model.updateDraft($0, for: importTarget) }
        )
    }

    private var reloadButtonTitle: String {
        switch importTarget {
        case .holdings:
            return "重载已保存"
        case .pendingTrades:
            return "重载买入中"
        case .investmentPlans:
            return "重载计划"
        }
    }

    private var saveDraftButtonTitle: String {
        if importTarget == .holdings, model.isResolvingPortfolioNames {
            return "补全名称中…"
        }
        return importTarget.buttonTitle
    }

    private var tableImportTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .commaSeparatedText, .json]
        if let xlsx = UTType(filenameExtension: "xlsx") {
            types.append(xlsx)
        }
        if let csv = UTType(filenameExtension: "csv") {
            types.append(csv)
        }
        if let tsv = UTType(filenameExtension: "tsv") {
            types.append(tsv)
        }
        return types
    }

    private var currentDraftText: String {
        model.draft(for: importTarget)
    }

    private var hasCurrentDraft: Bool {
        !currentDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentDraftLineCount: Int {
        currentDraftText
            .split(whereSeparator: \.isNewline)
            .count
    }

    private var currentDraftCharacterCount: Int {
        currentDraftText.count
    }

    private var currentDraftPreviewText: String {
        let lines = currentDraftText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard !lines.isEmpty else { return "" }
        let previewLines = Array(lines.prefix(8))
        let suffix = lines.count > previewLines.count
            ? "\n… 还有 \(lines.count - previewLines.count) 行，点击“展开编辑”查看完整草稿"
            : ""
        return previewLines.joined(separator: "\n") + suffix
    }

    private var hasAnyPersonalData: Bool {
        model.hasPersonalPortfolio || model.hasPendingTrades || model.hasInvestmentPlans
    }

    private func presentImportPanel(source: PersonalDataImportSource) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.allowedContentTypes = source == .image ? [.image] : tableImportTypes
        panel.title = source == .image ? "选择要 OCR 的图片" : "选择要导入的表格或文本"
        panel.message = source == .image
            ? "图片会先识别成文字，再填入当前导入对象的草稿区。"
            : "支持 txt、csv、tsv、json、xlsx，会转换成当前导入对象的草稿。"
        panel.prompt = "选择"

        let target = importTarget
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            return
        }
        Task { await model.importExternalFile(at: url, source: source, target: target) }
    }
}

// MARK: - Forum

private struct ForumSectionView: View {
    @EnvironmentObject private var model: AppModel
    private let compactThreshold: CGFloat = 1120
    private let detailAnchor = "forum-detail-panel"

    var body: some View {
        if !model.hasForumPosts {
            ScrollView {
                SectionCard(title: "论坛发言", subtitle: "原生抓取主理人帖子与评论入口", icon: "text.bubble") {
                    EmptySectionState(
                        title: model.currentSnapshot?.snapshotType == "posts" ? "当前还没拉到帖子" : "当前查询结果不是帖子流",
                        subtitle: "我已经补上了切到论坛页时的自动补拉。点一次刷新后，会优先回到帖子流并恢复发言列表。",
                        actionTitle: "刷新发言"
                    ) {
                        Task { try? await model.refreshLatest(persist: false) }
                    }
                }
            }
            .padding(16)
        } else {
            GeometryReader { proxy in
                let isCompact = proxy.size.width < compactThreshold

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        if isCompact {
                            VStack(alignment: .leading, spacing: 14) {
                                forumListPanel(isCompact: true, scrollProxy: scrollProxy)
                                forumDetailPanel
                                    .id(detailAnchor)
                            }
                            .padding(16)
                        } else {
                            HStack(alignment: .top, spacing: 14) {
                                forumListPanel(isCompact: false, scrollProxy: scrollProxy)
                                    .frame(width: min(max(proxy.size.width * 0.34, 320), 420), alignment: .top)

                                forumDetailPanel
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .padding(16)
                        }
                    }
                }
            }
        }
    }

    private func forumListPanel(isCompact: Bool, scrollProxy: ScrollViewProxy) -> some View {
        SectionCard(
            title: "发言列表",
            subtitle: isCompact ? "窄窗口先选发言，再自动跳到下面看详情" : "宽窗口左侧快速切换发言",
            icon: "list.bullet.rectangle"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("主理人发言")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("\(model.forumRecords.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppPalette.cardStrong)
                        .clipShape(Capsule())
                    Spacer()
                    if isCompact {
                        Text("点一下直接看详情")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                    }
                }

                LazyVStack(spacing: 8) {
                    ForEach(model.forumRecords) { record in
                        let isSelected = model.selectedPostID == record.id
                        Button {
                            model.selectedPostID = record.id
                            if isCompact {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    scrollProxy.scrollTo(detailAnchor, anchor: .top)
                                }
                            }
                        } label: {
                            ForumSelectableRow(record: record, isSelected: isSelected, isCompact: true)
                        }
                        .buttonStyle(PressResponsiveButtonStyle())
                    }
                }
            }
        }
    }

    private var forumDetailPanel: some View {
        SectionCard(title: "发言详情", subtitle: "支持原帖内容、评论排序和主理人回复过滤", icon: "text.book.closed") {
            if let post = model.selectedPost {
                VStack(alignment: .leading, spacing: 16) {
                    Text(post.titleText)
                        .font(.system(size: 22, weight: .bold))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if let createdAt = post.createdAt, !createdAt.isEmpty {
                                StatChip(title: "时间", value: createdAt)
                            }
                            if let groupName = post.groupName, !groupName.isEmpty {
                                StatChip(title: "小组", value: groupName)
                            }
                            if let userName = post.userName, !userName.isEmpty {
                                StatChip(title: "用户", value: userName)
                            }
                            if let interaction = post.interactionText {
                                StatChip(title: "互动", value: interaction)
                            }
                        }
                    }

                    Text(post.bodyText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let detail = post.detailUrl, let url = URL(string: detail) {
                        Link("打开原帖", destination: url)
                            .font(.system(size: 11, weight: .semibold))
                    }

                    if model.currentSnapshotSupportsComments {
                        Divider()

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                Picker("评论排序", selection: $model.commentSortType) {
                                    Text("热评").tag("hot")
                                    Text("最新评论").tag("latest")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 200)

                                Toggle("只看主理人回复", isOn: $model.onlyManagerReplies)
                                    .toggleStyle(.checkbox)

                                Button {
                                    Task { await model.loadCommentsForSelectedPost() }
                                } label: {
                                    Label(model.isLoadingComments ? "刷新中" : "刷新评论", systemImage: "arrow.clockwise")
                                }
                                .disabled(model.isLoadingComments)

                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Picker("评论排序", selection: $model.commentSortType) {
                                    Text("热评").tag("hot")
                                    Text("最新评论").tag("latest")
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 220)

                                Toggle("只看主理人回复", isOn: $model.onlyManagerReplies)
                                    .toggleStyle(.checkbox)

                                Button {
                                    Task { await model.loadCommentsForSelectedPost() }
                                } label: {
                                    Label(model.isLoadingComments ? "刷新中" : "刷新评论", systemImage: "arrow.clockwise")
                                }
                                .disabled(model.isLoadingComments)
                            }
                        }

                        if let comments = model.commentsPayload?.comments, !comments.isEmpty {
                            VStack(spacing: 10) {
                                ForEach(comments) { comment in
                                    CommentBlock(comment: comment)
                                }
                            }
                        } else {
                            Text(model.isLoadingComments ? "正在加载评论…" : "暂无评论，或当前登录态无法读取评论。")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .task(id: forumCommentsAutoLoadKey) {
                    guard model.currentSnapshotSupportsComments else { return }
                    await model.loadCommentsForSelectedPost()
                }
            } else {
                EmptySectionState(
                    title: "暂时没有可展示的论坛内容",
                    subtitle: "先选一条发言，或者执行一次刷新，这里就会显示正文和评论入口。",
                    actionTitle: "刷新发言"
                ) {
                    Task { try? await model.refreshLatest(persist: false) }
                }
            }
        }
    }

    private var forumCommentsAutoLoadKey: String {
        [
            model.selectedPost?.postId.map(String.init) ?? "",
            model.commentSortType,
            model.onlyManagerReplies ? "manager" : "all"
        ].joined(separator: "|")
    }
}

// MARK: - Snapshots

private struct SnapshotsSectionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width < 920 {
                compactLayout
            } else {
                desktopLayout
            }
        }
    }

    private var desktopLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            historyPanel
                .frame(width: 320)
            Divider()
                .overlay(AppPalette.line.opacity(0.5))
            detailPanel
        }
        .background(AppPalette.paper.opacity(0.82))
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            historyPanel
                .frame(height: 300)
            Divider()
                .overlay(AppPalette.line.opacity(0.5))
            detailPanel
        }
        .background(AppPalette.paper.opacity(0.82))
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("快照索引", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("按创建时间倒序，本地保留 \(model.history.count) 个快照")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                ToolbarBadge(title: "\(model.history.count)", tint: AppPalette.brand)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if model.history.isEmpty {
                        SnapshotEmptyInlineState()
                    } else {
                        ForEach(model.history, id: \.id) { snapshot in
                            SnapshotHistoryRow(
                                snapshot: snapshot,
                                isSelected: model.currentSnapshot?.id == snapshot.id
                            ) {
                                Task { await model.loadSnapshot(snapshot) }
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppPalette.cardStrong.opacity(0.34))
    }

    private var detailPanel: some View {
        ScrollView {
            if let snapshot = model.currentSnapshot {
                VStack(alignment: .leading, spacing: 16) {
                    SnapshotDetailHeader(snapshot: snapshot)

                    if let stats = snapshot.stats {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            SnapshotMetricTile(title: "用户", value: "\(stats.uniqueUsers ?? 0)", subtitle: "快照统计", icon: "person.2", accent: AppPalette.info)
                            SnapshotMetricTile(title: "分组", value: "\(stats.uniqueGroups ?? 0)", subtitle: "快照统计", icon: "square.grid.2x2", accent: AppPalette.positive)
                            SnapshotMetricTile(title: "点赞", value: "\(stats.totalLikes ?? 0)", subtitle: "累计互动", icon: "heart", accent: AppPalette.accentWarm)
                            SnapshotMetricTile(title: "评论", value: "\(stats.totalComments ?? 0)", subtitle: "累计互动", icon: "bubble.left", accent: AppPalette.warning)
                        }
                    }

                    SnapshotRecordsPreview(snapshot: snapshot)
                }
                .padding(18)
            } else {
                EmptySectionState(
                    title: "还没有选中的历史快照",
                    subtitle: "左侧选择一个快照后，这里会展示统计、来源和记录预览。",
                    actionTitle: "刷新"
                ) {
                    Task { try? await model.refreshLatest(persist: false) }
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SnapshotHistoryRow: View {
    let snapshot: SnapshotPayload
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(snapshot.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(snapshot.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? AppPalette.brand : AppPalette.muted)
                }

                Text(snapshot.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    SnapshotMiniBadge(text: snapshot.kindLabel ?? snapshot.snapshotType, tint: AppPalette.info)
                    SnapshotMiniBadge(text: snapshot.mode, tint: AppPalette.brand)
                }

                Text(snapshot.createdAt)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(isSelected ? AppPalette.brand.opacity(0.12) : AppPalette.card.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? AppPalette.brand.opacity(0.62) : AppPalette.line.opacity(0.42), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PressResponsiveButtonStyle())
    }
}

private struct SnapshotDetailHeader: View {
    let snapshot: SnapshotPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.displayTitle)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(2)
                    Text(snapshot.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                SnapshotMiniBadge(text: snapshot.persisted == true ? "已保存" : "临时", tint: snapshot.persisted == true ? AppPalette.positive : AppPalette.warning)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                StatChip(title: "类型", value: snapshot.kindLabel ?? snapshot.snapshotType)
                StatChip(title: "模式", value: snapshot.mode)
                StatChip(title: "条数", value: "\(snapshot.count)")
                StatChip(title: "创建时间", value: snapshot.createdAt)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.cardStrong.opacity(0.76))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppPalette.line.opacity(0.56), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct SnapshotMetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(12)
        .background(AppPalette.card.opacity(0.86))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppPalette.line.opacity(0.42), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct SnapshotRecordsPreview: View {
    let snapshot: SnapshotPayload

    private var previewRecords: [SnapshotRecordPayload] {
        Array(snapshot.records.prefix(16))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.snapshotType == "posts" ? "发言预览" : "记录预览")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("展示前 \(previewRecords.count) 条，保留原始快照顺序")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                SnapshotMiniBadge(text: "\(snapshot.records.count) 条", tint: AppPalette.brand)
            }

            if previewRecords.isEmpty {
                SnapshotEmptyInlineState()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(previewRecords) { record in
                        ForumRecordRow(record: record)
                    }
                }
            }
        }
    }
}

private struct SnapshotMiniBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.isEmpty ? "未标注" : text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.11))
            .clipShape(Capsule())
    }
}

private struct SnapshotEmptyInlineState: View {
    var body: some View {
        Text("暂无可展示内容")
            .font(.system(size: 11))
            .foregroundStyle(AppPalette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppPalette.card.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Shared Components

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let accent: Color
    let valueTint: Color

    init(title: String, value: String, subtitle: String, icon: String, accent: Color, valueTint: Color = AppPalette.ink) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.valueTint = valueTint
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(valueTint)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 96, alignment: .leading)
        .padding(14)
        .background(AppPalette.cardStrong.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppPalette.line.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct PressResponsiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.04 : 0.08),
                radius: configuration.isPressed ? 4 : 8,
                y: configuration.isPressed ? 1 : 4
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let content: Content

    init(title: String, subtitle: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
            }
            content
        }
        .padding(16)
        .background(AppPalette.paper.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppPalette.line.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppPalette.brand.opacity(0.06), radius: 10, y: 4)
    }
}

private struct EmptySectionState: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.brand)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct StatChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ToolbarBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct ToastBar: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3, height: 14)
            Text(text)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(AppPalette.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PersonalAssetOverviewCard: View {
    let row: PersonalAssetAggregateRow

    private var profitTint: Color {
        (row.profitAmount ?? 0) >= 0 ? AppPalette.positive : AppPalette.danger
    }

    private var changeTint: Color {
        let value = row.estimateChangePct ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.fundName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if let fundCode = row.fundCode, !fundCode.isEmpty {
                            Text(fundCode)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(AppPalette.muted)
                        }
                        ToolbarBadge(title: row.combinedStatusText, tint: row.hasPending ? AppPalette.warning : AppPalette.brand)
                        if row.hasDrawdownPlan {
                            ToolbarBadge(title: "涨跌幅 \(row.drawdownPlanCount)", tint: AppPalette.info)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(currencyText(row.effectiveHoldingAmount))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                    Text("总持仓")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                    if row.marketValue != nil {
                        Text(percentOptional(row.profitPct))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(profitTint)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                AssetMiniStat(title: "实时估值", value: row.marketValue.map(currencyText) ?? "—", tint: AppPalette.brand)
                AssetMiniStat(title: "总收益", value: signedCurrencyText(row.profitAmount), tint: profitTint)
                AssetMiniStat(title: "今日涨跌", value: signedCurrencyText(row.estimateChangeAmount), tint: changeTint)
                AssetMiniStat(
                    title: "待确认",
                    value: row.pendingCashAmount > 0 ? currencyText(row.pendingCashAmount) : (row.pendingUnitAmount > 0 ? "\(unitsText(row.pendingUnitAmount)) 份" : "—"),
                    tint: AppPalette.warning
                )
            }

            HStack(spacing: 18) {
                LabeledValue(title: "份额", value: row.holdingUnits.map { "\(unitsText($0)) 份" } ?? "—")
                LabeledValue(title: "现价", value: decimalOptional(row.currentPrice))
                LabeledValue(title: "成本", value: row.costPrice.map(decimalText) ?? "—")
            }

            HStack(spacing: 12) {
                if row.pendingTradeCount > 0 {
                    Text("待确认 \(row.pendingTradeCount) 笔")
                }
                if row.totalPlanCount > 0 {
                    Text("下次计划 \(currencyText(row.estimatedNextPlanAmount))")
                }
                if row.hasDrawdownPlan {
                    Text("涨跌幅 \(percentOptional(row.estimateChangePct))")
                }
                if let nextExecutionDate = row.nextExecutionDate {
                    Text("下次 \(nextExecutionDate)")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(row.hasDrawdownPlan ? changeTint : AppPalette.muted)
            .lineLimit(1)
        }
        .padding(14)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(minHeight: 246, alignment: .top)
    }
}

private struct PersonalAssetBrowser: View {
    let rows: [PersonalAssetAggregateRow]

    @State private var searchText = ""
    @State private var filterScope: PersonalAssetFilterScope = .all
    @State private var sortOption: PersonalAssetSortOption = .exposure

    private var displayedRows: [PersonalAssetAggregateRow] {
        rows
            .filter(matchesSearch)
            .filter(matchesFilter)
            .sorted(by: compareRows)
    }

    private var totalPendingAmount: Double {
        displayedRows.map(\.pendingCashAmount).reduce(0, +)
    }

    private var totalDisplayedProfit: Double? {
        let values = displayedRows.compactMap(\.profitAmount)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var totalDisplayedChange: Double? {
        let values = displayedRows.compactMap(\.estimateChangeAmount)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var drawdownFundCount: Int {
        displayedRows.filter(\.hasDrawdownPlan).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppPalette.muted)
                    TextField("搜索基金名或代码", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppPalette.cardStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 320)

                Spacer()

                Menu {
                    ForEach(PersonalAssetSortOption.allCases) { option in
                        Button {
                            sortOption = option
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("排序：\(sortOption.rawValue)", systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PersonalAssetFilterScope.allCases) { scope in
                        filterChip(scope: scope)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                StatChip(title: "显示", value: "\(displayedRows.count) / \(rows.count)")
                StatChip(title: "总收益", value: signedCurrencyText(totalDisplayedProfit))
                StatChip(title: "今日涨跌", value: signedCurrencyText(totalDisplayedChange))
                StatChip(title: "待确认", value: totalPendingAmount > 0 ? currencyText(totalPendingAmount) : "—")
                StatChip(title: "涨跌幅模式", value: "\(drawdownFundCount)")
            }

            if displayedRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前筛选下没有基金。")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("可以试试切换筛选条件，或者清空搜索词。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppPalette.cardStrong)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                PersonalAssetTable(rows: displayedRows)
            }
        }
    }

    private func filterChip(scope: PersonalAssetFilterScope) -> some View {
        let isSelected = filterScope == scope
        let count = rows.filter { row in
            filterScopeMatch(scope, row: row)
        }.count
        return Button {
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                filterScope = scope
            }
        } label: {
            HStack(spacing: 8) {
                Text(scope.rawValue)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? AppPalette.onBrand.opacity(0.88) : AppPalette.muted)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isSelected ? AppPalette.onBrand : AppPalette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? AppPalette.brand : AppPalette.cardStrong)
            .clipShape(Capsule())
        }
        .buttonStyle(PressResponsiveButtonStyle())
        .contentShape(Capsule())
    }

    private func matchesSearch(_ row: PersonalAssetAggregateRow) -> Bool {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return true }
        return row.fundName.lowercased().contains(keyword)
            || (row.fundCode?.lowercased().contains(keyword) ?? false)
    }

    private func matchesFilter(_ row: PersonalAssetAggregateRow) -> Bool {
        filterScopeMatch(filterScope, row: row)
    }

    private func filterScopeMatch(_ scope: PersonalAssetFilterScope, row: PersonalAssetAggregateRow) -> Bool {
        switch scope {
        case .all:
            return true
        case .holding:
            return row.hasHolding
        case .pending:
            return row.hasPending
        case .activePlan:
            return row.activePlanCount > 0
        case .archivedPlan:
            return row.pausedPlanCount > 0 || row.endedPlanCount > 0
        case .drawdownMode:
            return row.hasDrawdownPlan
        }
    }

    private func compareRows(_ left: PersonalAssetAggregateRow, _ right: PersonalAssetAggregateRow) -> Bool {
        switch sortOption {
        case .exposure:
            let leftValue = totalExposure(of: left)
            let rightValue = totalExposure(of: right)
            if abs(leftValue - rightValue) > 0.001 {
                return leftValue > rightValue
            }
        case .marketValue:
            if abs((left.marketValue ?? 0) - (right.marketValue ?? 0)) > 0.001 {
                return (left.marketValue ?? 0) > (right.marketValue ?? 0)
            }
        case .pendingAmount:
            if abs(left.pendingCashAmount - right.pendingCashAmount) > 0.001 {
                return left.pendingCashAmount > right.pendingCashAmount
            }
        case .nextExecution:
            let leftDate = sortableExecutionDate(left.nextExecutionDate)
            let rightDate = sortableExecutionDate(right.nextExecutionDate)
            switch (leftDate, rightDate) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs < rhs
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                break
            }
        case .planCumulative:
            if abs(left.totalCumulativePlanAmount - right.totalCumulativePlanAmount) > 0.001 {
                return left.totalCumulativePlanAmount > right.totalCumulativePlanAmount
            }
        case .name:
            let result = left.fundName.localizedStandardCompare(right.fundName)
            if result != .orderedSame {
                return result == .orderedAscending
            }
        }

        return left.fundName.localizedStandardCompare(right.fundName) == .orderedAscending
    }

    private func totalExposure(of row: PersonalAssetAggregateRow) -> Double {
        row.effectiveHoldingAmount
    }

    private func sortableExecutionDate(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(10))
    }
}

private struct PersonalAssetTable: View {
    let rows: [PersonalAssetAggregateRow]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("基金")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("实时估值 / 收益")
                    .frame(width: 220, alignment: .leading)
                Text("待确认")
                    .frame(width: 150, alignment: .leading)
                Text("计划档案")
                    .frame(width: 190, alignment: .leading)
                Text("观察点")
                    .frame(width: 170, alignment: .leading)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppPalette.cardStrong)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            LazyVStack(spacing: 8) {
                ForEach(rows) { row in
                    PersonalAssetTableRow(row: row)
                }
            }
            .padding(.top, 10)
        }
    }
}

private struct PersonalAssetTableRow: View {
    let row: PersonalAssetAggregateRow

    private var profitTint: Color {
        (row.profitAmount ?? 0) >= 0 ? AppPalette.positive : AppPalette.danger
    }

    private var changeTint: Color {
        let value = row.estimateChangeAmount ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.fundName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    ToolbarBadge(title: row.combinedStatusText, tint: row.hasPending ? AppPalette.warning : AppPalette.brand)
                    if row.hasDrawdownPlan {
                        ToolbarBadge(title: "涨跌幅 \(row.drawdownPlanCount)", tint: AppPalette.info)
                    }
                }
                HStack(spacing: 8) {
                    if let fundCode = row.fundCode, !fundCode.isEmpty {
                        Text(fundCode)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    if row.pendingTradeCount > 0, let latest = row.pendingTrades.first?.occurredAt {
                        Text("最新待确认 \(latest)")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.marketValue.map(currencyText) ?? "—")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text("总收益 \(signedCurrencyText(row.profitAmount)) · \(percentOptional(row.profitPct))")
                    .font(.system(size: 10))
                    .foregroundStyle(profitTint)
                Text("今日涨跌 \(signedCurrencyText(row.estimateChangeAmount)) · \(percentOptional(row.estimateChangePct))")
                    .font(.system(size: 10))
                    .foregroundStyle(changeTint)
            }
            .frame(width: 220, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                if row.pendingTradeCount > 0 {
                    Text(row.pendingCashAmount > 0 ? currencyText(row.pendingCashAmount) : "\(unitsText(row.pendingUnitAmount)) 份")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("\(row.pendingTradeCount) 笔 · \(row.pendingTrades.first?.actionLabel ?? "待确认")")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                } else {
                    Text("—")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("暂无")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
            }
            .frame(width: 150, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                if row.totalPlanCount > 0 {
                    Text("进行中 \(row.activePlanCount) · 暂停 \(row.pausedPlanCount) · 终止 \(row.endedPlanCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("下次估算 \(currencyText(row.estimatedNextPlanAmount)) · 累计 \(currencyText(row.totalCumulativePlanAmount))\(row.hasDrawdownPlan ? " · 涨跌幅 \(row.drawdownPlanCount)" : "")")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                } else {
                    Text("—")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("暂无")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
            }
            .frame(width: 190, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.nextExecutionDate ?? (row.hasDrawdownPlan ? "涨跌幅模式" : (row.pendingTrades.first?.status ?? "—")))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text(
                    row.hasDrawdownPlan
                    ? "含 \(row.drawdownPlanCount) 条涨跌幅计划"
                    : (row.currentPrice.map { "现价 \(decimalText($0))" } ?? "等待估值")
                )
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
            }
            .frame(width: 170, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PlanArchiveGroup: View {
    let title: String
    let tint: Color
    let plans: [PersonalInvestmentPlan]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text("\(plans.count) 条")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
            }

            LazyVStack(spacing: 10) {
                ForEach(plans) { plan in
                    InvestmentPlanCard(plan: plan)
                }
            }
        }
    }
}

private struct AssetMiniStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ForumRecordRow: View {
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

private struct ForumSelectableRow: View {
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

private struct PlatformActionRow: View {
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
                        Text(isBuy ? "买入" : "卖出")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(sideColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(sideColor.opacity(0.10))
                            .clipShape(Capsule())
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], spacing: 10) {
                        LabeledValue(title: "调仓时间", value: action.txnDate ?? action.createdAt ?? "未知")
                        LabeledValue(title: "调仓估值", value: decimalText(action.tradeValuation))
                        LabeledValue(title: "当前估值", value: decimalText(action.currentValuation))
                        LabeledValue(title: "变化", value: percentText(action.valuationChangePct), tint: changeTint)
                    }

                    if let article = action.articleUrl, let url = URL(string: article) {
                        Link("打开平台原文", destination: url)
                            .font(.system(size: 11))
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

private struct PlatformActionDetailCard: View {
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

private struct WrapLine: View {
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

private struct HoldingCard: View {
    let holding: HoldingItemPayload

    private var profitTint: Color {
        let value = holding.displayProfitPct ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(holding.label ?? holding.fundName ?? "未命名标的")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("\(holding.fundCode ?? "无代码") · \(holding.largeClass ?? "未分类")")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                Text("\(holding.currentUnits ?? 0) 份")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 10) {
                LabeledValue(title: "均价", value: decimalText(holding.avgCost))
                LabeledValue(title: "现价", value: decimalText(holding.currentPrice))
                LabeledValue(title: "持仓市值", value: amountText(holding.displayPositionValue))
                LabeledValue(title: "收益率", value: percentText(holding.displayProfitPct), tint: profitTint)
            }
            HStack(spacing: 12) {
                Text("最近动作：\(holding.latestActionTitle ?? holding.latestAction ?? "未知") · \(holding.latestTime ?? "未知时间")")
                Spacer()
                if let source = holding.priceSourceLabel ?? holding.priceSource, !source.isEmpty {
                    Text("价格来源：\(source)")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(AppPalette.muted)
        }
        .padding(12)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

private struct PlatformMonthlyOverview: View {
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
                monthGrid
            }

            VStack(alignment: .leading, spacing: 12) {
                summaryPanel
                monthGrid
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

    private var monthGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
            ForEach(months) { month in
                MonthSummaryCard(month: month)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

private struct MonthSummaryCard: View {
    let month: PlatformMonthSummary

    private var total: Int {
        max(month.totalCount, 1)
    }

    private var buyRatio: Double {
        Double(month.buyCount) / Double(total)
    }

    private var sellRatio: Double {
        Double(month.sellCount) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(month.month)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(month.totalCount)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.ink)
                Text("笔")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
            }

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppPalette.positive.opacity(0.72))
                        .frame(width: max(month.buyCount > 0 ? 6 : 0, proxy.size.width * buyRatio))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppPalette.warning.opacity(0.72))
                        .frame(width: max(month.sellCount > 0 ? 6 : 0, proxy.size.width * sellRatio))
                }
            }
            .frame(height: 8)

            HStack(spacing: 6) {
                miniCount(title: "买", value: month.buyCount, tint: AppPalette.positive)
                miniCount(title: "卖", value: month.sellCount, tint: AppPalette.warning)
                Spacer(minLength: 4)
                Text("活跃 \(month.activeDays) 天")
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }

            Text("每活跃日 \(month.perActiveDayText) 笔")
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppPalette.card.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppPalette.line.opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func miniCount(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
            Text("\(title) \(value)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)
        }
    }
}

private struct LabeledValue: View {
    let title: String
    let value: String
    let tint: Color

    init(title: String, value: String, tint: Color = AppPalette.ink) {
        self.title = title
        self.value = value
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct CommentBlock: View {
    let comment: CommentPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.userName ?? comment.brokerUserId ?? "未知用户")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text(comment.createdAt ?? "未知时间")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                Text("赞 \(comment.likeCount ?? 0)")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
            }

            Text(comment.content ?? "无内容")
                .font(.system(size: 12))
                .foregroundStyle(AppPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !comment.children.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(comment.children) { reply in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(AppPalette.brand.opacity(0.28))
                                .frame(width: 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reply.userName ?? reply.brokerUserId ?? "未知回复")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppPalette.ink)
                                Text(reply.content ?? "无内容")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppPalette.muted)
                            }
                        }
                        .padding(8)
                        .background(AppPalette.cardStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(12)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct InvestmentPlanCard: View {
    let plan: PersonalInvestmentPlan

    private var accent: Color {
        if plan.isEndedPlan {
            return AppPalette.muted
        }
        if plan.isPausedPlan {
            return AppPalette.warning
        }
        return plan.isSmartPlan ? AppPalette.info : AppPalette.brand
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.planTypeLabel)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accent)
                        Text(plan.fundName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                            .lineLimit(2)
                        if plan.isDrawdownMode {
                            ToolbarBadge(title: "涨跌幅模式", tint: AppPalette.info)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(plan.scheduleText)
                        if let fundCode = plan.fundCode, !fundCode.isEmpty {
                            Text(fundCode)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(plan.amountRangeText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                    Text(plan.normalizedStatus)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 10) {
                LabeledValue(title: "累计期数", value: plan.investedPeriods.map(String.init) ?? "—")
                LabeledValue(title: "累计投入", value: plan.cumulativeInvestedAmount.map(currencyText) ?? "—")
                LabeledValue(title: "支付方式", value: plan.paymentMethod ?? "—")
                LabeledValue(title: "下次执行", value: plan.nextExecutionDate.isEmpty ? "—" : plan.nextExecutionDate)
            }

            if let note = plan.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
            }
        }
        .padding(12)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PendingTradeCard: View {
    let trade: PersonalPendingTrade

    private var accent: Color {
        switch trade.actionLabel {
        case "买入", "定投":
            return AppPalette.danger
        case "转换":
            return AppPalette.info
        default:
            return AppPalette.brand
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(trade.actionLabel)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accent)
                        Text(trade.displayTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                            .lineLimit(2)
                    }

                    if let codeText = trade.displayCodeText, !codeText.isEmpty {
                        Text(codeText)
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(trade.amountText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                    Text(trade.status)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppPalette.brand)
                }
            }

            HStack {
                Text(trade.occurredAt)
                Spacer()
                if let note = trade.note, !note.isEmpty {
                    Text(note)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(AppPalette.muted)
        }
        .padding(12)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PersonalHoldingCard: View {
    let row: UserPortfolioValuationRow

    private var profitTint: Color {
        let value = row.profitPct ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    private var changeTint: Color {
        let value = row.estimateChangePct ?? 0
        if value > 0 { return AppPalette.positive }
        if value < 0 { return AppPalette.danger }
        return AppPalette.muted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.fundName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("\(row.holding.normalizedFundCode) · \(unitsText(row.holding.units)) 份")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(currencyOptional(row.marketValue))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                    Text(percentOptional(row.profitPct))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle((row.profitPct ?? 0) >= 0 ? AppPalette.positive : AppPalette.danger)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 10) {
                LabeledValue(title: "现价", value: decimalOptional(row.resolvedPrice))
                LabeledValue(title: "成本", value: row.holding.costPrice.map(decimalText) ?? "—")
                LabeledValue(title: "浮盈", value: currencyOptional(row.profitAmount), tint: profitTint)
                LabeledValue(title: "涨跌", value: row.estimateChangePct.map { String(format: "%+.2f%%", $0) } ?? "—", tint: changeTint)
            }

            HStack {
                Text("来源：\(row.resolvedPriceSource ?? "未知")")
                Spacer()
                Text("时间：\(row.resolvedPriceTime ?? "未知")")
            }
            .font(.system(size: 10))
            .foregroundStyle(AppPalette.muted)
        }
        .padding(12)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
