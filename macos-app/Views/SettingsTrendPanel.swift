import SwiftUI

// MARK: - Trend Analysis Settings

extension SettingsSectionView {
    var trendSettingsPanel: some View {
        SettingsPanel(title: "趋势分析", subtitle: "选择本地 Agent 生成趋势分析", icon: "sparkles") {
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
                    detail: "每天首次启动且本地 Agent 可用时自动更新一次",
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

                    Picker("默认 Agent", selection: trendAgentKindBinding) {
                        ForEach(TrendAgentKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)

                    trendField("自定义命令路径", text: trendAgentCommandPathBinding, placeholder: "/opt/homebrew/bin/claude")
                    trendField("模型/参数", text: trendAgentModelBinding, placeholder: "sonnet / opus / 留空")
                    trendField("配置 Profile", text: trendAgentProfileBinding, placeholder: "可选")
                    trendField("超时秒数", text: trendAgentTimeoutBinding, placeholder: "300")
                    trendField(
                        "自定义命令模板",
                        text: trendAgentTemplateBinding,
                        placeholder: "{{command}} {{promptFile}} {{schemaFile}} {{outputFile}} {{runDir}}"
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
                        model.detectTrendAgents()
                    } label: {
                        Label("检测 Agent", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await model.checkTrendAgentConnection() }
                    } label: {
                        Label(
                            model.trendConnectionState == .checking ? "检测中" : "检测连通性",
                            systemImage: model.trendConnectionState == .checking ? "hourglass" : "antenna.radiowaves.left.and.right"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.trendSettings.agent.isRunnable(with: model.trendAgentCandidates) || model.trendConnectionState == .checking)
                }

                if !model.trendAgentCandidates.isEmpty {
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
            ForEach(model.trendAgentCandidates) { candidate in
                trendCandidateRow(candidate)
            }
        }
        .padding(.vertical, 13)
    }

    private func trendCandidateRow(_ candidate: TrendAgentCandidate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: candidate.isRunnable ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(candidate.isRunnable ? AppPalette.positive : AppPalette.warning)
                .frame(width: 28, height: 28)
                .background((candidate.isRunnable ? AppPalette.positive : AppPalette.warning).opacity(AppPalette.accentOnFill), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text(candidate.commandPath)
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
                model.trendSettings.agent.kind = candidate.kind
                model.trendSettings.agent.commandPath = candidate.commandPath
                model.saveTrendAnalysisSettings()
            } label: {
                Label("使用", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(!candidate.isRunnable)
        }
        .padding(11)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.hairline.opacity(0.36), lineWidth: 1)
        )
    }

    private func candidateSummary(_ candidate: TrendAgentCandidate) -> String {
        let state = candidate.isRunnable ? "可用" : (candidate.isInstalled ? "不可执行" : "未安装")
        let capabilities = candidate.capabilities.map(\.rawValue).joined(separator: " / ")
        guard !capabilities.isEmpty else { return state }
        return "\(state) · \(capabilities)"
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

    private var trendAgentKindBinding: Binding<TrendAgentKind> {
        Binding(
            get: { model.trendSettings.agent.kind },
            set: { model.trendSettings.agent.kind = $0 }
        )
    }

    private var trendAgentCommandPathBinding: Binding<String> {
        Binding(
            get: { model.trendSettings.agent.commandPath },
            set: { model.trendSettings.agent.commandPath = $0 }
        )
    }

    private var trendAgentModelBinding: Binding<String> {
        Binding(
            get: { model.trendSettings.agent.model },
            set: { model.trendSettings.agent.model = $0 }
        )
    }

    private var trendAgentProfileBinding: Binding<String> {
        Binding(
            get: { model.trendSettings.agent.profile },
            set: { model.trendSettings.agent.profile = $0 }
        )
    }

    private var trendAgentTimeoutBinding: Binding<String> {
        Binding(
            get: {
                String(Int(model.trendSettings.agent.timeoutSeconds.rounded()))
            },
            set: { rawValue in
                if let timeout = Double(rawValue), timeout > 0 {
                    model.trendSettings.agent.timeoutSeconds = timeout
                }
            }
        )
    }

    private var trendAgentTemplateBinding: Binding<String> {
        Binding(
            get: { model.trendSettings.agent.customCommandTemplate },
            set: { model.trendSettings.agent.customCommandTemplate = $0 }
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
