import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

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
    private let sidebarWidth: CGFloat = 232
    @State private var isSidebarCollapsed = false

    private var shouldShowQueryToolbar: Bool {
        switch model.selectedSection {
        case .platform, .forum:
            return true
        case .overview, .portfolio, .settings:
            return false
        }
    }

    var body: some View {
        ZStack {
            AppPalette.canvasGradient

            HStack(spacing: 0) {
                if !isSidebarCollapsed {
                    sidebar()
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                mainContent
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 1080, minHeight: 780)
        .background(WindowChromeConfigurator())
        .background(SidebarToggleBridge(isCollapsed: isSidebarCollapsed, expandedSidebarWidth: sidebarWidth))
        .onReceive(NotificationCenter.default.publisher(for: .sidebarToggleRequested)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                isSidebarCollapsed.toggle()
            }
        }
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

    private func sidebar() -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                ForEach(AppSection.allCases) { section in
                    sidebarButton(section: section)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 72)

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
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
                        .foregroundStyle(AppPalette.muted.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(SidebarEffectView())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppPalette.line.opacity(0.48))
                .frame(width: 1)
        }
    }

    private func sidebarButton(section: AppSection) -> some View {
        let isSelected = model.selectedSection == section
        return Button {
            guard model.selectedSection != section else { return }
            model.selectedSection = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? AppPalette.ink : AppPalette.muted)

                Text(section.rawValue)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AppPalette.ink : AppPalette.ink.opacity(0.86))

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                    .fill(isSelected ? AppPalette.line.opacity(0.44) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppPalette.controlRadius))
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
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        toggleMainWindowZoom()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        toolbarTitleBlock
                        ScrollView(.horizontal, showsIndicators: false) {
                            toolbarActionRow
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        toggleMainWindowZoom()
                    }
                }

                if shouldShowQueryToolbar {
                    queryToolbarPanel
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 38)
            .padding(.bottom, 14)
            .background(AppPalette.paper.opacity(0.96))

            Divider()
        }
    }

    private var queryToolbarPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(QueryMode.allCases) { mode in
                        queryModeChip(mode: mode)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(QueryMode.allCases) { mode in
                        queryModeChip(mode: mode)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
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
            .padding(12)
            .background(AppPalette.card.opacity(0.52), in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                    .stroke(AppPalette.line.opacity(0.42), lineWidth: 1)
            )
        }
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
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
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
                .background(isSelected ? AppPalette.brand : AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                        .stroke(isSelected ? AppPalette.brand.opacity(0.40) : AppPalette.line.opacity(0.42), lineWidth: 1)
                )
        }
        .buttonStyle(PressResponsiveButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: AppPalette.controlRadius))
    }

    private func toggleMainWindowZoom() {
        let targetWindow = NSApp.keyWindow ?? NSApplication.shared.windows.first {
            $0.isVisible && $0.canBecomeMain && !($0 is NSPanel)
        }
        targetWindow?.performZoom(nil)
    }

    @ViewBuilder
    private var notifications: some View {
        if !model.noticeMessage.isEmpty || !model.errorMessage.isEmpty {
            VStack(spacing: 4) {
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
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
                    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))

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

private struct SidebarEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension Notification.Name {
    static let sidebarToggleRequested = Notification.Name("sidebarToggleRequested")
}

struct SidebarChromeMetrics {
    static let titlebarToggleSize = CGSize(width: 70, height: 44)
    private static let trafficLightGap: CGFloat = 20
    private static let expandedTrailingInset: CGFloat = 16

    static func toggleOriginX(
        isSidebarCollapsed: Bool,
        expandedSidebarWidth: CGFloat,
        toggleWidth: CGFloat,
        trafficLightRightX: CGFloat
    ) -> CGFloat {
        let afterTrafficLights = trafficLightRightX + trafficLightGap
        guard !isSidebarCollapsed else { return afterTrafficLights }
        return max(afterTrafficLights, expandedSidebarWidth - toggleWidth - expandedTrailingInset)
    }
}

private struct SidebarToggleBridge: NSViewRepresentable {
    let isCollapsed: Bool
    let expandedSidebarWidth: CGFloat

    func makeNSView(context: Context) -> ToggleHostView {
        let host = ToggleHostView()
        host.expandedSidebarWidth = expandedSidebarWidth
        host.onToggle = {
            NotificationCenter.default.post(name: .sidebarToggleRequested, object: nil)
        }
        return host
    }

    func updateNSView(_ host: ToggleHostView, context: Context) {
        host.isCollapsed = isCollapsed
        host.expandedSidebarWidth = expandedSidebarWidth
        host.refreshAppearance()
        host.reposition()
    }

    final class ToggleHostView: NSView {
        var isCollapsed = false
        var expandedSidebarWidth: CGFloat = 232
        var onToggle: (() -> Void)?
        private var button: TitlebarSidebarButton?
        private var resizeObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Delay to let the window chrome fully initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.installButton()
            }
        }

        private func installButton() {
            guard let window, button == nil else { return }
            // Find the titlebar container — same superview as the traffic light buttons
            guard let closeBtn = window.standardWindowButton(.closeButton),
                  let titleBarContainer = closeBtn.superview else { return }

            let size = SidebarChromeMetrics.titlebarToggleSize
            let btn = TitlebarSidebarButton(frame: NSRect(origin: .zero, size: size))
            btn.imagePosition = .imageOnly
            btn.imageScaling = .scaleProportionallyDown
            btn.target = self
            btn.action = #selector(clicked)

            titleBarContainer.addSubview(btn)
            button = btn

            refreshAppearance()
            reposition()

            // Keep aligned on resize
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { [weak self] _ in self?.reposition() }
        }

        @objc func clicked() { onToggle?() }

        func refreshAppearance() {
            guard let btn = button else { return }
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            btn.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            btn.contentTintColor = .secondaryLabelColor
            btn.toolTip = isCollapsed ? "展开侧边栏" : "收起侧边栏"
            btn.updateAppearance()
        }

        func reposition() {
            guard let window,
                  let zoomBtn = window.standardWindowButton(.zoomButton),
                  let btn = button else { return }
            let size = btn.frame.size
            let x = SidebarChromeMetrics.toggleOriginX(
                isSidebarCollapsed: isCollapsed,
                expandedSidebarWidth: expandedSidebarWidth,
                toggleWidth: size.width,
                trafficLightRightX: zoomBtn.frame.maxX
            )
            btn.frame.origin = CGPoint(
                x: x,
                y: zoomBtn.frame.midY - size.height / 2
            )
        }

        override func removeFromSuperview() {
            if let obs = resizeObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            button?.removeFromSuperview()
            button = nil
            super.removeFromSuperview()
        }
    }

    final class TitlebarSidebarButton: NSButton {
        private var trackingArea: NSTrackingArea?
        private var isHovered = false
        private var isPressed = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            configure()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configure()
        }

        private func configure() {
            isBordered = false
            wantsLayer = true
            focusRingType = .none
            layer?.cornerRadius = 10
            layer?.masksToBounds = true
            updateAppearance()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            isHovered = true
            updateAppearance()
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
            updateAppearance()
        }

        override func mouseDown(with event: NSEvent) {
            isPressed = true
            updateAppearance()
            super.mouseDown(with: event)
            isPressed = false
            updateAppearance()
        }

        func updateAppearance() {
            let color: NSColor
            if isPressed {
                color = NSColor.labelColor.withAlphaComponent(0.12)
            } else if isHovered {
                color = NSColor.labelColor.withAlphaComponent(0.07)
            } else {
                color = .clear
            }
            layer?.backgroundColor = color.cgColor
        }
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowChromeView {
        WindowChromeView()
    }

    func updateNSView(_ nsView: WindowChromeView, context: Context) {
        nsView.configureWindowChrome()
    }

    final class WindowChromeView: NSView {
        private weak var configuredWindow: NSWindow?
        private var didShiftTrafficLights = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindowChrome()
        }

        func configureWindowChrome() {
            guard let window else { return }
            if configuredWindow !== window {
                configuredWindow = window
                didShiftTrafficLights = false
            }

            window.title = "且慢主理人"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true

            if window.toolbar?.identifier != "main" {
                let tb = NSToolbar(identifier: "main")
                tb.showsBaselineSeparator = false
                window.toolbar = tb
            }
            window.toolbarStyle = .unified

            if !didShiftTrafficLights {
                didShiftTrafficLights = shiftTrafficLightsUp(by: 8, in: window)
            }
        }

        private func shiftTrafficLightsUp(by offset: CGFloat, in window: NSWindow) -> Bool {
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            guard buttons.allSatisfy({ window.standardWindowButton($0) != nil }) else {
                return false
            }
            for type in buttons {
                window.standardWindowButton(type)?.frame.origin.y += offset
            }
            return true
        }
    }
}
