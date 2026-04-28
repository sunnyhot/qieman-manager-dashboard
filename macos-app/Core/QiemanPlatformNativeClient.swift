import CryptoKit
import Foundation

enum NativePlatformError: LocalizedError {
    case missingProdCode
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingProdCode:
            return "没有产品代码，无法直拉平台调仓记录。"
        case .invalidResponse:
            return "平台调仓接口返回结构异常。"
        case .api(let message):
            return message
        }
    }
}

fileprivate actor QiemanPlatformCache {
    private var payloads: [String: (Date, PlatformPayload)] = [:]
    private var histories: [String: (Date, NativeFundHistory)] = [:]
    private var quotes: [String: (Date, NativeFundQuote)] = [:]
    private var stockQuotes: [String: (Date, NativeStockQuote)] = [:]

    func payload(for prodCode: String, ttl: TimeInterval) -> PlatformPayload? {
        guard let (loadedAt, payload) = payloads[prodCode], Date().timeIntervalSince(loadedAt) < ttl else {
            return nil
        }
        return payload
    }

    func store(payload: PlatformPayload, for prodCode: String) {
        payloads[prodCode] = (Date(), payload)
    }

    func history(for fundCode: String, ttl: TimeInterval) -> NativeFundHistory? {
        guard let (loadedAt, history) = histories[fundCode], Date().timeIntervalSince(loadedAt) < ttl else {
            return nil
        }
        return history
    }

    func store(history: NativeFundHistory, for fundCode: String) {
        histories[fundCode] = (Date(), history)
    }

    func quote(for fundCode: String, ttl: TimeInterval) -> NativeFundQuote? {
        guard let (loadedAt, quote) = quotes[fundCode], Date().timeIntervalSince(loadedAt) < ttl else {
            return nil
        }
        return quote
    }

    func store(quote: NativeFundQuote, for fundCode: String) {
        quotes[fundCode] = (Date(), quote)
    }

    func stockQuote(for stockCode: String, ttl: TimeInterval) -> NativeStockQuote? {
        guard let (loadedAt, quote) = stockQuotes[stockCode], Date().timeIntervalSince(loadedAt) < ttl else {
            return nil
        }
        return quote
    }

    func store(stockQuote: NativeStockQuote, for stockCode: String) {
        stockQuotes[stockCode] = (Date(), stockQuote)
    }
}

final class QiemanPlatformNativeClient {
    private let baseURL = URL(string: "https://qieman.com")!
    private let apiBase = "/pmdj/v2"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private let anonymousID = "anon-\(QiemanPlatformNativeClient.sha256Hex(UUID().uuidString).prefix(16))"
    private let payloadTTL: TimeInterval = 120
    private let historyTTL: TimeInterval = 12 * 60 * 60
    private let quoteTTL: TimeInterval = 5 * 60
    private let cache = QiemanPlatformCache()

    func fetchPlatformPayload(prodCode: String) async throws -> PlatformPayload {
        let target = normalizedString(prodCode)
        guard !target.isEmpty else {
            throw NativePlatformError.missingProdCode
        }
        if let cached = await cache.payload(for: target, ttl: payloadTTL) {
            return cached
        }

        let raw = try await requestAdjustments(prodCode: target)
        let payload = try await buildPlatformPayload(prodCode: target, rawItems: raw)
        await cache.store(payload: payload, for: target)
        return payload
    }

    func fetchUserPortfolioSnapshot(holdings: [UserPortfolioHolding]) async throws -> UserPortfolioSnapshot {
        let normalizedHoldings = holdings.filter { !$0.normalizedFundCode.isEmpty && $0.units > 0 }
        guard !normalizedHoldings.isEmpty else {
            return UserPortfolioSnapshot(
                rows: [],
                refreshedAt: isoTimestampNow(),
                totalMarketValue: 0,
                totalCostValue: nil,
                totalProfitAmount: nil,
                totalProfitPct: nil
            )
        }

        let fundCodes = Array(Set(normalizedHoldings.filter { $0.assetType == .fund }.map(\.normalizedFundCode)))
        let stockCodes = Array(Set(normalizedHoldings.filter { $0.assetType == .stock }.map(\.normalizedFundCode)))
        let histories = await preloadHistories(fundCodes)
        let quotes = await preloadQuotes(fundCodes, histories: histories)
        let stockQuotes = await preloadStockQuotes(stockCodes)

        let rows = normalizedHoldings.map { holding -> UserPortfolioValuationRow in
            let pricePayload = userPortfolioPricePayload(
                for: holding,
                histories: histories,
                quotes: quotes,
                stockQuotes: stockQuotes
            )
            let resolvedPrice = pricePayload.currentPrice ?? pricePayload.officialNav
            let marketValue = resolvedPrice.map { round($0 * holding.units, digits: 2) }
            let costValue = holding.costPrice.map { round($0 * holding.units, digits: 2) }
            let profitAmount = zipOptional(marketValue, costValue).map { round($0.0 - $0.1, digits: 2) }
            let profitPct = zipOptional(profitAmount, costValue).flatMap { pair -> Double? in
                let profit = pair.0
                let cost = pair.1
                guard cost > 0 else { return nil }
                return round(profit / cost * 100, digits: 2)
            }

            return UserPortfolioValuationRow(
                holding: holding,
                fundName: firstNonEmpty([
                    holding.normalizedName ?? "",
                    pricePayload.assetName,
                    holding.normalizedFundCode,
                ]),
                currentPrice: pricePayload.currentPrice.map { round($0, digits: 4) },
                priceTime: pricePayload.priceTime.nilIfEmpty,
                priceSource: pricePayload.priceSource.nilIfEmpty,
                officialNav: pricePayload.officialNav.map { round($0, digits: 4) },
                officialNavDate: pricePayload.officialNavDate.nilIfEmpty,
                marketValue: marketValue,
                costValue: costValue,
                profitAmount: profitAmount,
                profitPct: profitPct,
                estimateChangePct: pricePayload.estimateChangePct
            )
        }

        let totalMarketValue = round(rows.compactMap(\.marketValue).reduce(0, +), digits: 2)
        let costRows = rows.compactMap(\.costValue)
        let profitRows = rows.compactMap(\.profitAmount)
        let totalCostValue = costRows.isEmpty ? nil : round(costRows.reduce(0, +), digits: 2)
        let totalProfitAmount = profitRows.isEmpty ? nil : round(profitRows.reduce(0, +), digits: 2)
        let totalProfitPct: Double?
        if let totalCostValue, totalCostValue > 0, let totalProfitAmount {
            totalProfitPct = round(totalProfitAmount / totalCostValue * 100, digits: 2)
        } else {
            totalProfitPct = nil
        }

        return UserPortfolioSnapshot(
            rows: rows.sorted { ($0.marketValue ?? 0) > ($1.marketValue ?? 0) },
            refreshedAt: isoTimestampNow(),
            totalMarketValue: totalMarketValue,
            totalCostValue: totalCostValue,
            totalProfitAmount: totalProfitAmount,
            totalProfitPct: totalProfitPct
        )
    }

