import Foundation

struct PersonalPendingTrade: Codable, Hashable, Identifiable {
    let id: UUID
    let occurredAt: String
    let actionLabel: String
    let fundName: String
    let targetFundName: String?
    let fundCode: String?
    let targetFundCode: String?
    let amountText: String
    let amountValue: Double?
    let unitValue: Double?
    let status: String
    let note: String?

    init(
        id: UUID = UUID(),
        occurredAt: String,
        actionLabel: String,
        fundName: String,
        targetFundName: String? = nil,
        fundCode: String? = nil,
        targetFundCode: String? = nil,
        amountText: String,
        amountValue: Double? = nil,
        unitValue: Double? = nil,
        status: String,
        note: String? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.actionLabel = actionLabel
        self.fundName = fundName
        self.targetFundName = targetFundName
        self.fundCode = fundCode
        self.targetFundCode = targetFundCode
        self.amountText = amountText
        self.amountValue = amountValue
        self.unitValue = unitValue
        self.status = status
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id
        case occurredAt
        case actionLabel
        case fundName
        case targetFundName
        case fundCode
        case targetFundCode
        case amountText
        case amountValue
        case unitValue
        case status
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.occurredAt = try container.decodeIfPresent(String.self, forKey: .occurredAt) ?? ""
        self.actionLabel = try container.decodeIfPresent(String.self, forKey: .actionLabel) ?? ""
        self.fundName = try container.decodeIfPresent(String.self, forKey: .fundName) ?? ""
        self.targetFundName = try container.decodeIfPresent(String.self, forKey: .targetFundName)
        self.fundCode = try container.decodeIfPresent(String.self, forKey: .fundCode)
        self.targetFundCode = try container.decodeIfPresent(String.self, forKey: .targetFundCode)
        self.amountText = try container.decodeIfPresent(String.self, forKey: .amountText) ?? ""
        self.amountValue = try container.decodeIfPresent(Double.self, forKey: .amountValue)
        self.unitValue = try container.decodeIfPresent(Double.self, forKey: .unitValue)
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    var displayTitle: String {
        if let targetFundName, !targetFundName.isEmpty {
            return "\(fundName) -> \(targetFundName)"
        }
        return fundName
    }

    var displayCodeText: String? {
        if let fundCode, let targetFundCode, !targetFundCode.isEmpty {
            return "\(fundCode) -> \(targetFundCode)"
        }
        if let fundCode, !fundCode.isEmpty {
            return fundCode
        }
        return nil
    }

    var isCashTrade: Bool {
        amountValue != nil
    }
}

struct PersonalPendingTradeSummary: Hashable {
    let totalCashAmount: Double
    let cashTradeCount: Int
    let unitTradeCount: Int
    let latestTime: String?
    let actionCount: Int
}
