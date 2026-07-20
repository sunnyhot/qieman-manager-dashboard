import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "总览"
    case portfolio = "我的持仓"
    case platform = "平台调仓"
    case forum = "论坛发言"
    case enhancement = "工作台"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview:
            return "rectangle.grid.2x2"
        case .portfolio:
            return "briefcase"
        case .settings:
            return "gearshape"
        case .platform:
            return "chart.bar.xaxis"
        case .forum:
            return "text.bubble"
        case .enhancement:
            return "sparkles"
        }
    }
}

enum PersonalDataImportTarget: String, CaseIterable, Identifiable, Codable {
    case holdings = "持仓中"
    case pendingTrades = "买入中"
    case investmentPlans = "定投计划"

    var id: String { rawValue }

    var buttonTitle: String {
        switch self {
        case .holdings:
            return "保存持仓"
        case .pendingTrades:
            return "保存买入中"
        case .investmentPlans:
            return "保存计划"
        }
    }

    var sampleText: String {
        switch self {
        case .holdings:
            return "示例：021550 1200 1.1304；场内基金 510300 100 3.8；股票 600519 10 1500；港股 00700 100 350"
        case .pendingTrades:
            return "示例：2026-04-23 09:48:33 | 定投 | 019524 | 10.00元 | 交易进行中"
        case .investmentPlans:
            return "示例：定投 | 013308 | 每周三定投 | 500.00元 | 2 | 1000.00元 | 余额宝 | 2026-04-29(星期三) | 进行中"
        }
    }

    var helpText: String {
        switch self {
        case .holdings:
            return "支持 代码 份额 成本价 和 场内基金/股票/港股/美股 代码 数量 成本价 格式；ETF:、LOF:、EX: 或常见 ETF 前缀会归为场内基金。名称会保存时按代码自动补全。"
        case .pendingTrades:
            return "支持时间、动作、基金代码或名称、金额/份额、状态五列；保存时会按基金代码自动补全名称。"
        case .investmentPlans:
            return "支持计划类型、基金代码或名称、计划说明、金额、期数、累计、支付方式、下次时间，也支持“进行中 / 已暂停 / 已终止”状态。"
        }
    }
}

enum PersonalDataSaveMode: String, CaseIterable, Identifiable, Codable {
    case merge = "合并更新"
    case replace = "替换该类"

    var id: String { rawValue }

    var actionText: String {
        switch self {
        case .merge:
            return "合并"
        case .replace:
            return "替换"
        }
    }
}

enum PersonalAssetDeleteScope: String, CaseIterable, Identifiable {
    case holding
    case pendingTrades
    case investmentPlans
    case all

    var id: String { rawValue }

    var includesHolding: Bool {
        self == .holding || self == .all
    }

    var includesPendingTrades: Bool {
        self == .pendingTrades || self == .all
    }

    var includesInvestmentPlans: Bool {
        self == .investmentPlans || self == .all
    }
}

enum PersonalAssetUnitAdjustmentMode: String, Identifiable {
    case add
    case remove

    var id: String { rawValue }
}

struct PersonalAssetCodeResolution: Hashable {
    let assetType: PersonalAssetType
    let code: String
    let displayName: String?
    let stockMarket: StockMarket?
    let fundMarket: FundMarket?

    init(
        assetType: PersonalAssetType,
        code: String,
        displayName: String?,
        stockMarket: StockMarket? = nil,
        fundMarket: FundMarket? = nil
    ) {
        self.assetType = assetType
        self.code = code
        self.displayName = displayName
        self.stockMarket = stockMarket
        self.fundMarket = fundMarket
    }
}
