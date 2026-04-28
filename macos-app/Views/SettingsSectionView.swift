import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Settings

struct SettingsSectionView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("portfolio.import.center.expanded") private var isImportCenterExpanded = false
    @AppStorage("portfolio.import.show_imported_targets") private var shouldShowImportedImportTargets = false
    @State private var importTarget: PersonalDataImportTarget = .holdings
    @State private var isDraftEditorExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionCard(title: "账号与登录", subtitle: "管理且慢登录态，验证 Cookie 有效性", icon: "person.circle") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ToolbarBadge(
                                title: model.cookieAvailable ? "Cookie 可用" : "Cookie 缺失",
                                tint: model.cookieAvailable ? AppPalette.positive : AppPalette.warning
                            )
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            Button("登录且慢") {
                                model.presentLoginSheet()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppPalette.brand)

                            Button(model.isCheckingAuth ? "验证中…" : "验证登录态") {
                                Task { await model.validateAuth() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isCheckingAuth)
                        }
                    }
                }

                ManagerWatchControlCard()

                SectionCard(title: "导入中心", subtitle: "支持手动录入、上传图片 OCR、上传表格到三类资产区", icon: "square.and.arrow.down") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ToolbarBadge(
                                title: hasAnyPersonalData ? "已导入资产数据" : "尚未导入",
                                tint: hasAnyPersonalData ? AppPalette.positive : AppPalette.warning
                            )
                            ToolbarBadge(
                                title: hasCurrentDraft
                                ? "草稿 \(currentDraftLineCount) 行 / \(currentDraftCharacterCount) 字"
                                : "草稿为空",
                                tint: hasCurrentDraft ? AppPalette.info : AppPalette.muted
                            )
                            Spacer()
                        }

                        if hiddenImportedTargetCount > 0 {
                            HStack(spacing: 10) {
                                Text(shouldShowImportedImportTargets ? "当前显示全部导入对象，可继续补录或重导。" : "已导入成功的对象已暂时收起，需要补录或重导时可以显示全部。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppPalette.muted)
                                Spacer()
                                Button(shouldShowImportedImportTargets ? "只看未导入" : "显示已导入对象") {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        shouldShowImportedImportTargets.toggle()
                                        syncImportTargetWithVisibleTargets()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        } else if unimportedImportTargets.isEmpty {
                            Text("持仓中、买入中和定投计划都已导入成功。仍可选择任一对象继续补录或重导，股票录入在「持仓中」。")
                                .font(.system(size: 11))
                                .foregroundStyle(AppPalette.muted)
                                .padding(.horizontal, 2)
                        }

                        Picker("导入对象", selection: $importTarget) {
                            ForEach(visibleImportTargets) { target in
                                Text(target.rawValue).tag(target)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 520)

                        Text(importTarget.helpText)
                            .font(.system(size: 11))
                            .foregroundStyle(AppPalette.muted)

                        HStack(spacing: 8) {
                            Spacer()
                            Button(isDraftEditorExpanded ? "收起编辑" : "展开编辑") {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    isDraftEditorExpanded.toggle()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if isDraftEditorExpanded {
                            TextEditor(text: selectedDraftBinding)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(height: 220)
                                .padding(10)
                                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                                )
                        } else if hasCurrentDraft {
                            ScrollView {
                                Text(currentDraftPreviewText)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(AppPalette.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                            .frame(height: 122)
                            .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                            )
                        }

                        HStack {
                            Text(importTarget.sampleText)
                                .font(.system(size: 11))
                                .foregroundStyle(AppPalette.muted)
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Button(saveDraftButtonTitle) {
                                model.saveDraft(for: importTarget)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppPalette.brand)
                            .disabled(importTarget == .holdings && model.isResolvingPortfolioNames)

                            Button("上传图片") {
                                presentImportPanel(source: .image)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isProcessingImport)

                            Button("上传表格") {
                                presentImportPanel(source: .table)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isProcessingImport)

                            Button(reloadButtonTitle) {
                                model.reloadDraftTargetFromDisk(importTarget)
                            }
                            .buttonStyle(.bordered)

                            if importTarget == .holdings {
                                Button(model.isRefreshingPortfolio ? "刷新中…" : "刷新估值") {
                                    Task { try? await model.refreshUserPortfolio() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.isRefreshingPortfolio || !model.hasPersonalPortfolio)
                            }

                            Button("清空草稿") {
                                model.updateDraft("", for: importTarget)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.draft(for: importTarget).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                SectionCard(title: "应用版本", subtitle: "当前版本 \(AppUpdateChecker.bundleVersion)", icon: "arrow.down.circle") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Text(AppUpdateChecker.bundleVersion)
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppPalette.ink)
                                .monospacedDigit()
                            Spacer()
                            Button(model.isCheckingForUpdates ? "检查更新中…" : "检查更新") {
                                Task { await model.checkForUpdates(userInitiated: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppPalette.brand)
                            .disabled(model.isCheckingForUpdates)

                            if model.availableUpdate != nil {
                                Button(model.isInstallingUpdate ? "安装更新中…" : "下载并重启安装") {
                                    Task { await model.downloadAndInstallAvailableUpdate() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.isInstallingUpdate)

                                Button("查看 Release") {
                                    model.openAvailableUpdateReleasePage()
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if let update = model.availableUpdate {
                            HStack(spacing: 8) {
                                ToolbarBadge(title: "新版本 \(update.version)", tint: AppPalette.positive)
                                ToolbarBadge(title: update.asset?.name ?? "", tint: AppPalette.info)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            syncImportTargetWithVisibleTargets()
        }
        .onChange(of: importTarget) { _, _ in
            isDraftEditorExpanded = false
        }
        .onChange(of: importAvailabilityKey) { _, _ in
            syncImportTargetWithVisibleTargets()
        }
    }

    private var selectedDraftBinding: Binding<String> {
        Binding(
            get: { model.draft(for: importTarget) },
            set: { model.updateDraft($0, for: importTarget) }
        )
    }

    private var reloadButtonTitle: String {
        switch importTarget {
        case .holdings:
            return "重载已保存"
        case .pendingTrades:
            return "重载买入中"
        case .investmentPlans:
            return "重载计划"
        }
    }

    private var saveDraftButtonTitle: String {
        if importTarget == .holdings, model.isResolvingPortfolioNames {
            return "补全名称中…"
        }
        return importTarget.buttonTitle
    }

    private var tableImportTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .commaSeparatedText, .json]
        if let xlsx = UTType(filenameExtension: "xlsx") {
            types.append(xlsx)
        }
        if let csv = UTType(filenameExtension: "csv") {
            types.append(csv)
        }
        if let tsv = UTType(filenameExtension: "tsv") {
            types.append(tsv)
        }
        return types
    }

    private var currentDraftText: String {
        model.draft(for: importTarget)
    }

    private var visibleImportTargets: [PersonalDataImportTarget] {
        if shouldShowImportedImportTargets || unimportedImportTargets.isEmpty {
            return PersonalDataImportTarget.allCases
        }
        return unimportedImportTargets
    }

    private var unimportedImportTargets: [PersonalDataImportTarget] {
        PersonalDataImportTarget.allCases.filter { !model.hasImportedData(for: $0) }
    }

    private var hiddenImportedTargetCount: Int {
        guard !shouldShowImportedImportTargets else { return 0 }
        guard !unimportedImportTargets.isEmpty else { return 0 }
        return PersonalDataImportTarget.allCases.count - unimportedImportTargets.count
    }

    private var importAvailabilityKey: String {
        PersonalDataImportTarget.allCases
            .map { model.hasImportedData(for: $0) ? "1" : "0" }
            .joined()
    }

    private var hasCurrentDraft: Bool {
        !currentDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentDraftLineCount: Int {
        currentDraftText
            .split(whereSeparator: \.isNewline)
            .count
    }

    private var currentDraftCharacterCount: Int {
        currentDraftText.count
    }

    private var currentDraftPreviewText: String {
        let lines = currentDraftText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard !lines.isEmpty else { return "" }
        let previewLines = Array(lines.prefix(8))
        let suffix = lines.count > previewLines.count
            ? "\n… 还有 \(lines.count - previewLines.count) 行，点击「展开编辑」查看完整草稿"
            : ""
        return previewLines.joined(separator: "\n") + suffix
    }

    private var hasAnyPersonalData: Bool {
        model.hasPersonalPortfolio || model.hasPendingTrades || model.hasInvestmentPlans
    }

    private func syncImportTargetWithVisibleTargets() {
        guard !visibleImportTargets.isEmpty else { return }
        if !visibleImportTargets.contains(importTarget) {
            importTarget = visibleImportTargets[0]
            isDraftEditorExpanded = false
        }
    }

    private func presentImportPanel(source: PersonalDataImportSource) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.allowedContentTypes = source == .image ? [.image] : tableImportTypes
        panel.title = source == .image ? "选择要 OCR 的图片" : "选择要导入的表格或文本"
        panel.message = source == .image
            ? "图片会先识别成文字，再填入当前导入对象的草稿区。"
            : "支持 txt、csv、tsv、json、xlsx，会转换成当前导入对象的草稿。"
        panel.prompt = "选择"

        let target = importTarget
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            return
        }
        Task { await model.importExternalFile(at: url, source: source, target: target) }
    }
}

