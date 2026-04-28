import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

enum PersonalAssetFilterScope: String, CaseIterable, Identifiable {
    case all = "全部"
    case holding = "已持有"
    case pending = "待确认"
    case activePlan = "进行中计划"
    case archivedPlan = "已暂停/终止"
    case drawdownMode = "涨跌幅模式"

    var id: String { rawValue }
}

enum PersonalAssetSortOption: String, CaseIterable, Identifiable {
    case exposure = "综合敞口"
    case marketValue = "市值"
    case pendingAmount = "待确认金额"
    case nextExecution = "下次定投时间"
    case planCumulative = "累计计划金额"
    case name = "标的名"

    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    private let compactSidebarThreshold: CGFloat = 1360

    private var shouldShowQueryToolbar: Bool {
        switch model.selectedSection {
        case .platform, .forum:
            return true
        case .overview, .portfolio, .settings:
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

                        Button {
                            model.openDataDirectory()
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppPalette.muted)
                        .help("打开数据目录")
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
            model.selectedSection = section
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
        ZStack {
            OverviewSectionView()
                .opacity(model.selectedSection == .overview ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PortfolioSectionView()
                .opacity(model.selectedSection == .portfolio ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            SettingsSectionView()
                .opacity(model.selectedSection == .settings ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PlatformSectionView()
                .opacity(model.selectedSection == .platform ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ForumSectionView()
                .opacity(model.selectedSection == .forum ? 1 : 0)
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

