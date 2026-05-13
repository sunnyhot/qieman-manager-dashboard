import SwiftUI

// MARK: - Platform

struct PlatformSectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var platformListPage = 0
    @State private var sideFilter: SideFilter = .all
    @State private var searchText = ""
    private let compactThreshold: CGFloat = 1120
    private let detailAnchor = "platform-detail-panel"
    private let pageSize = 10

    enum SideFilter: String, CaseIterable {
        case all = "全部"
        case buy = "买入"
        case sell = "卖出"
    }

    // MARK: - Filtered data

    private var filteredActions: [PlatformActionPayload] {
        var actions = model.platformPayload?.actions ?? []

        if sideFilter != .all {
            actions = actions.filter { action in
                let isBuy = (action.side ?? "").lowercased().contains("buy")
                return sideFilter == .buy ? isBuy : !isBuy
            }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            actions = actions.filter { action in
                (action.fundName ?? "").lowercased().contains(q) ||
                (action.fundCode ?? "").lowercased().contains(q) ||
                (action.displayTitle).lowercased().contains(q) ||
                (action.adjustmentTitle ?? "").lowercased().contains(q)
            }
        }

        return actions
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < compactThreshold

            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        platformFilterBar

                        if !model.monthlyPlatformSummary.isEmpty || !model.platformHoldings.isEmpty {
                            collapsibleMonthlySection
                        }

                        SectionCard(
                            title: "调仓浏览",
                            subtitle: isCompact ? "点列表会直接跳到详情" : "左边选动作，右边看详情",
                            icon: "square.split.2x1"
                        ) {
                            if model.hasPlatformActions {
                                if isCompact {
                                    VStack(alignment: .leading, spacing: 8) {
                                        platformListPanel(isCompact: true, scrollProxy: scrollProxy)
                                        platformDetailPanel
                                            .id(detailAnchor)
                                    }
                                } else {
                                    HStack(alignment: .top, spacing: 10) {
                                        platformListPanel(isCompact: false, scrollProxy: scrollProxy)
                                            .frame(width: min(max(proxy.size.width * 0.36, 340), 430), alignment: .top)

                                        platformDetailPanel
                                            .frame(maxWidth: .infinity, alignment: .topLeading)
                                    }
                                }
                            } else {
                                EmptySectionState(
                                    title: "平台调仓暂时为空",
                                    subtitle: "我已经把平台和论坛改成了独立刷新。现在点一次刷新，就算其中一项失败，另一项也会照常显示。",
                                    actionTitle: "刷新调仓"
                                ) {
                                    Task { try? await model.refreshLatest(persist: false) }
                                }
                            }
                        }

                        SectionCard(title: "当前持仓", subtitle: "保留原项目的数据口径", icon: "bag") {
                            if model.platformHoldings.isEmpty {
                                EmptySectionState(
                                    title: "当前没有平台持仓",
                                    subtitle: "如果最近没有拉到调仓数据，这里会先留空；刷新后会自动恢复。",
                                    actionTitle: "立即刷新"
                                ) {
                                    Task { try? await model.refreshLatest(persist: false) }
                                }
                            } else {
                                LazyVStack(spacing: 6) {
                                    ForEach(model.platformHoldings) { holding in
                                        HoldingCard(holding: holding)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var platformFilterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(SideFilter.allCases, id: \.self) { filter in
                    let count = countForSide(filter)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sideFilter = filter
                            platformListPage = 0
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(filter.rawValue)
                                .font(.system(size: 11, weight: sideFilter == filter ? .bold : .medium))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        sideFilter == filter
                                            ? AppPalette.brand.opacity(0.25)
                                            : AppPalette.cardStrong,
                                        in: Capsule()
                                    )
                            }
                        }
                        .foregroundStyle(sideFilter == filter ? AppPalette.brand : AppPalette.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            sideFilter == filter
                                ? AppPalette.brand.opacity(0.10)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(model.platformPayload?.holdings?.assetCount ?? 0) 持仓")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppPalette.card, in: Capsule())
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.muted)

                TextField("搜索基金名称或代码…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onChange(of: searchText) { _, _ in
                        platformListPage = 0
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppPalette.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(AppPalette.line.opacity(0.5), lineWidth: 1)
            )
        }
        .padding(10)
        .background(AppPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.70), lineWidth: 1)
        )
    }

    private func countForSide(_ filter: SideFilter) -> Int {
        let all = model.platformPayload?.actions ?? []
        switch filter {
        case .all:
            return all.count
        case .buy:
            return model.platformPayload?.buyCount ?? all.filter { ($0.side ?? "").lowercased().contains("buy") }.count
        case .sell:
            return model.platformPayload?.sellCount ?? all.filter { !($0.side ?? "").lowercased().contains("buy") }.count
        }
    }

    // MARK: - Collapsible Monthly Section

    @State private var isMonthlyExpanded = false

    private var collapsibleMonthlySection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isMonthlyExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.brand)
                        .frame(width: 18, height: 18)
                        .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))

                    Text("交易时间总览")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)

                    if !model.monthlyPlatformSummary.isEmpty {
                        Text("\(model.monthlyPlatformSummary.count)月")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.muted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppPalette.card, in: Capsule())
                    }

                    Spacer()

                    Image(systemName: isMonthlyExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppPalette.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppPalette.paper.opacity(0.94))
            }
            .buttonStyle(.plain)

            if isMonthlyExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if model.monthlyPlatformSummary.isEmpty {
                        EmptySectionState(
                            title: "还没有平台调仓数据",
                            subtitle: "右上角点「刷新」后会重新直拉平台调仓。",
                            actionTitle: "立即刷新"
                        ) {
                            Task { try? await model.refreshLatest(persist: false) }
                        }
                    } else {
                        PlatformMonthlyOverview(months: model.monthlyPlatformSummary)
                    }

                    if !model.platformHoldings.isEmpty {
                        PlatformHoldingsPieChart(holdings: model.platformHoldings)
                    }
                }
                .padding(12)
                .background(AppPalette.paper.opacity(0.94))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.70), lineWidth: 1)
        )
    }

    // MARK: - List Panel

    private func platformListPanel(isCompact: Bool, scrollProxy: ScrollViewProxy) -> some View {
        let allActions = filteredActions
        let totalCount = allActions.count
        let totalPages = max(1, (totalCount + pageSize - 1) / pageSize)
        let safePage = min(platformListPage, totalPages - 1)
        let start = safePage * pageSize
        let end = min(start + pageSize, totalCount)
        let pageActions = Array(allActions[start..<end])

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("调仓动作")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text("\(totalCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppPalette.card, in: Capsule())

                if sideFilter != .all || !searchText.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sideFilter = .all
                            searchText = ""
                        }
                    } label: {
                        Text("清除筛选")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppPalette.brand)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                if isCompact {
                    Text("点一下自动跳到详情")
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.muted)
                }
            }

            if pageActions.isEmpty && totalCount == 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("没有匹配的调仓动作")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                    if !searchText.isEmpty {
                        Text("试试换个关键词搜索")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(pageActions) { action in
                        Button {
                            model.selectPlatformAction(action.id)
                            if isCompact {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    scrollProxy.scrollTo(detailAnchor, anchor: .top)
                                }
                            }
                        } label: {
                            PlatformActionRow(
                                action: action,
                                isSelected: model.selectedPlatformActionID == action.id,
                                isCompact: true
                            )
                        }
                        .buttonStyle(PressResponsiveButtonStyle())
                        .id(action.id)
                    }
                }
            }

            if totalPages > 1 {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { platformListPage = max(0, safePage - 1) }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(safePage == 0)

                    Text("\(safePage + 1) / \(totalPages)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppPalette.muted)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { platformListPage = min(totalPages - 1, safePage + 1) }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(safePage >= totalPages - 1)

                    Spacer()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
        )
    }

    // MARK: - Detail Panel

    private var platformDetailPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("调仓详情")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Spacer()
                if let action = model.selectedPlatformAction {
                    Text(action.txnDate ?? action.createdAt ?? "未知时间")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
            }

            if let selectedAction = model.selectedPlatformAction {
                PlatformActionDetailCard(action: selectedAction)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("还没有选中的调仓动作")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("从左侧动作列表里点一条，就会在这里展示调仓估值、当前估值和变化。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
        )
    }
}
