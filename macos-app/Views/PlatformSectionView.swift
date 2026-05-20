import SwiftUI

// MARK: - Platform

struct PlatformSectionView: View {
    @EnvironmentObject private var model: AppModel
    private let compactThreshold: CGFloat = 1120
    private let detailAnchor = "platform-detail-panel"

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < compactThreshold

            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        PlatformFilterBar(filterState: model.filterState)

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

    // MARK: - Collapsible Monthly Section

    @State private var isMonthlyExpanded = false

    private var collapsibleMonthlySection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isMonthlyExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.brand)
                        .frame(width: 20, height: 20)
                        .background(AppPalette.brand.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(AppPalette.brand.opacity(0.22), lineWidth: 1)
                        )

                    Text("交易时间总览")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)

                    if !model.monthlyPlatformSummary.isEmpty {
                        Text("\(model.monthlyPlatformSummary.count)月")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppPalette.cardStrong, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(AppPalette.line.opacity(0.35), lineWidth: 1)
                            )
                    }

                    Spacer()

                    Image(systemName: isMonthlyExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppPalette.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppPalette.card)
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
                .background(AppPalette.card)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.50), lineWidth: 1)
        )
    }

    // MARK: - List Panel

    private func platformListPanel(isCompact: Bool, scrollProxy: ScrollViewProxy) -> some View {
        let allActions = model.filteredPlatformActions
        let totalCount = allActions.count
        let totalPages = model.totalPlatformPages
        let currentPage = min(model.filterState.currentPage, totalPages - 1)
        let pageActions = model.paginatedPlatformActions

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
                    .background(AppPalette.cardStrong, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(AppPalette.line.opacity(0.35), lineWidth: 1)
                    )

                if model.filterState.sideFilter != .all || !model.filterState.searchText.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            model.filterState.reset()
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

            if pageActions.isEmpty, totalCount == 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("没有匹配的调仓动作")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                    if !model.filterState.searchText.isEmpty {
                        Text("试试换个关键词搜索")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                        .stroke(AppPalette.line.opacity(0.35), lineWidth: 1)
                )
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            model.filterState.currentPage = max(0, currentPage - 1)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppPalette.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppPalette.line.opacity(0.40), lineWidth: 1)
                    )
                    .disabled(currentPage == 0)
                    .opacity(currentPage == 0 ? 0.4 : 1.0)

                    Text("\(currentPage + 1) / \(totalPages)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppPalette.muted)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            model.filterState.currentPage = min(totalPages - 1, currentPage + 1)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppPalette.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppPalette.line.opacity(0.40), lineWidth: 1)
                    )
                    .disabled(currentPage >= totalPages - 1)
                    .opacity(currentPage >= totalPages - 1 ? 0.4 : 1.0)

                    Spacer()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.50), lineWidth: 1)
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
                .background(AppPalette.cardHover, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                        .stroke(AppPalette.line.opacity(0.35), lineWidth: 1)
                )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.50), lineWidth: 1)
        )
    }
}
