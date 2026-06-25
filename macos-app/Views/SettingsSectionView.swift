import AppKit
import SwiftUI

// MARK: - Settings

enum SettingsFocus: CaseIterable, Identifiable {
    case account
    case watch
    case trend
    case menuBar
    case version

    var id: Self { self }
}

struct SettingsSectionView: View {
    @EnvironmentObject var model: AppModel
    @State var selectedSettingsFocus: SettingsFocus = .menuBar
    @State var isMenuBarHoldingOptionsExpanded = false
    @State var isMenuBarMarketIndexExpanded = false
    @State var isMenuBarFundMarketExpanded = false
    @State var draggedTickerSelectionID: String?
    @State var tickerDropTargetID: String?

    var menuBarTickerEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.menuBarTickerSettings.isEnabled },
            set: { model.setMenuBarTickerEnabled($0) }
        )
    }

    var menuBarTickerMaxItemsBinding: Binding<Int> {
        Binding(
            get: { model.menuBarTickerSettings.maxVisibleItems },
            set: { model.setMenuBarTickerMaxVisibleItems($0) }
        )
    }

    var menuBarTickerCustomColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: MenuBarTickerAppearance.nsColor(hex: model.menuBarTickerSettings.appearance.customTextColorHex) ?? .labelColor)
            },
            set: { color in
                model.updateMenuBarTickerAppearance { appearance in
                    appearance.textColorMode = .custom
                    appearance.customTextColorHex = MenuBarTickerAppearance.normalizedHex(from: NSColor(color))
                }
            }
        )
    }

    var menuBarTickerCarouselIntervalBinding: Binding<Double> {
        Binding(
            get: { model.menuBarTickerSettings.carouselIntervalSeconds },
            set: { model.setMenuBarTickerCarouselInterval($0) }
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                overviewBand
                selectedSettingsPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private var overviewBand: some View {
        VStack(alignment: .leading, spacing: 14) {
            overviewIntro
            overviewMetrics
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            AppPalette.borderOverlay(radius: AppPalette.panelRadius, opacity: AppPalette.borderHeavy)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
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
        [GridItem(.adaptive(minimum: 176), spacing: 12)]
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
                selectedSettingsFocus = .trend
            }
        } label: {
            SettingsMetric(
                title: "趋势",
                value: model.enhancementTrendStatus.valueText,
                detail: model.trendSettings.provider.isConfigured ? model.trendSettings.provider.model : "模型未配置",
                icon: "sparkles",
                tint: model.enhancementTrendStatus.severity.settingsTint,
                isSelected: selectedSettingsFocus == .trend
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
    }

    @ViewBuilder
    private var selectedSettingsPanel: some View {
        switch selectedSettingsFocus {
        case .account:
            accountPanel
        case .watch:
            watchPanel
        case .trend:
            trendSettingsPanel
        case .menuBar:
            menuBarPanel
        case .version:
            appPanel
        }
    }
}
