import Charts
import SwiftUI

struct PersonalWatchlistPanel: View {
    @EnvironmentObject private var model: AppModel

    @State private var selectedItemID: UUID?
    @State private var isPresentingAddSheet = false
    @State private var deletingRecord: PersonalWatchlistRecord?
    @State private var configuringAlertRow: PersonalWatchlistQuoteRow?

    private var rows: [PersonalWatchlistQuoteRow] {
        model.personalWatchlistSnapshot?.rows
            ?? PersonalWatchlistSnapshot.local(records: model.personalWatchlistRecords).rows
    }

    var body: some View {
        SectionCard(
            title: "我的关注",
            subtitle: "记录首次关注价，持续对比场外基金、场内基金与股票的每日走势",
            icon: "star",
            trailing: {
                Spacer()
                Button {
                    Task { await refreshWatchlist() }
                } label: {
                    Label(
                        model.isRefreshingPersonalWatchlist ? "刷新中…" : "刷新",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(rows.isEmpty || model.isRefreshingPersonalWatchlist)

                Button {
                    isPresentingAddSheet = true
                } label: {
                    Label("添加关注", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.brand)
                .controlSize(.small)
            }
        ) {
            if rows.isEmpty {
                EmptySectionState(
                    title: "还没有关注标的",
                    subtitle: "添加后会锁定首次有效价格，并按交易日记录走势。支持场外基金、场内基金和股票。",
                    actionTitle: "添加关注",
                    action: { isPresentingAddSheet = true }
                )
            } else {
                groupedList
            }
        }
        .sheet(isPresented: $isPresentingAddSheet) {
            PersonalWatchlistAddSheet()
        }
        .sheet(item: $configuringAlertRow) { row in
            PersonalWatchlistAlertSheet(row: row)
        }
        .alert("取消关注？", isPresented: deleteConfirmationBinding) {
            Button("取消关注", role: .destructive) {
                if let deletingRecord {
                    model.removePersonalWatchlistItem(deletingRecord.id)
                    if selectedItemID == deletingRecord.id {
                        selectedItemID = nil
                    }
                }
                deletingRecord = nil
            }
            Button("保留", role: .cancel) {
                deletingRecord = nil
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            clearMissingSelection()
        }
    }

    private var groupedList: some View {
        LazyVStack(alignment: .leading, spacing: AppPalette.spaceL) {
            ForEach(PersonalWatchlistCategory.allCases) { category in
                let categoryRows = rows.filter { $0.category == category }
                if !categoryRows.isEmpty {
                    PersonalWatchlistGroup(
                        category: category,
                        rows: categoryRows,
                        selectedItemID: selectedItemID,
                        onSelect: { toggleSelection($0.id) },
                        onConfigureAlerts: { configuringAlertRow = $0 },
                        onDelete: { deletingRecord = $0.record }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletingRecord != nil },
            set: { isPresented in
                if !isPresented { deletingRecord = nil }
            }
        )
    }

    private var deleteConfirmationMessage: String {
        guard let deletingRecord else { return "" }
        let name = deletingRecord.item.normalizedName ?? deletingRecord.item.normalizedCode
        return "会删除 \(name) 的关注基准与本地每日价格记录，不会影响实际持仓。"
    }

    private func toggleSelection(_ id: UUID) {
        withAnimation(AppPalette.motionStandard) {
            selectedItemID = selectedItemID == id ? nil : id
        }
    }

    private func clearMissingSelection() {
        guard let selectedItemID,
              !rows.contains(where: { $0.id == selectedItemID }) else { return }
        self.selectedItemID = nil
    }

    private func refreshWatchlist() async {
        do {
            try await model.refreshPersonalWatchlist()
        } catch {
            model.errorMessage = "我的关注刷新失败：\(error.localizedDescription)"
        }
    }
}

private struct PersonalWatchlistGroup: View {
    let category: PersonalWatchlistCategory
    let rows: [PersonalWatchlistQuoteRow]
    let selectedItemID: UUID?
    let onSelect: (PersonalWatchlistQuoteRow) -> Void
    let onConfigureAlerts: (PersonalWatchlistQuoteRow) -> Void
    let onDelete: (PersonalWatchlistQuoteRow) -> Void

    private var tint: Color {
        switch category {
        case .offExchangeFund:
            return AppPalette.brand
        case .onExchangeFund:
            return AppPalette.accentWarm
        case .stock:
            return AppPalette.info
        }
    }

    private var gainCount: Int {
        rows.filter { ($0.changeSinceFollowPct ?? 0) > 0 }.count
    }

    private var lossCount: Int {
        rows.filter { ($0.changeSinceFollowPct ?? 0) < 0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceS) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 3, height: 18)
                Text(category.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                ToolbarBadge(title: "\(rows.count) 只", tint: tint)
                Spacer(minLength: 8)
                if gainCount > 0 {
                    Text("上涨 \(gainCount)")
                        .foregroundStyle(AppPalette.marketGain)
                }
                if lossCount > 0 {
                    Text("下跌 \(lossCount)")
                        .foregroundStyle(AppPalette.marketLoss)
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, AppPalette.spaceM)
            .padding(.vertical, 10)
            .background(tint.opacity(0.06))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(tint.opacity(0.18))
                    .frame(height: 1)
            }

            VStack(spacing: AppPalette.spaceS) {
                ForEach(rows) { row in
                    VStack(spacing: AppPalette.spaceS) {
                        PersonalWatchlistListRow(
                            row: row,
                            isSelected: selectedItemID == row.id,
                            tint: tint,
                            onSelect: { onSelect(row) },
                            onConfigureAlerts: { onConfigureAlerts(row) },
                            onDelete: { onDelete(row) }
                        )

                        if selectedItemID == row.id {
                            PersonalWatchlistDetailChart(row: row)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
        }
    }
}

private struct PersonalWatchlistListRow: View {
    let row: PersonalWatchlistQuoteRow
    let isSelected: Bool
    let tint: Color
    let onSelect: () -> Void
    let onConfigureAlerts: () -> Void
    let onDelete: () -> Void

    private var changeTint: Color {
        AppPalette.marketTint(for: row.changeSinceFollowPct)
    }

    private var activeAlertCount: Int {
        row.record.alertRules?.ruleCount ?? 0
    }

    private var triggeredAlertCount: Int {
        row.record.alertState?.breachedKinds.count ?? 0
    }

    private var alertTint: Color {
        if triggeredAlertCount > 0 { return AppPalette.warning }
        return activeAlertCount > 0 ? tint : AppPalette.muted
    }

    var body: some View {
        HStack(spacing: AppPalette.spaceS) {
            Button(action: onSelect) {
                HStack(spacing: AppPalette.spaceM) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(row.item.normalizedCode)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(AppPalette.muted)
                            Text(row.item.marketLabel)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(tint)
                        }
                    }
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

                    watchlistValue(
                        title: "关注价 · \(row.item.followedDate)",
                        value: watchlistPriceText(row.record.baseline?.price, item: row.item),
                        tint: AppPalette.ink
                    )
                    .frame(width: 112, alignment: .leading)

                    watchlistValue(
                        title: row.category == .offExchangeFund ? "当前净值" : "当前价格",
                        value: watchlistPriceText(row.currentPrice, item: row.item),
                        tint: AppPalette.ink
                    )
                    .frame(width: 90, alignment: .leading)

                    watchlistValue(
                        title: "关注以来",
                        value: percentOptional(row.changeSinceFollowPct),
                        tint: changeTint
                    )
                    .frame(width: 78, alignment: .leading)

                    PersonalWatchlistSparkline(row: row)
                        .frame(width: 118, height: 38)

                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? tint : AppPalette.muted)
                        .frame(width: 14)
                }
                .padding(.horizontal, AppPalette.spaceM)
                .padding(.vertical, 10)
                .contentShape(RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            }
            .buttonStyle(.plain)
            .interactiveSurface(
                isSelected: isSelected,
                tint: tint,
                fill: AppPalette.cardStrong,
                hoverFill: AppPalette.cardHover,
                lift: AppPalette.hoverLift
            )
            .animation(AppPalette.motionFast, value: isSelected)
            .accessibilityLabel("\(row.displayName)，\(isSelected ? "收起走势" : "展开走势")")

            Menu {
                Button(action: onConfigureAlerts) {
                    Label(
                        activeAlertCount > 0 ? "编辑提醒" : "设置提醒",
                        systemImage: "bell"
                    )
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("取消关注", systemImage: "star.slash")
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: activeAlertCount > 0 ? "bell.fill" : "bell")
                        .font(.system(size: 11, weight: .semibold))
                    if triggeredAlertCount > 0 {
                        Circle()
                            .fill(AppPalette.warning)
                            .frame(width: 6, height: 6)
                            .offset(x: 3, y: -2)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(alertTint)
            .help(alertHelpText)
            .accessibilityLabel("\(row.displayName)，\(alertHelpText)")
        }
    }

    private var alertHelpText: String {
        guard activeAlertCount > 0 else { return "设置价格提醒" }
        if triggeredAlertCount > 0 {
            return "\(activeAlertCount) 条提醒，\(triggeredAlertCount) 条已触发"
        }
        return "\(activeAlertCount) 条提醒正在监控"
    }

    private func watchlistValue(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct PersonalWatchlistSparkline: View {
    let row: PersonalWatchlistQuoteRow

    private var points: [PersonalWatchlistDailyPoint] {
        Array(row.dailyPoints.suffix(30))
    }

    private var tint: Color {
        AppPalette.marketTint(for: row.changeSinceFollowPct)
    }

    var body: some View {
        if points.isEmpty {
            Text("待记录")
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("价格", point.price)
                    )
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }

                if let baseline = row.record.baseline?.price {
                    RuleMark(y: .value("关注价", baseline))
                        .foregroundStyle(AppPalette.muted.opacity(0.38))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
                }

                if let last = points.last {
                    PointMark(
                        x: .value("日期", last.date),
                        y: .value("价格", last.price)
                    )
                    .foregroundStyle(tint)
                    .symbolSize(12)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .accessibilityLabel("\(row.displayName) 近 30 个交易日走势")
        }
    }
}

private enum PersonalWatchlistChartRange: String, CaseIterable, Identifiable {
    case thirty = "30日"
    case ninety = "90日"
    case all = "全部"

    var id: String { rawValue }

    var pointLimit: Int? {
        switch self {
        case .thirty: return 30
        case .ninety: return 90
        case .all: return nil
        }
    }
}

private struct PersonalWatchlistChartPoint: Identifiable {
    let date: Date
    let dateText: String
    let price: Double
    let quotedAt: String?

    var id: String { dateText }
}

private struct PersonalWatchlistDetailChart: View {
    let row: PersonalWatchlistQuoteRow

    @State private var range: PersonalWatchlistChartRange = .ninety
    @State private var hoveredPoint: PersonalWatchlistChartPoint?
    @State private var hoverLocation: CGPoint = .zero

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var allChartPoints: [PersonalWatchlistChartPoint] {
        row.dailyPoints.compactMap { point in
            guard let date = Self.dateFormatter.date(from: point.date) else { return nil }
            return PersonalWatchlistChartPoint(
                date: date,
                dateText: point.date,
                price: point.price,
                quotedAt: point.quotedAt
            )
        }
    }

    private var chartPoints: [PersonalWatchlistChartPoint] {
        guard let limit = range.pointLimit else { return allChartPoints }
        return Array(allChartPoints.suffix(limit))
    }

    private var changeTint: Color {
        AppPalette.marketTint(for: row.changeSinceFollowPct)
    }

    private var yDomain: ClosedRange<Double> {
        let prices = chartPoints.map(\.price) + [row.record.baseline?.price].compactMap { $0 }
        guard let minimum = prices.min(), let maximum = prices.max() else { return 0...1 }
        let spread = max(maximum - minimum, abs(maximum) * 0.01, 0.0001)
        return (minimum - spread * 0.12)...(maximum + spread * 0.12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            HStack(alignment: .top, spacing: AppPalette.spaceS) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(row.item.normalizedCode)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                        ToolbarBadge(title: row.item.marketLabel, tint: categoryTint)
                    }
                }
                Spacer(minLength: 8)
                Picker("范围", selection: $range) {
                    ForEach(PersonalWatchlistChartRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 172)
            }

            HStack(spacing: 0) {
                chartMetric(
                    "关注价",
                    watchlistPriceText(row.record.baseline?.price, item: row.item),
                    tint: AppPalette.ink
                )
                metricDivider
                chartMetric(
                    "当前",
                    watchlistPriceText(row.currentPrice, item: row.item),
                    tint: AppPalette.ink
                )
                metricDivider
                chartMetric("关注以来", percentOptional(row.changeSinceFollowPct), tint: changeTint)
            }

            if let rules = row.record.alertRules {
                HStack(spacing: 7) {
                    Image(systemName: row.record.effectiveAlertState.isTriggered ? "bell.badge.fill" : "bell.fill")
                    Text(watchlistAlertRulesText(rules, item: row.item))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(row.record.effectiveAlertState.isTriggered ? "已触发" : "监控中")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 9))
                .foregroundStyle(row.record.effectiveAlertState.isTriggered ? AppPalette.warning : categoryTint)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    (row.record.effectiveAlertState.isTriggered ? AppPalette.warning : categoryTint)
                        .opacity(0.08),
                    in: RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                )
            }

            if chartPoints.isEmpty {
                VStack(spacing: AppPalette.spaceS) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 24))
                        .foregroundStyle(AppPalette.muted)
                    Text("等待首个有效行情")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text("刷新成功后会按交易日记录并绘制折线。")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 210)
            } else {
                chart
                    .frame(height: 220)
                    .overlay { tooltipOverlay }
            }

            HStack(spacing: AppPalette.spaceS) {
                Label("实线：每日价格", systemImage: "minus")
                    .foregroundStyle(changeTint)
                Label("虚线：关注起点", systemImage: "line.diagonal")
                    .foregroundStyle(AppPalette.muted)
                Spacer(minLength: 4)
                Text("已记录 \(row.dailyPoints.count) 个交易日")
                    .foregroundStyle(AppPalette.muted)
            }
            .font(.system(size: 9, weight: .medium))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .cardStroke(opacity: 0.38)
        .animation(AppPalette.motionStandard, value: range)
        .onChange(of: row.id) { _, _ in
            hoveredPoint = nil
        }
    }

    private var chart: some View {
        Chart {
            ForEach(chartPoints) { point in
                LineMark(
                    x: .value("日期", point.date),
                    y: .value("价格", point.price)
                )
                .foregroundStyle(changeTint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            if let baseline = row.record.baseline?.price {
                RuleMark(y: .value("关注价", baseline))
                    .foregroundStyle(AppPalette.muted.opacity(0.62))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }

            if let hoveredPoint {
                RuleMark(x: .value("日期", hoveredPoint.date))
                    .foregroundStyle(AppPalette.line.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(
                    x: .value("日期", hoveredPoint.date),
                    y: .value("价格", hoveredPoint.price)
                )
                .foregroundStyle(changeTint)
                .symbolSize(36)
            } else if let last = chartPoints.last {
                PointMark(
                    x: .value("日期", last.date),
                    y: .value("价格", last.price)
                )
                .foregroundStyle(changeTint)
                .symbolSize(28)
            }
        }
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(AppPalette.line.opacity(0.28))
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(watchlistAxisPrice(price))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(AppPalette.line.opacity(0.16))
                AxisValueLabel(format: .dateTime.month().day())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let frame = proxy.plotFrame else { return }
                            let plotRect = geometry[frame]
                            let relativeX = location.x - plotRect.origin.x
                            let relativeY = location.y - plotRect.origin.y
                            guard relativeX >= 0,
                                  relativeX <= plotRect.width,
                                  relativeY >= 0,
                                  relativeY <= plotRect.height,
                                  let date: Date = proxy.value(atX: relativeX) else {
                                hoveredPoint = nil
                                return
                            }
                            hoverLocation = location
                            hoveredPoint = chartPoints.min {
                                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                            }
                        case .ended:
                            hoveredPoint = nil
                        }
                    }
            }
        }
    }

    private var tooltipOverlay: some View {
        GeometryReader { geometry in
            if let hoveredPoint {
                let width: CGFloat = 164
                let height: CGFloat = 66
                let x = min(max(hoverLocation.x + 12, 0), geometry.size.width - width)
                let y = min(max(hoverLocation.y - height - 8, 0), geometry.size.height - height)
                VStack(alignment: .leading, spacing: 3) {
                    Text(hoveredPoint.dateText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text(watchlistPriceText(hoveredPoint.price, item: row.item))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(changeTint)
                    if let baseline = row.record.baseline?.price, baseline > 0 {
                        Text("较关注价 \(percentOptional((hoveredPoint.price / baseline - 1) * 100))")
                            .font(.system(size: 9))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
                .padding(AppPalette.spaceS)
                .frame(width: width, alignment: .leading)
                .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .cardStroke(opacity: 0.48)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .position(x: x + width / 2, y: y + height / 2)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private var categoryTint: Color {
        switch row.category {
        case .offExchangeFund: return AppPalette.brand
        case .onExchangeFund: return AppPalette.accentWarm
        case .stock: return AppPalette.info
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(AppPalette.line.opacity(0.4))
            .frame(width: 1, height: 34)
    }

    private func chartMetric(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppPalette.spaceS)
    }
}

private struct PersonalWatchlistAlertSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let row: PersonalWatchlistQuoteRow

    @State private var priceAboveEnabled: Bool
    @State private var priceAboveText: String
    @State private var priceBelowEnabled: Bool
    @State private var priceBelowText: String
    @State private var gainEnabled: Bool
    @State private var gainText: String
    @State private var lossEnabled: Bool
    @State private var lossText: String
    @State private var inlineErrorMessage = ""
    @State private var isSaving = false

    init(row: PersonalWatchlistQuoteRow) {
        self.row = row
        let rules = row.record.alertRules
        _priceAboveEnabled = State(initialValue: rules?.priceAbove != nil)
        _priceAboveText = State(initialValue: alertEditableNumber(rules?.priceAbove))
        _priceBelowEnabled = State(initialValue: rules?.priceBelow != nil)
        _priceBelowText = State(initialValue: alertEditableNumber(rules?.priceBelow))
        _gainEnabled = State(initialValue: rules?.gainSinceFollowPct != nil)
        _gainText = State(initialValue: alertEditableNumber(rules?.gainSinceFollowPct))
        _lossEnabled = State(initialValue: rules?.lossSinceFollowPct != nil)
        _lossText = State(initialValue: alertEditableNumber(rules?.lossSinceFollowPct))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: row.record.hasActiveAlerts ? "bell.fill" : "bell")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(categoryTint)
                    .accentIconStyle(tint: categoryTint, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("价格提醒")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text("\(row.displayName) · \(row.item.normalizedCode) · \(row.item.marketLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                if let state = row.record.alertState, state.isTriggered {
                    Label("当前已触发", systemImage: "bell.badge.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.warning)
                }
            }

            HStack(spacing: 0) {
                alertMetric("关注价", watchlistPriceText(row.record.baseline?.price, item: row.item))
                alertMetricDivider
                alertMetric("当前", watchlistPriceText(row.currentPrice, item: row.item))
                alertMetricDivider
                alertMetric("关注以来", percentOptional(row.changeSinceFollowPct))
            }

            Divider()

            alertSectionHeader("价格监控", detail: "按当前价格判断")
            VStack(spacing: 0) {
                alertRuleEditor(
                    title: "涨到或高于",
                    icon: "arrow.up.right",
                    tint: AppPalette.marketGain,
                    enabled: $priceAboveEnabled,
                    text: $priceAboveText,
                    placeholder: pricePlaceholder,
                    unit: priceUnit
                )
                Divider().opacity(0.45)
                alertRuleEditor(
                    title: "跌到或低于",
                    icon: "arrow.down.right",
                    tint: AppPalette.marketLoss,
                    enabled: $priceBelowEnabled,
                    text: $priceBelowText,
                    placeholder: pricePlaceholder,
                    unit: priceUnit
                )
            }

            alertSectionHeader("涨跌幅监控", detail: "相对首次关注价判断")
            VStack(spacing: 0) {
                alertRuleEditor(
                    title: "上涨达到",
                    icon: "chart.line.uptrend.xyaxis",
                    tint: AppPalette.marketGain,
                    enabled: $gainEnabled,
                    text: $gainText,
                    placeholder: "例如 8",
                    unit: "%"
                )
                Divider().opacity(0.45)
                alertRuleEditor(
                    title: "下跌达到",
                    icon: "chart.line.downtrend.xyaxis",
                    tint: AppPalette.marketLoss,
                    enabled: $lossEnabled,
                    text: $lossText,
                    placeholder: "例如 5",
                    unit: "%"
                )
            }

            if !inlineErrorMessage.isEmpty {
                ToastBar(
                    text: inlineErrorMessage,
                    tint: AppPalette.danger,
                    onDismiss: { inlineErrorMessage = "" }
                )
            } else if let warningMessage {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(warningMessage)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.warning)
                .padding(9)
                .background(AppPalette.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
            }

            Text("应用运行期间随行情自动检查。条件从未达到变为达到时通知一次；回到阈值另一侧后会重新待命。")
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.muted)

            HStack(spacing: 10) {
                if row.record.hasActiveAlerts {
                    Button("清除全部", role: .destructive) {
                        clearDraft()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("保存中…")
                        }
                    } else {
                        Text(hasAnyEnabledRule || !row.record.hasActiveAlerts ? "保存提醒" : "关闭提醒")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(categoryTint)
                .disabled(isSaving || (!hasAnyEnabledRule && !row.record.hasActiveAlerts))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 500)
    }

    private var hasAnyEnabledRule: Bool {
        priceAboveEnabled || priceBelowEnabled || gainEnabled || lossEnabled
    }

    private var pricePlaceholder: String {
        row.currentPrice.map { alertEditableNumber($0) } ?? "目标价格"
    }

    private var priceUnit: String {
        guard row.item.assetType == .stock else { return "净值" }
        return row.item.detectedStockMarket?.currencySymbol ?? "价格"
    }

    private var warningMessage: String? {
        guard hasAnyEnabledRule else { return nil }
        guard let currentPrice = row.currentPrice, currentPrice.isFinite, currentPrice > 0 else {
            return "当前行情暂不可用；提醒会保存，取得有效价格后开始判断。"
        }
        if (gainEnabled || lossEnabled) && row.record.baseline == nil {
            return "关注价尚未锁定；首次成功刷新后开始判断涨跌幅。"
        }

        var reached: [String] = []
        if priceAboveEnabled, let value = alertDouble(priceAboveText), currentPrice >= value {
            reached.append("高价")
        }
        if priceBelowEnabled, let value = alertDouble(priceBelowText), currentPrice <= value {
            reached.append("低价")
        }
        if let change = row.changeSinceFollowPct {
            if gainEnabled, let value = alertDouble(gainText), change >= value {
                reached.append("涨幅")
            }
            if lossEnabled, let value = alertDouble(lossText), change <= -value {
                reached.append("跌幅")
            }
        }
        guard !reached.isEmpty else { return nil }
        return "当前行情已达到\(reached.joined(separator: "、"))条件；保存后会立即提醒一次。"
    }

    private var categoryTint: Color {
        switch row.category {
        case .offExchangeFund: return AppPalette.brand
        case .onExchangeFund: return AppPalette.accentWarm
        case .stock: return AppPalette.info
        }
    }

    private var alertMetricDivider: some View {
        Rectangle()
            .fill(AppPalette.line.opacity(0.42))
            .frame(width: 1, height: 34)
    }

    private func alertMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private func alertSectionHeader(_ title: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(AppPalette.muted)
            Spacer()
        }
    }

    private func alertRuleEditor(
        title: String,
        icon: String,
        tint: Color,
        enabled: Binding<Bool>,
        text: Binding<String>,
        placeholder: String,
        unit: String
    ) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled.wrappedValue ? tint : AppPalette.muted)
                .frame(width: 15)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled.wrappedValue ? AppPalette.ink : AppPalette.muted)
                .frame(width: 86, alignment: .leading)
            Spacer(minLength: 8)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .inputFieldStyle()
                .frame(width: 142)
                .disabled(!enabled.wrappedValue)
                .opacity(enabled.wrappedValue ? 1 : 0.5)
            Text(unit)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.muted)
                .frame(width: 34, alignment: .leading)
        }
        .padding(.vertical, 5)
    }

