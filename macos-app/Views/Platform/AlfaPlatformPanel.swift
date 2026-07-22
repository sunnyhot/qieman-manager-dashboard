import SwiftUI

// MARK: - AlfaPlatformPanel

/// alfa 投顾组合调仓面板：组合切换 + 添加 + 调仓列表/详情。
/// 复用 `PlatformActionRow` / `PlatformActionDetailCard` 渲染（数据已拍平为
/// `PlatformActionPayload`，百分比语义编码在 `actionTitle` 与 `beforePercent/afterPercent`）。
struct AlfaPlatformPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedActionID: String?
    @State private var showingAddSheet = false
    @State private var manualPoCode = ""

    private var actions: [PlatformActionPayload] {
        model.alfaPayload?.actions ?? []
    }

    private var selectedAction: PlatformActionPayload? {
        if let selectedActionID, let matched = actions.first(where: { $0.id == selectedActionID }) {
            return matched
        }
        return actions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            portfolioSwitcher

            if model.alfaPortfolios.isEmpty {
                EmptySectionState(
                    title: "还没有添加投顾组合",
                    subtitle: "点右上角"+"添加且慢投顾组合（如晓磊「基金全磊打之大航海时代」）。",
                    actionTitle: "添加组合"
                ) {
                    showingAddSheet = true
                }
            } else if model.isLoadingAlfa {
                loadingState
            } else if let error = model.alfaError {
                errorState(error)
            } else if actions.isEmpty {
                EmptySectionState(
                    title: "该组合暂无调仓记录",
                    subtitle: "这个投顾组合目前没有公开的调仓动作。",
                    actionTitle: "刷新"
                ) {
                    Task { await model.refreshAlfaPayload() }
                }
            } else {
                actionsContent
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            addPortfolioSheet
        }
        .onAppear {
            if model.alfaCatalog.isEmpty {
                Task { await model.loadAlfaCatalog() }
            }
        }
    }

    // MARK: - 组合切换器

    private var portfolioSwitcher: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppPalette.brand)

            if model.alfaPortfolios.isEmpty {
                Text("投顾组合")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
            } else {
                Picker("投顾组合", selection: alfaSelectionBinding) {
                    ForEach(model.alfaPortfolios) { portfolio in
                        Text(portfolio.name).tag(portfolio.poCode as String?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Spacer()

            Button {
                showingAddSheet = true
            } label: {
                Label("添加", systemImage: "plus.circle")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.brand)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                .stroke(AppPalette.line.opacity(0.5), lineWidth: 1)
        )
    }

    private var alfaSelectionBinding: Binding<String?> {
        Binding(
            get: { model.selectedAlfaPoCode },
            set: { newCode in
                guard let newCode else { return }
                model.selectedAlfaPoCode = newCode
                selectedActionID = nil
                Task { await model.fetchAlfaPayload(poCode: newCode) }
            }
        )
    }

    // MARK: - 调仓内容

    private var actionsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("调仓记录")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                Text("\(actions.count) 条")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppPalette.cardStrong, in: Capsule())
                Spacer()
                Button {
                    Task { await model.refreshAlfaPayload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                .buttonStyle(.plain)
            }

            LazyVStack(spacing: 4) {
                ForEach(actions.prefix(40)) { action in
                    PlatformActionRow(
                        action: action,
                        isSelected: selectedAction?.id == action.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedActionID = action.id
                    }
                }
            }

            if let selected = selectedAction {
                Divider().padding(.vertical, 4)
                PlatformActionDetailCard(action: selected)
            }
        }
    }

    // MARK: - 状态视图

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("正在拉取投顾调仓…")
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func errorState(_ message: String) -> some View {
        EmptySectionState(
            title: "拉取失败",
            subtitle: message,
            actionTitle: "重试"
        ) {
            Task { await model.refreshAlfaPayload() }
        }
    }

    // MARK: - 添加组合 sheet

    private var addPortfolioSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("添加投顾组合")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Spacer()
                Button("完成") { showingAddSheet = false }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppPalette.brand)
                    .buttonStyle(.plain)
            }

            Text("从且慢严选组合列表选择，或直接输入组合码（如 SI000192）。")
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)

            if model.isLoadingAlfaCatalog {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("加载组合列表…")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
            } else {
                catalogList
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("手动输入组合码")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                HStack(spacing: 8) {
                    TextField("如 SI000192", text: $manualPoCode)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                    Button("添加") {
                        Task {
                            let ok = await model.addAlfaPortfolioByCode(manualPoCode)
                            if ok { manualPoCode = "" }
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .disabled(manualPoCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private var catalogList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                let grouped = Dictionary(grouping: model.alfaCatalog, by: { $0.category })
                let sortedCategories = grouped.keys.sorted()
                ForEach(sortedCategories, id: \.self) { category in
                    Text(category.isEmpty ? "其他" : category)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppPalette.muted)
                        .padding(.top, 6)
                    ForEach(grouped[category] ?? []) { item in
                        let added = model.alfaPortfolios.contains(where: { $0.poCode == item.poCode })
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppPalette.ink)
                                Text("\(item.author) · \(item.poCode)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(AppPalette.muted)
                            }
                            Spacer()
                            if added {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(AppPalette.muted)
                            } else {
                                Button("添加") {
                                    model.addAlfaPortfolio(item)
                                }
                                .font(.system(size: 10, weight: .medium))
                                .buttonStyle(.plain)
                                .foregroundStyle(AppPalette.brand)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: AppPalette.badgeRadius)
                                .fill(AppPalette.card)
                        )
                    }
                }
            }
        }
        .frame(maxHeight: 260)
    }
}
