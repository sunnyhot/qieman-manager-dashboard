import Foundation

extension QiemanPlatformNativeClient {
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

        let fundCodes = Array(Set(normalizedHoldings.filter {
            $0.assetType == .fund && $0.detectedFundMarket != .onExchange
        }.map(\.normalizedFundCode)))
        let stockCodes = Array(Set(normalizedHoldings.filter {
            $0.assetType == .stock || ($0.assetType == .fund && $0.detectedFundMarket == .onExchange)
        }.map(\.normalizedFundCode)))
        async let stockQuotesTask = preloadStockQuotes(stockCodes)
        let (histories, quotes) = await preloadHistoriesAndQuotes(fundCodes)
        let stockQuotes = await stockQuotesTask

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
                estimatePrice: pricePayload.estimatePrice.map { round($0, digits: 4) },
                estimatePriceTime: pricePayload.estimatePriceTime.nilIfEmpty,
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
        let fundCodes = Array(Set(holdings.filter {
            $0.assetType == .fund && $0.detectedFundMarket != .onExchange
        }.map(\.normalizedFundCode).filter { !$0.isEmpty }))
        let stockCodes = Array(Set(holdings.filter {
            $0.assetType == .stock || ($0.assetType == .fund && $0.detectedFundMarket == .onExchange)
        }.map(\.normalizedFundCode).filter { !$0.isEmpty }))

        async let fundNamesByCodeTask = resolveFundNames(fundCodes: fundCodes)
        async let stockQuotesTask = preloadStockQuotes(stockCodes)
        let fundNamesByCode = await fundNamesByCodeTask
        let stockQuotes = await stockQuotesTask

        var names: [UUID: String] = [:]
        for holding in holdings {
            switch holding.assetType {
            case .fund:
                if holding.detectedFundMarket == .onExchange,
                   let name = stockQuotes[holding.normalizedFundCode]?.stockName,
                   !name.isEmpty {
                    names[holding.id] = name
                } else if let name = fundNamesByCode[holding.normalizedFundCode], !name.isEmpty {
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

        let (histories, quotes) = await preloadHistoriesAndQuotes(normalizedCodes)

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

    func userPortfolioPricePayload(
        for holding: UserPortfolioHolding,
        histories: [String: NativeFundHistory],
        quotes: [String: NativeFundQuote],
        stockQuotes: [String: NativeStockQuote]
    ) -> NativeUserPortfolioPricePayload {
        switch holding.assetType {
        case .fund:
            if holding.detectedFundMarket == .onExchange {
                let quote = stockQuotes[holding.normalizedFundCode]
                return NativeUserPortfolioPricePayload(
                    assetName: quote?.stockName ?? "",
                    currentPrice: (quote?.price ?? 0) > 0 ? quote?.price : nil,
                    priceTime: quote?.priceTime ?? "",
                    priceSource: quote?.priceSourceLabel ?? "",
                    officialNav: (quote?.previousClose ?? 0) > 0 ? quote?.previousClose : nil,
                    officialNavDate: quote?.priceTime ?? "",
                    estimatePrice: nil,
                    estimatePriceTime: "",
                    estimateChangePct: quote?.changePct
                )
            }
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
                estimatePrice: quote?.estimatePrice,
                estimatePriceTime: quote?.estimateTime ?? "",
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
                estimatePrice: nil,
                estimatePriceTime: "",
                estimateChangePct: quote?.changePct
            )
        }
    }
}
