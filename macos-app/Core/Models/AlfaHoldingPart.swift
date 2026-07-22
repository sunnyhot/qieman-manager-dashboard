import Foundation

/// alfa 投顾组合的当前持仓成分（来自 `PoFundComposition` GraphQL query）。
/// 与长赢的 `HoldingItemPayload`（份数口径）不同，这是百分比口径：占比 + 净值 + 日涨跌。
struct AlfaHoldingPart: Identifiable, Hashable {
    /// 来源组合码（汇总筛选用）。
    let sourcePoCode: String
    let fundCode: String
    let fundName: String
    /// 目标占比（0~1）。
    let percent: Double
    /// 最新净值。
    let nav: Double?
    /// 净值日期（yyyy-MM-dd）。
    let navDate: String?
    /// 日涨跌（小数，如 0.005 = +0.5%）。
    let dailyReturn: Double?
    /// 品种/分组类别码。
    let categoryCode: String?
    /// 品种名称（如"权益"/"债券"）。
    let varietyName: String?

    var id: String { "\(sourcePoCode):\(fundCode)" }

    /// 占比百分比文本，如 "12.02%"。
    var percentText: String {
        String(format: "%.2f%%", percent * 100)
    }

    /// 日涨跌百分比文本，如 "+0.52%"，无值则 "—"。
    var dailyReturnText: String {
        guard let dailyReturn else { return "—" }
        return String(format: "%+.2f%%", dailyReturn * 100)
    }
}