    func resolveAssetNames(holdings: [UserPortfolioHolding]) async -> [UUID: String] {
        let fundCodes = Array(Set(holdings.filter { $0.assetType == .fund }.map(\.normalizedFundCode).filter { !$0.isEmpty }))
        let stockCodes = Array(Set(holdings.filter { $0.assetType == .stock }.map(\.normalizedFundCode).filter { !$0.isEmpty }))

        let fundNamesByCode = await resolveFundNames(fundCodes: fundCodes)
        let stockQuotes = await preloadStockQuotes(stockCodes)

        var names: [UUID: String] = [:]
        for holding in holdings {
            switch holding.assetType {
            case .fund:
                if let name = fundNamesByCode[holding.normalizedFundCode], !name.isEmpty {
                    names[holding.id] = name
                }
            case .stock:
                if let name = stockQuotes[holding.normalizedFundCode]?.stockName, !name.isEmpty {
                    names[holding.id] = name
                }
            }
        }
        return names
    }

    func resolveAssetName(assetType: PersonalAssetType, code: String) async -> String? {
        let holding = UserPortfolioHolding(
            fundCode: code,
            assetType: assetType,
            units: 1,
            costPrice: nil,
            displayName: nil
        )
        return await resolveAssetNames(holdings: [holding])[holding.id]
    }

    func resolveFundNames(fundCodes: [String]) async -> [String: String] {
        let normalizedCodes = Array(Set(fundCodes.map(normalizedString).filter { !$0.isEmpty }))
        guard !normalizedCodes.isEmpty else { return [:] }

        let histories = await preloadHistories(normalizedCodes)
        let quotes = await preloadQuotes(normalizedCodes, histories: histories)

        var names: [String: String] = [:]
        for code in normalizedCodes {
            let name = firstNonEmpty([
                quotes[code]?.fundName ?? "",
                histories[code]?.fundName ?? "",
            ])
            if !name.isEmpty {
                names[code] = name
            }
        }
        return names
    }

    private func userPortfolioPricePayload(
        for holding: UserPortfolioHolding,
        histories: [String: NativeFundHistory],
        quotes: [String: NativeFundQuote],
        stockQuotes: [String: NativeStockQuote]
    ) -> NativeUserPortfolioPricePayload {
        switch holding.assetType {
        case .fund:
            let history = histories[holding.normalizedFundCode]
            let quote = quotes[holding.normalizedFundCode]
            let latestNav = history?.series.last
            return NativeUserPortfolioPricePayload(
                assetName: firstNonEmpty([quote?.fundName ?? "", history?.fundName ?? ""]),
                currentPrice: (quote?.price ?? 0) > 0 ? quote?.price : nil,
                priceTime: firstNonEmpty([quote?.priceTime ?? "", latestNav?.date ?? ""]),
                priceSource: firstNonEmpty([quote?.priceSourceLabel ?? "", quote?.priceSource ?? "", "最新净值"]),
                officialNav: quote?.officialNav ?? latestNav?.nav,
                officialNavDate: firstNonEmpty([quote?.officialNavDate ?? "", latestNav?.date ?? ""]),
                estimateChangePct: quote?.estimateChangePct
            )
        case .stock:
            let quote = stockQuotes[holding.normalizedFundCode]
            return NativeUserPortfolioPricePayload(
                assetName: quote?.stockName ?? "",
                currentPrice: (quote?.price ?? 0) > 0 ? quote?.price : nil,
                priceTime: quote?.priceTime ?? "",
                priceSource: quote?.priceSourceLabel ?? "",
                officialNav: (quote?.previousClose ?? 0) > 0 ? quote?.previousClose : nil,
                officialNavDate: quote?.priceTime ?? "",
                estimateChangePct: quote?.changePct
            )
        }
    }

