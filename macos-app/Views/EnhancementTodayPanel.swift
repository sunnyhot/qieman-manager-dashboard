import SwiftUI

extension EnhancementCenterView {
    /// 今日研判：组合结论 + 数据时间 + 周期/市场/板块/重点标的 + 行动候选(可加入跟踪) + 全部持仓研判 + 折叠证据边界
    var todayContent: some View {
        Group {
            if let report = model.trendReport {
                todayReportView(report)
            } else if model.trendSettings.provider.isConfigured {
                trendEmptyState("等待生成", detail: "趋势分析会结合本地持仓、平台动态和模型可用的外部信号，输出条件式判断和反证条件。")
            } else {
                trendEmptyState("未配置模型", detail: "点右上角「设置」填写模型地址、模型名称和 API Key 后即可生成。")
            }
        }
    }

    private func todayReportView(_ report: TrendAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceL) {
            trendPortfolioHeader(report)
            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                trendReportSectionTitle("组合方向", icon: "clock")
                trendHorizonGrid(report.horizons)
            }
            marketSection(report)
            actionSection(report)
            todayActionCandidates(report)
            todayVerificationSection(report)
        }
    }

    // 行动候选（最多 3 条）：原因/触发/失效/置信度 + 加入跟踪
    private func todayActionCandidates(_ report: TrendAnalysisReport) -> some View {
        let actions = Array(report.actions.prefix(3))
        return VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            trendReportSectionTitle("行动候选", icon: "checklist")
            if actions.isEmpty {
                trendEmptyState("暂无行动候选", detail: "当前报告没有建议新增观察、调仓复核或计划调整动作。")
            } else {
                VStack(spacing: AppPalette.spaceS) {
                    ForEach(actions) { action in
                        todayActionCard(action, report: report)
                    }
                }
            }
        }
    }

    private func todayActionCard(_ action: TrendActionCandidate, report: TrendAnalysisReport) -> some View {
        let tracked = model.hasActiveTrackingItem(for: action)
        let tint = todayActionTint(action.kind)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(action.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(action.kind.displayText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(AppPalette.accentFill), in: Capsule())
                    .overlay(Capsule().stroke(tint.opacity(AppPalette.accentBorder), lineWidth: 1))
                trendConfidenceMeter(action.confidence)
                Spacer(minLength: 6)
                Button {
                    model.addTrackingItem(from: action, report: report)
                } label: {
                    Label(tracked ? "已跟踪" : "加入跟踪", systemImage: tracked ? "checkmark.circle.fill" : "bell.badge")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.appSecondary)
                .tint(tint)
                .disabled(tracked)
            }

            Text(action.detail)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AppPalette.spaceS) {
                    todayConditionLine("触发", action.triggerConditions, tint: AppPalette.info)
                    todayConditionLine("失效", action.invalidatingConditions, tint: AppPalette.warning)
                }
                VStack(alignment: .leading, spacing: 4) {
                    todayConditionLine("触发", action.triggerConditions, tint: AppPalette.info)
                    todayConditionLine("失效", action.invalidatingConditions, tint: AppPalette.warning)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticSurface(
            tint: tint,
            fill: AppPalette.cardStrong,
            strokeOpacity: 0.18,
            activeStrokeOpacity: 0.40
        )
    }

    @ViewBuilder
    private func todayConditionLine(_ title: String, _ items: [String], tint: Color) -> some View {
        let trimmed = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                Text(trimmed.joined(separator: "；"))
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tint.opacity(0.35), lineWidth: 1))
        }
    }

    @ViewBuilder
    private func todayVerificationSection(_ report: TrendAnalysisReport) -> some View {
        if !report.evidence.isEmpty || !report.warnings.isEmpty {
            DisclosureGroup("证据与风险边界") {
                VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                    trendEvidenceList(report.evidence)
                    trendWarnings(report)
                }
                .padding(.top, 6)
            }
            .font(.system(size: 12, weight: .semibold))
            .tint(AppPalette.info)
        }
    }

    private func todayActionTint(_ kind: TrendActionKind) -> Color {
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
}
