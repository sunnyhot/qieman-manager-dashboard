import SwiftUI

// MARK: - App Panel (Version / Updates)

extension SettingsSectionView {
    var appPanel: some View {
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
