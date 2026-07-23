import SwiftUI

// MARK: - App Panel (General / Updates)

extension SettingsSectionView {
    var appPanel: some View {
        SettingsPanel(title: "通用", subtitle: "外观、版本与更新", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    title: "外观",
                    value: model.appearance.rawValue,
                    detail: "浅色 / 深色 / 跟随系统",
                    icon: "circle.lefthalf.filled",
                    tint: AppPalette.info
                )
                HStack(spacing: 8) {
                    ForEach(AppAppearance.allCases) { mode in
                        Button {
                            model.appearance = mode
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: mode == .light ? "sun.max.fill" : mode == .dark ? "moon.fill" : "circle.lefthalf.filled")
                                    .font(.system(size: 11))
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(model.appearance == mode ? AppPalette.onBrand : AppPalette.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(model.appearance == mode ? AppPalette.brand : AppPalette.card))
                            .overlay(Capsule().stroke(model.appearance == mode ? AppPalette.brand : AppPalette.line, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PressResponsiveButtonStyle())
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                SettingsDivider()
                SettingsToggleRow(
                    title: "启动时检查更新",
                    detail: "每次打开应用自动检测新版本",
                    icon: "arrow.triangle.2.circlepath",
                    tint: AppPalette.brand,
                    isOn: $model.autoCheckForUpdatesOnLaunch
                )
                SettingsDivider()
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
                    .buttonStyle(.appPrimary)
                    .tint(AppPalette.brand)
                    .disabled(model.isCheckingForUpdates)

                    if model.availableUpdate != nil {
                        Button {
                            Task { await model.downloadAndInstallAvailableUpdate() }
                        } label: {
                            Label(model.isInstallingUpdate ? "安装中…" : "下载并安装", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.appSecondary)
                        .disabled(model.isInstallingUpdate)

                        Button {
                            model.openAvailableUpdateReleasePage()
                        } label: {
                            Label("Release", systemImage: "safari")
                        }
                        .buttonStyle(.appSecondary)
                    }

                    Spacer()

                    Button {
                        model.quitApplication()
                    } label: {
                        Label("退出应用", systemImage: "power")
                    }
                    .buttonStyle(.appSecondary)
                    .tint(AppPalette.danger)
                    .help("退出且慢主理人看板")
                }

                if !model.updateInstallProgress.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if model.updateDownloadFraction > 0 {
                            ProgressView(value: model.updateDownloadFraction, total: 1.0)
                                .progressViewStyle(.linear)
                                .tint(AppPalette.brand)
                        }
                        ToastBar(text: model.updateInstallProgress, tint: AppPalette.info)
                    }
                    .padding(.top, 12)
                }
            }
        }
    }
}
