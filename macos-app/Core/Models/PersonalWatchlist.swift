import Foundation

enum PersonalWatchlistCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case offExchangeFund = "off_exchange_fund"
    case onExchangeFund = "on_exchange_fund"
    case stock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .offExchangeFund:
            return "场外基金"
        case .onExchangeFund:
            return "场内基金"
        case .stock:
            return "股票"
        }
    }

    var assetType: PersonalAssetType {
        self == .stock ? .stock : .fund
    }

    var fundMarket: FundMarket? {
        switch self {
        case .offExchangeFund:
            return .offExchange
        case .onExchangeFund:
            return .onExchange
        case .stock:
            return nil
        }
    }
}

struct PersonalWatchlistItem: Codable, Hashable, Identifiable {
    let id: UUID
    let code: String
    let displayName: String?
    let assetType: PersonalAssetType
    let stockMarket: StockMarket?
    let fundMarket: FundMarket?
    let followedAt: String

    init(
        id: UUID = UUID(),
        code: String,
        displayName: String?,
        assetType: PersonalAssetType,
        stockMarket: StockMarket? = nil,
        fundMarket: FundMarket? = nil,
        followedAt: String
    ) {
        self.id = id
        self.code = code
        self.displayName = displayName
        self.assetType = assetType
        self.stockMarket = stockMarket
        self.fundMarket = fundMarket
        self.followedAt = followedAt
    }

    var normalizedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedName: String? {
        let value = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    var detectedStockMarket: StockMarket? {
        guard assetType == .stock else { return nil }
        return stockMarket ?? UserPortfolioHolding.detectStockMarket(from: normalizedCode)
    }

    var detectedFundMarket: FundMarket? {
        guard assetType == .fund else { return nil }
        return fundMarket ?? UserPortfolioHolding.detectFundMarket(from: normalizedCode)
    }

    var category: PersonalWatchlistCategory {
        if assetType == .stock {
            return .stock
        }
        return detectedFundMarket == .onExchange ? .onExchangeFund : .offExchangeFund
    }

    var marketLabel: String {
        if let detectedStockMarket {
            return detectedStockMarket.displayName
        }
        return category.displayName
    }

    var identityKey: String {
        let market: String
        if assetType == .stock {
            market = detectedStockMarket?.rawValue ?? "a"
        } else {
            market = detectedFundMarket?.rawValue ?? FundMarket.offExchange.rawValue
        }
        return "\(assetType.rawValue):\(market):\(normalizedCode.lowercased())"
    }

    var followedDate: String {
        Self.normalizedDate(followedAt)
    }

    func replacingDisplayName(_ name: String?) -> PersonalWatchlistItem {
        PersonalWatchlistItem(
            id: id,
            code: code,
            displayName: name ?? displayName,
            assetType: assetType,
            stockMarket: stockMarket,
            fundMarket: fundMarket,
            followedAt: followedAt
        )
    }

    static func normalizedDate(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 10 ? String(trimmed.prefix(10)) : trimmed
    }
}

struct PersonalWatchlistBaseline: Codable, Hashable {
    let price: Double
    let quotedAt: String?
    let capturedAt: String
    let sourceLabel: String?
}

struct PersonalWatchlistDailyPoint: Codable, Hashable, Identifiable {
    let date: String
    let price: Double
    let quotedAt: String?
    let sourceLabel: String?

    var id: String { date }

    init(date: String, price: Double, quotedAt: String? = nil, sourceLabel: String? = nil) {
        self.date = PersonalWatchlistItem.normalizedDate(date)
        self.price = price
        self.quotedAt = quotedAt
        self.sourceLabel = sourceLabel
    }
}

enum PersonalWatchlistAlertKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case priceAbove = "price_above"
    case priceBelow = "price_below"
    case gainSinceFollow = "gain_since_follow"
    case lossSinceFollow = "loss_since_follow"

    var id: String { rawValue }
}

struct PersonalWatchlistAlertRules: Codable, Hashable {
    let priceAbove: Double?
    let priceBelow: Double?
    let gainSinceFollowPct: Double?
    let lossSinceFollowPct: Double?