    private func clearDraft() {
        priceAboveEnabled = false
        priceBelowEnabled = false
        gainEnabled = false
        lossEnabled = false
        inlineErrorMessage = ""
    }

    private func save() async {
        inlineErrorMessage = ""
        let priceAbove = validatedValue(
            enabled: priceAboveEnabled,
            text: priceAboveText,
            label: "高价提醒"
        )
        guard inlineErrorMessage.isEmpty else { return }
        let priceBelow = validatedValue(
            enabled: priceBelowEnabled,
            text: priceBelowText,
            label: "低价提醒"
        )
        guard inlineErrorMessage.isEmpty else { return }
        let gain = validatedValue(enabled: gainEnabled, text: gainText, label: "上涨幅度")
        guard inlineErrorMessage.isEmpty else { return }
        let loss = validatedValue(enabled: lossEnabled, text: lossText, label: "下跌幅度")
        guard inlineErrorMessage.isEmpty else { return }

        if let priceAbove, let priceBelow, priceBelow >= priceAbove {
            inlineErrorMessage = "低价提醒必须小于高价提醒。"
            return
        }
        if let loss, loss >= 100 {
            inlineErrorMessage = "下跌幅度需大于 0 且小于 100%。"
            return
        }

        let rules = PersonalWatchlistAlertRules(
            priceAbove: priceAbove,
            priceBelow: priceBelow,
            gainSinceFollowPct: gain,
            lossSinceFollowPct: loss
        )
        isSaving = true
        defer { isSaving = false }
        if await model.setPersonalWatchlistAlertRules(rules.isEmpty ? nil : rules, for: row.id) {
            dismiss()
        } else {
            inlineErrorMessage = model.errorMessage.isEmpty ? "提醒保存失败，请稍后重试。" : model.errorMessage
            model.errorMessage = ""
        }
    }