    private func requestAdjustments(prodCode: String) async throws -> [[String: Any]] {
        let payload = try await requestJSON(
            hostURL: baseURL,
            path: "/long-win/plan/adjustments",
            params: [
                "desc": "true",
                "prodCode": prodCode,
            ],
            headers: [:]
        )
        guard let list = payload as? [[String: Any]] else {
            throw NativePlatformError.invalidResponse
        }
        return list
    }

    private func buildPlatformPayload(prodCode: String, rawItems: [[String: Any]]) async throws -> PlatformPayload {
        var adjustments: [NativePlatformAdjustment] = []
        var actionSeeds: [NativePlatformActionSeed] = []

        for rawItem in rawItems {
            let adjustmentID = intValue(rawItem["adjustmentId"]) ?? 0
            let createdTs = intValue(rawItem["adjustCreateTime"]) ?? 0
            let txnTs = intValue(rawItem["adjustTxnDate"]) ?? 0
            let normalizedOrders = ((rawItem["orders"] as? [[String: Any]]) ?? []).map { normalizePlatformOrder($0, adjustmentID: adjustmentID) }
            let adjustmentTitle = firstNonEmpty([normalizedString(rawItem["comment"]), "调仓 \(adjustmentID)"])
            let articleURL = normalizedString(rawItem["url"])
            let createdAt = formatTime(formatTimestampMs(createdTs))
            let txnDate = formatTime(formatTimestampMs(txnTs))
            var orderCount = 0

            for (index, order) in normalizedOrders.enumerated() {
                let side = order.side
                guard side == "buy" || side == "sell" else { continue }
                orderCount += 1
                let actionTitle = "\(order.label)\(order.tradeUnit)份\(order.title)"
                actionSeeds.append(
                    NativePlatformActionSeed(
                        actionKey: "\(adjustmentID):\(order.fundCode):\(side):\(index + 1)",
                        adjustmentID: adjustmentID,
                        adjustmentTitle: adjustmentTitle,
                        title: order.title,
                        actionTitle: actionTitle,
                        fundName: order.fundName,
                        fundCode: order.fundCode,
                        side: side,
                        action: order.label,
                        tradeUnit: order.tradeUnit,
                        postPlanUnit: order.postPlanUnit,
                        createdAt: createdAt,
                        txnDate: txnDate,
                        createdTs: createdTs,
                        txnTs: txnTs,
                        articleURL: articleURL,
                        comment: adjustmentTitle,
                        strategyType: order.strategyType,
                        largeClass: order.largeClass,
                        buyDate: order.buyDate,
                        nav: order.nav,
                        navDate: order.navDate,
                        orderCountInAdjustment: normalizedOrders.count
                    )
                )
            }

            adjustments.append(
                NativePlatformAdjustment(
                    adjustmentID: adjustmentID,
                    title: adjustmentTitle,
                    createdTs: createdTs,
                    txnTs: txnTs,
                    orderCount: orderCount
                )
            )
        }

        actionSeeds.sort { actionTimestamp($0.txnTs, createdTs: $0.createdTs) > actionTimestamp($1.txnTs, createdTs: $1.createdTs) }
        adjustments.sort { actionTimestamp($0.txnTs, createdTs: $0.createdTs) > actionTimestamp($1.txnTs, createdTs: $1.createdTs) }

        let fundCodes = Array(Set(actionSeeds.map(\.fundCode).filter { !$0.isEmpty }))
        let histories = await preloadHistories(fundCodes)
        let quotes = await preloadQuotes(fundCodes, histories: histories)
        let actions = enrichPlatformActions(actionSeeds, histories: histories, quotes: quotes)
        let holdings = buildHoldings(actions: actions, histories: histories, quotes: quotes)
        let timeline = buildTimeline(actions: actions)

        let buyCount = actions.filter { $0.side == "buy" }.count
        let sellCount = actions.filter { $0.side == "sell" }.count

        return PlatformPayload(
            supported: true,
            prodCode: prodCode,
            count: actions.count,
            buyCount: buyCount,
            sellCount: sellCount,
            adjustmentCount: adjustments.count,
            latest: actions.first,
            actions: actions,
            holdings: holdings,
            timeline: timeline,
            error: nil
        )
    }

