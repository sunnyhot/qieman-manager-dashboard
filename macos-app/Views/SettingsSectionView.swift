import AppKit
import SwiftUI

// MARK: - Settings

enum SettingsFocus: CaseIterable, Identifiable {
    case general
    case watch
    case trend
    case menuBar

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "通用"
        case .watch:
            return "提醒与巡检"
        case .trend:
            return "AI 研判"
        case .menuBar:
            return "菜单栏"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "外观、启动与更新"
        case .watch:
            return "主理人动态通知"
        case .trend:
            return "模型与自动分析"
        case .menuBar:
            return "摘要样式与内容"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .watch:
            return "bell.badge"
        case .trend:
            return "sparkles"
        case .menuBar:
            return "menubar.rectangle"
        }
    }
}

struct SettingsSectionView: View {
    @EnvironmentObject var model: AppModel
    @State var selectedSettingsFocus: SettingsFocus = .general
    @State var isMenuBarHoldingOptionsExpanded = false
    @State var isMenuBarMarketIndexExpanded = false
    @State var isMenuBarFundMarketExpanded = false
    @State var draggedTickerSelectionID: String?
    @State var tickerDropTargetID: String?
    @State var isConfirmingMenuBarReset = false
    @State var isConfirmingHoldingSelectionClear = false

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
        HStack(spacing: 0) {
            settingsNavigation

            Divider()

            ScrollView(showsIndicators: false) {
                selectedSettingsPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .id(selectedSettingsFocus)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
        }
        .animation(AppPalette.motionSection, value: selectedSettingsFocus)
    }

    private var settingsNavigation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("功能与偏好")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            ForEach(SettingsFocus.allCases) { focus in
                Button {
                    selectedSettingsFocus = focus
                } label: {
                    SettingsNavigationRow(
                        title: focus.title,
                        subtitle: focus.subtitle,
                        status: settingsStatus(for: focus),
                        icon: focus.systemImage,
                        tint: settingsStatusTint(for: focus),
                        isSelected: selectedSettingsFocus == focus
                    )
                }
                .buttonStyle(PressResponsiveButtonStyle())
            }

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text("且慢主理人")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text("版本 \(AppUpdateChecker.bundleVersion)")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(AppPalette.muted)
            }
            .padding(.horizontal, 10)
        }
        .padding(12)
        .frame(width: 194)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            MaterialPanel(material: .underWindowBackground, blendingMode: .withinWindow)
                .opacity(0.36)
        )
    }

    private func settingsStatus(for focus: SettingsFocus) -> String {
        switch focus {
        case .general:
            return model.appearance.rawValue
        case .watch:
            return model.managerWatchSettings.isEnabled
                ? model.managerWatchSettings.intervalLabel
                : "已关闭"
        case .trend:
            let modelName = model.trendSettings.provider.model
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return model.trendSettings.provider.isConfigured && !modelName.isEmpty
                ? modelName
                : "未配置"
        case .menuBar:
            return model.menuBarTickerSettings.isEnabled
                ? "\(model.menuBarTickerVisibleEntries.count) 项"
                : "已关闭"
        }
    }

    private func settingsStatusTint(for focus: SettingsFocus) -> Color {
        switch focus {
        case .general:
            return AppPalette.brand
        case .watch:
            return model.managerWatchSettings.isEnabled ? AppPalette.positive : AppPalette.muted
        case .trend:
            return model.trendSettings.provider.isConfigured ? AppPalette.brand : AppPalette.muted
        case .menuBar:
            return model.menuBarTickerSettings.isEnabled ? AppPalette.info : AppPalette.muted
        }
    }

    @ViewBuilder
    private var selectedSettingsPanel: some View {
        switch selectedSettingsFocus {
        case .general:
            appPanel
        case .watch:
            watchPanel
        case .trend:
            TrendSettingsPanel()
        case .menuBar:
            menuBarPanel
        }
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let subtitle: String
    let status: String
    let icon: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? AppPalette.brand : AppPalette.muted)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                Text(status)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: AppPalette.sidebarRowRadius)
                .fill(isSelected ? AppPalette.selectionFill.opacity(0.82) : .clear)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(AppPalette.brand)
                    .frame(width: AppPalette.selectionRailWidth, height: 22)
                    .padding(.leading, 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: AppPalette.sidebarRowRadius))
    }
}