    init(
        priceAbove: Double? = nil,
        priceBelow: Double? = nil,
        gainSinceFollowPct: Double? = nil,
        lossSinceFollowPct: Double? = nil
    ) {
        self.priceAbove = Self.validPositiveValue(priceAbove)
        self.priceBelow = Self.validPositiveValue(priceBelow)
        self.gainSinceFollowPct = Self.validPositiveValue(gainSinceFollowPct)
        self.lossSinceFollowPct = Self.validPositiveValue(lossSinceFollowPct)
    }

    var isEmpty: Bool {
        priceAbove == nil
            && priceBelow == nil
            && gainSinceFollowPct == nil
            && lossSinceFollowPct == nil
    }

    var ruleCount: Int {
        [priceAbove, priceBelow, gainSinceFollowPct, lossSinceFollowPct]
            .compactMap { $0 }
            .count
    }

    var configuredKinds: Set<PersonalWatchlistAlertKind> {
        var kinds = Set<PersonalWatchlistAlertKind>()
        if priceAbove != nil { kinds.insert(.priceAbove) }
        if priceBelow != nil { kinds.insert(.priceBelow) }
        if gainSinceFollowPct != nil { kinds.insert(.gainSinceFollow) }
        if lossSinceFollowPct != nil { kinds.insert(.lossSinceFollow) }
        return kinds
    }

