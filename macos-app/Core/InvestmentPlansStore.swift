import Foundation

struct InvestmentPlansStore {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load(from fileURL: URL) throws -> [PersonalInvestmentPlan] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([PersonalInvestmentPlan].self, from: data)
    }

    func save(_ plans: [PersonalInvestmentPlan], to fileURL: URL) throws {
        let data = try encoder.encode(plans)
        try data.write(to: fileURL, options: .atomic)
    }

    func parseDraft(_ text: String) throws -> [PersonalInvestmentPlan] {
        var items: [PersonalInvestmentPlan] = []

        for (index, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            let parts = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count >= 8 else {
                throw UserPortfolioParseError.invalidLine(index + 1, line)
            }

            let (minAmount, maxAmount) = parseAmountRange(parts[3])
            items.append(
                PersonalInvestmentPlan(
                    planTypeLabel: parts[0],
                    fundName: parts[1],
                    fundCode: nil,
                    scheduleText: parts[2],
                    amountText: parts[3],
                    minAmount: minAmount,
                    maxAmount: maxAmount,
                    investedPeriods: Int(parts[4]),
                    cumulativeInvestedAmount: parseCurrency(parts[5]),
                    paymentMethod: parts[6],
                    nextExecutionDate: parts[7],
                    status: parts.count >= 9 ? parts[8] : "进行中",
                    note: parts.count >= 10 ? parts[9] : nil
                )
            )
        }

        guard !items.isEmpty else {
            throw UserPortfolioParseError.emptyInput
        }
        return items
    }

    func draft(from plans: [PersonalInvestmentPlan]) -> String {
        plans.map { plan in
            var parts = [
                plan.planTypeLabel,
                plan.fundName,
                plan.scheduleText,
                plan.amountText,
                plan.investedPeriods.map(String.init) ?? "",
                plan.cumulativeInvestedAmount.map { formatCurrency($0) } ?? "",
                plan.paymentMethod ?? "",
                plan.nextExecutionDate,
            ]
            if plan.status != "进行中" || plan.note != nil {
                parts.append(plan.status)
            }
            if let note = plan.note, !note.isEmpty {
                parts.append(note)
            }
            return parts.joined(separator: " | ")
        }.joined(separator: "\n")
    }

    func merging(_ imported: [PersonalInvestmentPlan], into existing: [PersonalInvestmentPlan]) -> [PersonalInvestmentPlan] {
        var merged = existing
        var indexByKey: [String: Int] = [:]
        for (index, plan) in merged.enumerated() {
            indexByKey[mergeKey(for: plan)] = index
        }

        for importedPlan in imported {
            let key = mergeKey(for: importedPlan)
            if let existingIndex = indexByKey[key] {
                let current = merged[existingIndex]
                merged[existingIndex] = replacingID(of: importedPlan, with: current.id)
            } else {
                indexByKey[key] = merged.count
                merged.append(importedPlan)
            }
        }
        return merged
    }

    func previewKey(for plan: PersonalInvestmentPlan) -> String {
        mergeKey(for: plan)
    }

    func delete(at fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func parseAmountRange(_ text: String) -> (Double?, Double?) {
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
            return (first, second)
        }
        return (first, first)
    }

    private func parseCurrency(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "元", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "%.2f元", value)
    }

    private func replacingID(of plan: PersonalInvestmentPlan, with id: UUID) -> PersonalInvestmentPlan {
        PersonalInvestmentPlan(
            id: id,
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
            status: plan.status,
            note: plan.note
        )
    }

    private func mergeKey(for plan: PersonalInvestmentPlan) -> String {
        [
            plan.fundCode ?? normalizedKey(plan.fundName),
            plan.planTypeLabel,
            plan.scheduleText,
            plan.paymentMethod ?? "",
        ]
        .map(normalizedKey)
        .joined(separator: "|")
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: " ", with: "")
    }
}
