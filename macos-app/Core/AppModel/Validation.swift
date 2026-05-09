import Foundation

// MARK: - Validation, Normalization & Formatting

extension AppModel {
    func sortInvestmentPlans(_ lhs: PersonalInvestmentPlan, _ rhs: PersonalInvestmentPlan) -> Bool {
        let lhsRank = investmentPlanStatusRank(lhs)
        let rhsRank = investmentPlanStatusRank(rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        let lhsDate = lhs.nextExecutionDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsDate = rhs.nextExecutionDate.trimmingCharacters(in: .whitespacesAndNewlines)
        if lhsDate != rhsDate {
            if lhsDate.isEmpty { return false }
            if rhsDate.isEmpty { return true }
            return lhsDate < rhsDate
        }
        return lhs.fundName.localizedStandardCompare(rhs.fundName) == .orderedAscending
    }

    func investmentPlanStatusRank(_ plan: PersonalInvestmentPlan) -> Int {
        if plan.isActivePlan { return 0 }
        if plan.isPausedPlan { return 1 }
        return 2
    }

    func replacingInvestmentPlan(_ plan: PersonalInvestmentPlan, status: String) -> PersonalInvestmentPlan {
        PersonalInvestmentPlan(
            id: plan.id,
            planTypeLabel: plan.planTypeLabel,
            fundName: plan.fundName,
            fundCode: plan.fundCode,
            scheduleText: plan.scheduleText,
            amountText: plan.amountText,
            minAmount: plan.minAmount,
            maxAmount: plan.maxAmount,
            investedPeriods: plan.investedPeriods,
            cumulativeInvestedAmount: plan.cumulativeInvestedAmount,
            paymentMethod: plan.paymentMethod,
            nextExecutionDate: plan.nextExecutionDate,
            status: normalizedInvestmentPlanStatus(status),
            note: plan.note
        )
    }

    func normalizedInvestmentPlanStatus(_ value: String) -> String {
        if value.contains("终止") {
            return "已终止"
        }
        if value.contains("暂停") {
            return "已暂停"
        }
        return "进行中"
    }

    func validatedPendingTrade(
        id: UUID,
        occurredAt: String,
        actionLabel: String,
        fundName: String,
        fundCode: String,
        targetFundName: String,
        targetFundCode: String,
        amountText: String,
        status: String,
        note: String
    ) -> PersonalPendingTrade? {
        let trimmedOccurredAt = occurredAt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAction = actionLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFundName = fundName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFundCode = normalizedCode(fundCode)
        let trimmedTargetName = targetFundName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTargetCode = normalizedCode(targetFundCode)
        let trimmedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAction.isEmpty else {
            errorMessage = "请输入交易动作。"
            return nil
        }
        guard !trimmedFundName.isEmpty || normalizedFundCode != nil else {
            errorMessage = "请输入基金名称或基金代码。"
            return nil
        }
        guard let amount = normalizedPendingAmount(from: amountText) else {
            errorMessage = "请输入大于 0 的金额或份额，例如 10元 或 100份。"
            return nil
        }

        return PersonalPendingTrade(
            id: id,
            occurredAt: trimmedOccurredAt.isEmpty ? Self.timestampString() : trimmedOccurredAt,
            actionLabel: trimmedAction,
            fundName: trimmedFundName.isEmpty ? (normalizedFundCode ?? "未命名标的") : trimmedFundName,
            targetFundName: trimmedTargetName.isEmpty ? nil : trimmedTargetName,
            fundCode: normalizedFundCode,
            targetFundCode: normalizedTargetCode,
            amountText: amount.text,
            amountValue: amount.cash,
            unitValue: amount.units,
            status: trimmedStatus.isEmpty ? "交易进行中" : trimmedStatus,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
    }

    func normalizedPendingAmount(from text: String) -> (text: String, cash: Double?, units: Double?)? {
        let trimmed = text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasSuffix("份") {
            guard let value = decimalInputValue(trimmed), value > 0 else { return nil }
            return ("\(personalAssetDecimalText(value))份", nil, value)
        }

        let cashText = trimmed.hasSuffix("元") ? String(trimmed.dropLast()) : trimmed
        guard let value = decimalInputValue(cashText), value > 0 else { return nil }
        return ("\(personalAssetDecimalText(value))元", value, nil)
    }

    func validatedInvestmentPlan(
        id: UUID,
        planTypeLabel: String,
        fundName: String,
        fundCode: String,
        scheduleText: String,
        amountText: String,
        investedPeriodsText: String,
        cumulativeInvestedAmountText: String,
        paymentMethod: String,
        nextExecutionDate: String,
        status: String,
        note: String
    ) -> PersonalInvestmentPlan? {
        let trimmedPlanType = planTypeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFundName = fundName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFundCode = normalizedCode(fundCode)
        let trimmedSchedule = scheduleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPayment = paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNextExecutionDate = nextExecutionDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStatus = normalizedInvestmentPlanStatus(status)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPlanType.isEmpty else {
            errorMessage = "请输入计划类型。"
            return nil
        }
        guard !trimmedFundName.isEmpty || normalizedFundCode != nil else {
            errorMessage = "请输入基金名称或基金代码。"
            return nil
        }
        guard !trimmedSchedule.isEmpty else {
            errorMessage = "请输入定投周期或计划说明。"
            return nil
        }

        let amountBounds = investmentPlanAmountBounds(from: trimmedAmount)
        guard let minAmount = amountBounds.min, minAmount > 0 else {
            errorMessage = "请输入大于 0 的定投金额。"
            return nil
        }
        if let maxAmount = amountBounds.max, maxAmount <= 0 {
            errorMessage = "定投金额上限需要大于 0。"
            return nil
        }
        if normalizedStatus == "进行中", trimmedNextExecutionDate.isEmpty {
            errorMessage = "进行中的定投计划需要填写下次执行时间。"
            return nil
        }

        let investedPeriods: Int?
        let trimmedPeriods = investedPeriodsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPeriods.isEmpty {
            investedPeriods = nil
        } else if let parsed = Int(trimmedPeriods), parsed >= 0 {
            investedPeriods = parsed
        } else {
            errorMessage = "已投期数需要是大于等于 0 的整数。"
            return nil
        }

        let cumulativeAmount: Double?
        let trimmedCumulative = cumulativeInvestedAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCumulative.isEmpty {
            cumulativeAmount = nil
        } else if let parsed = decimalInputValue(trimmedCumulative), parsed >= 0 {
            cumulativeAmount = parsed
        } else {
            errorMessage = "累计投入需要是大于等于 0 的金额。"
            return nil
        }

        return PersonalInvestmentPlan(
            id: id,
            planTypeLabel: trimmedPlanType,
            fundName: trimmedFundName.isEmpty ? (normalizedFundCode ?? "未命名标的") : trimmedFundName,
            fundCode: normalizedFundCode,
            scheduleText: trimmedSchedule,
            amountText: normalizedInvestmentPlanAmountText(trimmedAmount, bounds: amountBounds),
            minAmount: minAmount,
            maxAmount: amountBounds.max ?? minAmount,
            investedPeriods: investedPeriods,
            cumulativeInvestedAmount: cumulativeAmount,
            paymentMethod: trimmedPayment.isEmpty ? nil : trimmedPayment,
            nextExecutionDate: trimmedNextExecutionDate,
            status: normalizedStatus,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
    }

    func investmentPlanAmountBounds(from text: String) -> (min: Double?, max: Double?) {
        let normalized = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: "～", with: "~")
            .replacingOccurrences(of: "—", with: "~")
            .replacingOccurrences(of: "－", with: "~")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let numbers = normalized
            .split { !"0123456789.".contains($0) }
            .compactMap { Double($0) }
        guard let first = numbers.first else {
            return (nil, nil)
        }
        if numbers.count >= 2, let second = numbers.dropFirst().first {
            return first <= second ? (first, second) : (second, first)
        }
        return (first, first)
    }

    func normalizedInvestmentPlanAmountText(_ text: String, bounds: (min: Double?, max: Double?)) -> String {
        if text.contains("元") {
            return text
        }
        guard let minAmount = bounds.min else {
            return text
        }
        let maxAmount = bounds.max ?? minAmount
        if abs(maxAmount - minAmount) < 0.001 {
            return "\(personalAssetDecimalText(minAmount))元"
        }
        return "\(personalAssetDecimalText(minAmount))~\(personalAssetDecimalText(maxAmount))元"
    }

    func personalFundKey(code: String?, name: String?, market: StockMarket? = nil, fundMarket: FundMarket? = nil) -> String {
        personalAssetKey(assetType: .fund, code: code, name: name, market: market, fundMarket: fundMarket)
    }

    func personalAssetKey(assetType: PersonalAssetType, code: String?, name: String?, market: StockMarket? = nil, fundMarket: FundMarket? = nil) -> String {
        if let code = normalizedCode(code) {
            let marketSegment: String
            if assetType == .stock {
                marketSegment = ":mkt:\(market?.rawValue ?? "a")"
            } else {
                marketSegment = ":fundmkt:\((fundMarket ?? UserPortfolioHolding.detectFundMarket(from: code)).rawValue)"
            }
            return "\(assetType.rawValue)\(marketSegment):code:\(code)"
        }
        let normalizedName = (name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: " ", with: "")
        let marketSegment: String
        if assetType == .stock {
            marketSegment = ":mkt:\(market?.rawValue ?? "a")"
        } else {
            marketSegment = ":fundmkt:\((fundMarket ?? .offExchange).rawValue)"
        }
        return "\(assetType.rawValue)\(marketSegment):name:\(normalizedName)"
    }

    func normalizedCode(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func normalizedManualAssetRawCode(_ codeText: String) -> String {
        codeText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
    }

    func normalizedManualAssetCode(assetType: PersonalAssetType, codeText: String) -> String {
        let trimmed = normalizedManualAssetRawCode(codeText)
        guard assetType == .stock else {
            return UserPortfolioHolding.normalizedFundCode(from: trimmed)
        }

        let upper = trimmed.uppercased()
        if upper.hasPrefix("HK:") {
            return normalizedHongKongStockCode(String(upper.dropFirst(3)))
        }
        if upper.hasPrefix("US:") {
            return String(upper.dropFirst(3))
        }
        if upper.hasPrefix("HK"), upper.count > 2 {
            let raw = String(upper.dropFirst(2))
            if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: raw)) {
                return normalizedHongKongStockCode(raw)
            }
        }
        if upper.count == 8,
           (upper.hasPrefix("SH") || upper.hasPrefix("SZ") || upper.hasPrefix("BJ")),
           CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: String(upper.dropFirst(2)))) {
            return String(upper.dropFirst(2))
        }
        if upper.count == 9,
           (upper.hasSuffix(".SH") || upper.hasSuffix(".SZ") || upper.hasSuffix(".BJ")),
           CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: String(upper.prefix(6)))) {
            return String(upper.prefix(6))
        }
        return trimmed
    }

    func hasExplicitStockMarket(_ codeText: String) -> Bool {
        let upper = normalizedManualAssetRawCode(codeText).uppercased()
        return upper.hasPrefix("SH")
            || upper.hasPrefix("SZ")
            || upper.hasPrefix("BJ")
            || upper.hasPrefix("HK:")
            || upper.hasPrefix("US:")
            || upper.hasSuffix(".SH")
            || upper.hasSuffix(".SZ")
            || upper.hasSuffix(".BJ")
    }

    func hasExplicitFundMarket(_ codeText: String) -> Bool {
        let upper = normalizedManualAssetRawCode(codeText).uppercased()
        return upper.hasPrefix("ETF:")
            || upper.hasPrefix("LOF:")
            || upper.hasPrefix("EX:")
            || upper.hasPrefix("FUND:")
            || upper.hasPrefix("OTC:")
    }

    func manualStockMarket(assetType: PersonalAssetType, codeText: String) -> StockMarket? {
        guard assetType == .stock else { return nil }
        return UserPortfolioHolding.detectStockMarket(from: normalizedManualAssetRawCode(codeText))
            ?? UserPortfolioHolding.detectStockMarket(from: normalizedManualAssetCode(assetType: assetType, codeText: codeText))
    }

    func normalizedHongKongStockCode(_ value: String) -> String {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.allSatisfy(\.isNumber), code.count < 5 else {
            return code
        }
        return String(repeating: "0", count: 5 - code.count) + code
    }

    func manualFundMarket(assetType: PersonalAssetType, codeText: String) -> FundMarket? {
        guard assetType == .fund else { return nil }
        let upper = normalizedManualAssetRawCode(codeText).uppercased()
        if upper.hasPrefix("ETF:") || upper.hasPrefix("LOF:") || upper.hasPrefix("EX:") {
            return .onExchange
        }
        if upper.hasPrefix("FUND:") || upper.hasPrefix("OTC:") {
            return .offExchange
        }
        return UserPortfolioHolding.detectFundMarket(from: normalizedManualAssetCode(assetType: .fund, codeText: codeText))
    }

    func isLikelyStockCode(_ code: String) -> Bool {
        let value = normalizedManualAssetRawCode(code)
        guard value.count == 6, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: value)) else {
            return false
        }
        return value.hasPrefix("00")
            || value.hasPrefix("30")
            || value.hasPrefix("60")
            || value.hasPrefix("68")
            || value.hasPrefix("90")
            || value.hasPrefix("20")
            || value.hasPrefix("43")
            || value.hasPrefix("83")
            || value.hasPrefix("87")
            || value.hasPrefix("88")
            || value.hasPrefix("92")
    }

    func normalizedOptionalName(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func decimalInputValue(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "份", with: "")
            .replacingOccurrences(of: "元", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }

    func normalizedCostPrice(_ value: Double) -> Double {
        abs(value) < 0.0000001 ? 0 : value
    }

    func timestampNow() -> String {
        Self.isoTimestampFormatter.string(from: Date())
    }

    func personalAssetDecimalText(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0000001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.4f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let isoTimestampFormatter = ISO8601DateFormatter()

    static func timestampString() -> String {
        timestampFormatter.string(from: Date())
    }
}
