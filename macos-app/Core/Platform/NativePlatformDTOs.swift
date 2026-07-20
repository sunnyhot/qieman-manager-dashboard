import Foundation

// MARK: - Preload orchestration

enum PreloadResult {
    case history(code: String, data: NativeFundHistory)
    case quote(code: String, data: NativeFundQuote)
}

// MARK: - Platform action intermediate DTOs

struct NativePlatformOrder {
    let adjustmentID: Int
    let side: String
    let label: String
    let fundCode: String
    let fundName: String
    let title: String
    let tradeUnit: Int
    let postPlanUnit: Int
    let strategyType: String
    let largeClass: String
    let nav: Double
    let navDate: String
    let buyDate: String
    let orderCountInAdjustment: Int
}

struct NativePlatformActionSeed {
    let actionKey: String
    let adjustmentID: Int
    let adjustmentTitle: String
    let title: String
    let actionTitle: String
    let fundName: String
    let fundCode: String
    let side: String
    let action: String
    let tradeUnit: Int
    let postPlanUnit: Int
    let createdAt: String
    let txnDate: String
    let createdTs: Int
    let txnTs: Int
    let articleURL: String
    let comment: String
    let strategyType: String
    let largeClass: String
    let buyDate: String
    let nav: Double
    let navDate: String
    let orderCountInAdjustment: Int
}

struct NativePlatformAdjustment {
    let adjustmentID: Int
    let title: String
    let createdTs: Int
    let txnTs: Int
    let orderCount: Int
}

// MARK: - Fund history / quote / estimate DTOs

struct NativeFundHistoryEntry {
    let date: String
    let dateKey: Int
    let nav: Double
    let ts: Int
    let changePct: Double?
}

struct NativeFundHistory {
    let fundCode: String
    let fundName: String
    let series: [NativeFundHistoryEntry]
}

struct NativeFundQuote {
    let fundCode: String
    let fundName: String
    let price: Double
    let priceTime: String
    let priceSource: String
    let priceSourceLabel: String
    let officialNav: Double?
    let officialNavDate: String
    let estimatePrice: Double?
    let estimateTime: String
    let estimateChangePct: Double?

    static func empty(_ fundCode: String) -> NativeFundQuote {
        NativeFundQuote(
            fundCode: fundCode,
            fundName: "",
            price: 0,
            priceTime: "",
            priceSource: "",
            priceSourceLabel: "",
            officialNav: nil,
            officialNavDate: "",
            estimatePrice: nil,
            estimateTime: "",
            estimateChangePct: nil
        )
    }
}

struct NativeFundEstimate {
    let fundName: String
    let price: Double?
    let time: String
    let changePct: Double?
    let source: String
    let sourceLabel: String
}

struct NativeStockQuote {
    let stockCode: String
    let stockName: String
    let price: Double
    let priceTime: String
    let priceSource: String
    let priceSourceLabel: String
    let previousClose: Double?
    let changePct: Double?

    var hasUsableData: Bool {
        price > 0 || !stockName.isEmpty
    }

    static func empty(_ stockCode: String) -> NativeStockQuote {
        NativeStockQuote(
            stockCode: stockCode,
            stockName: "",
            price: 0,
            priceTime: "",
            priceSource: "",
            priceSourceLabel: "",
            previousClose: nil,
            changePct: nil
        )
    }
}

struct NativeUserPortfolioPricePayload {
    let assetName: String
    let currentPrice: Double?
    let priceTime: String
    let priceSource: String
    let officialNav: Double?
    let officialNavDate: String
    let estimatePrice: Double?
    let estimatePriceTime: String
    let estimateChangePct: Double?
}
