import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EnhancementCenterView: View {
    @EnvironmentObject var model: AppModel
    @State private var importTarget: PersonalDataImportTarget = .holdings
    @State private var importMode: PersonalDataSaveMode = .merge
    @State private var didCopyReport = false
    @State private var isImportingFile = false
    @State private var importSource: PersonalDataImportSource = .table
    @State private var selectedWatchFilter: EnhancementWatchFilter = .all
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
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: allowedImportContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await model.importExternalFile(at: url, source: importSource, target: importTarget) }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
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
                Text("增强工作台")
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
        Picker("增强中心", selection: $model.selectedEnhancementTab) {
            ForEach(EnhancementCenterTab.allCases) { tab in
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
        case .watch:
            watchPanel
        case .importPreview:
            importPanel
        case .insight:
            insightPanel
        case .trend:
            trendPanel
        }
    }

    private func actionQueueRail(_ summary: EnhancementDashboardSummary) -> some View {
        SectionCard(title: "下一步", subtitle: "\(summary.actionQueue.count) 项待办", icon: "list.bullet.rectangle.portrait") {
            if summary.actionQueue.isEmpty {
                emptyState("暂无待办", detail: "本月复盘、巡检、导入和组合洞察都处于稳定状态。")
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
        model.selectedEnhancementTab = targetTab
        switch kind {
        case .selectTab:
            break
        case .runWatch:
            model.runManagerWatchNow()
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
        case .recordSnapshot:
            model.recordPortfolioInsightSnapshotIfPossible()
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

    private var watchPanel: some View {
        SectionCard(title: "巡检", subtitle: model.managerWatchTimelineSummary.latestStatusText, icon: "bell.badge") {
            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                watchStatusStrip
                watchFilterRow
                watchTimelineList
            }
        }
    }

    private var watchStatusStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
            compactFact(
                "最新状态",
                model.managerWatchTimelineSummary.latestStatusText,
                tint: model.managerWatchTimelineSummary.failureCount > 0 ? AppPalette.warning : AppPalette.positive
            )
            compactFact(
                "失败次数",
                "\(model.managerWatchTimelineSummary.failureCount)",
                tint: model.managerWatchTimelineSummary.failureCount > 0 ? AppPalette.warning : AppPalette.positive
            )
            compactFact("时间线", "\(model.managerWatchTimelineSummary.events.count) 条", tint: AppPalette.info)
        }
    }

    private var watchFilterRow: some View {
        FlowLayout(spacing: AppPalette.spaceS) {
            ForEach(EnhancementWatchFilter.allCases) { filter in
                Button {
                    selectedWatchFilter = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, AppPalette.spaceS)
                        .padding(.vertical, AppPalette.spaceXS)
                }
                .buttonStyle(.plain)
                .background(
                    selectedWatchFilter == filter ? AppPalette.brand.opacity(0.14) : AppPalette.cardStrong,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(
                            selectedWatchFilter == filter ? AppPalette.brand.opacity(0.55) : AppPalette.line.opacity(0.28),
                            lineWidth: 1
                        )
                )
                .foregroundStyle(selectedWatchFilter == filter ? AppPalette.brand : AppPalette.muted)
            }
        }
    }

    private var filteredWatchEvents: [ManagerWatchTimelineEvent] {
        model.managerWatchTimelineSummary.events.filter { selectedWatchFilter.matches($0) }
    }

    private var watchTimelineList: some View {
        Group {
            if model.managerWatchTimelineEvents.isEmpty {
                emptyState("暂无巡检时间线", detail: "开启主理人提醒或点击立即巡检后，这里会记录命中、失败和重复通知抑制。")
            } else if filteredWatchEvents.isEmpty {
                emptyState("当前筛选无记录", detail: "切换到全部可以查看完整巡检时间线。")
            } else {
                LazyVStack(alignment: .leading, spacing: AppPalette.spaceS) {
                    ForEach(filteredWatchEvents) { event in
                        timelineRow(event)
                    }
                }
            }
        }
    }

    private var importPanel: some View {
        SectionCard(title: "导入预演", subtitle: "先预览变更，再确认写入", icon: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                importControlBar
                importDraftEditor
                importPreviewSummary
                importActionFooter
                if let session = model.activeImportPreviewSession {
                    importPreviewRows(session)
                } else {
                    emptyState("暂无导入预览", detail: "粘贴草稿或导入文件后点击生成预览。")
                }
            }
        }
    }

    private var importControlBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppPalette.spaceS) {
                importControls
                Button {
                    model.prepareImportPreview(target: importTarget, mode: importMode)
                } label: {
                    Label("生成预览", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.brand)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: AppPalette.spaceS) {
                importControls
                Button {
                    model.prepareImportPreview(target: importTarget, mode: importMode)
                } label: {
                    Label("生成预览", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.brand)
            }
        }
    }

    private var importDraftEditor: some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceS) {
            Text("源草稿")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            TextEditor(text: draftBinding)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 120)
                .padding(AppPalette.spaceS)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                        .stroke(AppPalette.line.opacity(AppPalette.borderFaint), lineWidth: 1)
                )
        }
    }

    private var importPreviewSummary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
            importCountChip("新增", dashboardSummary.importCounts.added, tint: AppPalette.positive)
            importCountChip("更新", dashboardSummary.importCounts.updated, tint: AppPalette.info)
            importCountChip("不变", dashboardSummary.importCounts.unchanged, tint: AppPalette.muted)
            importCountChip("重复", dashboardSummary.importCounts.duplicate, tint: AppPalette.warning)
            importCountChip("移除", dashboardSummary.importCounts.removed, tint: AppPalette.warning)
            importCountChip("阻塞", dashboardSummary.importCounts.blocked, tint: AppPalette.danger)
        }
    }

    private func importCountChip(_ title: String, _ count: Int, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(AppPalette.spaceS)
        .background(tint.opacity(AppPalette.accentFill), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                .stroke(tint.opacity(AppPalette.accentBorder), lineWidth: 1)
        )
    }

    private var importActionFooter: some View {
        HStack(spacing: AppPalette.spaceS) {
            Button {
                model.confirmActiveImportPreview()
            } label: {
                Label("确认写入", systemImage: "checkmark.circle")
            }
            .disabled(model.activeImportPreviewSession?.canConfirm != true)
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.brand)

            if model.activeImportPreviewSession?.canConfirm != true {
                Text(dashboardSummary.importCounts.blocked > 0 ? "存在阻塞项，暂不能写入" : "请先生成有效预览")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            Button(role: .destructive) {
                model.undoLatestImport()
            } label: {
                Label("撤销上次导入", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canUndoLatestImport)
        }
    }

    private var importControls: some View {
        Group {
            Picker("目标", selection: $importTarget) {
                ForEach(PersonalDataImportTarget.allCases) { target in
                    Text(target.rawValue).tag(target)
                }
            }
            .frame(minWidth: 150)

            Picker("模式", selection: $importMode) {
                ForEach(PersonalDataSaveMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .frame(minWidth: 150)

            Button {
                importSource = .table
                isImportingFile = true
            } label: {
                Label("导入表格", systemImage: "tablecells")
            }

            Button {
                importSource = .image
                isImportingFile = true
            } label: {
                Label("识别图片", systemImage: "photo")
            }
        }
    }

    private var insightPanel: some View {
        SectionCard(title: "洞察", subtitle: model.portfolioSnapshotInsightSummary.headline, icon: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                insightReadinessStrip
                if model.portfolioSnapshotInsightSummary.hasEnoughHistory {
                    insightMetricMatrix
                } else {
                    insufficientInsightState
                }
            }
        }
    }

    private var insightReadinessStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
            compactFact(
                "快照数量",
                "\(model.portfolioInsightSnapshots.count) 次",
                tint: model.portfolioInsightSnapshots.count >= 2 ? AppPalette.positive : AppPalette.info
            )
            compactFact(
                "洞察状态",
                model.portfolioSnapshotInsightSummary.hasEnoughHistory ? "已生成" : "待快照",
                tint: model.portfolioSnapshotInsightSummary.hasEnoughHistory ? AppPalette.positive : AppPalette.warning
            )
            compactFact("当前结论", model.portfolioSnapshotInsightSummary.headline, tint: AppPalette.info)
        }
    }

    private var insightMetricMatrix: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
            ForEach(model.portfolioSnapshotInsightSummary.cards) { card in
                insightCard(card)
            }
        }
    }

    private var insufficientInsightState: some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            emptyState("快照不足", detail: "至少需要两次组合快照才能生成变化洞察。当前已有 \(model.portfolioInsightSnapshots.count) 次。")
            Button {
                model.recordPortfolioInsightSnapshotIfPossible()
            } label: {
                Label("记录当前快照", systemImage: "camera.metering.center.weighted")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.brand)
            .disabled(model.personalAssetRows.isEmpty)
        }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { model.draft(for: importTarget) },
            set: { model.updateDraft($0, for: importTarget) }
        )
    }

    private var overwriteReportBinding: Binding<Bool> {
        Binding(
            get: { model.pendingOverwriteReportURL != nil },
            set: { if !$0 { model.pendingOverwriteReportURL = nil } }
        )
    }

    private var allowedImportContentTypes: [UTType] {
        switch importSource {
        case .image:
            return [.image]
        case .table:
            return [.commaSeparatedText, .plainText, .text, .data]
        }
    }

    private func presentSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.nameFieldStringValue = "\(model.monthlyReportSummary.monthText)-portfolio-report.md"
        if panel.runModal() == .OK, let url = panel.url {
            model.saveMonthlyReportAs(to: url)
        }
    }

    private func timelineRow(_ event: ManagerWatchTimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: event.kind))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint(for: event.tone))
                .accentIconStyle(tint: tint(for: event.tone), size: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text(event.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
                if let error = event.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.warning)
                }
            }

            Spacer(minLength: 0)

            Text(event.occurredAt.formatted(date: .numeric, time: .shortened))
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(10)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }

    private func icon(for kind: ManagerWatchTimelineEventKind) -> String {
        switch kind {
        case .pollStarted:
            return "play.circle"
        case .forumHit:
            return "text.bubble"
        case .platformHit:
            return "chart.bar.doc.horizontal"
        case .duplicateSuppressed:
            return "bell.slash"
        case .noUpdates:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        case .recovered:
            return "arrow.clockwise.circle"
        }
    }

    private func importPreviewRows(_ session: ImportPreviewSession) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(importPreviewDisplayOrder, id: \.self) { kind in
                let rows = session.rows.filter { $0.kind == kind }
                if !rows.isEmpty {
                    Text("\(label(for: kind)) \(rows.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint(for: kind))
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppPalette.ink)
                            Text(row.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(AppPalette.muted)
                            if let before = row.beforeSummary {
                                Text("原：\(before)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppPalette.muted)
                            }
                            if let after = row.afterSummary {
                                Text("新：\(after)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppPalette.ink)
                            }
                        }
                        .padding(10)
                        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                    }
                }
            }
        }
    }

    private var importPreviewDisplayOrder: [ImportPreviewChangeKind] {
        [.blocked, .duplicate, .removed, .updated, .added, .unchanged]
    }

    private func insightCard(_ card: PortfolioSnapshotInsightCard) -> some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceS) {
            HStack {
                Text(card.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                Spacer(minLength: 0)
                Circle()
                    .fill(tint(for: card.tone))
                    .frame(width: 8, height: 8)
            }
            Text(card.metric)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint(for: card.tone))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(card.detail)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(AppPalette.spaceM)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(tint(for: card.tone).opacity(0.18), lineWidth: 1)
        )
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

    private func tint(for tone: ManagerWatchTimelineTone) -> Color {
        switch tone {
        case .info:
            return AppPalette.info
        case .positive:
            return AppPalette.positive
        case .warning:
            return AppPalette.warning
        }
    }

    private func tint(for tone: PortfolioSnapshotInsightTone) -> Color {
        switch tone {
        case .gain:
            return AppPalette.marketGain
        case .loss:
            return AppPalette.marketLoss
        case .warning:
            return AppPalette.warning
        case .info:
            return AppPalette.info
        case .neutral:
            return AppPalette.muted
        }
    }

    private func tint(for kind: ImportPreviewChangeKind) -> Color {
        switch kind {
        case .added:
            return AppPalette.positive
        case .updated:
            return AppPalette.info
        case .unchanged:
            return AppPalette.muted
        case .duplicate:
            return AppPalette.warning
        case .removed, .blocked:
            return AppPalette.warning
        }
    }

    private func label(for kind: ImportPreviewChangeKind) -> String {
        switch kind {
        case .added:
            return "新增"
        case .updated:
            return "更新"
        case .unchanged:
            return "不变"
        case .duplicate:
            return "疑似重复"
        case .removed:
            return "移除"
        case .blocked:
            return "阻塞"
        }
    }
}
