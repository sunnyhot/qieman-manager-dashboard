import SwiftUI

// MARK: - Account Panel

extension SettingsSectionView {
    var accountPanel: some View {
        SettingsPanel(title: "账号与登录", subtitle: "登录状态、Cookie 与身份验证", icon: "person.circle") {
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
                            withAnimation(.easeInOut(duration: 0.18)) {
                                model.appearance = mode
                            }
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
                            .background(
                                Capsule()
                                    .fill(model.appearance == mode ? AppPalette.brand : AppPalette.card)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(model.appearance == mode ? AppPalette.brand : AppPalette.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(PressResponsiveButtonStyle())
                    }
                    Spacer()
                }
                .padding(.vertical, 6)

                SettingsDivider()

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
}
