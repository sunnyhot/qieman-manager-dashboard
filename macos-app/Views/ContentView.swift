import AppKit
import SwiftUI

enum PersonalAssetFilterScope: String, CaseIterable, Identifiable {
    case all = "全部"
    case holding = "已持有"
    case archivedHolding = "已归档"
    case pending = "待确认"
    case activePlan = "进行中计划"
    case archivedPlan = "已暂停/终止"
    case drawdownMode = "涨跌幅模式"

    var id: String { rawValue }
}

enum PersonalAssetSortOption: String, CaseIterable, Identifiable {
    case dailyChange = "今日涨跌"
    case dailyChangePct = "今日涨跌幅"
    case exposure = "综合敞口"
    case marketValue = "市值"
    case pendingAmount = "待确认金额"
    case nextExecution = "下次定投时间"
    case planCumulative = "累计计划金额"
    case name = "标的名"

    static let defaultOption: PersonalAssetSortOption = .dailyChange

    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    // MARK: - Collapsible Filter State
    @State private var isQueryExpanded = false

    /// 收起时展示当前活跃（非默认值）筛选条件摘要
    private var activeFilterSummary: String {
        var parts: [String] = []
        if !model.form.prodCode.isEmpty && model.form.prodCode != "LONG_WIN" {
            parts.append("产品: \(model.form.prodCode)")
        }
        if !model.form.userName.isEmpty && model.form.userName != "ETF拯救世界" {
            parts.append("主理人: \(model.form.userName)")
        }
        if !model.form.keyword.isEmpty {
            parts.append("关键词: \(model.form.keyword)")
        }
        return parts.isEmpty ? "" : parts.joined(separator: "  ")
    }

