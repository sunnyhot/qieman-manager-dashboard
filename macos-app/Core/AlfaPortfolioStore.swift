import Foundation

/// alfa 投顾组合列表的持久化（纯函数式 load/save，状态由 AppModel 持有）。
/// 仿 `InvestmentPlansStore` / `ManagerWatchStore` 的范式。
struct AlfaPortfolioStore {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load(from fileURL: URL) -> [AlfaPortfolioCatalogItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Self.defaultPortfolios
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decoder.decode([AlfaPortfolioCatalogItem].self, from: data)
            return decoded.isEmpty ? Self.defaultPortfolios : decoded
        } catch {
            return Self.defaultPortfolios
        }
    }

    func save(_ portfolios: [AlfaPortfolioCatalogItem], to fileURL: URL) throws {
        let data = try encoder.encode(portfolios)
        try data.write(to: fileURL, options: .atomic)
    }

    /// 默认预置组合（开箱即用）：晓磊「基金全磊打之大航海时代」。
    static let defaultPortfolios: [AlfaPortfolioCatalogItem] = [
        AlfaPortfolioCatalogItem(
            poCode: "SI000192",
            name: "基金全磊打之大航海时代",
            author: "杨晓磊",
            category: "长钱"
        ),
    ]
}
