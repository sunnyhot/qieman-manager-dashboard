import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EnhancementCenterView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importTarget: PersonalDataImportTarget = .holdings
    @State private var importMode: PersonalDataSaveMode = .merge
    @State private var didCopyReport = false
    @State private var isImportingFile = false
    @State private var importSource: PersonalDataImportSource = .table
    @State private var selectedWatchFilter: EnhancementWatchFilter = .all

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
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        reportActions
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        reportActions
                    }
                }

                if let export = model.lastMonthlyReportExport {
                    Text("最近导出：\(URL(fileURLWithPath: export.filePath).lastPathComponent) · \(export.exportedAt)")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }

                Text(model.monthlyReportSummary.markdown)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppPalette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            }
        }
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
            if model.managerWatchTimelineEvents.isEmpty {
                emptyState("暂无巡检时间线", detail: "开启主理人提醒或点击立即巡检后，这里会记录命中、失败和重复通知抑制。")
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.managerWatchTimelineSummary.events) { event in
                        timelineRow(event)
                    }
                }
            }
        }
    }

    private var importPanel: some View {
        SectionCard(title: "导入预演", subtitle: "先预览变更，再确认写入", icon: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        importControls
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        importControls
                    }
                }

                TextEditor(text: draftBinding)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))

                HStack(spacing: 10) {
                    Button {
                        model.prepareImportPreview(target: importTarget, mode: importMode)
                    } label: {
                        Label("生成预览", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.brand)

                    Button {
                        model.confirmActiveImportPreview()
                    } label: {
                        Label("确认写入", systemImage: "checkmark.circle")
                    }
                    .disabled(model.activeImportPreviewSession?.canConfirm != true)
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        model.undoLatestImport()
                    } label: {
                        Label("撤销上次导入", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!model.canUndoLatestImport)

                    Spacer(minLength: 0)
                }

                if let session = model.activeImportPreviewSession {
                    importPreviewRows(session)
                } else {
                    emptyState("暂无导入预览", detail: "粘贴草稿或导入文件后点击生成预览。")
                }
            }
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(model.portfolioSnapshotInsightSummary.cards) { card in
                    insightCard(card)
                }
            }
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
            Circle()
                .fill(tint(for: event.tone))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

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

    private func importPreviewRows(_ session: ImportPreviewSession) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(ImportPreviewChangeKind.allCases, id: \.self) { kind in
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

    private func insightCard(_ card: PortfolioSnapshotInsightCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
            Text(card.metric)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint(for: card.tone))
            Text(card.detail)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .padding(12)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
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