    private var shouldShowQueryToolbar: Bool {
        switch model.selectedSection {
        case .platform, .forum:
            return true
        case .overview, .portfolio, .enhancement, .settings:
            return false
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebarNavigation
                .navigationSplitViewColumnWidth(min: 200, ideal: 232)
                .safeAreaInset(edge: .bottom) {
                    sidebarFooter
                }
                .modifier(SidebarFloatingCompatModifier())
        } detail: {
            mainContent
                .background(
                    ZStack {
                        AppPalette.canvasGradient
                        // Subtle material overlay for depth on macOS 14+
                        MaterialPanel(material: .underWindowBackground, blendingMode: .behindWindow)
                            .opacity(0.30)
                    }
                )
        }
        .frame(minWidth: 860, idealWidth: 1200, minHeight: 600)
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
                    downloadFraction: model.updateDownloadFraction,
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

    private var sidebarNavigation: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppPalette.spaceXS + 2) {
                ForEach(AppSection.allCases) { section in
                    SidebarSectionButton(
                        section: section,
                        isSelected: model.selectedSection == section
                    ) {
                        withAnimation(AppPalette.motionSpring) {
                            model.selectedSection = section
                        }
                    }
                }
            }
            .padding(.horizontal, AppPalette.spaceM)
            .padding(.vertical, AppPalette.spaceL)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Sidebar Footer

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceS + 2) {
            HStack(spacing: AppPalette.spaceS) {
                Circle()
                    .fill(model.cookieAvailable ? AppPalette.positive : AppPalette.warning)
                    .frame(width: 7, height: 7)
                Text(model.cookieAvailable ? "Cookie 可用" : "Cookie 缺失")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                Spacer(minLength: 0)
                Button {
                    model.openDataDirectory()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.muted)
                .help("打开数据目录")
            }

            if let logURL = model.logFileURL {
                Text(logURL.lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted.opacity(AppPalette.textDimmed))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AppPalette.spaceXL - 2)
        .padding(.bottom, AppPalette.spaceXL - 2)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            toolbar
            notifications
            detailPanel
                .id(model.selectedSection)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .animation(AppPalette.motionSection, value: model.selectedSection)
        }
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            VStack(spacing: AppPalette.spaceM) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppPalette.spaceL) {
                        toolbarTitleBlock
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                toggleMainWindowZoom()
                            }
                        Spacer(minLength: AppPalette.spaceM)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                toggleMainWindowZoom()
                            }
                        toolbarActionRow
                    }

                    VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                        toolbarTitleBlock
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                toggleMainWindowZoom()
                            }
                        ScrollView(.horizontal, showsIndicators: false) {
                            toolbarActionRow
                        }
                    }
                }

                if shouldShowQueryToolbar {
                    queryToolbarPanel
                }
            }
            .padding(.horizontal, AppPalette.toolbarPaddingH)
            .padding(.top, AppPalette.toolbarPaddingTop)
            .padding(.bottom, AppPalette.toolbarPaddingBottom)
            .background(
                MaterialPanel(material: .windowBackground, blendingMode: .withinWindow)
                    .opacity(AppPalette.bgToolbar)
            )

            Divider()
        }
    }

    private var queryToolbarPanel: some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            // ① QueryMode 芯片行 — 始终显示
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppPalette.spaceS) {
                    ForEach(QueryMode.allCases) { mode in
                        queryModeChip(mode: mode)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: AppPalette.spaceS)], alignment: .leading, spacing: AppPalette.spaceS) {
                    ForEach(QueryMode.allCases) { mode in
                        queryModeChip(mode: mode)
                    }
                }
            }

            // ② 可折叠的参数卡片
            collapsibleFilterPanel
        }
    }

    // MARK: - Collapsible Query Filter Panel

    private var collapsibleFilterPanel: some View {
        VStack(spacing: 0) {
            // 标题栏（始终可见，点击切换展开/收起）
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isQueryExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppPalette.brand)
                        .frame(width: 18, height: 18)
                        .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: AppPalette.badgeRadius))

                    Text("社区动态筛选")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)

                    // 收起时展示活跃条件摘要
                    if !isQueryExpanded && !activeFilterSummary.isEmpty {
                        Text(activeFilterSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(AppPalette.muted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer()

                    Image(systemName: isQueryExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppPalette.muted)
                }
                .padding(.horizontal, AppPalette.spaceM)
                .padding(.vertical, 9)
                .background(AppPalette.toolbarBackground.opacity(AppPalette.bgSettings))
            }
            .buttonStyle(.plain)

            // 筛选内容区（展开时显示）
            if isQueryExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // 基本参数行
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom, spacing: 10) {
                            toolbarField("产品", text: $model.form.prodCode, minWidth: 170)
                                .frame(width: 210)
                            toolbarField("主理人", text: $model.form.userName, minWidth: 190)
                                .frame(width: 250)
                            toolbarField("关键词", text: $model.form.keyword, minWidth: 220)
                                .frame(maxWidth: .infinity)
                            toolbarField("页数", text: $model.form.pages, minWidth: 88)
                                .frame(width: 104)
                            toolbarField("每页", text: $model.form.pageSize, minWidth: 88)
                                .frame(width: 104)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], alignment: .leading, spacing: 10) {
                            toolbarField("产品", text: $model.form.prodCode, minWidth: 170)
                            toolbarField("主理人", text: $model.form.userName, minWidth: 190)
                            toolbarField("关键词", text: $model.form.keyword, minWidth: 220)
                            toolbarField("页数", text: $model.form.pages, minWidth: 88)
                            toolbarField("每页", text: $model.form.pageSize, minWidth: 88)
                        }
                    }

                    // 日期范围行
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom, spacing: 10) {
                            toolbarField("起始", text: $model.form.since, minWidth: 180)
                                .frame(width: 220)
                            toolbarField("结束", text: $model.form.until, minWidth: 180)
                                .frame(width: 220)
                            Spacer(minLength: 0)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], alignment: .leading, spacing: 10) {
                            toolbarField("起始", text: $model.form.since, minWidth: 180)
                            toolbarField("结束", text: $model.form.until, minWidth: 180)
                        }
                    }

                    // 高级参数（复用现有 showAdvancedParams 逻辑）
                    if model.showAdvancedParams {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], alignment: .leading, spacing: 10) {
                            toolbarField("groupId", text: $model.form.groupID, minWidth: 180)
                            toolbarField("groupUrl", text: $model.form.groupURL, minWidth: 260)
                            toolbarField("brokerUserId", text: $model.form.brokerUserID, minWidth: 180)
                            toolbarField("spaceUserId", text: $model.form.spaceUserID, minWidth: 180)
                            toolbarField("自动刷新", text: $model.form.autoRefresh, minWidth: 140)
                        }
                    }
                }
                .padding(AppPalette.spaceM)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppPalette.panelBackground.opacity(AppPalette.bgPanel), in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            AppPalette.borderOverlay(radius: AppPalette.panelRadius, opacity: AppPalette.borderMedium)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppPalette.panelRadius))
    }

    private var toolbarTitleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.selectedSection.rawValue)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            HStack(spacing: AppPalette.spaceXS + 2) {
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
        }
    }

    private func toolbarField(_ label: String, text: Binding<String>, minWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceXS + 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .inputFieldStyle()
                .controlSize(.regular)
        }
        .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
    }

    private func queryModeChip(mode: QueryMode) -> some View {
        let isSelected = model.form.mode == mode
        return Button {
            withAnimation(AppPalette.motionSpring) {
                model.form.mode = mode
            }
        } label: {
            Text(mode.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? AppPalette.onBrand : AppPalette.ink)
                .padding(.horizontal, AppPalette.spaceL)
                .padding(.vertical, 10)
                .interactiveSurface(
                    isSelected: isSelected,
                    tint: AppPalette.brand,
                    radius: AppPalette.controlRadius,
                    fill: AppPalette.controlFill,
                    hoverFill: AppPalette.cardHover,
                    selectedFill: AppPalette.brand,
                    strokeOpacity: AppPalette.strokeSubtle,
                    activeStrokeOpacity: AppPalette.selectionStrokeOpacity,
                    lift: 0.5
                )
        }
        .buttonStyle(PressResponsiveButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: AppPalette.controlRadius))
    }

    /// Double-click the toolbar title area to zoom (maximize/restore) the main window.
    /// Only targets the app's tracked main window — never a sheet, popover, or NSPanel.
    private func toggleMainWindowZoom() {
        // Prefer the AppDelegate's tracked mainWindow reference.
        if let delegate = NSApplication.shared.delegate as? QiemanApplicationDelegate,
           let mainWin = delegate.mainWindowForZoom {
            mainWin.performZoom(nil)
            return
        }
        // Fallback: find the first suitable window, excluding panels/sheets.
        guard let targetWindow = NSApplication.shared.windows.first(where: { window in
            window.isVisible
                && window.canBecomeMain
                && !(window is NSPanel)
                && !window.isSheet
                && window.styleMask.contains(.resizable)
        }) else { return }
        targetWindow.performZoom(nil)
    }

    @ViewBuilder
    private var notifications: some View {
        if !model.noticeMessage.isEmpty || !model.errorMessage.isEmpty {
            VStack(spacing: AppPalette.spaceXS) {
                if !model.noticeMessage.isEmpty {
                    ToastBar(text: model.noticeMessage, tint: AppPalette.positive)
                        .task(id: model.noticeMessage) {
                            await dismissNoticeToast(model.noticeMessage, after: 4.5)
                        }
                }
                if !model.errorMessage.isEmpty {
                    ToastBar(text: model.errorMessage, tint: AppPalette.danger)
                        .task(id: model.errorMessage) {
                            await dismissErrorToast(model.errorMessage, after: 8)
                        }
                }
            }
            .padding(.horizontal, AppPalette.contentPadding)
            .padding(.top, AppPalette.spaceS)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func dismissNoticeToast(_ message: String, after seconds: Double) async {
        guard !message.isEmpty else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        await MainActor.run {
            guard model.noticeMessage == message else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                model.noticeMessage = ""
            }
        }
    }

    private func dismissErrorToast(_ message: String, after seconds: Double) async {
        guard !message.isEmpty else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        await MainActor.run {
            guard model.errorMessage == message else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                model.errorMessage = ""
            }
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        switch model.selectedSection {
        case .overview:
            OverviewSectionView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .portfolio:
            PortfolioSectionView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .settings:
            SettingsSectionView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .platform:
            PlatformSectionView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .forum:
            ForumSectionView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .enhancement:
            EnhancementCenterView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SidebarSectionButton: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var activeTint: Color {
        isSelected ? AppPalette.brand : (isHovering ? AppPalette.ink : AppPalette.muted)
    }

    private var rowFill: Color {
        if isSelected {
            return AppPalette.selectionFill.opacity(0.78)
        }
        if isHovering {
            return AppPalette.cardHover.opacity(0.72)
        }
        return .clear
    }

    private var strokeColor: Color {
        isSelected
            ? AppPalette.selectionStroke.opacity(AppPalette.selectionStrokeOpacity)
            : AppPalette.line.opacity(isHovering ? AppPalette.borderMedium : 0)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppPalette.spaceS) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? AppPalette.brand : .clear)
                    .frame(width: AppPalette.selectionRailWidth, height: 24)

                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(activeTint)
                    .frame(width: 26, height: 26)
                    .background(
                        (isSelected ? AppPalette.brand.opacity(0.13) : activeTint.opacity(isHovering ? 0.08 : 0.05)),
                        in: RoundedRectangle(cornerRadius: AppPalette.iconBoxRadius)
                    )

                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AppPalette.ink : activeTint)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppPalette.spaceS)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowFill, in: RoundedRectangle(cornerRadius: AppPalette.sidebarRowRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.sidebarRowRadius)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(
                color: AppPalette.selectionGlow.opacity(isSelected ? AppPalette.selectionGlowOpacity : 0),
                radius: isSelected ? AppPalette.selectionGlowRadius : 0,
                x: 0,
                y: isSelected ? 4 : 0
            )
            .offset(y: isHovering && !isSelected ? -AppPalette.hoverLift : 0)
            .contentShape(RoundedRectangle(cornerRadius: AppPalette.sidebarRowRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(AppPalette.motionStandard, value: isHovering)
        .animation(AppPalette.motionSpring, value: isSelected)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct AppUpdateSheet: View {
    let release: AppUpdateRelease
    let isInstalling: Bool
    let installProgress: String
    let downloadFraction: Double
    let onInstall: () -> Void
    let onReleasePage: () -> Void
    let onDismiss: () -> Void

    private var releaseNoteItems: [String] {
        let items = AppUpdateReleaseNotesFormatter.items(from: release.notes)
        return items.isEmpty ? ["这个版本没有填写更新说明。"] : items
    }

    private var publishedText: String? {
        guard let publishedAt = release.publishedAt else { return nil }
        return Self.releaseDateFormatter.string(from: publishedAt)
    }

    private static let releaseDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                    .frame(width: 48, height: 48)
                    .background(AppPalette.brandSoft, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

                VStack(alignment: .leading, spacing: AppPalette.spaceS - 2) {
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
                HStack(spacing: AppPalette.spaceS) {
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

                VStack(alignment: .leading, spacing: AppPalette.spaceS) {
                    Text("本次更新")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)

                    ScrollView {
                        VStack(alignment: .leading, spacing: AppPalette.spaceS) {
                            ForEach(Array(releaseNoteItems.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .firstTextBaseline, spacing: AppPalette.spaceS) {
                                    Text("•")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppPalette.muted)
                                    Text(item)
                                        .font(.system(size: 13))
                                        .foregroundStyle(AppPalette.ink)
                                        .lineSpacing(AppPalette.spaceXS)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
                .padding(AppPalette.spaceM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))

                if isInstalling {
                    VStack(alignment: .leading, spacing: AppPalette.spaceS) {
                        if downloadFraction > 0 {
                            // Determinate progress bar during download
                            ProgressView(value: downloadFraction, total: 1.0)
                                .progressViewStyle(.linear)
                                .tint(AppPalette.brand)
                        } else {
                            // Indeterminate spinner for non-download phases (extract, verify, install)
                            ProgressView()
                                .controlSize(.small)
                        }
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

// MARK: - Sidebar Floating Compatibility Modifier

/// Applies a floating visual effect to the sidebar on all macOS versions.
/// Uses a translucent material background, rounded corners, padding, and
/// a subtle shadow to create the "hovering" look.
struct SidebarFloatingCompatModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, AppPalette.spaceS)
            .padding(.leading, AppPalette.spaceS)
            .padding(.trailing, AppPalette.spaceXS)
            .background(
                MaterialPanel(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            )
            .clipShape(RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            .shadow(color: AppPalette.sidebarShadowColor, radius: AppPalette.sidebarShadowRadius, x: AppPalette.sidebarShadowX, y: 0)
    }
}

// MARK: - NSVisualEffectView Wrapper (Legacy Alias)

/// Wraps `NSVisualEffectView` to provide a blurred material backdrop.
/// Kept for backward compatibility; new code should use `MaterialPanel` instead.
struct VisualEffectBlurView: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}
