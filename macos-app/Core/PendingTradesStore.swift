import Foundation

struct PendingTradesStore {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load(from fileURL: URL) throws -> [PersonalPendingTrade] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([PersonalPendingTrade].self, from: data)
    }

    func save(_ trades: [PersonalPendingTrade], to fileURL: URL) throws {
        let data = try encoder.encode(trades)
        try data.write(to: fileURL, options: .atomic)
    }

    func parseDraft(_ text: String) throws -> [PersonalPendingTrade] {
        var items: [PersonalPendingTrade] = []

        for (index, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            let parts = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count >= 5 else {
                throw UserPortfolioParseError.invalidLine(index + 1, line)
            }

            let fundRoute = parts[2]
            let fundName: String
            let targetFundName: String?
            if fundRoute.contains("->") {
                let route = fundRoute.components(separatedBy: "->").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                fundName = route.first ?? fundRoute
                targetFundName = route.count > 1 ? route[1] : nil
            } else {
                fundName = fundRoute
                targetFundName = nil
            }

            let amountText = parts[3]
            let (amountValue, unitValue) = parseAmount(amountText)

            items.append(
                PersonalPendingTrade(
                    occurredAt: parts[0],
                    actionLabel: parts[1],
                    fundName: fundName,
                    targetFundName: targetFundName,
                    fundCode: nil,
                    targetFundCode: nil,
                    amountText: amountText,
                    amountValue: amountValue,
                    unitValue: unitValue,
                    status: parts[4],
                    note: parts.count >= 6 ? parts[5] : nil
                )
            )
        }

        guard !items.isEmpty else {
            throw UserPortfolioParseError.emptyInput
        }
        return items
    }

    func draft(from trades: [PersonalPendingTrade]) -> String {
        trades.map { trade in
            let route: String
            if let target = trade.targetFundName, !target.isEmpty {
                route = "\(trade.fundName) -> \(target)"
            } else {
                route = trade.fundName
            }
            var parts = [trade.occurredAt, trade.actionLabel, route, trade.amountText, trade.status]
            if let note = trade.note, !note.isEmpty {
                parts.append(note)
            }
            return parts.joined(separator: " | ")
        }.joined(separator: "\n")
    }

    func merging(_ imported: [PersonalPendingTrade], into existing: [PersonalPendingTrade]) -> [PersonalPendingTrade] {
        var merged = existing
        var indexByKey: [String: Int] = [:]
        for (index, trade) in merged.enumerated() {
            indexByKey[mergeKey(for: trade)] = index
        }

        for importedTrade in imported {
            let key = mergeKey(for: importedTrade)
            if let existingIndex = indexByKey[key] {
                let current = merged[existingIndex]
                merged[existingIndex] = replacingID(of: importedTrade, with: current.id)
            } else {
                indexByKey[key] = merged.count
                merged.append(importedTrade)
            }
        }
        return merged.sorted { $0.occurredAt > $1.occurredAt }
    }

    func previewKey(for trade: PersonalPendingTrade) -> String {
        [
            trade.occurredAt,
            trade.actionLabel,
            trade.fundCode ?? normalizedKey(trade.fundName),
            trade.targetFundCode ?? normalizedKey(trade.targetFundName ?? ""),
            trade.status,
        ]
        .map(normalizedKey)
        .joined(separator: "|")
    }

    func delete(at fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func parseAmount(_ amountText: String) -> (Double?, Double?) {
        let normalized = amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix("元") {
            let raw = String(normalized.dropLast())
            return (Double(raw), nil)
        }
        if normalized.hasSuffix("份") {
            let raw = String(normalized.dropLast())
            return (nil, Double(raw))
        }
        return (nil, nil)
    }

    private func replacingID(of trade: PersonalPendingTrade, with id: UUID) -> PersonalPendingTrade {
        PersonalPendingTrade(
            id: id,
            occurredAt: trade.occurredAt,
            actionLabel: trade.actionLabel,
            fundName: trade.fundName,
            targetFundName: trade.targetFundName,
            fundCode: trade.fundCode,
            targetFundCode: trade.targetFundCode,
            amountText: trade.amountText,
            amountValue: trade.amountValue,
            unitValue: trade.unitValue,
            status: trade.status,
            note: trade.note
        )
    }

    private func mergeKey(for trade: PersonalPendingTrade) -> String {
        [
            trade.occurredAt,
            trade.actionLabel,
            trade.fundCode ?? normalizedKey(trade.fundName),
            trade.targetFundCode ?? normalizedKey(trade.targetFundName ?? ""),
            trade.amountText,
            trade.status,
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
