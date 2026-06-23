import SwiftUI

// MARK: - Trend Analysis Settings

extension SettingsSectionView {
    var trendSettingsPanel: some View {
        SettingsPanel(title: "趋势分析", subtitle: "连接本地或云端 OpenAI-compatible 模型", icon: "sparkles") {
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
                    title: "每日自动分析",
                    detail: "每天首次启动且模型已配置时自动更新一次",
                    icon: "clock.badge.checkmark",
                    tint: model.trendSettings.dailyAutoAnalysisEnabled ? AppPalette.positive : AppPalette.muted,
                    isOn: trendAutoAnalysisBinding
                )

                SettingsDivider()

                VStack(alignment: .leading, spacing: 12) {
                    Picker("隐私模式", selection: trendPrivacyModeBinding) {
                        ForEach(TrendPrivacyMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    trendField("服务名称", text: trendProviderNameBinding, placeholder: "OpenAI-compatible")
                    trendField("Base URL", text: trendBaseURLBinding, placeholder: "https://api.openai.com/v1")
                    trendField("模型", text: trendModelBinding, placeholder: "gpt-4.1")
                    trendSecureField("API Key", text: trendAPIKeyBinding, placeholder: "sk-...")
                    SettingsToggleRow(
                        title: "模型支持联网检索",
                        detail: "开启后 prompt 会要求引用最新新闻/数据来源",
                        icon: "network",
                        tint: model.trendSettings.provider.supportsOnlineSearch ? AppPalette.info : AppPalette.muted,
                        isOn: trendOnlineSearchBinding
                    )
                }
                .padding(.vertical, 13)

                SettingsDivider()

                SettingsActionRow {
                    Button {
                        model.saveTrendAnalysisSettings()
                    } label: {
                        Label("保存配置", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.brand)

                    Button {
                        model.detectLocalAIConfigurations()
                    } label: {
                        Label("检测本地配置", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await model.checkTrendAIConnection() }
                    } label: {
                        Label(
                            model.trendConnectionState == .checking ? "检测中" : "检测连通性",
                            systemImage: model.trendConnectionState == .checking ? "hourglass" : "antenna.radiowaves.left.and.right"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.trendSettings.provider.isConfigured || model.trendConnectionState == .checking)
                }

                if !model.trendLocalCandidates.isEmpty {
                    SettingsDivider()
                    localTrendCandidates
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
        }
    }

    private var localTrendCandidates: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("检测结果")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            ForEach(model.trendLocalCandidates) { candidate in
                trendCandidateRow(candidate)
            }
        }
        .padding(.vertical, 13)
    }

    private func trendCandidateRow(_ candidate: LocalAIConfigurationCandidate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: candidate.canImport ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(candidate.canImport ? AppPalette.positive : AppPalette.warning)
                .frame(width: 28, height: 28)
                .background((candidate.canImport ? AppPalette.positive : AppPalette.warning).opacity(AppPalette.accentOnFill), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.providerName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text(candidate.sourceDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(candidateSummary(candidate))
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                if let warning = candidate.warning {
                    Text(warning)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Button {
                model.importTrendProvider(candidate)
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(!candidate.canImport)
        }
        .padding(11)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.hairline.opacity(0.36), lineWidth: 1)
        )
    }

    private func candidateSummary(_ candidate: LocalAIConfigurationCandidate) -> String {
        let base = candidate.baseURL ?? "缺 Base URL"
        let modelName = candidate.model ?? "缺模型"
        let key = candidate.maskedAPIKey.isEmpty ? (candidate.apiKeySource ?? "缺 API Key") : candidate.maskedAPIKey
        return "\(base) · \(modelName) · \(key)"
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

    private var trendBaseURLBinding: Binding<String> {
        Binding(
            get: { model.trendSettings.provider.baseURL },
            set: { model.trendSettings.provider.baseURL = $0 }
        )
    }

    private var trendModelBinding: Binding<String> {
        Binding(
            get: { model.trendSettings.provider.model },
            set: { model.trendSettings.provider.model = $0 }
        )
    }

    private var trendAPIKeyBinding: Binding<String> {
        Binding(
            get: { model.trendSettings.provider.apiKey },
            set: { model.trendSettings.provider.apiKey = $0 }
        )
    }

    private var trendOnlineSearchBinding: Binding<Bool> {
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
            set: { model.trendSettings.dailyAutoAnalysisEnabled = $0 }
        )
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