    private func enrichPlatformActions(_ seeds: [NativePlatformActionSeed], histories: [String: NativeFundHistory], quotes: [String: NativeFundQuote]) -> [PlatformActionPayload] {
        seeds.map { seed in
            let history = histories[seed.fundCode]
            let quote = quotes[seed.fundCode]

            var tradeValuation = seed.nav
            var tradeValuationDate = normalizeDateText(seed.navDate)
            var tradeValuationSource = "调仓净值"
            if tradeValuation <= 0 {
                let navEntry = lookupNav(history: history, dateText: firstNonEmpty([seed.txnDate, seed.createdAt]))
                tradeValuation = navEntry?.nav ?? 0
                tradeValuationDate = firstNonEmpty([tradeValuationDate, navEntry?.date ?? ""])
                tradeValuationSource = tradeValuation > 0 ? "历史净值回填" : ""
            } else if tradeValuationDate.isEmpty {
                tradeValuationDate = normalizeDateText(firstNonEmpty([seed.txnDate, seed.createdAt]))
            }

            let currentValuation = quote?.price ?? 0
            let currentValuationTime = quote?.priceTime ?? ""
            let currentValuationSource = firstNonEmpty([quote?.priceSourceLabel ?? "", "当前估值"])

            let valuationChangeAmount: Double?
            let valuationChangePct: Double?
            if tradeValuation > 0, currentValuation > 0 {
                valuationChangeAmount = round(currentValuation - tradeValuation, digits: 4)
                valuationChangePct = round((currentValuation / tradeValuation - 1) * 100, digits: 2)
            } else {
                valuationChangeAmount = nil
                valuationChangePct = nil
            }

            return PlatformActionPayload(
                actionKey: seed.actionKey,
                adjustmentId: seed.adjustmentID,
                adjustmentTitle: seed.adjustmentTitle,
                title: seed.title,
                actionTitle: seed.actionTitle,
                fundName: seed.fundName,
                fundCode: seed.fundCode,
                side: seed.side,
                action: seed.action,
                tradeUnit: seed.tradeUnit,
                postPlanUnit: seed.postPlanUnit,
                createdAt: seed.createdAt,
                txnDate: seed.txnDate,
                createdTs: seed.createdTs,
                txnTs: seed.txnTs,
                articleUrl: seed.articleURL,
                comment: seed.comment,
                strategyType: seed.strategyType,
                largeClass: seed.largeClass,
                buyDate: seed.buyDate,
                nav: seed.nav > 0 ? round(seed.nav, digits: 4) : nil,
                navDate: seed.navDate.isEmpty ? nil : seed.navDate,
                orderCountInAdjustment: seed.orderCountInAdjustment,
                tradeValuation: tradeValuation > 0 ? round(tradeValuation, digits: 4) : nil,
                tradeValuationDate: tradeValuationDate.isEmpty ? nil : tradeValuationDate,
                tradeValuationSource: tradeValuationSource.isEmpty ? nil : tradeValuationSource,
                currentValuation: currentValuation > 0 ? round(currentValuation, digits: 4) : nil,
                currentValuationTime: currentValuationTime.isEmpty ? nil : currentValuationTime,
                currentValuationSource: currentValuationSource.isEmpty ? nil : currentValuationSource,
                valuationChangeAmount: valuationChangeAmount,
                valuationChangePct: valuationChangePct
            )
        }
    }

    private func buildHoldings(actions: [PlatformActionPayload], histories: [String: NativeFundHistory], quotes: [String: NativeFundQuote]) -> PlatformHoldingsPayload {
        var latestByAsset: [String: PlatformActionPayload] = [:]
        for action in actions.sorted(by: { actionTimestamp($0.txnTs, createdTs: $0.createdTs) > actionTimestamp($1.txnTs, createdTs: $1.createdTs) }) {
            let assetKey = firstNonEmpty([action.fundCode ?? "", action.title ?? "", action.fundName ?? ""])
            if assetKey.isEmpty || latestByAsset[assetKey] != nil {
                continue
            }
            latestByAsset[assetKey] = action
        }

        var items: [HoldingItemPayload] = []
        for (_, latestAction) in latestByAsset {
            let currentUnits = latestAction.postPlanUnit ?? 0
            guard currentUnits > 0 else { continue }
            let assetKey = firstNonEmpty([latestAction.fundCode ?? "", latestAction.title ?? "", latestAction.fundName ?? ""])
            let relevantActions = actions
                .filter { firstNonEmpty([$0.fundCode ?? "", $0.title ?? "", $0.fundName ?? ""]) == assetKey }
                .sorted(by: { actionTimestamp($0.txnTs, createdTs: $0.createdTs) < actionTimestamp($1.txnTs, createdTs: $1.createdTs) })

            var simulatedUnits = 0
            var totalCost = 0.0
            var coveredActions = 0
            var missingActions = 0
            let history = histories[latestAction.fundCode ?? ""]

            for action in relevantActions {
                let tradeUnits = action.tradeUnit ?? 0
                guard tradeUnits > 0 else { continue }
                var navValue = action.tradeValuation ?? 0
                if navValue <= 0 {
                    navValue = lookupNav(history: history, dateText: firstNonEmpty([action.txnDate ?? "", action.createdAt ?? ""]))?.nav ?? 0
                }
                if navValue <= 0 {
                    missingActions += 1
                    continue
                }
                coveredActions += 1
                if action.side == "buy" {
                    simulatedUnits += tradeUnits
                    totalCost += navValue * Double(tradeUnits)
                } else if action.side == "sell", simulatedUnits > 0 {
                    let sellUnits = min(tradeUnits, simulatedUnits)
                    let averageBeforeSell = simulatedUnits > 0 ? totalCost / Double(simulatedUnits) : 0
                    totalCost -= averageBeforeSell * Double(sellUnits)
                    simulatedUnits -= sellUnits
                    if simulatedUnits <= 0 {
                        simulatedUnits = 0
                        totalCost = 0
                    }
                } else {
                    missingActions += 1
                }
            }

            let avgCost = (currentUnits > 0 && simulatedUnits == currentUnits && totalCost > 0) ? round(totalCost / Double(currentUnits), digits: 4) : nil
            let quote = quotes[latestAction.fundCode ?? ""]
            let currentPrice = (quote?.price ?? 0) > 0 ? round(quote?.price ?? 0, digits: 4) : nil
            let positionCost = (avgCost != nil && currentUnits > 0) ? round((avgCost ?? 0) * Double(currentUnits), digits: 2) : nil
            let positionValue = (currentPrice != nil && currentUnits > 0) ? round((currentPrice ?? 0) * Double(currentUnits), digits: 2) : nil
            let profitAmount = (positionCost != nil && positionValue != nil) ? round((positionValue ?? 0) - (positionCost ?? 0), digits: 2) : nil
            let profitRatio = (avgCost != nil && currentPrice != nil && (avgCost ?? 0) > 0) ? round(((currentPrice ?? 0) / (avgCost ?? 1) - 1) * 100, digits: 2) : nil

            items.append(
                HoldingItemPayload(
                    assetKey: assetKey,
                    label: firstNonEmpty([latestAction.title ?? "", latestAction.fundName ?? "", latestAction.fundCode ?? ""]).nilIfEmpty,
                    fundName: latestAction.fundName,
                    fundCode: latestAction.fundCode,
                    currentUnits: currentUnits,
                    latestAction: latestAction.action,
                    latestActionTitle: latestAction.actionTitle,
                    latestTime: latestAction.txnDate ?? latestAction.createdAt,
                    latestTs: actionTimestamp(latestAction.txnTs, createdTs: latestAction.createdTs),
                    strategyType: latestAction.strategyType,
                    largeClass: latestAction.largeClass,
                    buyDate: latestAction.buyDate,
                    avgCost: avgCost,
                    positionCost: positionCost,
                    currentPrice: currentPrice,
                    priceSource: quote?.priceSource.nilIfEmpty,
                    priceSourceLabel: quote?.priceSourceLabel.nilIfEmpty,
                    priceTime: firstNonEmpty([quote?.priceTime ?? "", quote?.officialNavDate ?? ""]).nilIfEmpty,
                    officialNav: quote?.officialNav,
                    officialNavDate: quote?.officialNavDate.nilIfEmpty,
                    estimateChangePct: quote?.estimateChangePct,
                    positionValue: positionValue,
                    profitRatio: profitRatio,
                    costMethod: avgCost != nil ? "移动平均" : nil,
                    costCoveredActions: coveredActions,
                    costMissingActions: missingActions,
                    costReady: avgCost != nil,
                    quoteReady: currentPrice != nil,
                    estimatedValue: positionValue,
                    profitAmount: profitAmount,
                    profitPct: profitRatio
                )
            )
        }

        items.sort {
            if ($0.currentUnits ?? 0) != ($1.currentUnits ?? 0) {
                return ($0.currentUnits ?? 0) > ($1.currentUnits ?? 0)
            }
            return ($0.latestTs ?? 0) > ($1.latestTs ?? 0)
        }

        let latestItem = items.max(by: { ($0.latestTs ?? 0) < ($1.latestTs ?? 0) })
        return PlatformHoldingsPayload(
            assetCount: items.count,
            totalUnits: items.compactMap(\.currentUnits).reduce(0, +),
            latestTime: latestItem?.latestTime,
            latestTs: latestItem?.latestTs,
            items: items
        )
    }

