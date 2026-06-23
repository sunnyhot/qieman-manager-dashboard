import Foundation

enum TrendPrivacyMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case sanitized = "脱敏摘要"
    case fullDetail = "完整明细"

    var id: String { rawValue }
}

enum TrendGenerationState: String, Codable, Hashable {
    case idle
    case generating
    case succeeded
    case failed
    case rejected
}

enum TrendConnectionState: String, Codable, Hashable {
    case idle
    case checking
    case succeeded
    case failed
}

struct TrendConnectionCheckResult: Codable, Hashable {
    let endpoint: String
    let model: String
    let preview: String
}

enum TrendExternalSignalStatus: String, Codable, Hashable {
    case available
    case unavailable
    case partial
    case stale
}

enum TrendRiskLevel: String, Codable, Hashable {
    case low
    case medium
    case high
    case unknown
}

enum TrendDirection: String, Codable, Hashable {
    case bullish
    case neutralPositive
    case neutral
    case neutralNegative
    case bearish
    case uncertain
}

enum TrendHorizon: String, Codable, CaseIterable, Identifiable, Hashable {
    case short
    case medium
    case long

    var id: String { rawValue }
}

enum TrendActionKind: String, Codable, Hashable {
    case watch
    case waitForConfirmation
    case observeInBatches
    case pausePlan
    case considerIncrease
    case considerReduce
    case rebalanceReview
}

struct TrendConfidence: Codable, Hashable {
    let score: Int
    let label: String

    var normalizedScore: Int {
        min(100, max(0, score))
    }
}

struct TrendAIProviderSettings: Codable, Hashable {
    var providerName: String
    var baseURL: String
    var model: String
    var apiKey: String
    var supportsOnlineSearch: Bool
    var timeoutSeconds: Double

    static let empty = TrendAIProviderSettings(
        providerName: "",
        baseURL: "",
        model: "",
        apiKey: "",
        supportsOnlineSearch: false,
        timeoutSeconds: 60
    )

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var redactedAPIKey: String {
        Self.mask(apiKey)
    }

    static func mask(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed.isEmpty ? "" : "...." }
        return "\(trimmed.prefix(3))...\(trimmed.suffix(4))"
    }
}

struct TrendAnalysisSettings: Codable, Hashable {
    var provider: TrendAIProviderSettings
    var defaultPrivacyMode: TrendPrivacyMode
    var dailyAutoAnalysisEnabled: Bool
    var lastAutoAnalysisDay: String?

    static let `default` = TrendAnalysisSettings(
        provider: .empty,
        defaultPrivacyMode: .sanitized,
        dailyAutoAnalysisEnabled: false,
        lastAutoAnalysisDay: nil
    )

    func hasAutoAnalyzed(on day: String) -> Bool {
        lastAutoAnalysisDay == day
    }
}

enum LocalAIConfigurationCompatibility: String, Codable, Hashable {
    case openAICompatible
    case needsCompatibleEndpoint
    case incomplete
}

struct LocalAIConfigurationCandidate: Identifiable, Codable, Hashable {
    let id: String
    let providerName: String
    let sourceDescription: String
    let baseURL: String?
    let model: String?
    let apiKey: String?
    let apiKeySource: String?
    let compatibility: LocalAIConfigurationCompatibility
    let confidence: Int
    let warning: String?

    var maskedAPIKey: String {
        guard let apiKey else { return "" }
        return TrendAIProviderSettings.mask(apiKey)
    }

    var canImport: Bool {
        compatibility == .openAICompatible
            && !(baseURL ?? "").isEmpty
            && !(model ?? "").isEmpty
            && !(apiKey ?? "").isEmpty
    }

    func importedSettings() -> TrendAIProviderSettings? {
        guard canImport, let baseURL, let model else { return nil }
        return TrendAIProviderSettings(
            providerName: providerName,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey ?? "",
            supportsOnlineSearch: true,
            timeoutSeconds: 60
        )
    }
}

struct TrendPortfolioSummary: Codable, Hashable {
    let headline: String
    let riskLevel: TrendRiskLevel
    let summary: String
}

struct TrendHorizonView: Codable, Hashable {
    let horizon: TrendHorizon
    let direction: TrendDirection
    let confidence: TrendConfidence
    let rationale: String
    let counterSignals: [String]
}

struct TrendSectorView: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let exposureText: String
    let direction: TrendDirection
    let confidence: TrendConfidence
    let rationale: String
    let evidenceIDs: [String]
    let counterSignals: [String]
}

struct TrendAssetView: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let code: String?
    let sector: String
    let impactText: String
    let horizons: [TrendHorizonView]
    let rationale: String
    let counterSignals: [String]
}

struct TrendActionCandidate: Codable, Identifiable, Hashable {
    let id: String
    let kind: TrendActionKind
    let title: String
    let detail: String
    let targetName: String?
    let confidence: TrendConfidence
    let triggerConditions: [String]
    let invalidatingConditions: [String]
}

struct TrendEvidence: Codable, Identifiable, Hashable {
    let id: String
    let sourceName: String
    let title: String
    let url: String?
    let publishedAt: String?
    let retrievedAt: String
    let summary: String
}

struct TrendWarning: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
}

struct TrendAnalysisReport: Codable, Identifiable, Hashable {
    let id: UUID
    let generatedAt: String
    let dataAsOf: String
    let privacyMode: TrendPrivacyMode
    let externalSignalStatus: TrendExternalSignalStatus
    let portfolio: TrendPortfolioSummary
    let horizons: [TrendHorizonView]
    let sectors: [TrendSectorView]
    let keyAssets: [TrendAssetView]
    let actions: [TrendActionCandidate]
    let evidence: [TrendEvidence]
    let warnings: [TrendWarning]
    let disclaimer: String
}

struct TrendAnalysisContext: Codable, Hashable {
    let createdAt: String
    let privacyMode: TrendPrivacyMode
    let portfolio: TrendContextPortfolio
    let assets: [TrendContextAsset]
    let sectors: [TrendContextSector]
    let platformSignals: [String]
    let watchSummary: String
    let insightHeadline: String

    func debugJSONString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct TrendContextPortfolio: Codable, Hashable {
    let assetCount: Int
    let holdingCount: Int
    let activePlanCount: Int
    let pendingAssetCount: Int
    let totalMarketValue: Double?
    let totalPendingCashAmount: Double?
    let totalEstimatedNextPlanAmount: Double?
    let totalEffectiveHoldingAmount: Double?
}

struct TrendContextAsset: Codable, Hashable {
    let id: String
    let name: String
    let code: String?
    let assetType: String
    let sector: String
    let statusText: String
    let weightText: String?
    let profitPct: Double?
    let estimateChangePct: Double?
    let pendingTradeCount: Int
    let activePlanCount: Int
    let pausedPlanCount: Int
    let endedPlanCount: Int
    let marketValue: Double?
    let costValue: Double?
    let profitAmount: Double?
    let pendingCashAmount: Double?
    let estimatedNextPlanAmount: Double?
    let totalCumulativePlanAmount: Double?
}

struct TrendContextSector: Codable, Hashable {
    let name: String
    let assetCount: Int
    let exposureText: String
    let exposureAmount: Double?
}
