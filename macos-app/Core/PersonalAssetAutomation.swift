import Foundation

struct PersonalAssetAutomationChange: Hashable {
    var generatedPendingCount = 0
    var advancedPlanCount = 0
    var confirmedPendingCount = 0
    var skippedConfirmationCount = 0

    var hasChanges: Bool {
        generatedPendingCount > 0 || advancedPlanCount > 0 || confirmedPendingCount > 0
    }

    var noticeText: String? {
        guard hasChanges else { return nil }
        var parts: [String] = []
        if generatedPendingCount > 0 {
            parts.append("已自动生成 \(generatedPendingCount) 笔定投待确认")
        }
        if confirmedPendingCount > 0 {
            parts.append("已自动确认 \(confirmedPendingCount) 笔买入到持仓")
        }
        if advancedPlanCount > generatedPendingCount {
            parts.append("已推进 \(advancedPlanCount) 个定投计划的下次执行日")
        }
        if skippedConfirmationCount > 0 {
            parts.append("\(skippedConfirmationCount) 笔因缺少价格暂留待确认")
        }
        return parts.joined(separator: "，") + "。"
    }
}

struct PersonalAssetAutomation {
    private let calendar: Calendar
    private let dateFormatter: DateFormatter
    private let dateTimeFormatter: DateFormatter

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.dateFormatter = DateFormatter()
        self.dateTimeFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateTimeFormatter.locale = Locale(identifier: "zh_CN")
        dateTimeFormatter.calendar = calendar
        dateTimeFormatter.timeZone = calendar.timeZone
        dateTimeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    func generateDuePlanTrades(
        plans: [PersonalInvestmentPlan],
        existingPendingTrades: [PersonalPendingTrade],
        today: Date,
        estimatedAmount: (PersonalInvestmentPlan, Date) -> Double?
    ) -> (plans: [PersonalInvestmentPlan], pendingTrades: [PersonalPendingTrade], change: PersonalAssetAutomationChange) {
        let todayStart = calendar.startOfDay(for: today)
        var pendingTrades = existingPendingTrades
        var updatedPlans: [PersonalInvestmentPlan] = []
        var change = PersonalAssetAutomationChange()

        for plan in plans {
            guard plan.isActivePlan, let firstExecutionDate = firstDate(in: plan.nextExecutionDate) else {
                updatedPlans.append(plan)
                continue
            }

            var executionDate = calendar.startOfDay(for: firstExecutionDate)
            guard executionDate <= todayStart else {
                updatedPlans.append(plan)
                continue
            }

            var executedCount = 0
            var executedAmountTotal = 0.0
            var safetyCounter = 0

            while executionDate <= todayStart && safetyCounter < 366 {
                safetyCounter += 1
                let amount = estimatedAmount(plan, executionDate) ?? defaultPlanAmount(for: plan)
                if amount > 0 {
                    executedCount += 1
                    executedAmountTotal += amount
                    if !hasPendingTrade(for: plan, executionDate: executionDate, in: pendingTrades) {
                        pendingTrades.append(pendingTrade(from: plan, executionDate: executionDate, amount: amount))
                        change.generatedPendingCount += 1
                    }
                }

                guard let nextDate = nextExecutionDate(after: executionDate, scheduleText: plan.scheduleText) else {
                    break
                }
                executionDate = nextDate
            }

            if executedCount > 0 || executionDate != calendar.startOfDay(for: firstExecutionDate) {
                change.advancedPlanCount += 1
                updatedPlans.append(
                    updatedPlan(
                        plan,
                        nextExecutionDate: displayDate(executionDate),
                        generatedCount: executedCount,
                        generatedAmountTotal: executedAmountTotal
                    )
                )
            } else {
                updatedPlans.append(plan)
            }
        }

        return (updatedPlans, pendingTrades, change)
    }

    func confirmDuePendingTrades(
        holdings: [UserPortfolioHolding],
        pendingTrades: [PersonalPendingTrade],
        today: Date,
        priceByKey: [String: Double],
        keyForFund: (String?, String?) -> String
    ) -> (holdings: [UserPortfolioHolding], pendingTrades: [PersonalPendingTrade], change: PersonalAssetAutomationChange) {
        let todayStart = calendar.startOfDay(for: today)
        var currentHoldings = holdings
        var remainingTrades: [PersonalPendingTrade] = []
        var change = PersonalAssetAutomationChange()

        for trade in pendingTrades {
            guard shouldAutoConfirm(trade),
                  let confirmationDate = confirmationDate(for: trade),
                  calendar.startOfDay(for: confirmationDate) <= todayStart
            else {
                remainingTrades.append(trade)
                continue
            }

            if let merged = merge(trade: trade, into: currentHoldings, priceByKey: priceByKey, keyForFund: keyForFund) {
                currentHoldings = merged
                change.confirmedPendingCount += 1
            } else {
                remainingTrades.append(trade)
                change.skippedConfirmationCount += 1
            }
        }

        return (currentHoldings, remainingTrades, change)
    }