    private func buildTimeline(actions: [PlatformActionPayload]) -> [PlatformTimelinePayload] {
        var grouped: [String: [PlatformActionPayload]] = [:]
        for action in actions {
            let label = firstNonEmpty([action.title ?? "", action.fundName ?? "", action.fundCode ?? "", "未命名标的"])
            grouped[label, default: []].append(action)
        }

        return grouped.map { label, entries in
            let sortedEntries = entries.sorted { actionTimestamp($0.txnTs, createdTs: $0.createdTs) > actionTimestamp($1.txnTs, createdTs: $1.createdTs) }
            return PlatformTimelinePayload(
                label: label,
                entries: Array(sortedEntries.prefix(12)),
                buyCount: entries.filter { $0.side == "buy" }.count,
                sellCount: entries.filter { $0.side == "sell" }.count,
                eventCount: entries.count,
                latestTime: sortedEntries.first?.txnDate ?? sortedEntries.first?.createdAt,
                latestTs: sortedEntries.first.map { actionTimestamp($0.txnTs, createdTs: $0.createdTs) }
            )
        }
        .sorted {
            if ($0.eventCount ?? 0) != ($1.eventCount ?? 0) {
                return ($0.eventCount ?? 0) > ($1.eventCount ?? 0)
            }
            return ($0.latestTs ?? 0) > ($1.latestTs ?? 0)
        }
    }

    private func preloadHistories(_ fundCodes: [String]) async -> [String: NativeFundHistory] {
        var results: [String: NativeFundHistory] = [:]
        let uniqueCodes = Array(Set(fundCodes.filter { !$0.isEmpty }))
        await withTaskGroup(of: (String, NativeFundHistory).self) { group in
            for code in uniqueCodes {
                group.addTask {
                    if let cached = await self.cache.history(for: code, ttl: self.historyTTL) {
                        return (code, cached)
                    }
                    let history = (try? await self.fetchFundHistorySeries(code)) ?? NativeFundHistory(fundCode: code, fundName: "", series: [])
                    await self.cache.store(history: history, for: code)
                    return (code, history)
                }
            }
            for await (code, history) in group {
                results[code] = history
            }
        }
        return results
    }

    private func preloadQuotes(_ fundCodes: [String], histories: [String: NativeFundHistory]) async -> [String: NativeFundQuote] {
        var results: [String: NativeFundQuote] = [:]
        let uniqueCodes = Array(Set(fundCodes.filter { !$0.isEmpty }))
        await withTaskGroup(of: (String, NativeFundQuote).self) { group in
            for code in uniqueCodes {
                group.addTask {
                    if let cached = await self.cache.quote(for: code, ttl: self.quoteTTL) {
                        return (code, cached)
                    }
                    let quote = (try? await self.fetchFundQuote(code, history: histories[code])) ?? NativeFundQuote.empty(code)
                    await self.cache.store(quote: quote, for: code)
                    return (code, quote)
                }
            }
            for await (code, quote) in group {
                results[code] = quote
            }
        }
        return results
    }

