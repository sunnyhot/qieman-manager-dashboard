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

struct TrendProgressLog: Identifiable, Hashable {
    let id: UUID
    let timestamp: String
    let message: String

    init(id: UUID = UUID(), timestamp: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
    }
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

    init(score: Int, label: String) {
        self.score = score
        self.label = label
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer() {
            if let score = try? singleValue.decode(Int.self) {
                self.score = score
                self.label = Self.label(for: score)
                return
            }
            if let ratio = try? singleValue.decode(Double.self) {
                let score = ratio <= 1 ? Int((ratio * 100).rounded()) : Int(ratio.rounded())
                self.score = score
                self.label = Self.label(for: score)
                return
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decode(Int.self, forKey: .score)
        label = try container.decode(String.self, forKey: .label)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(score, forKey: .score)
        try container.encode(label, forKey: .label)
    }

    private enum CodingKeys: String, CodingKey {
        case score
        case label
    }

    private static func label(for score: Int) -> String {
        if score >= 75 { return "高" }
        if score >= 45 { return "中" }
        return "低"
    }
}

struct TrendAIProviderSettings: Codable, Hashable {
    var providerName: String
    var baseURL: String
    var model: String
    var apiKey: String
    var supportsOnlineSearch: Bool
    var timeoutSeconds: Double

    static let defaultGenerationTimeoutSeconds: Double = 300

    static let empty = TrendAIProviderSettings(
        providerName: "",
        baseURL: "",
        model: "",
        apiKey: "",
        supportsOnlineSearch: false,
        timeoutSeconds: defaultGenerationTimeoutSeconds
    )

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var redactedAPIKey: String {
        Self.mask(apiKey)
    }

    var upgradedForTrendGeneration: TrendAIProviderSettings {
        guard isConfigured, timeoutSeconds < Self.defaultGenerationTimeoutSeconds else { return self }
        var upgraded = self
        upgraded.timeoutSeconds = Self.defaultGenerationTimeoutSeconds
        return upgraded
    }

    static func mask(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed.isEmpty ? "" : "...." }
        return "\(trimmed.prefix(3))...\(trimmed.suffix(4))"
    }
}

struct TrendAnalysisSettings: Codable, Hashable {
    var agent: TrendAgentSettings
    var provider: TrendAIProviderSettings
    var defaultPrivacyMode: TrendPrivacyMode
    var dailyAutoAnalysisEnabled: Bool
    var lastAutoAnalysisDay: String?

    static let `default` = TrendAnalysisSettings(
        agent: .default,
        provider: .empty,
        defaultPrivacyMode: .sanitized,
        dailyAutoAnalysisEnabled: false,
        lastAutoAnalysisDay: nil
    )

    init(
        agent: TrendAgentSettings,
        defaultPrivacyMode: TrendPrivacyMode,
        dailyAutoAnalysisEnabled: Bool,
        lastAutoAnalysisDay: String?
    ) {
        self.agent = agent
        self.provider = .empty
        self.defaultPrivacyMode = defaultPrivacyMode
        self.dailyAutoAnalysisEnabled = dailyAutoAnalysisEnabled
        self.lastAutoAnalysisDay = lastAutoAnalysisDay
    }

    init(
        provider: TrendAIProviderSettings,
        defaultPrivacyMode: TrendPrivacyMode,
        dailyAutoAnalysisEnabled: Bool,
        lastAutoAnalysisDay: String?
    ) {
        self.agent = .default
        self.provider = provider
        self.defaultPrivacyMode = defaultPrivacyMode
        self.dailyAutoAnalysisEnabled = dailyAutoAnalysisEnabled
        self.lastAutoAnalysisDay = lastAutoAnalysisDay
    }