    private func validatedValue(enabled: Bool, text: String, label: String) -> Double? {
        guard enabled else { return nil }
        guard let value = alertDouble(text), value.isFinite, value > 0 else {
            inlineErrorMessage = "\(label)请输入大于 0 的数字。"
            return nil
        }
        return value
    }
}

struct PersonalWatchlistAddSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var category: PersonalWatchlistCategory = .offExchangeFund
    @State private var codeText = ""
    @State private var resolution: PersonalAssetCodeResolution?
    @State private var isResolving = false
    @State private var isSaving = false
    @State private var inlineErrorMessage = ""
    @FocusState private var isCodeFocused: Bool

    private var lookupKey: String {
        "\(category.rawValue):\(codeText.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: category == .stock ? "chart.line.uptrend.xyaxis" : "star.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(categoryTint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加关注")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text("选择标的类型并输入代码。加入时会读取当前有效价格，作为之后对比的固定起点。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }

            Picker("类型", selection: $category) {
                ForEach(PersonalWatchlistCategory.allCases) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("代码")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                TextField(codePlaceholder, text: $codeText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($isCodeFocused)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(AppPalette.controlFill, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                            .stroke(AppPalette.line.opacity(0.48), lineWidth: 1)
                    )
            }

            lookupStatus

            if !inlineErrorMessage.isEmpty {
                ToastBar(
                    text: inlineErrorMessage,
                    tint: AppPalette.danger,
                    onDismiss: { inlineErrorMessage = "" }
                )
            }

            HStack(spacing: 10) {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("读取起始价…")
                        }
                    } else {
                        Text("开始关注")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(categoryTint)
                .disabled(resolution == nil || isResolving || isSaving)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 440)
        .task {
            isCodeFocused = true
        }
        .task(id: lookupKey) {
            await resolveCode()
        }
    }

    @ViewBuilder
    private var lookupStatus: some View {
        HStack(spacing: AppPalette.spaceS) {
            if isResolving {
                ProgressView()
                    .controlSize(.small)
                Text("正在确认代码与名称…")
            } else if let resolution {
                Image(systemName: "checkmark.circle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolution.displayName ?? "未查到名称，将按代码保存")
                        .fontWeight(.semibold)
                    Text("\(category.displayName) · \(resolution.code)")
                        .font(.system(size: 9, design: .monospaced))
                }
            } else if codeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "info.circle")
                Text("输入代码后会自动核对标的。")
            } else {
                Image(systemName: "exclamationmark.circle")
                Text("暂未识别这个代码，请检查类型与代码。")
            }
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(resolution == nil ? AppPalette.muted : categoryTint)
        .padding(.horizontal, 10)
        .padding(.vertical, AppPalette.spaceS)
        .background(
            (resolution == nil ? AppPalette.muted : categoryTint)
                .opacity(AppPalette.accentSubtle),
            in: RoundedRectangle(cornerRadius: AppPalette.cardRadius)
        )
    }

    private var categoryTint: Color {
        switch category {
        case .offExchangeFund: return AppPalette.brand
        case .onExchangeFund: return AppPalette.accentWarm
        case .stock: return AppPalette.info
        }
    }

    private var codePlaceholder: String {
        switch category {
        case .offExchangeFund: return "例如 021550"
        case .onExchangeFund: return "例如 510300 / 159915"
        case .stock: return "例如 600519 / HK:00700 / US:AAPL"
        }
    }

    private func resolveCode() async {
        resolution = nil
        inlineErrorMessage = ""
        let code = codeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            isResolving = false
            return
        }

        isResolving = true
        do {
            try await Task.sleep(nanoseconds: 350_000_000)
        } catch {
            isResolving = false
            return
        }
        guard !Task.isCancelled else {
            isResolving = false
            return
        }
        resolution = await model.resolvePersonalWatchlistCode(category: category, codeText: code)
        isResolving = false
    }

    private func save() async {
        guard let resolution else { return }
        inlineErrorMessage = ""
        isSaving = true
        defer { isSaving = false }

        if await model.addPersonalWatchlistItem(category: category, resolution: resolution) {
            dismiss()
        } else {
            inlineErrorMessage = model.errorMessage.isEmpty ? "添加关注失败，请稍后重试。" : model.errorMessage
            model.errorMessage = ""
        }
    }
}

