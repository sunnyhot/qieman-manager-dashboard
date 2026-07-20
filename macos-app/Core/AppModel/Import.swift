import Foundation

// MARK: - Draft Routing & Import

extension AppModel {
    func draft(for target: PersonalDataImportTarget) -> String {
        switch target {
        case .holdings:
            return portfolioDraft
        case .pendingTrades:
            return pendingTradesDraft
        case .investmentPlans:
            return investmentPlansDraft
        }
    }

    func updateDraft(_ value: String, for target: PersonalDataImportTarget) {
        switch target {
        case .holdings:
            portfolioDraft = value
        case .pendingTrades:
            pendingTradesDraft = value
        case .investmentPlans:
            investmentPlansDraft = value
        }
    }

    func saveDraft(for target: PersonalDataImportTarget, mode: PersonalDataSaveMode = .merge) {
        switch target {
        case .holdings:
            savePortfolioFromDraft(mode: mode)
        case .pendingTrades:
            savePendingTradesFromDraft(mode: mode)
        case .investmentPlans:
            saveInvestmentPlansFromDraft(mode: mode)
        }
    }

    func reloadDraftTargetFromDisk(_ target: PersonalDataImportTarget) {
        switch target {
        case .holdings:
            reloadPortfolioFromDisk()
        case .pendingTrades:
            reloadPendingTradesFromDisk()
        case .investmentPlans:
            reloadInvestmentPlansFromDisk()
        }
    }

    func hasImportedData(for target: PersonalDataImportTarget) -> Bool {
        switch target {
        case .holdings:
            return hasAnyPortfolioRecords
        case .pendingTrades:
            return hasPendingTrades
        case .investmentPlans:
            return hasInvestmentPlans
        }
    }

    func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func importedPortfolioHoldings(from text: String) throws -> [UserPortfolioHolding] {
        return try portfolioStore.parseDraft(text)
    }

    func importedPendingTrades(from text: String) throws -> [PersonalPendingTrade] {
        try pendingTradesStore.parseDraft(text)
    }

    func importedInvestmentPlans(from text: String) throws -> [PersonalInvestmentPlan] {
        try investmentPlansStore.parseDraft(text)
    }

    func fetchPlatformIfPossible() async throws -> PlatformPayload? {
        let prodCode = form.prodCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prodCode.isEmpty else {
            return nil
        }
        return try await platformClient.fetchPlatformPayload(prodCode: prodCode)
    }
}