    init(
        agent: TrendAgentSettings,
        provider: TrendAIProviderSettings,
        defaultPrivacyMode: TrendPrivacyMode,
        dailyAutoAnalysisEnabled: Bool,
        lastAutoAnalysisDay: String?
    ) {
        self.agent = agent
        self.provider = provider
        self.defaultPrivacyMode = defaultPrivacyMode
        self.dailyAutoAnalysisEnabled = dailyAutoAnalysisEnabled
        self.lastAutoAnalysisDay = lastAutoAnalysisDay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agent = try container.decodeIfPresent(TrendAgentSettings.self, forKey: .agent) ?? .default
        provider = try container.decodeIfPresent(TrendAIProviderSettings.self, forKey: .provider) ?? .empty
        defaultPrivacyMode = try container.decodeIfPresent(TrendPrivacyMode.self, forKey: .defaultPrivacyMode) ?? .sanitized
        dailyAutoAnalysisEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyAutoAnalysisEnabled) ?? false
        lastAutoAnalysisDay = try container.decodeIfPresent(String.self, forKey: .lastAutoAnalysisDay)
    }

    private enum CodingKeys: String, CodingKey {
        case agent
        case provider
        case defaultPrivacyMode
        case dailyAutoAnalysisEnabled
        case lastAutoAnalysisDay
    }

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
            timeoutSeconds: TrendAIProviderSettings.defaultGenerationTimeoutSeconds
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

    init(
        horizon: TrendHorizon,
        direction: TrendDirection,
        confidence: TrendConfidence,
        rationale: String,
        counterSignals: [String]
    ) {
        self.horizon = horizon
        self.direction = direction
        self.confidence = confidence
        self.rationale = rationale
        self.counterSignals = counterSignals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        horizon = try container.decode(TrendHorizon.self, forKey: .horizon)
        direction = try container.decode(TrendDirection.self, forKey: .direction)
        confidence = try container.decode(TrendConfidence.self, forKey: .confidence)
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale) ?? ""
        counterSignals = try container.decodeIfPresent([String].self, forKey: .counterSignals) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case horizon
        case direction
        case confidence
        case rationale
        case counterSignals
    }
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

    init(
        id: String,
        name: String,
        exposureText: String,
        direction: TrendDirection,
        confidence: TrendConfidence,
        rationale: String,
        evidenceIDs: [String],
        counterSignals: [String]
    ) {
        self.id = id
        self.name = name
        self.exposureText = exposureText
        self.direction = direction
        self.confidence = confidence
        self.rationale = rationale
        self.evidenceIDs = evidenceIDs
        self.counterSignals = counterSignals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? name
        exposureText = try container.decode(String.self, forKey: .exposureText)
        direction = try container.decode(TrendDirection.self, forKey: .direction)
        confidence = try container.decode(TrendConfidence.self, forKey: .confidence)
        rationale = try container.decode(String.self, forKey: .rationale)
        evidenceIDs = try container.decodeIfPresent([String].self, forKey: .evidenceIDs) ?? []
        counterSignals = try container.decodeIfPresent([String].self, forKey: .counterSignals) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case exposureText
        case direction
        case confidence
        case rationale
        case evidenceIDs
        case counterSignals
    }
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

    init(
        id: String,
        name: String,
        code: String?,
        sector: String,
        impactText: String,
        horizons: [TrendHorizonView],
        rationale: String,
        counterSignals: [String]
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.sector = sector
        self.impactText = impactText
        self.horizons = horizons
        self.rationale = rationale
        self.counterSignals = counterSignals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? code ?? name
        sector = try container.decode(String.self, forKey: .sector)
        impactText = try container.decode(String.self, forKey: .impactText)
        horizons = try container.decodeIfPresent([TrendHorizonView].self, forKey: .horizons) ?? []
        rationale = try container.decode(String.self, forKey: .rationale)
        counterSignals = try container.decodeIfPresent([String].self, forKey: .counterSignals) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case code
        case sector
        case impactText
        case horizons
        case rationale
        case counterSignals
    }
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

    init(
        id: String,
        kind: TrendActionKind,
        title: String,
        detail: String,
        targetName: String?,
        confidence: TrendConfidence,
        triggerConditions: [String],
        invalidatingConditions: [String]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.targetName = targetName
        self.confidence = confidence
        self.triggerConditions = triggerConditions
        self.invalidatingConditions = invalidatingConditions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(TrendActionKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "\(kind.rawValue)-\(title)"
        detail = try container.decode(String.self, forKey: .detail)
        targetName = try container.decodeIfPresent(String.self, forKey: .targetName)
        confidence = try container.decode(TrendConfidence.self, forKey: .confidence)
        triggerConditions = try container.decodeIfPresent([String].self, forKey: .triggerConditions) ?? []
        invalidatingConditions = try container.decodeIfPresent([String].self, forKey: .invalidatingConditions) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case detail
        case targetName
        case confidence
        case triggerConditions
        case invalidatingConditions
    }
}

