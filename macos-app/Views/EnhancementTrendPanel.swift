import SwiftUI

// MARK: - Workbench Segments

extension EnhancementCenterView {
    // ① 分析配置：状态条、操作栏、模型配置、进度日志、错误
    var configSegment: some View {
        SectionCard(title: "分析与配置", subtitle: configSegmentSubtitle, icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                trendStatusStrip
                trendActionBar
                trendConfigurationPanel
                trendProgressLogView

                if !model.lastTrendError.isEmpty {
                    trendEmptyState("最近错误", detail: model.lastTrendError)
                }
            }
        }
    }

    // ② 趋势报告：组合头 + 周期/板块/重点标的/行动候选/证据/边界（AI观察移至独立分段）
    var reportSegment: some View {
        SectionCard(title: "趋势报告", subtitle: trendPanelSubtitle, icon: "sparkles") {
            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                if let report = model.trendReport {
                    trendReportView(report)
                } else if model.trendSettings.provider.isConfigured {
                    trendEmptyState("等待生成", detail: "趋势分析会结合本地持仓、平台动态和模型可用的外部信号，输出条件式判断和反证条件。")
                } else {
                    trendEmptyState("未配置模型", detail: "在「分析配置」填写模型地址、模型名称和 API Key 后即可生成。")
                }

                if !model.lastTrendError.isEmpty {
                    trendEmptyState("最近错误", detail: model.lastTrendError)
                }
            }
        }
    }

    // ③ AI 操作观察：基于趋势分析衍生的交易信号
    var signalsSegment: some View {
        SectionCard(title: "AI 操作观察", subtitle: model.tradeSignalSummary.headline, icon: "bell.badge") {
            tradeSignalDetailList(model.tradeSignalSummary)
        }
    }

    private var configSegmentSubtitle: String {
        if model.trendSettings.provider.isConfigured {
            return "已配置 · \(model.trendSettings.provider.model)"
        }
        return "填写模型地址、模型名称和 API Key"
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
        trendReportBalancedLayout(report)
    }

    private func trendReportBalancedLayout(_ report: TrendAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            trendPortfolioHeader(report)
            trendReportSectionGrid(report)
        }
    }

    private func trendReportSectionGrid(_ report: TrendAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceL) {
            marketSection(report)
            actionSection(report)
            verificationSection(report)
        }
    }

    private var trendReportWideColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 340), spacing: AppPalette.spaceM, alignment: .top)]
    }

    // MARK: - Report Sections

    // ① 市场视图：周期判断 + 板块
    private func marketSection(_ report: TrendAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            trendReportSectionTitle("市场视图", icon: "chart.line.uptrend.xyaxis")
            trendHorizonGrid(report.horizons)
            trendSectorGrid(report.sectors)
        }
    }

    // ② 操作建议：重点标的 + 行动候选
    private func actionSection(_ report: TrendAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            trendReportSectionTitle("操作建议", icon: "checklist")
            trendAssetList(report.keyAssets)
            trendActionList(report.actions)
        }
    }

    // ③ 核验：证据来源 + 边界与提示
    private func verificationSection(_ report: TrendAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            trendReportSectionTitle("核验", icon: "shield.checkered")
            trendEvidenceList(report.evidence)
            trendWarnings(report)
        }
    }

    private func trendReportSectionTitle(_ title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
            }
            Rectangle()
                .fill(AppPalette.hairline.opacity(AppPalette.borderSubtle))
                .frame(height: 1)
        }
        .padding(.top, 2)
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

            HStack(spacing: AppPalette.spaceS) {
                trendMetaTag("数据时点", report.dataAsOf, tint: AppPalette.info)
                trendMetaTag("外部信号", report.externalSignalStatus.displayText, tint: report.externalSignalStatus.tint)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.hairline.opacity(0.38), lineWidth: 1)
        )
    }

    private func trendMetaTag(_ title: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
        }
        .lineLimit(1)
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
            ForEach(horizons, id: \.horizon) { horizon in
                trendHorizonCard(horizon)
            }
        }
    }

    private func trendHorizonCard(_ horizon: TrendHorizonView) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                trendDirectionDot(horizon.direction)
                Text(horizon.horizon.displayText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                Spacer(minLength: 4)
                trendDirectionBadge(horizon.direction)
            }
            trendConfidenceBar(horizon.confidence)
            Text(horizon.rationale)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !horizon.counterSignals.isEmpty {
                trendCounterSignalsRow(horizon.counterSignals)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .interactiveSurface(
            tint: horizon.direction.tint,
            fill: AppPalette.cardStrong,
            hoverFill: AppPalette.cardHover,
            strokeOpacity: 0.18,
            activeStrokeOpacity: 0.40,
            lift: 0.8
        )
    }

    private func trendSectorGrid(_ sectors: [TrendSectorView]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
            ForEach(sectors) { sector in
                trendSectorCard(sector)
            }
        }
    }

    private func trendSectorCard(_ sector: TrendSectorView) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                trendDirectionDot(sector.direction)
                Text(sector.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(sector.exposureText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.info)
                    .lineLimit(1)
            }
            HStack(spacing: AppPalette.spaceS) {
                trendDirectionBadge(sector.direction)
                trendConfidencePill(sector.confidence)
            }
            Text(sector.rationale)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            if !sector.counterSignals.isEmpty {
                trendCounterSignalsRow(sector.counterSignals)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .interactiveSurface(
            tint: sector.direction.tint,
            fill: AppPalette.cardStrong,
            hoverFill: AppPalette.cardHover,
            strokeOpacity: 0.18,
            activeStrokeOpacity: 0.40,
            lift: 0.8
        )
    }

    // MARK: - Report helpers

    private func trendDirectionDot(_ direction: TrendDirection) -> some View {
        Circle()
            .fill(direction.tint)
            .frame(width: 7, height: 7)
    }

    private func trendDirectionBadge(_ direction: TrendDirection) -> some View {
        Text(direction.displayText)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(direction.tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(direction.tint.opacity(AppPalette.accentFill), in: Capsule())
            .overlay(Capsule().stroke(direction.tint.opacity(AppPalette.accentBorder), lineWidth: 1))
    }

    private func trendConfidencePill(_ confidence: TrendConfidence) -> some View {
        HStack(spacing: 3) {
            Text("置信")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            Text(confidence.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppPalette.info)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(AppPalette.info.opacity(AppPalette.accentSubtle), in: Capsule())
    }

    private func trendCounterSignalsRow(_ signals: [String]) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(AppPalette.warning)
                .padding(.top, 1)
            Text("反证：\(signals.prefix(2).joined(separator: "；"))")
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func trendAssetList(_ assets: [TrendAssetView]) -> some View {
        if assets.isEmpty {
            trendEmptyState("暂无重点标的", detail: "模型没有给出需要单独关注的基金或股票。")
        } else {
            VStack(spacing: AppPalette.spaceS) {
                ForEach(assets.prefix(8)) { asset in
                    trendAssetCard(asset)
                }
            }
        }
    }

    private func trendAssetCard(_ asset: TrendAssetView) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(asset.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                if let code = asset.code, !code.isEmpty {
                    Text(code)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer(minLength: 4)
                Text(asset.sector)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.info)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppPalette.info.opacity(AppPalette.accentSubtle), in: Capsule())
            }
            Text(asset.impactText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(asset.rationale)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            if !asset.counterSignals.isEmpty {
                trendCounterSignalsRow(asset.counterSignals)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .interactiveSurface(
            tint: AppPalette.info,
            fill: AppPalette.cardStrong,
            hoverFill: AppPalette.cardHover,
            strokeOpacity: 0.18,
            activeStrokeOpacity: 0.40,
            lift: 0.8
        )
    }

    @ViewBuilder
    private func trendActionList(_ actions: [TrendActionCandidate]) -> some View {
        if actions.isEmpty {
            trendEmptyState("暂无行动候选", detail: "当前报告没有建议新增观察、调仓复核或计划调整动作。")
        } else {
            VStack(spacing: AppPalette.spaceS) {
                ForEach(actions.prefix(8)) { action in
                    trendActionCard(action)
                }
            }
        }
    }

    private func trendActionCard(_ action: TrendActionCandidate) -> some View {
        let tint = trendActionTint(action.kind)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(action.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(action.kind.displayText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(AppPalette.accentFill), in: Capsule())
                    .overlay(Capsule().stroke(tint.opacity(AppPalette.accentBorder), lineWidth: 1))
            }

            if let target = action.targetName?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty {
                Text("标的：\(target)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }

            Text(action.detail)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppPalette.spaceS) {
                trendConfidencePill(action.confidence)
                Spacer(minLength: 0)
            }

            trendConditionRow(title: "触发", values: action.triggerConditions)
            trendConditionRow(title: "反证", values: action.invalidatingConditions)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .interactiveSurface(
            tint: trendActionTint(action.kind),
            fill: AppPalette.cardStrong,
            hoverFill: AppPalette.cardHover,
            strokeOpacity: 0.18,
            activeStrokeOpacity: 0.40,
            lift: 0.8
        )
    }

    private func trendActionTint(_ kind: TrendActionKind) -> Color {
        switch kind {
        case .watch, .waitForConfirmation:
            return AppPalette.info
        case .observeInBatches, .rebalanceReview:
            return AppPalette.brand
        case .pausePlan, .considerReduce:
            return AppPalette.warning
        case .considerIncrease:
            return AppPalette.positive
        }
    }

    @ViewBuilder
    private func tradeSignalDetailList(_ summary: TradeSignalSummary) -> some View {
        if summary.items.isEmpty {
            trendEmptyState("暂无观察", detail: summary.headline)
        } else {
            VStack(spacing: AppPalette.spaceM) {
                ForEach(summary.items.prefix(8)) { item in
                    tradeSignalDetailRow(item)
                }
            }
        }
    }

    private func tradeSignalDetailRow(_ item: TradeSignalItem) -> some View {
        let tint = trendSignalTint(for: item)
        return HStack(alignment: .top, spacing: 0) {
            // 左侧状态色条
            RoundedRectangle(cornerRadius: AppPalette.selectionRailWidth / 2)
                .fill(AppPalette.accentGlow(tint))
                .frame(width: AppPalette.selectionRailWidth)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: AppPalette.spaceM - 2) {
                // 头部：图标盒 + 资产名/副标题 + 状态徽章
                HStack(alignment: .top, spacing: AppPalette.spaceS) {
                    Image(systemName: tradeSignalActionIcon(item.action))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .accentIconStyle(tint: tint, size: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.assetName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                            .lineLimit(1)
                        tradeSignalAssetSubtitle(item)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    tradeSignalStatusBadge(item)
                }

                // 操作区：操作胶囊 + 旧分析标记
                HStack(spacing: AppPalette.spaceS) {
                    Text(item.action.displayText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(tint.opacity(AppPalette.accentFill), in: Capsule())
                        .overlay(Capsule().stroke(tint.opacity(AppPalette.accentBorder), lineWidth: 1))

                    if item.isBasedOnStaleAnalysis {
                        Text("基于上次分析")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppPalette.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppPalette.muted.opacity(AppPalette.accentSubtle), in: Capsule())
                    }

                    Spacer(minLength: AppPalette.spaceS)
                    Text("置信度")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                    Text("\(item.confidence.normalizedScore)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.info)
                }

                // 置信度进度条
                trendConfidenceBar(item.confidence)

                // 原因说明
                Text(item.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                // 触发 / 反证条件
                VStack(alignment: .leading, spacing: 5) {
                    tradeSignalConditionLine(title: "触发", text: item.triggerSummary, tint: AppPalette.info, glyph: .filled)
                    tradeSignalConditionLine(title: "反证", text: item.invalidatingSummary, tint: AppPalette.warning, glyph: .half)
                }
            }
            .padding(.leading, AppPalette.spaceS)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .interactiveSurface(
                tint: tint,
                fill: AppPalette.cardStrong,
                hoverFill: AppPalette.cardHover,
                strokeOpacity: 0.26,
                activeStrokeOpacity: 0.40,
                lift: 0.6
            )
        }
    }

    private func tradeSignalAssetSubtitle(_ item: TradeSignalItem) -> some View {
        let parts: [String] = [item.assetCode, item.title].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty == false) ? trimmed : nil
        }
        if parts.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            Text(parts.joined(separator: " · "))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        )
    }

    private func tradeSignalStatusBadge(_ item: TradeSignalItem) -> some View {
        let tint = trendSignalTint(for: item)
        return Text(item.status.displayText)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(AppPalette.accentFill), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(AppPalette.accentBorder), lineWidth: 1))
    }

    private func tradeSignalActionIcon(_ action: TradeSignalAction) -> String {
        switch action {
        case .watchBuy:
            return "arrow.up.circle"
        case .watchSell:
            return "arrow.down.circle"
        case .holdObserve:
            return "eye"
        case .waitForConfirmation:
            return "clock"
        case .rebalanceReview:
            return "arrow.2.squarepath"
        }
    }

    private func tradeSignalConditionLine(title: String, text: String, tint: Color, glyph: TradeSignalConditionGlyph) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Group {
                switch glyph {
                case .filled:
                    Circle().fill(tint)
                case .half:
                    Circle().fill(tint.opacity(0.5))
                        .overlay(Circle().stroke(tint, lineWidth: 1))
                }
            }
            .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private enum TradeSignalConditionGlyph { case filled, half }

    @ViewBuilder
    private func trendEvidenceList(_ evidence: [TrendEvidence]) -> some View {
        if evidence.isEmpty {
            trendEmptyState("暂无外部证据", detail: "模型没有返回可核验来源，按本地上下文结果理解。")
        } else {
            VStack(spacing: AppPalette.spaceS) {
                ForEach(evidence.prefix(6)) { item in
                    trendEvidenceCard(item)
                }
            }
        }
    }

    private func trendEvidenceCard(_ item: TrendEvidence) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "link")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppPalette.info)
                Text(item.sourceName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.info)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(item.publishedAt ?? item.retrievedAt)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
            if let urlText = item.url, let url = URL(string: urlText) {
                Link(item.title, destination: url)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(item.summary)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .interactiveSurface(
            tint: AppPalette.info,
            fill: AppPalette.cardStrong,
            hoverFill: AppPalette.cardHover,
            strokeOpacity: 0.18,
            activeStrokeOpacity: 0.38,
            lift: 0.8
        )
    }

    private func trendWarnings(_ report: TrendAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceS) {
            VStack(alignment: .leading, spacing: AppPalette.spaceS) {
                ForEach(report.warnings) { warning in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(AppPalette.warning)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(warning.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppPalette.ink)
                            Text(warning.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(AppPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Text(report.disclaimer)
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