private func watchlistPriceText(_ value: Double?, item: PersonalWatchlistItem) -> String {
    guard let value else { return "—" }
    let number = decimalText(value)
    guard item.assetType == .stock, let market = item.detectedStockMarket else { return number }
    return "\(market.currencySymbol)\(number)"
}

private func watchlistAxisPrice(_ value: Double) -> String {
    if abs(value) >= 1_000 {
        return String(format: "%.0f", value)
    }
    if abs(value) >= 10 {
        return String(format: "%.2f", value)
    }
    return String(format: "%.4f", value)
}

private func alertEditableNumber(_ value: Double?) -> String {
    guard let value else { return "" }
    var text = String(format: "%.4f", value)
    while text.contains(".") && text.last == "0" {
        text.removeLast()
    }
    if text.last == "." {
        text.removeLast()
    }
    return text
}

private func alertDouble(_ text: String) -> Double? {
    Double(
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
    )
}

private func watchlistAlertRulesText(
    _ rules: PersonalWatchlistAlertRules,
    item: PersonalWatchlistItem
) -> String {
    var parts: [String] = []
    if let value = rules.priceAbove {
        parts.append("≥ \(watchlistPriceText(value, item: item))")
    }
    if let value = rules.priceBelow {
        parts.append("≤ \(watchlistPriceText(value, item: item))")
    }
    if let value = rules.gainSinceFollowPct {
        parts.append("涨幅 ≥ \(String(format: "%.2f%%", value))")
    }
    if let value = rules.lossSinceFollowPct {
        parts.append("跌幅 ≥ \(String(format: "%.2f%%", value))")
    }
    return parts.joined(separator: " · ")
}
