import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EnhancementCenterView: View {
    @EnvironmentObject var model: AppModel
    @State private var didCopyReport = false
    @State private var isMonthlyReportPreviewExpanded = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppPalette.spaceL) {
                let summary = dashboardSummary
                dashboardHeader(summary)
                statusCardGrid(summary)
                workbenchContent(summary)
            }
            .padding(18)
        }
        .alert("覆盖已有月报？", isPresented: overwriteReportBinding) {
            Button("覆盖", role: .destructive) {
                model.archiveMonthlyReport(overwriteConfirmed: true)
            }
            Button("取消", role: .cancel) {
                model.pendingOverwriteReportURL = nil
            }
        } message: {
            Text(model.pendingOverwriteReportURL?.lastPathComponent ?? "同月月报已存在。")
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
            reminders: model.portfolioReminderSummary,
            planSimulation: model.planSimulationSummary
        )
    }

    private func dashboardHeader(_ summary: EnhancementDashboardSummary) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: AppPalette.spaceL) {
                headerTitleBlock(summary)
                Spacer(minLength: AppPalette.spaceL)
                primaryActionButton(summary.primaryAction)
            }

            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                headerTitleBlock(summary)
                primaryActionButton(summary.primaryAction)
            }
        }
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
                Text(summary.stateText)
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

    private func statusCardGrid(_ summary: EnhancementDashboardSummary) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: AppPalette.spaceM)], spacing: AppPalette.spaceM) {
            ForEach(summary.statusCards) { card in
                Button {
                    model.selectedEnhancementTab = card.tab
                } label: {
                    enhancementStatusCard(card)
                }
                .buttonStyle(PressResponsiveButtonStyle())
            }
        }
    }

    private func enhancementStatusCard(_ card: EnhancementStatusCard) -> some View {
        let tint = tint(for: card.severity)
        let isSelected = model.selectedEnhancementTab == card.tab
        return VStack(alignment: .leading, spacing: AppPalette.spaceS) {
            HStack(alignment: .center, spacing: AppPalette.spaceS) {
                Image(systemName: card.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .accentIconStyle(tint: tint, size: 28)

                Text(card.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(card.nextAction)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text(card.value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(card.detail)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(AppPalette.spaceM)
        .interactiveSurface(
            isSelected: isSelected,
            tint: tint,
            radius: AppPalette.panelRadius,
            fill: AppPalette.card,
            selectedFill: tint.opacity(0.14),
            activeStrokeOpacity: 0.62
        )
    }

    private func workbenchContent(_ summary: EnhancementDashboardSummary) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppPalette.spaceM) {
                VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                    tabPicker
                    selectedWorkflowPanel
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                actionQueueRail(summary)
                    .frame(width: 286)
            }

            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                tabPicker
                selectedWorkflowPanel
                actionQueueRail(summary)
            }
        }
    }

    private var tabPicker: some View {
        Picker("工作台", selection: $model.selectedEnhancementTab) {
            ForEach(EnhancementCenterTab.workbenchTabs) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(3)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                .stroke(AppPalette.line.opacity(0.32), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var selectedWorkflowPanel: some View {
        switch model.selectedEnhancementTab {
        case .review:
            reviewPanel
        case .trend:
            trendPanel
        case .importPreview, .watch, .insight:
            reviewPanel
        }
    }

    private func actionQueueRail(_ summary: EnhancementDashboardSummary) -> some View {
        SectionCard(title: "下一步", subtitle: "\(summary.actionQueue.count) 项待办", icon: "list.bullet.rectangle.portrait") {
            if summary.actionQueue.isEmpty {
                emptyState("暂无待办", detail: "本月复盘和趋势分析都处于稳定状态。")
            } else {
                LazyVStack(alignment: .leading, spacing: AppPalette.spaceS) {
                    ForEach(summary.actionQueue) { item in
                        actionQueueRow(item)
                    }
                }
            }
        }
    }

    private func actionQueueRow(_ item: EnhancementActionItem) -> some View {
        let tint = tint(for: item.severity)
        return Button {
            perform(item)
        } label: {
            HStack(alignment: .top, spacing: AppPalette.spaceS) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 3, height: 34)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                    Text(item.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.metric)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(AppPalette.spaceS)
            .interactiveSurface(tint: tint, radius: AppPalette.controlRadius, fill: AppPalette.cardStrong, lift: 0.5)
        }
        .buttonStyle(PressResponsiveButtonStyle())
    }

    private func primaryActionButton(_ action: EnhancementPrimaryAction) -> some View {
        Button {
            perform(action)
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint(for: action.severity))
    }

    private func perform(_ action: EnhancementPrimaryAction) {
        perform(kind: action.kind, targetTab: action.targetTab)
    }

    private func perform(_ item: EnhancementActionItem) {
        perform(kind: item.kind, targetTab: item.targetTab)
    }

    private func perform(kind: EnhancementActionKind, targetTab: EnhancementCenterTab) {
        model.selectedEnhancementTab = targetTab.isVisibleInWorkbench ? targetTab : .review
        switch kind {
        case .selectTab:
            break
        case .runTrendAnalysis:
            Task {
                await model.generateTrendAnalysis(userInitiated: true)
            }
        case .archiveReport:
            model.archiveMonthlyReport()
        case .confirmImport:
            model.confirmActiveImportPreview()
        case .undoImport:
            model.undoLatestImport()
        }
    }

    private func normalizeSelectedTab() {
        if !model.selectedEnhancementTab.isVisibleInWorkbench {
            model.selectedEnhancementTab = .review
        }
    }

    private var reviewPanel: some View {
        SectionCard(title: "复盘", subtitle: model.monthlyReportSummary.title, icon: "doc.text") {
            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                reportStatusStrip
                reportSummaryGrid
                reportActionRow
                monthlyReportPreview
            }
        }
    }

    private var reportStatusStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
            compactFact("报告月份", dashboardSummary.reportMetadata.monthText, tint: AppPalette.brand)
            compactFact("生成时间", dashboardSummary.reportMetadata.generatedAt, tint: AppPalette.info)
            compactFact("Markdown", dashboardSummary.reportMetadata.lineCountText, tint: AppPalette.positive)
            compactFact(
                "归档",
                dashboardSummary.reportMetadata.archiveText,
                tint: dashboardSummary.reportMetadata.isArchivedForCurrentMonth ? AppPalette.positive : AppPalette.warning
            )
        }
    }

    private var reportSummaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
            compactFact("组合诊断", model.portfolioDiagnosticsSummary.headline, tint: AppPalette.info)
            compactFact(
                "提醒通知",
                model.portfolioReminderSummary.headline,
                tint: model.portfolioReminderSummary.actionCount > 0 ? AppPalette.warning : AppPalette.positive
            )
            compactFact(
                "收益归因",
                model.profitAttributionSummary.headline,
                tint: AppPalette.marketTint(for: model.profitAttributionSummary.totalProfitValue)
            )
            compactFact(
                "计划模拟",
                model.planSimulationSummary.headline,
                tint: model.planSimulationSummary.activePlanCount > 0 ? AppPalette.info : AppPalette.muted
            )
        }
    }

    private var reportActionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppPalette.spaceS) {
                reportActions
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: AppPalette.spaceS) {
                reportActions
            }
        }
    }

    private var monthlyReportPreview: some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceS) {
            HStack {
                Text("Markdown 预览")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isMonthlyReportPreviewExpanded.toggle()
                    }
                } label: {
                    Label(
                        isMonthlyReportPreviewExpanded ? "收起" : "展开全文",
                        systemImage: isMonthlyReportPreviewExpanded ? "chevron.up" : "chevron.down"
                    )
                }
                .buttonStyle(.bordered)
            }

            Text(model.monthlyReportSummary.markdown)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppPalette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: isMonthlyReportPreviewExpanded ? .infinity : 260, alignment: .top)
                .clipped()
                .padding(AppPalette.spaceM)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                        .stroke(AppPalette.line.opacity(AppPalette.borderFaint), lineWidth: 1)
                )
        }
    }

    private func compactFact(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppPalette.spaceS)
        .background(tint.opacity(AppPalette.accentFill), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                .stroke(tint.opacity(AppPalette.accentBorder), lineWidth: 1)
        )
    }

    private var reportActions: some View {
        Group {
            Button {
                model.copyMonthlyReportToPasteboard(model.monthlyReportSummary)
                didCopyReport = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopyReport = false }
            } label: {
                Label(didCopyReport ? "已复制" : "复制 Markdown", systemImage: didCopyReport ? "checkmark.circle" : "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button {
                model.archiveMonthlyReport()
            } label: {
                Label("保存到归档", systemImage: "archivebox")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.brand)

            Button {
                presentSavePanel()
            } label: {
                Label("另存为", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
        }
    }

    private var overwriteReportBinding: Binding<Bool> {
        Binding(
            get: { model.pendingOverwriteReportURL != nil },
            set: { if !$0 { model.pendingOverwriteReportURL = nil } }
        )
    }

    private func presentSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.nameFieldStringValue = "\(model.monthlyReportSummary.monthText)-portfolio-report.md"
        if panel.runModal() == .OK, let url = panel.url {
            model.saveMonthlyReportAs(to: url)
        }
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
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
