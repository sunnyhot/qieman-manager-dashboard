import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Platform

struct PlatformSectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var platformListPage = 0
    private let compactThreshold: CGFloat = 1120
    private let detailAnchor = "platform-detail-panel"
    private let pageSize = 10

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < compactThreshold

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                            MetricCard(title: "调仓动作", value: "\(model.platformPayload?.count ?? 0)", subtitle: "覆盖调仓单 \(model.platformPayload?.adjustmentCount ?? 0)", icon: "arrow.left.arrow.right", accent: AppPalette.info)
                            MetricCard(title: "买入", value: "\(model.platformPayload?.buyCount ?? 0)", subtitle: "本地原生筛选", icon: "arrow.down.circle", accent: AppPalette.positive)
                            MetricCard(title: "卖出", value: "\(model.platformPayload?.sellCount ?? 0)", subtitle: "本地原生筛选", icon: "arrow.up.circle", accent: AppPalette.warning)
                            MetricCard(title: "持仓标的", value: "\(model.platformPayload?.holdings?.assetCount ?? 0)", subtitle: model.platformPayload?.prodCode ?? model.form.prodCode, icon: "bag", accent: AppPalette.accentWarm)
                        }

                        SectionCard(title: "交易时间总览", subtitle: "按月看买卖节奏", icon: "calendar") {
                            VStack(alignment: .leading, spacing: 12) {
                                if model.monthlyPlatformSummary.isEmpty {
                                    EmptySectionState(
                                        title: "还没有平台调仓数据",
                                        subtitle: "右上角点「刷新」后会重新直拉平台调仓；即使论坛抓取失败，调仓也会单独更新。",
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
                        }

                        SectionCard(
                            title: "调仓浏览",
                            subtitle: isCompact ? "窄窗口自动切成上下结构，点列表会直接跳到详情" : "宽窗口保持双栏，左边选动作，右边看详情",
                            icon: "square.split.2x1"
                        ) {
                            if model.hasPlatformActions {
                                if isCompact {
                                    VStack(alignment: .leading, spacing: 12) {
                                        platformListPanel(isCompact: true, scrollProxy: scrollProxy)
                                        platformDetailPanel
                                            .id(detailAnchor)
                                    }
                                } else {
                                    HStack(alignment: .top, spacing: 14) {
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
                                LazyVStack(spacing: 8) {
                                    ForEach(model.platformHoldings) { holding in
                                        HoldingCard(holding: holding)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func platformListPanel(isCompact: Bool, scrollProxy: ScrollViewProxy) -> some View {
        let allActions = model.platformPayload?.actions ?? []
        let totalCount = allActions.count
        let totalPages = max(1, (totalCount + pageSize - 1) / pageSize)
        let safePage = min(platformListPage, totalPages - 1)
        let start = safePage * pageSize
        let end = min(start + pageSize, totalCount)
        let pageActions = Array(allActions[start..<end])

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("调仓动作列表")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text("\(totalCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppPalette.card, in: Capsule())
                Spacer()
                if isCompact {
                    Text("点一下自动跳到详情")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
            }

            LazyVStack(spacing: 8) {
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
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                        .monospacedDigit()

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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
        )
    }

    private var platformDetailPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                .padding(14)
                .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
        )
    }
}
