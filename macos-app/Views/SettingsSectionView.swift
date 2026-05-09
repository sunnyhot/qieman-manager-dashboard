import AppKit
import SwiftUI

// MARK: - Settings

private enum SettingsFocus: CaseIterable, Identifiable {
    case account
    case watch
    case menuBar
    case version

    var id: Self { self }
}

struct SettingsSectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedSettingsFocus: SettingsFocus = .menuBar
    @State private var isMenuBarHoldingOptionsExpanded = false
    @State private var isMenuBarMarketIndexExpanded = false
    @State private var isMenuBarFundMarketExpanded = false

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

    private var menuBarTickerEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.menuBarTickerSettings.isEnabled },
            set: { model.setMenuBarTickerEnabled($0) }
        )
    }

    private var menuBarTickerMaxItemsBinding: Binding<Int> {
        Binding(
            get: { model.menuBarTickerSettings.maxVisibleItems },
            set: { model.setMenuBarTickerMaxVisibleItems($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                overviewBand
                selectedSettingsPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)
        }
        .scrollIndicators(.visible)
    }

    private var overviewBand: some View {
        VStack(alignment: .leading, spacing: 14) {
            overviewIntro
            overviewMetrics
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.55), lineWidth: 1)
        )
    }

    private var overviewIntro: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                    .frame(width: 30, height: 30)
                    .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                Text("设置中心")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    overviewBadges
                }

                VStack(alignment: .leading, spacing: 7) {
                    overviewBadges
                }
            }
        }
    }

    private var overviewBadges: some View {
        Group {
            ToolbarBadge(title: model.cookieAvailable ? "Cookie 可用" : "需要登录", tint: model.cookieAvailable ? AppPalette.positive : AppPalette.warning)
            ToolbarBadge(title: model.liveModeLabel, tint: model.hasLiveService ? AppPalette.brand : AppPalette.muted)
            ToolbarBadge(title: model.managerWatchSettings.isEnabled ? "巡检已开" : "巡检关闭", tint: model.managerWatchSettings.isEnabled ? AppPalette.positive : AppPalette.muted)
            ToolbarBadge(title: model.menuBarTickerSettings.isEnabled ? "菜单栏已显" : "菜单栏关闭", tint: model.menuBarTickerSettings.isEnabled ? AppPalette.info : AppPalette.muted)
        }
    }

    private var overviewMetrics: some View {
        let tickerEntries = model.menuBarTickerVisibleEntries

        return ViewThatFits {
            LazyVGrid(columns: settingsMetricWideColumns, spacing: 12) {
                overviewMetricButtons(tickerEntries: tickerEntries)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 176), spacing: 12)], spacing: 12) {
                overviewMetricButtons(tickerEntries: tickerEntries)
            }
        }
    }

    private var settingsMetricWideColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 176), spacing: 12), count: 4)
    }

    @ViewBuilder
    private func overviewMetricButtons(tickerEntries: [MenuBarTickerEntry]) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSettingsFocus = .account
            }
        } label: {
            SettingsMetric(
                title: "账号",
                value: model.cookieAvailable ? "登录态可用" : "等待登录",
                detail: model.isCheckingAuth ? "验证中" : model.cookieFileURL?.lastPathComponent ?? "未找到 Cookie",
                icon: "person.crop.circle.badge.checkmark",
                tint: model.cookieAvailable ? AppPalette.positive : AppPalette.warning,
                isSelected: selectedSettingsFocus == .account
            )
        }
        .buttonStyle(PressResponsiveButtonStyle())

        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSettingsFocus = .watch
            }
        } label: {
            SettingsMetric(
                title: "巡检",
                value: model.managerWatchStatusText,
                detail: model.managerWatchScopeText,
                icon: "bell.and.waves.left.and.right",
                tint: model.managerWatchSettings.isEnabled ? AppPalette.positive : AppPalette.muted,
                isSelected: selectedSettingsFocus == .watch
            )
        }
        .buttonStyle(PressResponsiveButtonStyle())

        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSettingsFocus = .version
            }
        } label: {
            SettingsMetric(
                title: "版本",
                value: AppUpdateChecker.bundleVersion,
                detail: model.isCheckingForUpdates ? "正在检查更新" : model.availableUpdate.map { "可更新到 \($0.version)" } ?? "当前构建",
                icon: "arrow.down.circle",
                tint: model.availableUpdate == nil ? AppPalette.info : AppPalette.positive,
                isSelected: selectedSettingsFocus == .version
            )
        }
        .buttonStyle(PressResponsiveButtonStyle())

        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSettingsFocus = .menuBar
            }
        } label: {
            SettingsMetric(
                title: "菜单栏",
                value: model.menuBarTickerSettings.isEnabled ? "\(tickerEntries.count) 项显示" : "已关闭",
                detail: "最多 \(model.menuBarTickerSettings.maxVisibleItems) 项 · 已选 \(model.menuBarTickerConfiguredItemCount)",
                icon: "menubar.rectangle",
                tint: model.menuBarTickerSettings.isEnabled ? AppPalette.info : AppPalette.muted,
                isSelected: selectedSettingsFocus == .menuBar
            )
        }
        .buttonStyle(PressResponsiveButtonStyle())
    }

    @ViewBuilder
    private var selectedSettingsPanel: some View {
        switch selectedSettingsFocus {
        case .account:
            accountPanel
        case .watch:
            watchPanel
        case .menuBar:
            menuBarPanel
        case .version:
            appPanel
        }
    }

    private var accountPanel: some View {
        SettingsPanel(title: "账号与登录", subtitle: "登录状态、Cookie 与身份验证", icon: "person.circle") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    title: "Cookie",
                    value: model.cookieAvailable ? "可用" : "缺失",
                    detail: model.cookieFileURL?.lastPathComponent ?? "未找到本地文件",
                    icon: "key.horizontal",
                    tint: model.cookieAvailable ? AppPalette.positive : AppPalette.warning
                )
                SettingsDivider()
                SettingsRow(
                    title: "登录态验证",
                    value: model.isCheckingAuth ? "验证中" : "手动触发",
                    detail: model.authPayload?.message ?? "尚未验证",
                    icon: "checkmark.shield",
                    tint: model.isCheckingAuth ? AppPalette.info : AppPalette.muted
                )
                SettingsDivider()

                SettingsActionRow {
                    Button {
                        model.presentLoginSheet()
                    } label: {
                        Label("登录且慢", systemImage: "person.badge.key")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.brand)

                    Button {
                        Task { await model.validateAuth() }
                    } label: {
                        Label(model.isCheckingAuth ? "验证中…" : "验证登录态", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isCheckingAuth)
                }
            }
        }
    }

    private var watchPanel: some View {
        SettingsPanel(title: "主理人提醒", subtitle: "通知巡检、监控目标与启动项", icon: "bell.badge") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(
                    title: "通知巡检",
                    detail: model.managerWatchStatusText,
                    icon: "bell.and.waves.left.and.right",
                    tint: model.managerWatchSettings.isEnabled ? AppPalette.positive : AppPalette.muted,
                    isOn: enabledBinding
                )
                SettingsDivider()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                    settingsField("产品", text: prodCodeBinding, placeholder: "LONG_WIN")
                    settingsField("主理人", text: managerNameBinding, placeholder: "ETF拯救世界")
                }
                .padding(.vertical, 14)

                SettingsDivider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        Toggle("调仓", isOn: platformBinding)
                            .toggleStyle(.checkbox)
                        Toggle("发言", isOn: forumBinding)
                            .toggleStyle(.checkbox)
                        Spacer()
                    }
                    intervalMenu
                }
                .font(.system(size: 12))
                .padding(.vertical, 14)

                SettingsDivider()

                VStack(spacing: 0) {
                    SettingsRow(title: "上次检查", value: model.managerWatchSettings.lastCheckedAt ?? "暂无", detail: "检查时间", icon: "clock", tint: AppPalette.muted)
                    SettingsDivider(isInset: true)
                    SettingsRow(title: "上次成功", value: model.managerWatchSettings.lastSuccessAt ?? "暂无", detail: "成功时间", icon: "checkmark.circle", tint: AppPalette.positive)
                }

                SettingsDivider()

                SettingsActionRow {
                    Button {
                        model.saveManagerWatchConfiguration()
                    } label: {
                        Label("保存", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.brand)

                    Button {
                        model.syncManagerWatchTargetsFromCurrentForm()
                    } label: {
                        Label("同步当前查询", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.runManagerWatchNow()
                    } label: {
                        Label("立即巡检", systemImage: "play.circle")
                    }
                    .buttonStyle(.bordered)
                }

                SettingsDivider()

                SettingsToggleRow(
                    title: "开机自启",
                    detail: model.launchAtLoginStatusText,
                    icon: "power",
                    tint: model.launchAtLoginEnabled ? AppPalette.positive : AppPalette.muted,
                    isOn: launchAtLoginBinding
                )

                if let error = model.managerWatchSettings.lastErrorMessage, !error.isEmpty {
                    ToastBar(text: error, tint: AppPalette.warning)
                        .padding(.top, 12)
                }
            }
        }
    }

    private var appPanel: some View {
        SettingsPanel(title: "版本更新", subtitle: "当前版本与在线更新", icon: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    title: "更新状态",
                    value: model.isCheckingForUpdates ? "检查中" : (model.availableUpdate == nil ? "暂无更新" : "发现更新"),
                    detail: model.isCheckingForUpdates ? "正在检查 GitHub Release" : (model.availableUpdate == nil ? "可手动检查 GitHub Release" : "可下载并安装"),
                    icon: "app.badge",
                    tint: model.availableUpdate == nil ? AppPalette.info : AppPalette.positive
                )
                if let update = model.availableUpdate {
                    SettingsDivider()
                    SettingsRow(
                        title: "可用更新",
                        value: update.version,
                        detail: update.asset?.name ?? "Release 可查看",
                        icon: "sparkles",
                        tint: AppPalette.positive
                    )
                }

                SettingsDivider()

                SettingsActionRow {
                    Button {
                        Task { await model.checkForUpdates(userInitiated: true) }
                    } label: {
                        Label(model.isCheckingForUpdates ? "检查中…" : "检查更新", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.brand)
                    .disabled(model.isCheckingForUpdates)

                    if model.availableUpdate != nil {
                        Button {
                            Task { await model.downloadAndInstallAvailableUpdate() }
                        } label: {
                            Label(model.isInstallingUpdate ? "安装中…" : "下载并安装", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isInstallingUpdate)

                        Button {
                            model.openAvailableUpdateReleasePage()
                        } label: {
                            Label("Release", systemImage: "safari")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if !model.updateInstallProgress.isEmpty {
                    ToastBar(text: model.updateInstallProgress, tint: AppPalette.info)
                        .padding(.top, 12)
                }
            }
        }
    }

    private var menuBarPanel: some View {
        let tickerEntries = model.menuBarTickerVisibleEntries

        return SettingsPanel(title: "菜单栏摘要", subtitle: "不用点开菜单栏，也能直接看到你选中的关键数据", icon: "menubar.rectangle") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(
                    title: "启用菜单栏数据",
                    detail: "关闭后菜单栏恢复为普通持仓状态标题",
                    icon: "eye",
                    tint: model.menuBarTickerSettings.isEnabled ? AppPalette.info : AppPalette.muted,
                    isOn: menuBarTickerEnabledBinding
                )

                SettingsDivider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("最多显示 \(model.menuBarTickerSettings.maxVisibleItems) 项")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppPalette.ink)
                            Text("超过上限时，按下面选择顺序只取前 \(model.menuBarTickerSettings.maxVisibleItems) 项，避免菜单栏过长。")
                                .font(.system(size: 10))
                                .foregroundStyle(AppPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Stepper("", value: menuBarTickerMaxItemsBinding, in: 1...MenuBarTickerSettings.maxVisibleItemsLimit)
                            .labelsHidden()
                    }

                    menuBarPreview(entries: tickerEntries)
                }
                .padding(.vertical, 14)

                SettingsDivider()

                menuBarOptionGroup(title: "整体资产", subtitle: "总资产、整体今日涨跌和整体持有收益", kinds: MenuBarTickerKind.overallKinds)

                SettingsDivider()

                menuBarOptionGroup(title: "自动 Top 标的", subtitle: "自动把今日波动最大、收益率最高的单个标的放到菜单栏", kinds: MenuBarTickerKind.automaticKinds)

                SettingsDivider()

                menuBarMarketIndexOptions

                SettingsDivider()

                menuBarFundMarketOptions

                SettingsDivider()

                menuBarHoldingOptions

                SettingsDivider()

                SettingsActionRow {
                    Button {
                        model.resetMenuBarTickerSettings()
                    } label: {
                        Label("恢复默认", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.clearMenuBarHoldingSelections()
                    } label: {
                        Label("清空单标的", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.menuBarTickerSettings.holdingSelections.isEmpty)
                }
            }
        }
    }

    private var menuBarFundMarketOptions: some View {
        DisclosureGroup(isExpanded: $isMenuBarFundMarketExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("场外")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
                        fundMarketToggle(.offExchangeDailyAmount, "场外涨跌额")
                        fundMarketToggle(.offExchangeDailyPct, "场外涨跌率")
                        fundMarketToggle(.offExchangeProfitAmount, "场外收益额")
                        fundMarketToggle(.offExchangeProfitPct, "场外收益率")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("场内")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
                        fundMarketToggle(.onExchangeDailyAmount, "场内涨跌额")
                        fundMarketToggle(.onExchangeDailyPct, "场内涨跌率")
                        fundMarketToggle(.onExchangeProfitAmount, "场内收益额")
                        fundMarketToggle(.onExchangeProfitPct, "场内收益率")
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("基金分组")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("按场外基金、场内基金聚合涨跌与收益")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }
        }
        .padding(.vertical, 14)
    }

    private func menuBarTickerSelectionToggle(isOn: Binding<Bool>, label: String) -> some View {
        Toggle(label, isOn: isOn)
            .toggleStyle(.checkbox)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppPalette.muted)
            .fixedSize()
    }

    private func fundMarketToggle(_ kind: MenuBarTickerKind, _ label: String) -> some View {
        menuBarTickerSelectionToggle(
            isOn: Binding(
                get: { model.isMenuBarTickerKindEnabled(kind) },
                set: { model.setMenuBarTickerKind(kind, isEnabled: $0) }
            ),
            label: label
        )
    }

    private var menuBarMarketIndexOptions: some View {
        DisclosureGroup(isExpanded: $isMenuBarMarketIndexExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                menuBarIndexGroupToggles(title: "A股", kinds: [.sseComposite, .csi300, .chinext])
                menuBarIndexGroupToggles(title: "港股", kinds: [.hsi])
                menuBarIndexGroupToggles(title: "美股", kinds: [.nasdaq, .sp500, .dowJones])

                HStack(spacing: 10) {
                    Text(model.isRefreshingMarketIndices ? "大盘行情刷新中…" : "行情来自腾讯指数报价，开启任一项后自动刷新。")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        Task { await model.refreshMarketIndices(kinds: MarketIndexKind.allCases, updateNotice: true) }
                    } label: {
                        Label(model.isRefreshingMarketIndices ? "刷新中" : "刷新大盘", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isRefreshingMarketIndices)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("大盘指数")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("按指数开启点位、涨跌点或涨跌率")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }
        }
        .padding(.vertical, 14)
    }

    private func menuBarIndexGroupToggles(title: String, kinds: [MarketIndexKind]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(kinds) { indexKind in
                    ForEach([
                        (MarketIndexMetric.changePct, "涨跌率"),
                        (MarketIndexMetric.changeAmount, "涨跌点"),
                        (MarketIndexMetric.level, "点位"),
                    ], id: \.0) { metric, label in
                        if let kind = MenuBarTickerKind.tickerKind(indexKind: indexKind, metric: metric) {
                            menuBarTickerSelectionToggle(
                                isOn: Binding(
                                    get: { model.isMenuBarTickerKindEnabled(kind) },
                                    set: { model.setMenuBarTickerKind(kind, isEnabled: $0) }
                                ),
                                label: "\(indexKind.compactLabel)\(label)"
                            )
                        }
                    }
                }
            }
        }
    }

    private func menuBarPreview(entries: [MenuBarTickerEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("当前菜单栏")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                ToolbarBadge(title: "已选 \(model.menuBarTickerConfiguredItemCount)", tint: AppPalette.info)
                ToolbarBadge(title: "显示 \(entries.count)", tint: entries.isEmpty ? AppPalette.muted : AppPalette.positive)
                Spacer()
            }

            if entries.isEmpty {
                Text(model.menuBarTickerSettings.isEnabled ? "当前选择项暂时没有可用数据。刷新持仓估值后会自动显示。" : "菜单栏数据展示已关闭。")
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        menuBarPreviewEntries(entries)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
                        menuBarPreviewEntries(entries)
                    }
                }
            }
        }
        .padding(12)
        .background(AppPalette.cardStrong.opacity(0.62), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.line.opacity(0.42), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func menuBarPreviewEntries(_ entries: [MenuBarTickerEntry]) -> some View {
        ForEach(entries) { entry in
            HStack(spacing: 6) {
                Circle()
                    .fill(menuBarToneColor(entry.tone))
                    .frame(width: 6, height: 6)
                Text(entry.compactText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(menuBarToneColor(entry.tone).opacity(0.08), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                    .stroke(menuBarToneColor(entry.tone).opacity(0.18), lineWidth: 1)
            )
        }
    }

    private func menuBarOptionGroup(title: String, subtitle: String, kinds: [MenuBarTickerKind]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 174), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(kinds) { kind in
                    menuBarKindToggle(kind)
                }
            }
        }
        .padding(.vertical, 14)
    }

    private func menuBarKindToggle(_ kind: MenuBarTickerKind) -> some View {
        Toggle(isOn: Binding(
            get: { model.isMenuBarTickerKindEnabled(kind) },
            set: { model.setMenuBarTickerKind(kind, isEnabled: $0) }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                Text(kind.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .toggleStyle(.checkbox)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(AppPalette.card.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.line.opacity(0.34), lineWidth: 1)
        )
    }

    private var menuBarHoldingOptions: some View {
        DisclosureGroup(isExpanded: $isMenuBarHoldingOptionsExpanded) {
            menuBarHoldingOptionsContent
                .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("单个基金 / 股票")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("需要精确到单个标的时再展开，避免一次渲染过多配置项。")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                ToolbarBadge(title: "\(model.userPortfolioSnapshot?.rows.count ?? 0) 个标的", tint: AppPalette.info)
                if !model.menuBarTickerSettings.holdingSelections.isEmpty {
                    ToolbarBadge(title: "已选 \(model.menuBarTickerSettings.holdingSelections.count)", tint: AppPalette.positive)
                }
            }
        }
        .padding(.vertical, 14)
    }

    private var menuBarHoldingOptionsContent: some View {
        Group {
            if let snapshot = model.userPortfolioSnapshot, !snapshot.rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("可为任意持仓选择涨跌、收益、现价或市值；菜单栏最终仍受最多显示项限制。")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                    LazyVStack(spacing: 8) {
                        ForEach(snapshot.rows) { row in
                            menuBarHoldingRow(row)
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Text(model.hasPersonalPortfolio ? "还没有持仓估值结果，刷新后可选择单标的。" : "导入持仓后可选择单标的。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                    Spacer()
                    Button {
                        Task { try? await model.refreshUserPortfolio() }
                    } label: {
                        Label("刷新估值", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!model.hasPersonalPortfolio || model.isRefreshingPortfolio)
                }
                .padding(12)
                .background(AppPalette.card.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            }
        }
    }

    private func menuBarHoldingRow(_ row: UserPortfolioValuationRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            menuBarHoldingIdentity(row)
            menuBarHoldingMetricToggles(row)
        }
        .padding(10)
        .background(AppPalette.card.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.line.opacity(0.34), lineWidth: 1)
        )
    }

    private func menuBarHoldingIdentity(_ row: UserPortfolioValuationRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(row.fundName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                if let marketLabel = row.holding.marketLabel {
                    ToolbarBadge(title: marketLabel, tint: AppPalette.info)
                }
            }
            Text(row.holding.normalizedFundCode)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
        }
    }

    private func menuBarHoldingMetricToggles(_ row: UserPortfolioValuationRow) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], alignment: .leading, spacing: 8) {
            menuBarHoldingMetricToggle(row, .dailyAmount)
            menuBarHoldingMetricToggle(row, .dailyPct)
            menuBarHoldingMetricToggle(row, .profitAmount)
            menuBarHoldingMetricToggle(row, .profitPct)
            menuBarHoldingMetricToggle(row, .price)
            menuBarHoldingMetricToggle(row, .marketValue)
        }
    }

    private func menuBarHoldingMetricToggle(_ row: UserPortfolioValuationRow, _ metric: MenuBarHoldingMetric) -> some View {
        menuBarTickerSelectionToggle(
            isOn: Binding(
                get: { model.isMenuBarHoldingMetricEnabled(holdingID: row.holding.id, metric: metric) },
                set: { model.setMenuBarHoldingMetric(holdingID: row.holding.id, metric: metric, isEnabled: $0) }
            ),
            label: metric.label
        )
    }

    private func menuBarToneColor(_ tone: MenuBarTickerTone) -> Color {
        switch tone {
        case .positive:
            return AppPalette.marketGain
        case .negative:
            return AppPalette.marketLoss
        case .neutral:
            return AppPalette.muted
        }
    }

    private var settingsControlBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.72)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(settingsControlBackground, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
    }

    private func settingsField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(settingsControlBackground, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
        }
    }

}

private struct SettingsPanel<Content: View>: View {
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                    .frame(width: 30, height: 30)
                    .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            content
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.58), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(AppPalette.brand.opacity(0.22))
                .frame(width: 72, height: 2)
                .clipShape(Capsule())
                .padding(.leading, 15)
        }
    }
}

private struct SettingsMetric: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 6)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(AppPalette.cardStrong.opacity(isSelected ? 0.94 : 0.76), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(isSelected ? tint.opacity(0.72) : AppPalette.line.opacity(0.42), lineWidth: isSelected ? 1.2 : 1)
        )
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 54)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let isOn: Binding<Bool>

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(minHeight: 54)
    }
}

private struct SettingsStatePill: View {
    let title: String
    let state: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            Text(state)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.62), in: Capsule())
        .overlay(
            Capsule()
                .stroke(AppPalette.line.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct SettingsActionRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                content
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .padding(.vertical, 13)
    }
}

private struct SettingsDivider: View {
    var isInset = false

    var body: some View {
        Divider()
            .overlay(AppPalette.line.opacity(0.35))
            .padding(.leading, isInset ? 39 : 0)
    }
}
