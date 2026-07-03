import Foundation

enum TradeSignalRiskPreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case conservative
    case balanced
    case aggressive

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .conservative:
            return "保守"
        case .balanced:
            return "均衡"
        case .aggressive:
            return "积极"
        }
    }
}

enum TradeSignalHorizonPreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case short
    case medium
    case long

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .short:
            return "短期"
        case .medium:
            return "中期"
        case .long:
            return "长期"
        }
    }
}

enum TradeSignalAssetPreferenceMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case followGlobal
    case raiseAttention
    case lowerAttention
    case holdOnly
    case ignore

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .followGlobal:
            return "跟随全局"
        case .raiseAttention:
            return "提高关注"
        case .lowerAttention:
            return "降低关注"
        case .holdOnly:
            return "仅持有观察"
        case .ignore:
            return "忽略提醒"
        }
    }
}

struct TradeSignalAssetPreference: Codable, Identifiable, Hashable {
    var assetKey: String
    var mode: TradeSignalAssetPreferenceMode
    var preferredHorizon: TradeSignalHorizonPreference?
    var notes: String

    var id: String { assetKey }

    init(
        assetKey: String,
        mode: TradeSignalAssetPreferenceMode = .followGlobal,
        preferredHorizon: TradeSignalHorizonPreference? = nil,
        notes: String = ""
    ) {
        self.assetKey = assetKey
        self.mode = mode
        self.preferredHorizon = preferredHorizon
        self.notes = notes
    }
}

struct TradeSignalSettings: Codable, Hashable {
    var enabled: Bool
    var localNotificationsEnabled: Bool
    var riskPreference: TradeSignalRiskPreference
    var primaryHorizon: TradeSignalHorizonPreference
    var minimumConfidence: Int
    var allowBuySignals: Bool
    var allowSellSignals: Bool
    var useStaleAnalysis: Bool
    var assetPreferences: [TradeSignalAssetPreference]

    static let `default` = TradeSignalSettings(
        enabled: true,
        localNotificationsEnabled: false,
        riskPreference: .balanced,
        primaryHorizon: .medium,
        minimumConfidence: 60,
        allowBuySignals: true,
        allowSellSignals: true,
        useStaleAnalysis: true,
        assetPreferences: []
    )

    init(
        enabled: Bool,
        localNotificationsEnabled: Bool,
        riskPreference: TradeSignalRiskPreference,
        primaryHorizon: TradeSignalHorizonPreference,
        minimumConfidence: Int,
        allowBuySignals: Bool,
        allowSellSignals: Bool,
        useStaleAnalysis: Bool,
        assetPreferences: [TradeSignalAssetPreference]
    ) {
        self.enabled = enabled
        self.localNotificationsEnabled = localNotificationsEnabled
        self.riskPreference = riskPreference
        self.primaryHorizon = primaryHorizon
        self.minimumConfidence = min(100, max(0, minimumConfidence))
        self.allowBuySignals = allowBuySignals
        self.allowSellSignals = allowSellSignals
        self.useStaleAnalysis = useStaleAnalysis
        self.assetPreferences = assetPreferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        localNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .localNotificationsEnabled) ?? defaults.localNotificationsEnabled
        riskPreference = try container.decodeIfPresent(TradeSignalRiskPreference.self, forKey: .riskPreference) ?? defaults.riskPreference
        primaryHorizon = try container.decodeIfPresent(TradeSignalHorizonPreference.self, forKey: .primaryHorizon) ?? defaults.primaryHorizon
        minimumConfidence = min(100, max(0, try container.decodeIfPresent(Int.self, forKey: .minimumConfidence) ?? defaults.minimumConfidence))
        allowBuySignals = try container.decodeIfPresent(Bool.self, forKey: .allowBuySignals) ?? defaults.allowBuySignals
        allowSellSignals = try container.decodeIfPresent(Bool.self, forKey: .allowSellSignals) ?? defaults.allowSellSignals
        useStaleAnalysis = try container.decodeIfPresent(Bool.self, forKey: .useStaleAnalysis) ?? defaults.useStaleAnalysis
        assetPreferences = try container.decodeIfPresent([TradeSignalAssetPreference].self, forKey: .assetPreferences) ?? defaults.assetPreferences
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case localNotificationsEnabled
        case riskPreference
        case primaryHorizon
        case minimumConfidence
        case allowBuySignals
        case allowSellSignals
        case useStaleAnalysis
        case assetPreferences
    }
}

struct TradeSignalSettingsStore {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load(from fileURL: URL) throws -> TradeSignalSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(TradeSignalSettings.self, from: data)
    }

    func save(_ settings: TradeSignalSettings, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