struct TrendEvidence: Codable, Identifiable, Hashable {
    let id: String
    let sourceName: String
    let title: String
    let url: String?
    let publishedAt: String?
    let retrievedAt: String
    let summary: String

    init(
        id: String,
        sourceName: String,
        title: String,
        url: String?,
        publishedAt: String?,
        retrievedAt: String,
        summary: String
    ) {
        self.id = id
        self.sourceName = sourceName
        self.title = title
        self.url = url
        self.publishedAt = publishedAt
        self.retrievedAt = retrievedAt
        self.summary = summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceName = try container.decode(String.self, forKey: .sourceName)
        title = try container.decode(String.self, forKey: .title)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "\(sourceName)-\(title)"
        url = try container.decodeIfPresent(String.self, forKey: .url)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        retrievedAt = try container.decode(String.self, forKey: .retrievedAt)
        summary = try container.decode(String.self, forKey: .summary)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceName
        case title
        case url
        case publishedAt
        case retrievedAt
        case summary
    }
}

struct TrendWarning: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String

    init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? title
        detail = try container.decode(String.self, forKey: .detail)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
    }
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

    init(
        id: UUID,
        generatedAt: String,
        dataAsOf: String,
        privacyMode: TrendPrivacyMode,
        externalSignalStatus: TrendExternalSignalStatus,
        portfolio: TrendPortfolioSummary,
        horizons: [TrendHorizonView],
        sectors: [TrendSectorView],
        keyAssets: [TrendAssetView],
        actions: [TrendActionCandidate],
        evidence: [TrendEvidence],
        warnings: [TrendWarning],
        disclaimer: String
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.dataAsOf = dataAsOf
        self.privacyMode = privacyMode
        self.externalSignalStatus = externalSignalStatus
        self.portfolio = portfolio
        self.horizons = horizons
        self.sectors = sectors
        self.keyAssets = keyAssets
        self.actions = actions
        self.evidence = evidence
        self.warnings = warnings
        self.disclaimer = disclaimer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        dataAsOf = try container.decode(String.self, forKey: .dataAsOf)
        privacyMode = try container.decode(TrendPrivacyMode.self, forKey: .privacyMode)
        externalSignalStatus = try container.decode(TrendExternalSignalStatus.self, forKey: .externalSignalStatus)
        portfolio = try container.decode(TrendPortfolioSummary.self, forKey: .portfolio)
        horizons = try container.decode([TrendHorizonView].self, forKey: .horizons)
        sectors = try container.decodeIfPresent([TrendSectorView].self, forKey: .sectors) ?? []
        keyAssets = try container.decodeIfPresent([TrendAssetView].self, forKey: .keyAssets) ?? []
        actions = try container.decodeIfPresent([TrendActionCandidate].self, forKey: .actions) ?? []
        evidence = try container.decodeIfPresent([TrendEvidence].self, forKey: .evidence) ?? []
        warnings = try container.decodeIfPresent([TrendWarning].self, forKey: .warnings) ?? []
        disclaimer = try container.decode(String.self, forKey: .disclaimer)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case generatedAt
        case dataAsOf
        case privacyMode
        case externalSignalStatus
        case portfolio
        case horizons
        case sectors
        case keyAssets
        case actions
        case evidence
        case warnings
        case disclaimer
    }
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
