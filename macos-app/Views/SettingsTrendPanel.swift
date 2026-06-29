import SwiftUI

// MARK: - Trend Analysis Settings

extension SettingsSectionView {
    var trendSettingsPanel: some View {
        SettingsPanel(title: "趋势分析", subtitle: "直连 OpenAI-compatible 模型生成趋势分析", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    title: "当前状态",
                    value: model.enhancementTrendStatus.valueText,
                    detail: model.enhancementTrendStatus.detailText,
                    icon: "waveform.path.ecg",
                    tint: model.enhancementTrendStatus.severity.settingsTint
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "每日定时分析",
                    detail: "默认 09:30、14:30；打开主界面时会补跑错过的最近一次",
                    icon: "clock.badge.checkmark",
                    tint: model.trendSettings.dailyAutoAnalysisEnabled ? AppPalette.positive : AppPalette.muted,
                    isOn: trendAutoAnalysisBinding
                )

                SettingsDivider()

                VStack(alignment: .leading, spacing: 12) {
                    trendField("每日时间", text: trendAutoAnalysisTimesBinding, placeholder: "09:30, 14:30")
                        .disabled(!model.trendSettings.dailyAutoAnalysisEnabled)
                        .opacity(model.trendSettings.dailyAutoAnalysisEnabled ? 1 : 0.55)

                    Picker("隐私模式", selection: trendPrivacyModeBinding) {
                        ForEach(TrendPrivacyMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    trendField("供应商", text: trendProviderNameBinding, placeholder: "智谱 / OpenAI / 其他")
                    trendField("Base URL", text: trendProviderBaseURLBinding, placeholder: "https://open.bigmodel.cn/api/coding/paas/v4")
                    trendField("模型", text: trendProviderModelBinding, placeholder: "glm-5.2")
                    trendSecureField("API Key", text: trendProviderAPIKeyBinding, placeholder: "sk-...")
                    trendField("超时秒数", text: trendProviderTimeoutBinding, placeholder: "300")

                    trendLabeledControl("外部信号") {
                        Toggle("支持联网/外部信号", isOn: trendProviderSearchBinding)
                            .toggleStyle(.switch)
                    }
                }
                .padding(.vertical, 13)

                SettingsDivider()

                SettingsActionRow {
                    Button {
                        saveTrendSettingsFromDraft()
                    } label: {
                        Label("保存配置", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.brand)

                    Button {
                        Task { await model.checkTrendAIConnection() }
                    } label: {
                        Label(
                            model.trendConnectionState == .checking ? "检测中" : "检测模型",
                            systemImage: model.trendConnectionState == .checking ? "hourglass" : "antenna.radiowaves.left.and.right"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.trendSettings.provider.isConfigured || model.trendConnectionState == .checking)
                }

                if !model.lastTrendConnectionMessage.isEmpty {
                    ToastBar(text: model.lastTrendConnectionMessage, tint: trendConnectionTint)
                        .padding(.top, 12)
                }

                if !model.lastTrendError.isEmpty && model.lastTrendError != model.lastTrendConnectionMessage {
                    ToastBar(text: model.lastTrendError, tint: AppPalette.warning)
                        .padding(.top, 12)
                }
            }
            .onAppear {
                if trendAutoAnalysisTimesDraft.isEmpty {
                    trendAutoAnalysisTimesDraft = model.trendSettings.dailyAutoAnalysisTimesText
                }
            }
        }
    }

    private func trendField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        trendLabeledControl(label) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(trendControlBackground, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(trendInputBorder)
        }
    }

    private func trendSecureField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        trendLabeledControl(label) {
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(trendControlBackground, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(trendInputBorder)
        }
    }

    private func trendLabeledControl<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trendInputBorder: some View {
        RoundedRectangle(cornerRadius: AppPalette.controlRadius)
            .stroke(AppPalette.hairline.opacity(0.32), lineWidth: 1)
    }

    private var trendProviderNameBinding: Binding<String> {
        Binding(
            get: { model.trendSettings.provider.providerName },
            set: { model.trendSettings.provider.providerName = $0 }
        )
    }

    private var trendProviderBaseURLBinding: Binding<String> {
        Binding(
            get: { model.trendSettings.provider.baseURL },
            set: { model.trendSettings.provider.baseURL = $0 }
        )
    }

    private var trendProviderModelBinding: Binding<String> {
        Binding(
            get: { model.trendSettings.provider.model },
            set: { model.trendSettings.provider.model = $0 }
        )
    }

    private var trendProviderAPIKeyBinding: Binding<String> {
        Binding(
            get: { model.trendSettings.provider.apiKey },
            set: { model.trendSettings.provider.apiKey = $0 }
        )
    }

    private var trendProviderTimeoutBinding: Binding<String> {
        Binding(
            get: {
                String(Int(model.trendSettings.provider.timeoutSeconds.rounded()))
            },
            set: { rawValue in
                if let timeout = Double(rawValue), timeout > 0 {
                    model.trendSettings.provider.timeoutSeconds = timeout
                }
            }
        )
    }

    private var trendProviderSearchBinding: Binding<Bool> {
        Binding(
            get: { model.trendSettings.provider.supportsOnlineSearch },
            set: { model.trendSettings.provider.supportsOnlineSearch = $0 }
        )
    }

    private var trendPrivacyModeBinding: Binding<TrendPrivacyMode> {
        Binding(
            get: { model.trendPrivacyMode },
            set: { mode in
                model.trendPrivacyMode = mode
                model.trendSettings.defaultPrivacyMode = mode
            }
        )
    }

    private var trendAutoAnalysisBinding: Binding<Bool> {
        Binding(
            get: { model.trendSettings.dailyAutoAnalysisEnabled },
            set: { isEnabled in
                model.trendSettings.dailyAutoAnalysisEnabled = isEnabled
                saveTrendSettingsFromDraft()
            }
        )
    }

    private var trendAutoAnalysisTimesBinding: Binding<String> {
        Binding(
            get: {
                trendAutoAnalysisTimesDraft.isEmpty
                    ? model.trendSettings.dailyAutoAnalysisTimesText
                    : trendAutoAnalysisTimesDraft
            },
            set: { trendAutoAnalysisTimesDraft = $0 }
        )
    }

    private func saveTrendSettingsFromDraft() {
        model.trendSettings.updateDailyAutoAnalysisTimes(from: trendAutoAnalysisTimesDraft)
        trendAutoAnalysisTimesDraft = model.trendSettings.dailyAutoAnalysisTimesText
        model.saveTrendAnalysisSettings()
    }

    private var trendConnectionTint: Color {
        switch model.trendConnectionState {
        case .idle:
            return AppPalette.muted
        case .checking:
            return AppPalette.info
        case .succeeded:
            return AppPalette.positive
        case .failed:
            return AppPalette.warning
        }
    }

    private var trendControlBackground: Color {
        AppPalette.cardStrong.opacity(AppPalette.bgDefault)
    }
}

extension EnhancementPresentationSeverity {
    var settingsTint: Color {
        switch self {
        case .brand:
            return AppPalette.brand
        case .info:
            return AppPalette.info
        case .positive:
            return AppPalette.positive
        case .warning:
            return AppPalette.warning
        case .danger:
            return AppPalette.danger
        case .neutral:
            return AppPalette.muted
        }
    }
}