    private static func validPositiveValue(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

struct PersonalWatchlistAlertState: Codable, Hashable {
    var breachedKinds: Set<PersonalWatchlistAlertKind>
    var lastTriggeredAtByKind: [PersonalWatchlistAlertKind: String]

    init(
        breachedKinds: Set<PersonalWatchlistAlertKind> = [],
        lastTriggeredAtByKind: [PersonalWatchlistAlertKind: String] = [:]
    ) {
        self.breachedKinds = breachedKinds
        self.lastTriggeredAtByKind = lastTriggeredAtByKind
    }

    var isTriggered: Bool { !breachedKinds.isEmpty }
}

struct PersonalWatchlistRecord: Codable, Hashable, Identifiable {
    static let maximumDailyPointCount = 730

    let item: PersonalWatchlistItem
    let baseline: PersonalWatchlistBaseline?
    let dailyPoints: [PersonalWatchlistDailyPoint]
    let alertRules: PersonalWatchlistAlertRules?
    let alertState: PersonalWatchlistAlertState?

    var id: UUID { item.id }

    init(
        item: PersonalWatchlistItem,
        baseline: PersonalWatchlistBaseline? = nil,
        dailyPoints: [PersonalWatchlistDailyPoint] = [],
        alertRules: PersonalWatchlistAlertRules? = nil,
        alertState: PersonalWatchlistAlertState? = nil
    ) {
        self.item = item
        self.baseline = baseline
        self.dailyPoints = Self.mergingDailyPoints(dailyPoints)
        let normalizedRules = alertRules.flatMap { $0.isEmpty ? nil : $0 }
        self.alertRules = normalizedRules
        if let normalizedRules {
            let configuredKinds = normalizedRules.configuredKinds
            var normalizedState = alertState ?? PersonalWatchlistAlertState()
            normalizedState.breachedKinds.formIntersection(configuredKinds)
            normalizedState.lastTriggeredAtByKind = normalizedState.lastTriggeredAtByKind.filter {
                configuredKinds.contains($0.key)
            }
            self.alertState = normalizedState
        } else {
            self.alertState = nil
        }
    }

    var effectiveAlertState: PersonalWatchlistAlertState {
        alertState ?? PersonalWatchlistAlertState()
    }

    var hasActiveAlerts: Bool {
        alertRules?.isEmpty == false
    }

    func updating(
        displayName: String? = nil,
        baseline proposedBaseline: PersonalWatchlistBaseline? = nil,
        appending points: [PersonalWatchlistDailyPoint] = []
    ) -> PersonalWatchlistRecord {
        PersonalWatchlistRecord(
            item: item.replacingDisplayName(displayName),
            baseline: baseline ?? proposedBaseline,
            dailyPoints: Self.mergingDailyPoints(dailyPoints + points),
            alertRules: alertRules,
            alertState: alertState
        )
    }

    func replacingAlertRules(_ rules: PersonalWatchlistAlertRules?) -> PersonalWatchlistRecord {
        PersonalWatchlistRecord(
            item: item,
            baseline: baseline,
            dailyPoints: dailyPoints,
            alertRules: rules,
            alertState: PersonalWatchlistAlertState()
        )
    }

    func replacingAlertState(_ state: PersonalWatchlistAlertState) -> PersonalWatchlistRecord {
        PersonalWatchlistRecord(
            item: item,
            baseline: baseline,
            dailyPoints: dailyPoints,
            alertRules: alertRules,
            alertState: state
        )
    }

    static func mergingDailyPoints(
        _ points: [PersonalWatchlistDailyPoint],
        limit: Int = maximumDailyPointCount
    ) -> [PersonalWatchlistDailyPoint] {
        guard limit > 0 else { return [] }
        var latestByDate: [String: PersonalWatchlistDailyPoint] = [:]
        for point in points {
            let date = PersonalWatchlistItem.normalizedDate(point.date)
            guard !date.isEmpty, point.price.isFinite, point.price > 0 else { continue }
            latestByDate[date] = PersonalWatchlistDailyPoint(
                date: date,
                price: point.price,
                quotedAt: point.quotedAt,
                sourceLabel: point.sourceLabel
            )
        }
        return Array(
            latestByDate.values
                .sorted { $0.date < $1.date }
                .suffix(limit)
        )
    }
}

struct PersonalWatchlistQuoteRow: Hashable, Identifiable {
    let record: PersonalWatchlistRecord
    let assetName: String
    let currentPrice: Double?
    let quotedAt: String?
    let sourceLabel: String?
    let dailyChangePct: Double?
    let dailyPoints: [PersonalWatchlistDailyPoint]

    var id: UUID { record.id }
    var item: PersonalWatchlistItem { record.item }
    var category: PersonalWatchlistCategory { item.category }

    var displayName: String {
        let resolved = assetName.trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved.isEmpty ? (item.normalizedName ?? item.normalizedCode) : resolved
    }

    var changeSinceFollowAmount: Double? {
        guard let currentPrice, let baseline = record.baseline?.price, baseline > 0 else { return nil }
        return currentPrice - baseline
    }

    var changeSinceFollowPct: Double? {
        guard let currentPrice, let baseline = record.baseline?.price, baseline > 0 else { return nil }
        return (currentPrice / baseline - 1) * 100
    }

    var latestRecordedDate: String? {
        dailyPoints.last?.date
    }

    func replacingRecord(_ record: PersonalWatchlistRecord) -> PersonalWatchlistQuoteRow {
        PersonalWatchlistQuoteRow(
            record: record,
            assetName: assetName,
            currentPrice: currentPrice,
            quotedAt: quotedAt,
            sourceLabel: sourceLabel,
            dailyChangePct: dailyChangePct,
            dailyPoints: record.dailyPoints
        )
    }
}

struct PersonalWatchlistSnapshot: Hashable {
    let rows: [PersonalWatchlistQuoteRow]
    let refreshedAt: String

    var itemCount: Int { rows.count }
    var quotedItemCount: Int { rows.filter { $0.currentPrice != nil }.count }

    static func local(records: [PersonalWatchlistRecord], refreshedAt: String = "") -> PersonalWatchlistSnapshot {
        let rows = records.map { record in
            PersonalWatchlistQuoteRow(
                record: record,
                assetName: record.item.normalizedName ?? record.item.normalizedCode,
                currentPrice: record.dailyPoints.last?.price ?? record.baseline?.price,
                quotedAt: record.dailyPoints.last?.quotedAt ?? record.baseline?.quotedAt,
                sourceLabel: record.dailyPoints.last?.sourceLabel ?? record.baseline?.sourceLabel,
                dailyChangePct: nil,
                dailyPoints: record.dailyPoints
            )
        }
        return PersonalWatchlistSnapshot(rows: rows, refreshedAt: refreshedAt)
    }
}
