import Foundation

/// 且慢 alfa 投顾组合目录项（来自 `/m4/hand-picked` 推荐 + 用户手动添加）。
struct AlfaPortfolioCatalogItem: Identifiable, Hashable, Codable {
    /// 组合代码，同时作为 GraphQL 的 `poCode`（如 "SI000192" / "ZH045531"）。
    let poCode: String
    /// 组合名称（如 "基金全磊打之大航海时代"）。
    let name: String
    /// 主理人/机构（如 "盈米基金" / "南方基金"）。
    let author: String
    /// 资金分类（如 "长钱" / "稳钱" / "短钱"），来自 hand-picked 分组。
    let category: String

    var id: String { poCode }
}
