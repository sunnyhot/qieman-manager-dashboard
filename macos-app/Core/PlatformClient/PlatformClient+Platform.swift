import Foundation

extension QiemanPlatformNativeClient {
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

    func requestAdjustments(prodCode: String) async throws -> [[String: Any]] {
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

    func buildPlatformPayload(prodCode: String, rawItems: [[String: Any]]) async throws -> PlatformPayload {
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
        let (histories, quotes) = await preloadHistoriesAndQuotes(fundCodes)
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

    func enrichPlatformActions(_ seeds: [NativePlatformActionSeed], histories: [String: NativeFundHistory], quotes: [String: NativeFundQuote]) -> [PlatformActionPayload] {
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

    func buildHoldings(actions: [PlatformActionPayload], histories: [String: NativeFundHistory], quotes: [String: NativeFundQuote]) -> PlatformHoldingsPayload {
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

    func buildTimeline(actions: [PlatformActionPayload]) -> [PlatformTimelinePayload] {
        var grouped: [String: [PlatformActionPayload]] = [:]
        for action in actions {
            let label = firstNonEmpty([action.title ?? "", action.fundName ?? "", action.fundCode ?? "", "未命名标的"])
            grouped[label, default: []].append(action)
        }

        return grouped.map { label, entries in
            var buyCount = 0
            var sellCount = 0
            for entry in entries {
                if entry.side == "buy" {
                    buyCount += 1
                } else if entry.side == "sell" {
                    sellCount += 1
                }
            }
            let sortedEntries = entries.sorted { actionTimestamp($0.txnTs, createdTs: $0.createdTs) > actionTimestamp($1.txnTs, createdTs: $1.createdTs) }
            return PlatformTimelinePayload(
                label: label,
                entries: Array(sortedEntries.prefix(12)),
                buyCount: buyCount,
                sellCount: sellCount,
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
}
