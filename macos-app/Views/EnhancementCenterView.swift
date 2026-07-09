import SwiftUI

struct EnhancementCenterView: View {
    @EnvironmentObject var model: AppModel
    @State var trendAutoAnalysisTimesDraft = ""
    @State var isTrendConfigurationExpanded = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppPalette.spaceL) {
                let summary = dashboardSummary
                dashboardHeader(summary)
                trendPanel
            }
            .padding(18)
        }
        .onAppear(perform: normalizeSelectedTab)
    }

    private var dashboardSummary: EnhancementDashboardSummary {
        EnhancementDashboardSummary.make(
            report: model.monthlyReportSummary,
            lastMonthlyReportExport: model.lastMonthlyReportExport,
            cookieAvailable: model.cookieAvailable,
            nativeConnectionAvailable: true,
            watchSummary: model.managerWatchTimelineSummary,
            importSession: model.activeImportPreviewSession,
            canUndoLatestImport: model.canUndoLatestImport,
            insightSummary: model.portfolioSnapshotInsightSummary,
            snapshotCount: model.portfolioInsightSnapshots.count,
            trendStatus: model.enhancementTrendStatus,
            tradeSignals: model.tradeSignalSummary,
            reminders: model.portfolioReminderSummary,
            planSimulation: model.planSimulationSummary
        )
    }

    private func dashboardHeader(_ summary: EnhancementDashboardSummary) -> some View {
        headerTitleBlock(summary)
        .padding(AppPalette.spaceXL)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .panelStroke()
        .sectionShadow()
    }

    private func headerTitleBlock(_ summary: EnhancementDashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            VStack(alignment: .leading, spacing: 4) {
                Text("理财工作台")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.ink)
                Text("趋势分析、模型配置与 AI 操作观察")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
            }

            FlowLayout(spacing: AppPalette.spaceS) {
                ForEach(summary.runtimeChips) { chip in
                    runtimeChip(chip)
                }
            }
        }
    }

    private func runtimeChip(_ chip: EnhancementRuntimeChip) -> some View {
        let tint = tint(for: chip.severity)
        return HStack(spacing: 5) {
            Text(chip.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
            Text(chip.value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .lineLimit(1)
        .padding(.horizontal, AppPalette.spaceS)
        .padding(.vertical, AppPalette.spaceXS + 1)
        .background(tint.opacity(AppPalette.accentFill), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(AppPalette.accentBorder), lineWidth: 1))
    }

    private func normalizeSelectedTab() {
        if !model.selectedEnhancementTab.isVisibleInWorkbench {
            model.selectedEnhancementTab = .trend
        }
    }

    private func tint(for severity: EnhancementPresentationSeverity) -> Color {
        switch severity {
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
