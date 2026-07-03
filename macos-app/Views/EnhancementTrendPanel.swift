import SwiftUI

// MARK: - Trend Panel

extension EnhancementCenterView {
    var trendPanel: some View {
        SectionCard(title: "趋势", subtitle: trendPanelSubtitle, icon: "sparkles") {
            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                trendStatusStrip
                trendActionBar
                trendProgressLogView

                if let report = model.trendReport {
                    trendReportView(report)
                } else if model.trendSettings.provider.isConfigured {
                    trendEmptyState("等待生成", detail: "趋势分析会结合本地持仓、平台动态和模型可用的外部信号，输出条件式判断和反证条件。")
                } else {
                    trendEmptyState("未配置模型", detail: "先在设置中填写模型地址、模型名称和 API Key。")
                }

                if !model.lastTrendError.isEmpty {
                    trendEmptyState("最近错误", detail: model.lastTrendError)
                }
            }
        }
    }

    @ViewBuilder
    private var trendProgressLogView: some View {
        if !model.trendProgressLogs.isEmpty {
            trendBlock("分析过程", icon: "list.bullet.rectangle") {
                trendProgressSummaryCard
            }
        }
    }

    private var trendProgressSummaryCard: some View {
        let latest = model.trendProgressLogs.last
        return DisclosureGroup {
            VStack(spacing: AppPalette.spaceS) {
                ForEach(model.trendProgressLogs.suffix(6)) { item in
                    trendProgressRow(item)
                }
            }
            .padding(.top, AppPalette.spaceS)
        } label: {
            HStack(alignment: .center, spacing: AppPalette.spaceS) {
                Image(systemName: model.trendGenerationState == .generating ? "clock.arrow.circlepath" : "checkmark.seal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(trendStateTint)
                    .frame(width: 26, height: 26)
                    .background(trendStateTint.opacity(AppPalette.accentFill), in: RoundedRectangle(cornerRadius: AppPalette.iconBoxRadius))

                VStack(alignment: .leading, spacing: 3) {
                    Text(latest?.message ?? "暂无过程")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                    Text("\(model.trendProgressLogs.count) 条记录 · 最近 \(latest.map { trendLogTime($0.timestamp) } ?? "--")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                }

                Spacer(minLength: AppPalette.spaceS)

                Text("最近 6 条")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.info)
                    .padding(.horizontal, AppPalette.spaceS)
                    .padding(.vertical, AppPalette.spaceXS)
                    .background(AppPalette.info.opacity(AppPalette.accentFill), in: Capsule())
            }
        }
        .font(.system(size: 11))
        .tint(AppPalette.info)
        .padding(AppPalette.spaceS)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.hairline.opacity(AppPalette.borderFaint), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func trendProgressRow(_ item: TrendProgressLog) -> some View {
        let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            DisclosureGroup {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 7)
            } label: {
                trendProgressRowHeader(item)
            }
            .font(.system(size: 11))
            .tint(AppPalette.info)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppPalette.paper.opacity(0.68), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        } else {
            trendProgressRowHeader(item)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppPalette.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        }
    }

    private func trendProgressRowHeader(_ item: TrendProgressLog) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(trendLogTime(item.timestamp))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.info)
                .frame(width: 56, alignment: .leading)
            Text(item.message)
                .font(.system(size: 11, weight: item.detail == nil ? .regular : .semibold))
                .foregroundStyle(item.detail == nil ? AppPalette.muted : AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var trendStatusStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
            trendFact(
                "模型",
                value: model.trendSettings.provider.isConfigured ? model.trendSettings.provider.model : "未配置",
                tint: model.trendSettings.provider.isConfigured ? AppPalette.positive : AppPalette.warning
            )
            trendFact("隐私模式", value: model.trendPrivacyMode.rawValue, tint: AppPalette.info)
            trendFact("最近生成", value: model.lastTrendGeneratedAt ?? "暂无", tint: model.trendReport == nil ? AppPalette.muted : AppPalette.brand)
            trendFact("状态", value: trendStateText, tint: trendStateTint)
        }
    }

    private var trendActionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppPalette.spaceS) {
                trendActionButtons
            }

            VStack(alignment: .leading, spacing: AppPalette.spaceS) {
                trendActionButtons
            }
        }
    }

    private var trendActionButtons: some View {
        Group {
            Picker("隐私模式", selection: trendPrivacyModeBinding) {
                ForEach(TrendPrivacyMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Button {
                Task {
                    await model.generateTrendAnalysis(userInitiated: true)
                }
            } label: {
                Label(model.trendGenerationState == .generating ? "生成中…" : "立即分析", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.brand)
            .disabled(!model.trendSettings.provider.isConfigured || model.trendGenerationState == .generating)

            Button {
                Task {
                    await model.checkTrendAIConnection()
                }
            } label: {
                Label("检测模型", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.bordered)
            .disabled(!model.trendSettings.provider.isConfigured || model.trendConnectionState == .checking)
        }
    }

    private func trendReportView(_ report: TrendAnalysisReport) -> some View {
        trendReportResponsiveLayout(report)
    }

    private func trendReportResponsiveLayout(_ report: TrendAnalysisReport) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppPalette.spaceL) {
                trendReportPrimaryColumn(report)
                    .frame(minWidth: 520, maxWidth: .infinity, alignment: .topLeading)
                    .layoutPriority(1)

                trendReportSidebarColumn(report)
                    .frame(width: 360, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                trendReportPrimaryColumn(report)
                trendReportSidebarColumn(report)
            }
        }
    }

    private func trendReportPrimaryColumn(_ report: TrendAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            trendPortfolioHeader(report)
            trendHorizonGrid(report.horizons)
            trendAssetList(report.keyAssets)
        }
    }

    private func trendReportSidebarColumn(_ report: TrendAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            trendSectorGrid(report.sectors)
            trendActionList(report.actions)
            tradeSignalDetailList(model.tradeSignalSummary)
            trendEvidenceList(report.evidence)
            trendWarnings(report)
        }
    }

    private func trendPortfolioHeader(_ report: TrendAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceS) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: AppPalette.spaceS) {
                    trendPortfolioHeadline(report)
                    Spacer(minLength: AppPalette.spaceS)
                    trendRiskBadge(report.portfolio.riskLevel)
                }

                VStack(alignment: .leading, spacing: AppPalette.spaceS) {
                    trendPortfolioHeadline(report)
                    trendRiskBadge(report.portfolio.riskLevel)
                }
            }

            Text(report.portfolio.summary)
                .font(.system(size: 12))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: AppPalette.spaceS) {
                trendMiniPill("数据时点", report.dataAsOf, tint: AppPalette.info)
                trendMiniPill("外部信号", report.externalSignalStatus.displayText, tint: report.externalSignalStatus.tint)
                trendMiniPill("声明", report.disclaimer, tint: AppPalette.muted)
            }
        }
        .padding(14)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.hairline.opacity(0.38), lineWidth: 1)
        )
    }

    private func trendPortfolioHeadline(_ report: TrendAnalysisReport) -> some View {
        Text(report.portfolio.headline)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(AppPalette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func trendRiskBadge(_ riskLevel: TrendRiskLevel) -> some View {
        Text(riskLevel.displayText)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(riskLevel.tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(riskLevel.tint.opacity(AppPalette.accentOnFill), in: Capsule())
    }

    private func trendHorizonGrid(_ horizons: [TrendHorizonView]) -> some View {
        trendBlock("周期判断", icon: "calendar") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
                ForEach(horizons, id: \.horizon) { horizon in
                    trendHorizonCard(horizon)
                }
            }
        }
    }

    private func trendHorizonCard(_ horizon: TrendHorizonView) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(horizon.horizon.displayText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                Spacer(minLength: 4)
                Text(horizon.direction.displayText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(horizon.direction.tint)
            }
            trendConfidenceBar(horizon.confidence)
            Text(horizon.rationale)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !horizon.counterSignals.isEmpty {
                Text("反证：\(horizon.counterSignals.prefix(2).joined(separator: "；"))")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .background(AppPalette.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }

    private func trendSectorGrid(_ sectors: [TrendSectorView]) -> some View {
        trendBlock("板块", icon: "square.grid.2x2") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
                ForEach(sectors) { sector in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(sector.name)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppPalette.ink)
                            Spacer(minLength: 4)
                            Text(sector.exposureText)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(AppPalette.info)
                        }
                        Text(sector.direction.displayText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(sector.direction.tint)
                        Text(sector.rationale)
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                            .lineLimit(3)
                    }
                    .padding(11)
                    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                }
            }
        }
    }

    private func trendAssetList(_ assets: [TrendAssetView]) -> some View {
        trendBlock("重点标的", icon: "target") {
            if assets.isEmpty {
                trendEmptyState("暂无重点标的", detail: "模型没有给出需要单独关注的基金或股票。")
            } else {
                VStack(spacing: AppPalette.spaceS) {
                    ForEach(assets.prefix(8)) { asset in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(asset.name)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AppPalette.ink)
                                if let code = asset.code {
                                    Text(code)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AppPalette.muted)
                                }
                                Spacer(minLength: 4)
                                Text(asset.sector)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppPalette.info)
                            }
                            Text(asset.impactText)
                                .font(.system(size: 11))
                                .foregroundStyle(AppPalette.muted)
                            Text(asset.rationale)
                                .font(.system(size: 10))
                                .foregroundStyle(AppPalette.muted)
                                .lineLimit(2)
                        }
                        .padding(11)
                        .background(AppPalette.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                    }
                }
            }
        }
    }

    private func trendActionList(_ actions: [TrendActionCandidate]) -> some View {
        trendBlock("行动候选", icon: "checklist") {
            if actions.isEmpty {
                trendEmptyState("暂无行动候选", detail: "当前报告没有建议新增观察、调仓复核或计划调整动作。")
            } else {
                VStack(spacing: AppPalette.spaceS) {
                    ForEach(actions.prefix(8)) { action in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(action.title)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AppPalette.ink)
                                Spacer(minLength: 4)
                                Text(action.kind.displayText)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppPalette.brand)
                            }
                            Text(action.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(AppPalette.muted)
                            trendConditionRow(title: "触发", values: action.triggerConditions)
                            trendConditionRow(title: "反证", values: action.invalidatingConditions)
                        }
                        .padding(11)
                        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                    }
                }
            }
        }
    }

    private func tradeSignalDetailList(_ summary: TradeSignalSummary) -> some View {
        trendBlock("AI 操作观察", icon: "bell.badge") {
            if summary.items.isEmpty {
                trendEmptyState("暂无观察", detail: summary.headline)
            } else {
                VStack(spacing: AppPalette.spaceS) {
                    ForEach(summary.items.prefix(8)) { item in
                        tradeSignalDetailRow(item)
                    }
                }
            }
        }
    }

    private func tradeSignalDetailRow(_ item: TradeSignalItem) -> some View {
        let tint = trendSignalTint(for: item)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.assetName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(item.status.displayText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }

            HStack(spacing: AppPalette.spaceS) {
                Text(item.action.displayText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(AppPalette.accentFill), in: Capsule())
                Text("置信度 \(item.confidence.normalizedScore)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppPalette.info)
                if item.isBasedOnStaleAnalysis {
                    Text("上次分析")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                }
            }

            Text(item.reason)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            trendConditionRow(title: "触发", values: [item.triggerSummary])
            trendConditionRow(title: "反证", values: [item.invalidatingSummary])
        }
        .padding(11)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }

    private func trendEvidenceList(_ evidence: [TrendEvidence]) -> some View {
        trendBlock("证据来源", icon: "link") {
            if evidence.isEmpty {
                trendEmptyState("暂无外部证据", detail: "模型没有返回可核验来源，按本地上下文结果理解。")
            } else {
                VStack(spacing: AppPalette.spaceS) {
                    ForEach(evidence.prefix(6)) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.sourceName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppPalette.info)
                                Spacer(minLength: 4)
                                Text(item.publishedAt ?? item.retrievedAt)
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppPalette.muted)
                            }
                            if let urlText = item.url, let url = URL(string: urlText) {
                                Link(item.title, destination: url)
                                    .font(.system(size: 12, weight: .semibold))
                            } else {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppPalette.ink)
                            }
                            Text(item.summary)
                                .font(.system(size: 10))
                                .foregroundStyle(AppPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(11)
                        .background(AppPalette.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                    }
                }
            }
        }
    }

    private func trendWarnings(_ report: TrendAnalysisReport) -> some View {
        trendBlock("边界与提示", icon: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: AppPalette.spaceS) {
                ForEach(report.warnings) { warning in
                    trendEmptyState(warning.title, detail: warning.detail)
                }
                Text(report.disclaimer)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func trendBlock<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceS) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
            }
            content()
        }
    }

    private func trendFact(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(11)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }

    private func trendMiniPill(_ title: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.08), in: Capsule())
    }

    private func trendConfidenceBar(_ confidence: TrendConfidence) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(confidence.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                Spacer()
                Text("\(confidence.normalizedScore)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.info)
            }
            ProgressView(value: Double(confidence.normalizedScore), total: 100)
                .progressViewStyle(.linear)
                .tint(AppPalette.info)
        }
    }

    private func trendConditionRow(title: String, values: [String]) -> some View {
        Text("\(title)：\(values.prefix(3).joined(separator: "；"))")
            .font(.system(size: 10))
            .foregroundStyle(title == "触发" ? AppPalette.info : AppPalette.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func trendSignalTint(for item: TradeSignalItem) -> Color {
        switch item.status {
        case .triggered, .upgraded:
            return AppPalette.warning
        case .approaching, .new:
            return AppPalette.info
        case .invalidated:
            return AppPalette.danger
        case .staleAnalysis:
            return AppPalette.muted
        }
    }

    private func trendEmptyState(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }

    private var trendPanelSubtitle: String {
        if let report = model.trendReport {
            return "\(report.dataAsOf) · \(report.externalSignalStatus.displayText)"
        }
        return model.trendSettings.provider.isConfigured ? "已配置模型，等待生成" : "需要配置趋势分析模型"
    }

    private func trendLogTime(_ timestamp: String) -> String {
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16 else { return trimmed }
        return String(trimmed.dropFirst(11).prefix(5))
    }

    private var trendStateText: String {
        switch model.trendGenerationState {
        case .idle:
            return "空闲"
        case .generating:
            return "生成中"
        case .succeeded:
            return "已完成"
        case .failed:
            return "失败"
        case .rejected:
            return "已拦截"
        }
    }

    private var trendStateTint: Color {
        switch model.trendGenerationState {
        case .idle:
            return AppPalette.muted
        case .generating:
            return AppPalette.info
        case .succeeded:
            return AppPalette.positive
        case .failed:
            return AppPalette.danger
        case .rejected:
            return AppPalette.warning
        }
    }

    private var trendPrivacyModeBinding: Binding<TrendPrivacyMode> {
        Binding(
            get: { model.trendPrivacyMode },
            set: { mode in
                model.trendPrivacyMode = mode
                model.trendSettings.defaultPrivacyMode = mode
                model.saveTrendAnalysisSettings()
            }
        )
    }
}

private extension TrendRiskLevel {
    var displayText: String {
        switch self {
        case .low:
            return "低风险"
        case .medium:
            return "中风险"
        case .high:
            return "高风险"
        case .unknown:
            return "风险未知"
        }
    }

    var tint: Color {
        switch self {
        case .low:
            return AppPalette.positive
        case .medium:
            return AppPalette.warning
        case .high:
            return AppPalette.danger
        case .unknown:
            return AppPalette.muted
        }
    }
}

private extension TrendExternalSignalStatus {
    var displayText: String {
        switch self {
        case .available:
            return "可用"
        case .unavailable:
            return "不可用"
        case .partial:
            return "部分可用"
        case .stale:
            return "可能过期"
        }
    }

    var tint: Color {
        switch self {
        case .available:
            return AppPalette.positive
        case .unavailable:
            return AppPalette.warning
        case .partial:
            return AppPalette.info
        case .stale:
            return AppPalette.warning
        }
    }
}

private extension TrendHorizon {
    var displayText: String {
        switch self {
        case .short:
            return "短期"
        case .medium:
            return "中期"
        case .long:
            return "长期"
        }
    }
}

private extension TrendDirection {
    var displayText: String {
        switch self {
        case .bullish:
            return "偏强"
        case .neutralPositive:
            return "中性偏强"
        case .neutral:
            return "中性"
        case .neutralNegative:
            return "中性偏弱"
        case .bearish:
            return "偏弱"
        case .uncertain:
            return "不确定"
        }
    }

    var tint: Color {
        switch self {
        case .bullish, .neutralPositive:
            return AppPalette.positive
        case .neutral:
            return AppPalette.info
        case .neutralNegative, .bearish:
            return AppPalette.warning
        case .uncertain:
            return AppPalette.muted
        }
    }
}

private extension TrendActionKind {
    var displayText: String {
        switch self {
        case .watch:
            return "观察"
        case .waitForConfirmation:
            return "等待确认"
        case .observeInBatches:
            return "分批观察"
        case .pausePlan:
            return "暂停计划"
        case .considerIncrease:
            return "考虑增加"
        case .considerReduce:
            return "考虑降低"
        case .rebalanceReview:
            return "调仓复核"
        }
    }
}