    private func preloadStockQuotes(_ stockCodes: [String]) async -> [String: NativeStockQuote] {
        var results: [String: NativeStockQuote] = [:]
        let uniqueCodes = Array(Set(stockCodes.filter { !$0.isEmpty }))
        await withTaskGroup(of: (String, NativeStockQuote).self) { group in
            for code in uniqueCodes {
                group.addTask {
                    if let cached = await self.cache.stockQuote(for: code, ttl: self.quoteTTL) {
                        return (code, cached)
                    }
                    let quote = (try? await self.fetchStockQuote(code)) ?? NativeStockQuote.empty(code)
                    await self.cache.store(stockQuote: quote, for: code)
                    return (code, quote)
                }
            }
            for await (code, quote) in group {
                results[code] = quote
            }
        }
        return results
    }

    private func fetchFundHistorySeries(_ fundCode: String) async throws -> NativeFundHistory {
        let now = Int(Date().timeIntervalSince1970)
        let url = URL(string: "https://fund.eastmoney.com/pingzhongdata/\(fundCode).js?v=\(now)")!
        let text = try await requestText(hostURL: url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(), absoluteURL: url, headers: [
            "Referer": "https://fund.eastmoney.com/",
        ])

        let name = firstMatch(in: text, pattern: #"var\s+fS_name\s*=\s*"([^"]*)";"#) ?? ""
        guard let trendText = firstMatch(in: text, pattern: #"var\s+Data_netWorthTrend\s*=\s*(\[[\s\S]*?\]);"#),
              let data = trendText.data(using: .utf8),
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return NativeFundHistory(fundCode: fundCode, fundName: name, series: [])
        }

        let series = rows.compactMap { row -> NativeFundHistoryEntry? in
            guard let nav = doubleValue(row["y"]), nav > 0,
                  let ts = intValue(row["x"]), ts > 0 else {
                return nil
            }
            let date = dateTextFromTimestampMs(ts)
            guard !date.isEmpty else { return nil }
            return NativeFundHistoryEntry(date: date, dateKey: dateKey(date), nav: nav, ts: ts)
        }
        return NativeFundHistory(fundCode: fundCode, fundName: name, series: series)
    }

    private func fetchFundQuote(_ fundCode: String, history: NativeFundHistory?) async throws -> NativeFundQuote {
        let now = Int(Date().timeIntervalSince1970)
        let url = URL(string: "https://fundgz.1234567.com.cn/js/\(fundCode).js?rt=\(now)")!
        let text = (try? await requestText(hostURL: url.deletingLastPathComponent().deletingLastPathComponent(), absoluteURL: url, headers: [
            "Referer": "https://fund.eastmoney.com/",
        ])) ?? ""

        if let payloadText = firstMatch(in: text, pattern: #"jsonpgz\((\{[\s\S]*\})\);"#),
           let data = payloadText.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let estimatePrice = doubleValue(object["gsz"]),
           estimatePrice > 0 {
            return NativeFundQuote(
                fundCode: fundCode,
                fundName: normalizedString(object["name"]),
                price: estimatePrice,
                priceTime: normalizedString(object["gztime"]),
                priceSource: "estimate",
                priceSourceLabel: "盘中估值",
                officialNav: doubleValue(object["dwjz"]),
                officialNavDate: normalizedString(object["jzrq"]),
                estimateChangePct: doubleValue(object["gszzl"])
            )
        }

        if let latest = history?.series.last {
            return NativeFundQuote(
                fundCode: fundCode,
                fundName: history?.fundName ?? "",
                price: latest.nav,
                priceTime: latest.date,
                priceSource: "official_nav",
                priceSourceLabel: "最近净值",
                officialNav: latest.nav,
                officialNavDate: latest.date,
                estimateChangePct: nil
            )
        }
        return .empty(fundCode)
    }

    private func fetchStockQuote(_ stockCode: String) async throws -> NativeStockQuote {
        if let quote = try? await fetchEastmoneyStockQuote(stockCode), quote.hasUsableData {
            return quote
        }
        if let quote = try? await fetchTencentStockQuote(stockCode), quote.hasUsableData {
            return quote
        }
        return .empty(stockCode)
    }

    private func fetchEastmoneyStockQuote(_ stockCode: String) async throws -> NativeStockQuote {
        guard let secid = stockSecID(for: stockCode) else {
            return .empty(stockCode)
        }
        let url = URL(string: "https://push2.eastmoney.com/api/qt/stock/get?secid=\(secid)&fields=f43,f57,f58,f59,f60,f169,f170")!
        let text = try await requestText(hostURL: url, absoluteURL: url, headers: [
            "Accept": "application/json",
            "Referer": "https://quote.eastmoney.com/",
        ])
        let payload = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) ?? [:]
        guard let object = payload as? [String: Any],
              let data = object["data"] as? [String: Any],
              let code = normalizedString(data["f57"]).nilIfEmpty else {
            return .empty(stockCode)
        }

        let scale = pow(10.0, Double(intValue(data["f59"]) ?? 2))
        let price = scaledQuoteValue(data["f43"], scale: scale)
        let previousClose = scaledQuoteValue(data["f60"], scale: scale)
        let changePct = scaledQuoteValue(data["f170"], scale: 100)

        return NativeStockQuote(
            stockCode: code,
            stockName: normalizedString(data["f58"]),
            price: price ?? 0,
            priceTime: isoTimestampNow(),
            priceSource: "stock_quote",
            priceSourceLabel: "股票行情",
            previousClose: previousClose,
            changePct: changePct
        )
    }

    private func fetchTencentStockQuote(_ stockCode: String) async throws -> NativeStockQuote {
        guard let symbol = tencentStockSymbol(for: stockCode) else {
            return .empty(stockCode)
        }
        let url = URL(string: "https://qt.gtimg.cn/q=\(symbol)")!
        let text = try await requestText(hostURL: url, absoluteURL: url, headers: [
            "Accept": "text/plain,*/*",
            "Referer": "https://gu.qq.com/",
        ])
        guard let quoted = firstMatch(in: text, pattern: #"="([^"]*)";"#) else {
            return .empty(stockCode)
        }
        let parts = quoted.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 32 else {
            return .empty(stockCode)
        }
        let code = normalizedString(parts[safe: 2]).nilIfEmpty ?? stockCode
        let price = doubleValue(parts[safe: 3]) ?? 0
        let previousClose = doubleValue(parts[safe: 4])
        let changePct = doubleValue(parts[safe: 32])

        return NativeStockQuote(
            stockCode: code,
            stockName: normalizedString(parts[safe: 1]),
            price: price,
            priceTime: formattedTencentQuoteTime(parts[safe: 30]),
            priceSource: "tencent_stock_quote",
            priceSourceLabel: "股票行情",
            previousClose: previousClose,
            changePct: changePct
        )
    }

    private func lookupNav(history: NativeFundHistory?, dateText: String) -> NativeFundHistoryEntry? {
        guard let history else { return nil }
        let targetKey = dateKey(dateText)
        guard targetKey > 0, !history.series.isEmpty else { return nil }
        var low = 0
        var high = history.series.count
        while low < high {
            let mid = (low + high) / 2
            if history.series[mid].dateKey <= targetKey {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let index = low - 1
        guard index >= 0, index < history.series.count else { return nil }
        return history.series[index]
    }

    private func normalizePlatformOrder(_ order: [String: Any], adjustmentID: Int) -> NativePlatformOrder {
        let orderCode = normalizedString(order["orderCode"])
        let side: String
        let label: String
        switch orderCode {
        case "022":
            side = "buy"
            label = "买入"
        case "024":
            side = "sell"
            label = "卖出"
        default:
            side = "unknown"
            label = orderCode.isEmpty ? "未知" : orderCode
        }
        let fund = order["fund"] as? [String: Any] ?? [:]
        let title = firstNonEmpty([
            normalizedString(order["variety"]),
            normalizedString(fund["fundName"]),
            normalizedString(fund["fundCode"]),
            "未命名标的",
        ])
        return NativePlatformOrder(
            adjustmentID: adjustmentID,
            side: side,
            label: label,
            fundCode: normalizedString(fund["fundCode"]),
            fundName: normalizedString(fund["fundName"]),
            title: title,
            tradeUnit: intValue(order["tradeUnit"]) ?? 0,
            postPlanUnit: intValue(order["postPlanUnit"]) ?? 0,
            strategyType: normalizedString(order["strategyType"]),
            largeClass: normalizedString(order["largeClass"]),
            nav: doubleValue(order["nav"]) ?? 0,
            navDate: formatTime(firstNonEmpty([formatTimestampMs(order["navDate"]), normalizedString(order["navDate"])])),
            buyDate: formatTime(formatTimestampMs(((order["gridDetail"] as? [String: Any])?["buyDate"]))),
            orderCountInAdjustment: 0
        )
    }

    private func requestJSON(hostURL: URL, path: String, params: [String: String], headers: [String: String]) async throws -> Any {
        var components = URLComponents(url: hostURL.appendingPathComponent(apiBase + path), resolvingAgainstBaseURL: false)
        components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }.sorted(by: { $0.name < $1.name })
        guard let url = components?.url else {
            throw NativePlatformError.invalidResponse
        }
        let query = components?.percentEncodedQuery.map { "?\($0)" } ?? ""
        let pathWithQuery = apiBase + path + query

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(makeXSign(), forHTTPHeaderField: "x-sign")
        request.setValue(makeXRequestID(pathWithQuery: pathWithQuery), forHTTPHeaderField: "x-request-id")
        request.setValue(anonymousID, forHTTPHeaderField: "sensors-anonymous-id")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NativePlatformError.invalidResponse
        }
        let payload = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        if !(200..<300).contains(http.statusCode) {
            throw NativePlatformError.api(buildErrorMessage(payload, statusCode: http.statusCode))
        }
        if let object = payload as? [String: Any] {
            let code = normalizedString(object["code"])
            if !code.isEmpty, code != "0", code != "200" {
                throw NativePlatformError.api(buildErrorMessage(payload, statusCode: http.statusCode))
            }
        }
        return payload
    }

    private func requestText(hostURL: URL, absoluteURL: URL, headers: [String: String]) async throws -> String {
        var request = URLRequest(url: absoluteURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NativePlatformError.invalidResponse
        }
        return decodeResponseText(data)
    }

    private func buildErrorMessage(_ payload: Any, statusCode: Int) -> String {
        if let object = payload as? [String: Any] {
            let detail = object["detail"] as? [String: Any]
            let detailMessage = firstNonEmpty([normalizedString(detail?["msg"]), normalizedString(detail?["message"])])
            let message = firstNonEmpty([normalizedString(object["msg"]), normalizedString(object["message"]), detailMessage, "请求失败"])
            return "HTTP \(statusCode) | \(message)"
        }
        return "HTTP \(statusCode)"
    }

    private func makeXSign() -> String {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let digest = QiemanPlatformNativeClient.sha256Hex(String(Int(Double(now) * 1.01))).uppercased()
        return "\(now)\(digest.prefix(32))"
    }

    private func makeXRequestID(pathWithQuery: String) -> String {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let seed = "\(Double.random(in: 0..<1))\(now)\(pathWithQuery)\(anonymousID)"
        return "albus.\(QiemanPlatformNativeClient.sha256Hex(seed).suffix(20).uppercased())"
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func normalizedString(_ value: Any?) -> String {
        guard let value else { return "" }
        if value is NSNull { return "" }
        return String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstNonEmpty(_ values: [String]) -> String {
        values.first(where: { !$0.isEmpty }) ?? ""
    }

    private func intValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private func scaledQuoteValue(_ value: Any?, scale: Double) -> Double? {
        guard let raw = doubleValue(value), scale > 0 else { return nil }
        return raw / scale
    }

    private func stockSecID(for stockCode: String) -> String? {
        let code = stockCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: code)) else {
            return nil
        }
        if code.hasPrefix("6") || code.hasPrefix("9") {
            return "1.\(code)"
        }
        return "0.\(code)"
    }

    private func tencentStockSymbol(for stockCode: String) -> String? {
        let code = stockCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: code)) else {
            return nil
        }
        if code.hasPrefix("6") || code.hasPrefix("9") {
            return "sh\(code)"
        }
        if code.hasPrefix("4") || code.hasPrefix("8") {
            return "bj\(code)"
        }
        return "sz\(code)"
    }

    private func formattedTencentQuoteTime(_ value: String?) -> String {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 14 else { return raw }
        let year = raw.prefix(4)
        let month = raw.dropFirst(4).prefix(2)
        let day = raw.dropFirst(6).prefix(2)
        let hour = raw.dropFirst(8).prefix(2)
        let minute = raw.dropFirst(10).prefix(2)
        let second = raw.dropFirst(12).prefix(2)
        return "\(year)-\(month)-\(day) \(hour):\(minute):\(second)"
    }

    private func decodeResponseText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let text = String(data: data, encoding: gb18030) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func actionTimestamp(_ txnTs: Int?, createdTs: Int?) -> Int {
        (txnTs ?? 0) > 0 ? (txnTs ?? 0) : (createdTs ?? 0)
    }

    private func formatTimestampMs(_ value: Any?) -> String {
        guard let ms = intValue(value), ms > 0 else { return "" }
        return isoDateTime(Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let isoDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static let displayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private func dateTextFromTimestampMs(_ value: Int) -> String {
        Self.dateOnlyFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(value) / 1000))
    }

    private func isoDateTime(_ date: Date) -> String {
        Self.isoDateTimeFormatter.string(from: date)
    }

    private func formatTime(_ value: String) -> String {
        let text = normalizedString(value)
        guard !text.isEmpty else { return "未记录" }
        return text.replacingOccurrences(of: "T", with: " ").prefixString(19)
    }

    private func normalizeDateText(_ value: String) -> String {
        let text = normalizedString(value)
        return text.count >= 10 ? String(text.prefix(10)) : text
    }

    private func dateKey(_ value: String) -> Int {
        let text = normalizeDateText(value)
        guard !text.isEmpty else { return 0 }
        return Int(text.replacingOccurrences(of: "-", with: "")) ?? 0
    }

    private func round(_ value: Double, digits: Int) -> Double {
        let base = pow(10.0, Double(digits))
        return (value * base).rounded() / base
    }

    private func isoTimestampNow() -> String {
        Self.displayTimeFormatter.string(from: Date())
    }

    private func zipOptional(_ lhs: Double?, _ rhs: Double?) -> (Double, Double)? {
        guard let lhs, let rhs else { return nil }
        return (lhs, rhs)
    }

    private static var regexCache: [String: NSRegularExpression] = [:]

    private func firstMatch(in text: String, pattern: String) -> String? {
        let regex = Self.regexCache[pattern] ?? {
            guard let compiled = try? NSRegularExpression(pattern: pattern, options: []) else {
                return nil
            }
            Self.regexCache[pattern] = compiled
            return compiled
        }()
        guard let regex else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let resultRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[resultRange])
    }
}

private struct NativePlatformOrder {
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

private struct NativePlatformActionSeed {
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

private struct NativePlatformAdjustment {
    let adjustmentID: Int
    let title: String
    let createdTs: Int
    let txnTs: Int
    let orderCount: Int
}

private struct NativeFundHistoryEntry {
    let date: String
    let dateKey: Int
    let nav: Double
    let ts: Int
}

private struct NativeFundHistory {
    let fundCode: String
    let fundName: String
    let series: [NativeFundHistoryEntry]
}

private struct NativeFundQuote {
    let fundCode: String
    let fundName: String
    let price: Double
    let priceTime: String
    let priceSource: String
    let priceSourceLabel: String
    let officialNav: Double?
    let officialNavDate: String
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
            estimateChangePct: nil
        )
    }
}

private struct NativeStockQuote {
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private struct NativeUserPortfolioPricePayload {
    let assetName: String
    let currentPrice: Double?
    let priceTime: String
    let priceSource: String
    let officialNav: Double?
    let officialNavDate: String
    let estimateChangePct: Double?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func prefixString(_ length: Int) -> String {
        String(prefix(length))
    }
}
