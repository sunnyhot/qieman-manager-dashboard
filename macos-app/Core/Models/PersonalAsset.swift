import Foundation

enum PersonalAssetType: String, Codable, Hashable, Identifiable {
    case fund
    case stock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fund:
            return "基金"
        case .stock:
            return "股票"
        }
    }

    var draftPrefix: String? {
        switch self {
        case .fund:
            return nil
        case .stock:
            return "股票"
        }
    }
}

enum StockMarket: String, Codable, Hashable, CaseIterable {
    case aShare = "a"
    case hk = "hk"
    case us = "us"

    var displayName: String {
        switch self {
        case .aShare: return "A股"
        case .hk: return "港股"
        case .us: return "美股"
        }
    }

    var currencySymbol: String {
        switch self {
        case .aShare: return "¥"
        case .hk: return "HK$"
        case .us: return "$"
        }
    }
}

enum FundMarket: String, Codable, Hashable, CaseIterable {
    case offExchange = "off_exchange"
    case onExchange = "on_exchange"

    var displayName: String {
        switch self {
        case .offExchange:
            return "场外基金"
        case .onExchange:
            return "场内基金"
        }
    }
}
