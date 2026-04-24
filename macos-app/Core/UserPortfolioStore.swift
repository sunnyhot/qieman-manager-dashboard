import Foundation

enum UserPortfolioParseError: LocalizedError {
    case emptyInput
    case invalidLine(Int, String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "没有解析到任何持仓。请至少提供一行“基金代码 份额”。"
        case .invalidLine(let line, let sample):
            return "第 \(line) 行格式无法识别：\(sample)"
        }
    }
}

struct UserPortfolioStore {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load(from fileURL: URL) throws -> [UserPortfolioHolding] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([UserPortfolioHolding].self, from: data)
    }

    func save(_ holdings: [UserPortfolioHolding], to fileURL: URL) throws {
        let data = try encoder.encode(holdings)
        try data.write(to: fileURL, options: .atomic)
    }

    func delete(at fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    func parseDraft(_ text: String) throws -> [UserPortfolioHolding] {
        var items: [UserPortfolioHolding] = []

        for (index, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            guard let item = parseLine(line) else {
                throw UserPortfolioParseError.invalidLine(index + 1, line)
            }
            items.append(item)
        }

        guard !items.isEmpty else {
            throw UserPortfolioParseError.emptyInput
        }
        return items
    }

    func draft(from holdings: [UserPortfolioHolding]) -> String {
        holdings.map(\.draftLine).joined(separator: "\n")
    }

    private func parseLine(_ line: String) -> UserPortfolioHolding? {
        let normalized = line
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ",")
            .replacingOccurrences(of: "|", with: " ")
        let commaParts = normalized
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if commaParts.count >= 2 {
            return parseTokens(commaParts)
        }

        let parts = normalized
            .split(whereSeparator: { $0 == "\t" || $0 == " " })
            .map(String.init)
        return parseTokens(parts)
    }

    private func parseTokens(_ tokens: [String]) -> UserPortfolioHolding? {
        let cleaned = tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard cleaned.count >= 2 else { return nil }

        var tokens = cleaned
        var assetType: PersonalAssetType = .fund
        if let explicitType = parseAssetType(tokens[0]) {
            assetType = explicitType
            tokens.removeFirst()
        } else if tokens.count >= 2, let explicitType = parseAssetType(tokens[1]) {
            assetType = explicitType
            tokens.remove(at: 1)
        } else if let parsedCode = parseAssetCode(tokens[0]), parsedCode.assetType == .stock {
            assetType = .stock
        } else if tokens.count >= 2, let parsedCode = parseAssetCode(tokens[1]), parsedCode.assetType == .stock {
            assetType = .stock
        }

        guard tokens.count >= 2 else { return nil }

        if let parsedCode = parseAssetCode(tokens[0]) {
            return buildHolding(
                code: parsedCode.code,
                assetType: parsedCode.assetType ?? assetType,
                unitsText: tokens[safe: 1],
                costText: tokens[safe: 2],
                nameParts: Array(tokens.dropFirst(3))
            )
        }

        if tokens.count >= 3, let parsedCode = parseAssetCode(tokens[1]) {
            return buildHolding(
                code: parsedCode.code,
                assetType: parsedCode.assetType ?? assetType,
                unitsText: tokens[safe: 2],
                costText: tokens[safe: 3],
                nameParts: [tokens[0]] + Array(tokens.dropFirst(4))
            )
        }

        return nil
    }

    private func buildHolding(code: String, assetType: PersonalAssetType, unitsText: String?, costText: String?, nameParts: [String]) -> UserPortfolioHolding? {
        guard let unitsText, let units = decimalValue(unitsText), units > 0 else {
            return nil
        }
        let parsedCost = costText.flatMap(decimalValue)
        let derivedNameParts: [String]
        if parsedCost == nil, let costText, !costText.isEmpty {
            derivedNameParts = [costText] + nameParts
        } else {
            derivedNameParts = nameParts
        }
        let name = derivedNameParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return UserPortfolioHolding(
            fundCode: code,
            assetType: assetType,
            units: units,
            costPrice: parsedCost,
            displayName: name.isEmpty ? nil : name
        )
    }

    private func decimalValue(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }

    private func parseAssetType(_ value: String) -> PersonalAssetType? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "股票", "stock", "a股", "沪深":
            return .stock
        case "基金", "fund":
            return .fund
        default:
            return nil
        }
    }

    private func parseAssetCode(_ value: String) -> (code: String, assetType: PersonalAssetType?)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()

        if upper.count == 8,
           (upper.hasPrefix("SH") || upper.hasPrefix("SZ")),
           isDigits(String(upper.dropFirst(2))) {
            return (String(upper.dropFirst(2)), .stock)
        }

        if upper.count == 9,
           (upper.hasSuffix(".SH") || upper.hasSuffix(".SZ")),
           isDigits(String(upper.prefix(6))) {
            return (String(upper.prefix(6)), .stock)
        }

        guard trimmed.count >= 5 && trimmed.count <= 6, isDigits(trimmed) else { return nil }
        return (trimmed, nil)
    }

    private func isDigits(_ value: String) -> Bool {
        CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: value))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