    func firstDate(in text: String?) -> Date? {
        guard let text, let range = text.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else {
            return nil
        }
        return dateFormatter.date(from: String(text[range]))
    }

    func displayDate(_ date: Date) -> String {
        "\(dateFormatter.string(from: date))(\(weekdayText(for: date)))"
    }

    func dateTimeString(for date: Date, hour: Int = 9, minute: Int = 30, second: Int = 0) -> String {
        let start = calendar.startOfDay(for: date)
        let value = calendar.date(bySettingHour: hour, minute: minute, second: second, of: start) ?? start
        return dateTimeFormatter.string(from: value)
    }

    func pendingConfirmationDate(for executionDate: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: executionDate)) ?? executionDate
    }

    private func pendingTrade(from plan: PersonalInvestmentPlan, executionDate: Date, amount: Double) -> PersonalPendingTrade {
        PersonalPendingTrade(
            occurredAt: dateTimeString(for: executionDate),
            actionLabel: plan.planTypeLabel.contains("定投") ? "定投" : plan.planTypeLabel,
            fundName: plan.fundName,
            targetFundName: nil,
            fundCode: plan.fundCode,
            targetFundCode: nil,
            amountText: String(format: "%.2f元", amount),
            amountValue: amount,
            unitValue: nil,
            status: "交易进行中",
            note: "定投计划自动生成，确认日 \(dateFormatter.string(from: pendingConfirmationDate(for: executionDate)))"
        )
    }

    private func updatedPlan(
        _ plan: PersonalInvestmentPlan,
        nextExecutionDate: String,
        generatedCount: Int,
        generatedAmountTotal: Double
    ) -> PersonalInvestmentPlan {
        PersonalInvestmentPlan(
            id: plan.id,
            planTypeLabel: plan.planTypeLabel,
            fundName: plan.fundName,
            fundCode: plan.fundCode,
            scheduleText: plan.scheduleText,
            amountText: plan.amountText,
            minAmount: plan.minAmount,
            maxAmount: plan.maxAmount,
            investedPeriods: plan.investedPeriods.map { $0 + generatedCount } ?? (generatedCount > 0 ? generatedCount : nil),
            cumulativeInvestedAmount: plan.cumulativeInvestedAmount.map { $0 + generatedAmountTotal } ?? (generatedAmountTotal > 0 ? generatedAmountTotal : nil),
            paymentMethod: plan.paymentMethod,
            nextExecutionDate: nextExecutionDate,
            status: plan.status,
            note: plan.note
        )
    }

    private func hasPendingTrade(for plan: PersonalInvestmentPlan, executionDate: Date, in trades: [PersonalPendingTrade]) -> Bool {
        let executionDay = dateFormatter.string(from: executionDate)
        let planCode = normalizedCode(plan.fundCode)
        let planName = normalizedName(plan.fundName)
        return trades.contains { trade in
            guard firstDate(in: trade.occurredAt).map({ dateFormatter.string(from: $0) }) == executionDay else {
                return false
            }
            let sameFund: Bool
            if let planCode, let tradeCode = normalizedCode(trade.fundCode) {
                sameFund = planCode == tradeCode
            } else {
                sameFund = normalizedName(trade.fundName) == planName
            }
            guard sameFund else { return false }
            guard trade.actionLabel.contains("定投") || plan.planTypeLabel.contains(trade.actionLabel) else {
                return false
            }
            return true
        }
    }

    private func nextExecutionDate(after date: Date, scheduleText: String) -> Date? {
        let text = scheduleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("每日") || text.contains("每天") || text.contains("日定投") {
            return calendar.date(byAdding: .day, value: 1, to: date).map { calendar.startOfDay(for: $0) }
        }
        if text.contains("每月") || text.contains("月定投") {
            return calendar.date(byAdding: .month, value: 1, to: date).map { calendar.startOfDay(for: $0) }
        }
        return calendar.date(byAdding: .day, value: 7, to: date).map { calendar.startOfDay(for: $0) }
    }

    private func confirmationDate(for trade: PersonalPendingTrade) -> Date? {
        if let explicitDate = firstDate(in: trade.note), trade.note?.contains("确认") == true {
            return explicitDate
        }
        if let explicitDate = firstDate(in: trade.status), trade.status.contains("确认") {
            return explicitDate
        }
        guard let occurredDate = firstDate(in: trade.occurredAt) else {
            return nil
        }
        let delay = explicitConfirmationDelayDays(in: trade.note) ?? explicitConfirmationDelayDays(in: trade.status) ?? 1
        return calendar.date(byAdding: .day, value: delay, to: calendar.startOfDay(for: occurredDate))
    }

    private func explicitConfirmationDelayDays(in text: String?) -> Int? {
        guard let text,
              let range = text.range(of: #"T\s*\+\s*\d+"#, options: [.regularExpression, .caseInsensitive])
        else {
            return nil
        }
        let digits = text[range].filter(\.isNumber)
        return Int(String(digits))
    }

    private func shouldAutoConfirm(_ trade: PersonalPendingTrade) -> Bool {
        let action = trade.actionLabel
        if action.contains("卖") || action.contains("赎回") || action.contains("转换") {
            return false
        }
        return action.contains("买") || action.contains("定投") || action.contains("申购")
    }

    private func merge(
        trade: PersonalPendingTrade,
        into holdings: [UserPortfolioHolding],
        priceByKey: [String: Double],
        keyForFund: (String?, String?) -> String
    ) -> [UserPortfolioHolding]? {
        let targetCode = normalizedCode(trade.targetFundCode) ?? normalizedCode(trade.fundCode)
        let targetName = normalizedDisplayName(trade.targetFundName) ?? normalizedDisplayName(trade.fundName)
        let targetKey = keyForFund(targetCode, targetName)
        let index = holdings.firstIndex { holding in
            guard holding.assetType == .fund else { return false }
            keyForFund(holding.fundCode, holding.displayName) == targetKey
        }
        let existing = index.map { holdings[$0] }
        let resolvedCode = existing?.fundCode ?? targetCode
        guard let fundCode = normalizedCode(resolvedCode) else {
            return nil
        }

        let price = priceByKey[targetKey]
        let unitsToAdd: Double
        if let unitValue = trade.unitValue, unitValue > 0 {
            unitsToAdd = unitValue
        } else if let amountValue = trade.amountValue, amountValue > 0, let price, price > 0 {
            unitsToAdd = amountValue / price
        } else {
            return nil
        }

        guard unitsToAdd > 0 else { return nil }

        let oldUnits = existing?.units ?? 0
        let newUnits = roundUnits(oldUnits + unitsToAdd)
        let newCostPrice = mergedCostPrice(
            oldCostPrice: existing?.costPrice,
            oldUnits: oldUnits,
            tradeAmount: trade.amountValue,
            tradeUnits: unitsToAdd,
            price: price
        )
        let mergedHolding = UserPortfolioHolding(
            fundCode: fundCode,
            units: newUnits,
            costPrice: newCostPrice,
            displayName: existing?.displayName ?? targetName
        )

        var result = holdings
        if let index {
            result[index] = mergedHolding
        } else {
            result.append(mergedHolding)
        }
        return result
    }

    private func mergedCostPrice(
        oldCostPrice: Double?,
        oldUnits: Double,
        tradeAmount: Double?,
        tradeUnits: Double,
        price: Double?
    ) -> Double? {
        let newCostValue: Double?
        if let tradeAmount, tradeAmount > 0 {
            newCostValue = tradeAmount
        } else if let price, price > 0 {
            newCostValue = tradeUnits * price
        } else {
            newCostValue = nil
        }

        guard oldUnits > 0 else {
            guard let newCostValue, tradeUnits > 0 else { return oldCostPrice }
            return roundPrice(newCostValue / tradeUnits)
        }
        guard let oldCostPrice, let newCostValue else {
            return oldCostPrice
        }
        return roundPrice(((oldCostPrice * oldUnits) + newCostValue) / (oldUnits + tradeUnits))
    }

    private func defaultPlanAmount(for plan: PersonalInvestmentPlan) -> Double {
        let range = amountRange(for: plan)
        guard let low = range.min else { return 0 }
        let high = range.max ?? low
        if abs(high - low) < 0.001 {
            return low
        }
        return (low + high) / 2
    }

    private func amountRange(for plan: PersonalInvestmentPlan) -> (min: Double?, max: Double?) {
        let parsed = parsedAmountRange(from: plan.amountText)
        let minValue = plan.minAmount ?? parsed.min
        let maxValue = plan.maxAmount ?? parsed.max
        switch (minValue, maxValue) {
        case let (min?, max?) where max < min:
            return (max, min)
        case let (min?, max?):
            return (min, max)
        case let (min?, nil):
            return (min, min)
        case let (nil, max?):
            return (max, max)
        default:
            return (nil, nil)
        }
    }

    private func parsedAmountRange(from text: String) -> (min: Double?, max: Double?) {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "元", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let numbers = cleaned
            .split { !"0123456789.".contains($0) }
            .compactMap { Double($0) }
        guard let first = numbers.first else {
            return (nil, nil)
        }
        if numbers.count >= 2, let second = numbers.dropFirst().first {
            return (first, second)
        }
        return (first, first)
    }

    private func weekdayText(for date: Date) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: return "星期日"
        case 2: return "星期一"
        case 3: return "星期二"
        case 4: return "星期三"
        case 5: return "星期四"
        case 6: return "星期五"
        default: return "星期六"
        }
    }

    private func normalizedCode(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedDisplayName(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedName(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: " ", with: "")
    }

    private func roundUnits(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }

    private func roundPrice(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}
