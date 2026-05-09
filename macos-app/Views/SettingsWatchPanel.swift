import SwiftUI

// MARK: - Watch Panel

extension SettingsSectionView {
    var watchPanel: some View {
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
