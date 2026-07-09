import SwiftUI

struct EnhancementCenterView: View {
    @EnvironmentObject var model: AppModel
    @State var trendAutoAnalysisTimesDraft = ""
    @State var isTrendConfigurationExpanded = false
    @State var selectedWorkbenchSegment: WorkbenchSegment = .config

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppPalette.spaceL) {
                workbenchSegmentBar
                workbenchSegmentContent
            }
            .padding(18)
        }
        .onAppear {
            normalizeSelectedTab()
            normalizeDefaultSegment()
        }
    }

    // MARK: - Workbench Segments

    enum WorkbenchSegment: String, CaseIterable, Identifiable {
        case config = "分析配置"
        case report = "趋势报告"
        case signals = "AI操作观察"

        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .config: return "slider.horizontal.3"
            case .report: return "sparkles"
            case .signals: return "bell.badge"
            }
        }
    }

    @ViewBuilder
    private var workbenchSegmentContent: some View {
        switch selectedWorkbenchSegment {
        case .config:
            configSegment
        case .report:
            reportSegment
        case .signals:
            signalsSegment
        }
    }

    private var workbenchSegmentBar: some View {
        HStack(spacing: AppPalette.spaceS) {
            ForEach(WorkbenchSegment.allCases) { segment in
                workbenchSegmentButton(segment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workbenchSegmentButton(_ segment: WorkbenchSegment) -> some View {
        let isSelected = selectedWorkbenchSegment == segment
        return Button {
            withAnimation(AppPalette.motionSpring) {
                selectedWorkbenchSegment = segment
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: segment.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(segment.rawValue)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? AppPalette.onBrand : AppPalette.ink)
            .padding(.horizontal, AppPalette.spaceL)
            .padding(.vertical, 10)
            .interactiveSurface(
                isSelected: isSelected,
                tint: AppPalette.brand,
                radius: AppPalette.controlRadius,
                fill: AppPalette.controlFill,
                hoverFill: AppPalette.cardHover,
                selectedFill: AppPalette.brand,
                strokeOpacity: AppPalette.strokeSubtle,
                activeStrokeOpacity: AppPalette.selectionStrokeOpacity,
                lift: 0.5
            )
        }
        .buttonStyle(PressResponsiveButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: AppPalette.controlRadius))
    }

    private func normalizeDefaultSegment() {
        if model.trendReport != nil {
            if selectedWorkbenchSegment == .config {
                selectedWorkbenchSegment = .report
            }
        } else if selectedWorkbenchSegment == .report {
            selectedWorkbenchSegment = .config
        }
    }

    private func normalizeSelectedTab() {
        if !model.selectedEnhancementTab.isVisibleInWorkbench {
            model.selectedEnhancementTab = .trend
        }
    }

}
