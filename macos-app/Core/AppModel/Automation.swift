import Foundation

// MARK: - Personal Asset Automation Engine

extension AppModel {
    func restartPersonalAssetAutomationLoop() {
        personalAssetAutomationTask?.cancel()
        personalAssetAutomationTask = Task { [weak self] in
            let interval: UInt64 = 15 * 60 * 1_000_000_000
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                await self?.applyPersonalAssetAutomation()
            }
        }
    }

    @discardableResult
    func applyPersonalAssetAutomation(updateNotice: Bool = true) async -> Bool {
        guard dataDirectoryURL != nil, !isApplyingPersonalAssetAutomation else { return false }
        isApplyingPersonalAssetAutomation = true
        defer { isApplyingPersonalAssetAutomation = false }

        let today = Date()
        let costDeviationByFundKey = latestCostDeviationPctByFundKey()
        let planResult = personalAssetAutomation.generateDuePlanTrades(
            plans: investmentPlans,
            existingPendingTrades: pendingTrades,
            today: today
        ) { [weak self, costDeviationByFundKey] plan, _ in
            self?.estimatedAutomationAmount(for: plan, costDeviationByFundKey: costDeviationByFundKey)
        }

        let priceByKey = await automationPriceLookup(for: planResult.pendingTrades, holdings: userPortfolioHoldings)
        let confirmationResult = personalAssetAutomation.confirmDuePendingTrades(
            holdings: userPortfolioHoldings,
            pendingTrades: planResult.pendingTrades,
            today: today,
            priceByKey: priceByKey,
            keyForFund: { [weak self] code, name in
                self?.personalFundKey(code: code, name: name) ?? "name:\(name ?? "")"
            }
        )

        var change = planResult.change
        change.confirmedPendingCount += confirmationResult.change.confirmedPendingCount
        change.skippedConfirmationCount += confirmationResult.change.skippedConfirmationCount

        let nextHoldings = confirmationResult.holdings
        let nextPendingTrades = confirmationResult.pendingTrades.sorted { $0.occurredAt > $1.occurredAt }
        let nextInvestmentPlans = planResult.plans.sorted(by: sortInvestmentPlans)

        let holdingsChanged = nextHoldings != userPortfolioHoldings
        let pendingChanged = nextPendingTrades != pendingTrades
        let plansChanged = nextInvestmentPlans != investmentPlans
        guard holdingsChanged || pendingChanged || plansChanged else {
            return false
        }

        do {
            if holdingsChanged, let portfolioFileURL {
                userPortfolioHoldings = nextHoldings
                try portfolioStore.save(nextHoldings, to: portfolioFileURL)
            }
            if pendingChanged, let pendingTradeFileURL {
                pendingTrades = nextPendingTrades
                try pendingTradesStore.save(nextPendingTrades, to: pendingTradeFileURL)
            }
            if plansChanged, let investmentPlanFileURL {
                investmentPlans = nextInvestmentPlans
                try investmentPlansStore.save(nextInvestmentPlans, to: investmentPlanFileURL)
            }
            if holdingsChanged || pendingChanged || plansChanged {
                rebuildAssetRows()
                clearPendingTradeCaches()
                clearInvestmentPlanCaches()
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        if holdingsChanged, !activeUserPortfolioHoldings.isEmpty {
            try? await refreshUserPortfolio(updateNotice: false)
        }
        if updateNotice, let noticeText = change.noticeText {
            noticeMessage = noticeText
        }
        return true
    }

    func automationPriceLookup(
        for pendingTrades: [PersonalPendingTrade],
        holdings: [UserPortfolioHolding]
    ) async -> [String: Double] {
        var priceByKey: [String: Double] = [:]

        for row in userPortfolioSnapshot?.rows ?? [] {
            let key = personalAssetKey(assetType: row.holding.assetType, code: row.holding.normalizedFundCode, name: row.fundName, market: row.holding.detectedMarket, fundMarket: row.holding.detectedFundMarket)
            if let price = row.resolvedPrice, price > 0 {
                priceByKey[key] = price
            }
        }

        for holding in holdings {
            let key = personalAssetKey(assetType: holding.assetType, code: holding.normalizedFundCode, name: holding.normalizedName, market: holding.detectedMarket, fundMarket: holding.detectedFundMarket)
            if priceByKey[key] == nil, let costPrice = holding.costPrice, costPrice > 0 {
                priceByKey[key] = costPrice
            }
        }

        var syntheticHoldingsByKey: [String: UserPortfolioHolding] = [:]
        for trade in pendingTrades {
            let code = normalizedCode(trade.targetFundCode) ?? normalizedCode(trade.fundCode)
            let name = normalizedText(trade.targetFundName) ?? normalizedText(trade.fundName)
            let key = personalFundKey(code: code, name: name)
            guard priceByKey[key] == nil, let code else { continue }
            syntheticHoldingsByKey[key] = UserPortfolioHolding(
                fundCode: code,
                units: 1,
                costPrice: nil,
                displayName: name
            )
        }

        guard !syntheticHoldingsByKey.isEmpty else {
            return priceByKey
        }

        do {
            let snapshot = try await platformClient.fetchUserPortfolioSnapshot(holdings: Array(syntheticHoldingsByKey.values))
            for row in snapshot.rows {
                let key = personalAssetKey(assetType: row.holding.assetType, code: row.holding.normalizedFundCode, name: row.fundName, market: row.holding.detectedMarket, fundMarket: row.holding.detectedFundMarket)
                if let price = row.resolvedPrice, price > 0 {
                    priceByKey[key] = price
                }
            }
        } catch {
            if errorMessage.isEmpty {
                errorMessage = "部分待确认买入缺少实时价格，暂时保留在待确认。"
            }
        }

        return priceByKey
    }

    func estimatedAutomationAmount(for plan: PersonalInvestmentPlan, costDeviationByFundKey: [String: Double]) -> Double? {
        guard plan.normalizedAmountBounds.min != nil else { return nil }
        let key = personalFundKey(code: plan.fundCode, name: plan.fundName)
        return plan.estimatedExecutionAmount(costDeviationPct: costDeviationByFundKey[key])
    }

    func latestCostDeviationPctByFundKey() -> [String: Double] {
        var values: [String: Double] = [:]
        for row in userPortfolioSnapshot?.rows ?? [] {
            guard row.holding.assetType == .fund else { continue }
            let key = personalFundKey(code: row.holding.normalizedFundCode, name: row.fundName)
            values[key] = PersonalInvestmentPlan.drawdownCostDeviationPct(
                currentPrice: row.resolvedPrice,
                costPrice: row.holding.costPrice
            )
        }
        return values
    }
}
