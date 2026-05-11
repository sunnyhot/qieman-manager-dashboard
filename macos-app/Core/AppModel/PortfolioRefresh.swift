import Foundation

// MARK: - Portfolio Refresh & Market Indices

extension AppModel {
    func refreshUserPortfolio(updateNotice: Bool = true) async throws {
        let holdings = activeUserPortfolioHoldings
        guard !holdings.isEmpty else {
            userPortfolioSnapshot = nil
            clearCachedComputedProperties()
            await refreshMarketIndicesIfNeeded()
            return
        }
        guard !isRefreshingPortfolio else { return }
        isRefreshingPortfolio = true
        defer { isRefreshingPortfolio = false }

        let snapshot = try await platformClient.fetchUserPortfolioSnapshot(holdings: holdings)
        userPortfolioSnapshot = snapshot
        clearCachedComputedProperties()
        if updateNotice {
            noticeMessage = "个人持仓估值已刷新。"
        }
        await refreshMarketIndicesIfNeeded()
    }

    func refreshMarketIndices(kinds requestedKinds: [MarketIndexKind]? = nil, updateNotice: Bool = true) async {
        let kinds = requestedKinds ?? selectedMenuBarMarketIndexKinds
        guard !kinds.isEmpty, !isRefreshingMarketIndices else { return }

        isRefreshingMarketIndices = true
        defer { isRefreshingMarketIndices = false }

        let quotes = await platformClient.fetchMarketIndexQuotes(kinds: kinds)
        if !quotes.isEmpty {
            marketIndexQuotes.merge(quotes) { _, new in new }
            if updateNotice {
                noticeMessage = "大盘行情已刷新。"
            }
        } else if updateNotice {
            errorMessage = "大盘行情暂时没有拉到可用数据。"
        }
    }

    func refreshMarketIndicesIfNeeded() async {
        guard menuBarTickerSettings.isEnabled, !selectedMenuBarMarketIndexKinds.isEmpty else { return }
        await refreshMarketIndices(updateNotice: false)
    }

    var selectedMenuBarMarketIndexKinds: [MarketIndexKind] {
        var seen = Set<MarketIndexKind>()
        let selected = menuBarTickerSettings.selections.compactMap { selection -> MarketIndexKind? in
            guard let kind = selection.kindValue,
                  let indexKind = kind.marketIndexRequest?.kind else { return nil }
            return seen.insert(indexKind).inserted ? indexKind : nil
        }
        return selected.sorted { left, right in
            let all = MarketIndexKind.allCases
            return (all.firstIndex(of: left) ?? 0) < (all.firstIndex(of: right) ?? 0)
        }
    }

    @discardableResult
    func resolveAndPersistPortfolioNames() async -> Int {
        guard let portfolioFileURL else { return 0 }

        let missingNameHoldings = userPortfolioHoldings.filter {
            !$0.normalizedFundCode.isEmpty && $0.normalizedName == nil
        }
        guard !missingNameHoldings.isEmpty else { return 0 }

        isResolvingPortfolioNames = true
        defer { isResolvingPortfolioNames = false }

        let namesByHoldingID = await platformClient.resolveAssetNames(holdings: missingNameHoldings)
        guard !namesByHoldingID.isEmpty else { return 0 }

        var resolvedCount = 0
        let enrichedHoldings = userPortfolioHoldings.map { holding in
            guard holding.normalizedName == nil,
                  let resolvedName = namesByHoldingID[holding.id],
                  !resolvedName.isEmpty
            else {
                return holding
            }
            resolvedCount += 1
            return UserPortfolioHolding(
                id: holding.id,
                fundCode: holding.fundCode,
                assetType: holding.assetType,
                units: holding.units,
                costPrice: holding.costPrice,
                displayName: resolvedName,
                stockMarket: holding.stockMarket,
                fundMarket: holding.fundMarket,
                isArchived: holding.isArchived,
                archivedAt: holding.archivedAt
            )
        }

        guard resolvedCount > 0 else { return 0 }

        do {
            userPortfolioHoldings = enrichedHoldings
            clearCachedComputedProperties()
            try portfolioStore.save(enrichedHoldings, to: portfolioFileURL)
            return resolvedCount
        } catch {
            errorMessage = error.localizedDescription
            return 0
        }
    }

    func restartPortfolioAutoRefreshLoop() {
        portfolioAutoRefreshTask?.cancel()
        let interval = portfolioAutoRefreshIntervalSeconds * 1_000_000_000
        portfolioAutoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                await self?.refreshPortfolioIfAutoRefreshVisible()
            }
        }
    }

    func refreshPortfolioIfAutoRefreshVisible() async {
        guard hasPersonalPortfolio, !isRefreshingPortfolio else {
            await refreshMarketIndicesIfNeeded()
            return
        }
        guard selectedSection == .portfolio || selectedSection == .overview || menuBarTickerSettings.isEnabled else {
            await refreshMarketIndicesIfNeeded()
            return
        }

        do {
            try await refreshUserPortfolio(updateNotice: false)
        } catch {
            if selectedSection == .portfolio {
                errorMessage = "个人持仓自动刷新失败：\(error.localizedDescription)"
            }
        }
    }
}
