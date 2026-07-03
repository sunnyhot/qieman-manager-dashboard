# AI Trade Signals Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an AI trade-observation workflow that surfaces workbench-first AI signals, tracks today's data changes against the latest trend report, and sends rate-limited local notifications.

**Architecture:** Add focused Core models for trade-signal settings, signal derivation, and notification decisions. Reuse existing `TrendAnalysisReport`, `TrendPromptBuilder`, `EnhancementDashboardSummary`, `EnhancementCenterView`, and `LocalNotificationManager`; do not introduce a new analysis service or a new settings section.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit for macOS 14+, XCTest via Swift Package Manager, JSON stores in the app data directory, UserNotifications through the existing local notification wrapper.

## Global Constraints

- macOS native app target remains macOS 14+.
- Python service remains zero third-party dependencies; this feature is Swift-only.
- China market color convention remains red for gains and green for losses via `AppPalette.marketGain`, `AppPalette.marketLoss`, and `AppPalette.marketTint`.
- Do not automatically place orders.
- Do not generate forced buy or forced sell amounts.
- Do not write AI conclusions back into original portfolio holdings.
- Do not replace AI judgment with fixed percentage thresholds.
- Do not present stale AI reports as today's analysis; stale signals must say `基于上次 AI 分析`.
- Do not use mandatory investment language such as `必须买入`, `必须卖出`, `一定上涨`, or `保证收益`.
- Keep business derivation in Core. SwiftUI consumes presentation models only.
- Tests are run from `macos-app/` with `swift test`.

---

## File Structure

- Create `macos-app/Core/TradeSignalSettings.swift`
  - Owns global trade-signal preferences, per-asset overrides, and JSON persistence.
- Create `macos-app/Core/TradeSignalSummary.swift`
  - Derives workbench signal items from `TrendAnalysisReport`, current `PersonalAssetAggregateRow` data, and settings.
- Create `macos-app/Core/TradeSignalNotification.swift`
  - Owns notification state, rate-limit keys, and notification decision text.
- Create `macos-app/Core/AppModel/TradeSignals.swift`
  - Loads/saves settings and notification state, exposes `tradeSignalSummary`, and sends local notifications.
- Modify `macos-app/Core/AppModel/SubModels.swift`
  - Adds published enhancement state for trade-signal settings and notification state.
- Modify `macos-app/Core/AppModel/ComputedProperties.swift`
  - Adds data-directory URLs for settings and notification state.
- Modify `macos-app/Core/AppModel/EnhancementCenter.swift`
  - Loads trade-signal state with the rest of enhancement state.
- Modify `macos-app/Core/AppModel/PortfolioRefresh.swift`
  - Evaluates trade-signal notifications after portfolio refresh updates today's data.
- Modify `macos-app/Core/AppModel/TrendAnalysis.swift`
  - Passes trade-signal preferences into the prompt builder and evaluates notifications after a fresh AI report is saved.
- Modify `macos-app/Core/TrendPromptBuilder.swift`
  - Injects concise preference instructions into all prompt variants without changing report JSON schema.
- Modify `macos-app/Core/EnhancementDashboardPresentation.swift`
  - Adds trade-signal action queue items before generic reminders.
- Modify `macos-app/Core/Models.swift` and `macos-app/Core/AppModel/ManagerWatch.swift`
  - Adds a `workbenchTrend` notification deep link and routes it to the workbench trend tab.
- Modify `macos-app/Views/EnhancementCenterView.swift`
  - Adds the workbench-first `AI 操作观察` panel and action routing.
- Modify `macos-app/Views/EnhancementTrendPanel.swift`
  - Adds full signal-detail cards inside the existing trend page.
- Modify `macos-app/Views/SettingsTrendPanel.swift`
  - Adds compact trade-signal preference controls under the existing trend settings panel.
- Add tests:
  - `macos-app/Tests/QiemanDashboardTests/TradeSignalSettingsStoreTests.swift`
  - `macos-app/Tests/QiemanDashboardTests/TradeSignalSummaryTests.swift`
  - `macos-app/Tests/QiemanDashboardTests/TradeSignalNotificationDecisionTests.swift`
  - Extend `TrendPromptBuilderTests.swift`
  - Extend `EnhancementDashboardPresentationTests.swift`

---

### Task 1: Trade Signal Settings Store

**Files:**
- Create: `macos-app/Core/TradeSignalSettings.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TradeSignalSettingsStoreTests.swift`

**Interfaces:**
- Produces:
  - `TradeSignalSettings.default`
  - `TradeSignalSettingsStore.load(from:) throws -> TradeSignalSettings`
  - `TradeSignalSettingsStore.save(_:to:) throws`
  - `TradeSignalAssetPreference`
  - `TradeSignalRiskPreference`, `TradeSignalHorizonPreference`, `TradeSignalAssetPreferenceMode`
- Consumes: none.

- [ ] **Step 1: Write the failing settings store tests**

Create `macos-app/Tests/QiemanDashboardTests/TradeSignalSettingsStoreTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class TradeSignalSettingsStoreTests: XCTestCase {
    func testLoadReturnsDefaultWhenFileIsMissing() throws {
        let url = temporaryURL("missing-trade-signal-settings.json")

        let settings = try TradeSignalSettingsStore().load(from: url)

        XCTAssertTrue(settings.enabled)
        XCTAssertFalse(settings.localNotificationsEnabled)
        XCTAssertEqual(settings.riskPreference, .balanced)
        XCTAssertEqual(settings.primaryHorizon, .medium)
        XCTAssertEqual(settings.minimumConfidence, 60)
        XCTAssertTrue(settings.allowBuySignals)
        XCTAssertTrue(settings.allowSellSignals)
        XCTAssertTrue(settings.useStaleAnalysis)
        XCTAssertTrue(settings.assetPreferences.isEmpty)
    }

    func testSaveAndLoadKeepsGlobalAndAssetPreferences() throws {
        let url = temporaryURL("trade-signal-settings.json")
        let settings = TradeSignalSettings(
            enabled: true,
            localNotificationsEnabled: true,
            riskPreference: .conservative,
            primaryHorizon: .long,
            minimumConfidence: 75,
            allowBuySignals: true,
            allowSellSignals: false,
            useStaleAnalysis: true,
            assetPreferences: [
                TradeSignalAssetPreference(
                    assetKey: "fund-000001",
                    mode: .raiseAttention,
                    preferredHorizon: .short,
                    notes: "核心观察"
                )
            ]
        )

        try TradeSignalSettingsStore().save(settings, to: url)
        let loaded = try TradeSignalSettingsStore().load(from: url)

        XCTAssertEqual(loaded, settings)
    }

    func testLegacyPartialJSONMigratesMissingFieldsToDefaults() throws {
        let url = temporaryURL("legacy-trade-signal-settings.json")
        try """
        {
          "enabled" : false,
          "minimumConfidence" : 80
        }
        """.data(using: .utf8)!.write(to: url)

        let loaded = try TradeSignalSettingsStore().load(from: url)

        XCTAssertFalse(loaded.enabled)
        XCTAssertFalse(loaded.localNotificationsEnabled)
        XCTAssertEqual(loaded.riskPreference, .balanced)
        XCTAssertEqual(loaded.primaryHorizon, .medium)
        XCTAssertEqual(loaded.minimumConfidence, 80)
        XCTAssertTrue(loaded.allowBuySignals)
        XCTAssertTrue(loaded.allowSellSignals)
        XCTAssertTrue(loaded.useStaleAnalysis)
        XCTAssertTrue(loaded.assetPreferences.isEmpty)
    }

    private func temporaryURL(_ filename: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }
}
```

- [ ] **Step 2: Run the settings tests and verify RED**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter TradeSignalSettingsStoreTests
```

Expected: FAIL because `TradeSignalSettings`, `TradeSignalSettingsStore`, and related enums are not defined.

- [ ] **Step 3: Implement the settings store**

Create `macos-app/Core/TradeSignalSettings.swift`:

```swift
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
```

- [ ] **Step 4: Run the settings tests and verify GREEN**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter TradeSignalSettingsStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```bash
git add macos-app/Core/TradeSignalSettings.swift macos-app/Tests/QiemanDashboardTests/TradeSignalSettingsStoreTests.swift
git commit -m "feat: add trade signal settings store"
```

---

### Task 2: Trade Signal Summary Derivation

**Files:**
- Create: `macos-app/Core/TradeSignalSummary.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TradeSignalSummaryTests.swift`

**Interfaces:**
- Consumes:
  - `TradeSignalSettings`
  - `TrendAnalysisReport`
  - `PersonalAssetAggregateRow`
- Produces:
  - `TradeSignalSummary.make(report:rows:settings:now:) -> TradeSignalSummary`
  - `TradeSignalItem`
  - `TradeSignalAction`
  - `TradeSignalStatus`

- [ ] **Step 1: Write the failing summary tests**

Create `macos-app/Tests/QiemanDashboardTests/TradeSignalSummaryTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class TradeSignalSummaryTests: XCTestCase {
    func testMakeBuildsWorkbenchSignalsFromTrendActions() {
        let report = makeReport(
            generatedAt: "2026-07-03 09:30:00",
            actions: [
                TrendActionCandidate(
                    id: "buy-000001",
                    kind: .considerIncrease,
                    title: "关注买入红利低波",
                    detail: "回撤未破坏中期逻辑，可小额分批观察。",
                    targetName: "红利低波",
                    confidence: TrendConfidence(score: 78, label: "中"),
                    triggerConditions: ["继续回撤且量能缩小"],
                    invalidatingConditions: ["红利板块跌破趋势支撑"]
                ),
                TrendActionCandidate(
                    id: "sell-000002",
                    kind: .considerReduce,
                    title: "复核纳指仓位",
                    detail: "冲高回落时复核再平衡。",
                    targetName: "纳斯达克100",
                    confidence: TrendConfidence(score: 71, label: "中"),
                    triggerConditions: ["放量冲高回落"],
                    invalidatingConditions: ["盈利预期继续上修"]
                )
            ],
            assetTrends: []
        )
        let rows = [
            row(name: "红利低波", code: "000001", estimateChangePct: -1.2),
            row(name: "纳斯达克100", code: "000002", estimateChangePct: 1.6)
        ]

        let summary = TradeSignalSummary.make(
            report: report,
            rows: rows,
            settings: .default,
            now: "2026-07-03 15:00:00"
        )

        XCTAssertEqual(summary.headline, "2 条 AI 操作观察")
        XCTAssertEqual(summary.triggeredCount, 2)
        XCTAssertFalse(summary.staleAnalysis)
        XCTAssertEqual(summary.items.map(\.action), [.watchBuy, .watchSell])
        XCTAssertEqual(summary.items.first?.assetKey, "000001")
        XCTAssertEqual(summary.items.first?.status, .approaching)
        XCTAssertEqual(summary.items.first?.triggerSummary, "继续回撤且量能缩小")
        XCTAssertEqual(summary.items.first?.invalidatingSummary, "红利板块跌破趋势支撑")
    }

    func testMakeMarksStaleAnalysisButKeepsSignalsWhenAllowed() {
        let report = makeReport(
            generatedAt: "2026-07-02 09:30:00",
            actions: [
                TrendActionCandidate(
                    id: "buy-000001",
                    kind: .considerIncrease,
                    title: "关注买入红利低波",
                    detail: "回撤未破坏中期逻辑。",
                    targetName: "红利低波",
                    confidence: TrendConfidence(score: 78, label: "中"),
                    triggerConditions: ["继续回撤"],
                    invalidatingConditions: ["趋势破位"]
                )
            ],
            assetTrends: []
        )

        let summary = TradeSignalSummary.make(
            report: report,
            rows: [row(name: "红利低波", code: "000001", estimateChangePct: -0.8)],
            settings: .default,
            now: "2026-07-03 15:00:00"
        )

        XCTAssertTrue(summary.staleAnalysis)
        XCTAssertTrue(summary.items.first?.isBasedOnStaleAnalysis == true)
        XCTAssertEqual(summary.items.first?.status, .approaching)
        XCTAssertTrue(summary.items.first?.reason.contains("基于上次 AI 分析") == true)
    }

    func testMakeFiltersDisabledOrLowConfidenceSignals() {
        let report = makeReport(
            generatedAt: "2026-07-03 09:30:00",
            actions: [
                TrendActionCandidate(
                    id: "low-buy",
                    kind: .considerIncrease,
                    title: "低置信买入",
                    detail: "信号不足。",
                    targetName: "红利低波",
                    confidence: TrendConfidence(score: 40, label: "低"),
                    triggerConditions: ["回撤"],
                    invalidatingConditions: ["破位"]
                ),
                TrendActionCandidate(
                    id: "sell",
                    kind: .considerReduce,
                    title: "卖出观察",
                    detail: "仓位偏高。",
                    targetName: "纳斯达克100",
                    confidence: TrendConfidence(score: 80, label: "高"),
                    triggerConditions: ["冲高"],
                    invalidatingConditions: ["继续走强"]
                )
            ],
            assetTrends: []
        )
        let settings = TradeSignalSettings(
            enabled: true,
            localNotificationsEnabled: false,
            riskPreference: .balanced,
            primaryHorizon: .medium,
            minimumConfidence: 60,
            allowBuySignals: true,
            allowSellSignals: false,
            useStaleAnalysis: true,
            assetPreferences: []
        )

        let summary = TradeSignalSummary.make(
            report: report,
            rows: [row(name: "红利低波", code: "000001", estimateChangePct: -1)],
            settings: settings,
            now: "2026-07-03 15:00:00"
        )

        XCTAssertTrue(summary.items.isEmpty)
        XCTAssertEqual(summary.headline, "暂无 AI 操作观察")
    }

    private func makeReport(
        generatedAt: String,
        actions: [TrendActionCandidate],
        assetTrends: [TrendAssetView]
    ) -> TrendAnalysisReport {
        TrendAnalysisReport(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            generatedAt: generatedAt,
            dataAsOf: generatedAt,
            privacyMode: .sanitized,
            externalSignalStatus: .partial,
            portfolio: TrendPortfolioSummary(
                headline: "组合保持观察",
                riskLevel: .medium,
                summary: "等待信号确认。"
            ),
            horizons: [],
            marketOutlook: [],
            sectors: [],
            opportunities: [],
            keyAssets: [],
            assetTrends: assetTrends,
            actions: actions,
            evidence: [],
            warnings: [],
            disclaimer: "仅供研究，不构成投资建议。"
        )
    }

    private func row(name: String, code: String, estimateChangePct: Double?) -> PersonalAssetAggregateRow {
        let holding = UserPortfolioHolding(fundCode: code, assetType: .fund, units: 1_000, costPrice: 1, displayName: name)
        let valuationRow = UserPortfolioValuationRow(
            holding: holding,
            fundName: name,
            currentPrice: nil,
            priceTime: "2026-07-03 15:00",
            priceSource: nil,
            officialNav: nil,
            officialNavDate: nil,
            estimatePrice: nil,
            estimatePriceTime: nil,
            marketValue: 1_000,
            costValue: 900,
            profitAmount: 100,
            profitPct: 11.11,
            estimateChangePct: estimateChangePct
        )
        return PersonalAssetAggregateRow(
            key: code,
            assetType: .fund,
            fundName: name,
            fundCode: code,
            holdingRow: valuationRow,
            rawHolding: holding,
            archivedHolding: nil,
            pendingTrades: [],
            plans: []
        )
    }
}
```

- [ ] **Step 2: Run the summary tests and verify RED**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter TradeSignalSummaryTests
```

Expected: FAIL because `TradeSignalSummary` and related types are not defined.

- [ ] **Step 3: Implement the summary model**

Create `macos-app/Core/TradeSignalSummary.swift`:

```swift
import Foundation

enum TradeSignalAction: String, Codable, Hashable {
    case watchBuy
    case holdObserve
    case watchSell
    case waitForConfirmation
    case rebalanceReview

    var displayText: String {
        switch self {
        case .watchBuy:
            return "关注买入"
        case .holdObserve:
            return "持有观察"
        case .watchSell:
            return "关注卖出"
        case .waitForConfirmation:
            return "等待确认"
        case .rebalanceReview:
            return "再平衡复核"
        }
    }
}

enum TradeSignalStatus: String, Codable, Hashable {
    case new
    case approaching
    case triggered
    case invalidated
    case upgraded
    case staleAnalysis

    var displayText: String {
        switch self {
        case .new:
            return "新信号"
        case .approaching:
            return "接近触发"
        case .triggered:
            return "已触发"
        case .invalidated:
            return "已失效"
        case .upgraded:
            return "信号升级"
        case .staleAnalysis:
            return "基于上次分析"
        }
    }
}

struct TradeSignalItem: Identifiable, Hashable {
    let id: String
    let assetKey: String?
    let assetName: String
    let assetCode: String?
    let action: TradeSignalAction
    let status: TradeSignalStatus
    let confidence: TrendConfidence
    let title: String
    let reason: String
    let triggerSummary: String
    let invalidatingSummary: String
    let dataAsOf: String
    let analysisGeneratedAt: String
    let isBasedOnStaleAnalysis: Bool
    let priority: Int
}

struct TradeSignalSummary: Hashable {
    let headline: String
    let generatedAt: String?
    let dataAsOf: String?
    let triggeredCount: Int
    let staleAnalysis: Bool
    let items: [TradeSignalItem]

    static func make(
        report: TrendAnalysisReport?,
        rows: [PersonalAssetAggregateRow],
        settings: TradeSignalSettings,
        now: String
    ) -> TradeSignalSummary {
        guard settings.enabled, let report else {
            return TradeSignalSummary(
                headline: "等待 AI 分析",
                generatedAt: report?.generatedAt,
                dataAsOf: report?.dataAsOf,
                triggeredCount: 0,
                staleAnalysis: false,
                items: []
            )
        }

        let stale = dayString(report.generatedAt) != dayString(now)
        guard settings.useStaleAnalysis || !stale else {
            return TradeSignalSummary(
                headline: "AI 分析待更新",
                generatedAt: report.generatedAt,
                dataAsOf: report.dataAsOf,
                triggeredCount: 0,
                staleAnalysis: true,
                items: []
            )
        }

        let rowsByNameOrCode = rowLookup(rows)
        let items = report.actions.compactMap { action in
            item(
                from: action,
                report: report,
                rowsByNameOrCode: rowsByNameOrCode,
                settings: settings,
                stale: stale
            )
        }
        .sorted { left, right in
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            if left.confidence.normalizedScore != right.confidence.normalizedScore {
                return left.confidence.normalizedScore > right.confidence.normalizedScore
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }

        let headline = items.isEmpty ? "暂无 AI 操作观察" : "\(items.count) 条 AI 操作观察"
        let triggeredCount = items.filter { $0.status == .approaching || $0.status == .triggered || $0.status == .upgraded }.count
        return TradeSignalSummary(
            headline: headline,
            generatedAt: report.generatedAt,
            dataAsOf: report.dataAsOf,
            triggeredCount: triggeredCount,
            staleAnalysis: stale,
            items: items
        )
    }

    private static func item(
        from action: TrendActionCandidate,
        report: TrendAnalysisReport,
        rowsByNameOrCode: [String: PersonalAssetAggregateRow],
        settings: TradeSignalSettings,
        stale: Bool
    ) -> TradeSignalItem? {
        guard action.confidence.normalizedScore >= settings.minimumConfidence else { return nil }
        guard let mappedAction = mappedAction(for: action.kind) else { return nil }
        guard settings.allowBuySignals || mappedAction != .watchBuy else { return nil }
        guard settings.allowSellSignals || mappedAction != .watchSell else { return nil }

        let row = matchedRow(for: action, rowsByNameOrCode: rowsByNameOrCode)
        if let row, preference(for: row.key, settings: settings)?.mode == .ignore {
            return nil
        }

        let status = status(for: mappedAction, row: row, stale: stale)
        let assetName = row?.fundName ?? action.targetName ?? action.title
        let assetCode = row?.fundCode
        let stalePrefix = stale ? "基于上次 AI 分析：" : ""
        let reason = stalePrefix + action.detail
        let assetKey = row?.key
        let id = [action.id, assetKey ?? assetName, mappedAction.rawValue].joined(separator: "|")
        return TradeSignalItem(
            id: id,
            assetKey: assetKey,
            assetName: assetName,
            assetCode: assetCode,
            action: mappedAction,
            status: status,
            confidence: action.confidence,
            title: action.title,
            reason: reason,
            triggerSummary: summaryText(action.triggerConditions),
            invalidatingSummary: summaryText(action.invalidatingConditions),
            dataAsOf: report.dataAsOf,
            analysisGeneratedAt: report.generatedAt,
            isBasedOnStaleAnalysis: stale,
            priority: priority(for: mappedAction, status: status, preference: row.flatMap { preference(for: $0.key, settings: settings) })
        )
    }

    private static func mappedAction(for kind: TrendActionKind) -> TradeSignalAction? {
        switch kind {
        case .considerIncrease:
            return .watchBuy
        case .considerReduce:
            return .watchSell
        case .rebalanceReview:
            return .rebalanceReview
        case .observeInBatches:
            return .holdObserve
        case .waitForConfirmation, .watch:
            return .waitForConfirmation
        case .pausePlan:
            return .holdObserve
        }
    }

    private static func status(
        for action: TradeSignalAction,
        row: PersonalAssetAggregateRow?,
        stale: Bool
    ) -> TradeSignalStatus {
        guard let pct = row?.estimateChangePct else {
            return stale ? .staleAnalysis : .new
        }
        switch action {
        case .watchBuy where pct < 0:
            return .approaching
        case .watchSell where pct > 0:
            return .approaching
        case .rebalanceReview where abs(pct) >= 1:
            return .approaching
        default:
            return stale ? .staleAnalysis : .new
        }
    }

    private static func priority(
        for action: TradeSignalAction,
        status: TradeSignalStatus,
        preference: TradeSignalAssetPreference?
    ) -> Int {
        var value: Int
        switch status {
        case .triggered, .upgraded:
            value = 10
        case .approaching:
            value = 20
        case .invalidated:
            value = 30
        case .new:
            value = 40
        case .staleAnalysis:
            value = 50
        }
        switch action {
        case .watchBuy, .watchSell:
            value += 0
        case .rebalanceReview:
            value += 5
        case .holdObserve, .waitForConfirmation:
            value += 10
        }
        switch preference?.mode {
        case .raiseAttention:
            value -= 8
        case .lowerAttention:
            value += 8
        case .holdOnly:
            value += action == .holdObserve ? 0 : 12
        case .followGlobal, .ignore, .none:
            break
        }
        return value
    }

    private static func rowLookup(_ rows: [PersonalAssetAggregateRow]) -> [String: PersonalAssetAggregateRow] {
        var lookup: [String: PersonalAssetAggregateRow] = [:]
        for row in rows {
            lookup[row.fundName.lowercased()] = row
            lookup[row.key.lowercased()] = row
            if let code = row.fundCode {
                lookup[code.lowercased()] = row
            }
        }
        return lookup
    }

    private static func matchedRow(
        for action: TrendActionCandidate,
        rowsByNameOrCode: [String: PersonalAssetAggregateRow]
    ) -> PersonalAssetAggregateRow? {
        guard let targetName = action.targetName?.trimmingCharacters(in: .whitespacesAndNewlines), !targetName.isEmpty else {
            return nil
        }
        let key = targetName.lowercased()
        if let exact = rowsByNameOrCode[key] {
            return exact
        }
        return rowsByNameOrCode.first { key.contains($0.key) || $0.key.contains(key) }?.value
    }

    private static func preference(for assetKey: String, settings: TradeSignalSettings) -> TradeSignalAssetPreference? {
        settings.assetPreferences.first { $0.assetKey == assetKey }
    }

    private static func summaryText(_ values: [String]) -> String {
        let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return trimmed.isEmpty ? "等待确认" : trimmed.prefix(2).joined(separator: "；")
    }

    private static func dayString(_ timestamp: String) -> String {
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 10 ? String(trimmed.prefix(10)) : trimmed
    }
}
```

- [ ] **Step 4: Run the summary tests and verify GREEN**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter TradeSignalSummaryTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add macos-app/Core/TradeSignalSummary.swift macos-app/Tests/QiemanDashboardTests/TradeSignalSummaryTests.swift
git commit -m "feat: derive AI trade signal summary"
```

---

### Task 3: Notification State and Decision Model

**Files:**
- Create: `macos-app/Core/TradeSignalNotification.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TradeSignalNotificationDecisionTests.swift`

**Interfaces:**
- Consumes:
  - `TradeSignalSummary`
  - `TradeSignalSettings`
- Produces:
  - `TradeSignalNotificationState`
  - `TradeSignalNotificationStateStore`
  - `TradeSignalNotificationDecision.makeRequests(summary:settings:state:day:) -> [TradeSignalNotificationRequest]`

- [ ] **Step 1: Write the failing notification decision tests**

Create `macos-app/Tests/QiemanDashboardTests/TradeSignalNotificationDecisionTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class TradeSignalNotificationDecisionTests: XCTestCase {
    func testDecisionSendsSignalOncePerDay() {
        var state = TradeSignalNotificationState()
        let item = signal(status: .approaching, stale: false)
        let summary = TradeSignalSummary(
            headline: "1 条 AI 操作观察",
            generatedAt: "2026-07-03 09:30:00",
            dataAsOf: "2026-07-03 15:00:00",
            triggeredCount: 1,
            staleAnalysis: false,
            items: [item]
        )
        let settings = settings(localNotificationsEnabled: true)

        let first = TradeSignalNotificationDecision.makeRequests(
            summary: summary,
            settings: settings,
            state: state,
            day: "2026-07-03"
        )
        for request in first {
            state.markSent(request.key)
        }
        let second = TradeSignalNotificationDecision.makeRequests(
            summary: summary,
            settings: settings,
            state: state,
            day: "2026-07-03"
        )

        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(second.isEmpty)
    }

    func testStatusUpgradeCanNotifyAgain() {
        var state = TradeSignalNotificationState()
        state.markSent("2026-07-03|000001|watchBuy|approaching")
        let upgraded = signal(status: .triggered, stale: false)
        let summary = TradeSignalSummary(
            headline: "1 条 AI 操作观察",
            generatedAt: "2026-07-03 09:30:00",
            dataAsOf: "2026-07-03 15:00:00",
            triggeredCount: 1,
            staleAnalysis: false,
            items: [upgraded]
        )

        let requests = TradeSignalNotificationDecision.makeRequests(
            summary: summary,
            settings: settings(localNotificationsEnabled: true),
            state: state,
            day: "2026-07-03"
        )

        XCTAssertEqual(requests.map(\.key), ["2026-07-03|000001|watchBuy|triggered"])
    }

    func testStaleAnalysisNotificationMentionsPreviousAnalysis() {
        let item = signal(status: .approaching, stale: true)
        let summary = TradeSignalSummary(
            headline: "1 条 AI 操作观察",
            generatedAt: "2026-07-02 09:30:00",
            dataAsOf: "2026-07-03 15:00:00",
            triggeredCount: 1,
            staleAnalysis: true,
            items: [item]
        )

        let requests = TradeSignalNotificationDecision.makeRequests(
            summary: summary,
            settings: settings(localNotificationsEnabled: true),
            state: TradeSignalNotificationState(),
            day: "2026-07-03"
        )

        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests.first?.body.contains("基于上次 AI 分析") == true)
    }

    func testDecisionSkipsWhenNotificationsDisabled() {
        let summary = TradeSignalSummary(
            headline: "1 条 AI 操作观察",
            generatedAt: "2026-07-03 09:30:00",
            dataAsOf: "2026-07-03 15:00:00",
            triggeredCount: 1,
            staleAnalysis: false,
            items: [signal(status: .approaching, stale: false)]
        )

        let requests = TradeSignalNotificationDecision.makeRequests(
            summary: summary,
            settings: settings(localNotificationsEnabled: false),
            state: TradeSignalNotificationState(),
            day: "2026-07-03"
        )

        XCTAssertTrue(requests.isEmpty)
    }

    private func signal(status: TradeSignalStatus, stale: Bool) -> TradeSignalItem {
        TradeSignalItem(
            id: "buy-000001",
            assetKey: "000001",
            assetName: "红利低波",
            assetCode: "000001",
            action: .watchBuy,
            status: status,
            confidence: TrendConfidence(score: 78, label: "中"),
            title: "关注买入红利低波",
            reason: stale ? "基于上次 AI 分析：回撤未破坏中期逻辑。" : "回撤未破坏中期逻辑。",
            triggerSummary: "继续回撤",
            invalidatingSummary: "趋势破位",
            dataAsOf: "2026-07-03 15:00:00",
            analysisGeneratedAt: stale ? "2026-07-02 09:30:00" : "2026-07-03 09:30:00",
            isBasedOnStaleAnalysis: stale,
            priority: 10
        )
    }

    private func settings(localNotificationsEnabled: Bool) -> TradeSignalSettings {
        TradeSignalSettings(
            enabled: true,
            localNotificationsEnabled: localNotificationsEnabled,
            riskPreference: .balanced,
            primaryHorizon: .medium,
            minimumConfidence: 60,
            allowBuySignals: true,
            allowSellSignals: true,
            useStaleAnalysis: true,
            assetPreferences: []
        )
    }
}
```

- [ ] **Step 2: Run notification tests and verify RED**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter TradeSignalNotificationDecisionTests
```

Expected: FAIL because notification decision types are not defined.

- [ ] **Step 3: Implement notification decision and state**

Create `macos-app/Core/TradeSignalNotification.swift`:

```swift
import Foundation

struct TradeSignalNotificationState: Codable, Hashable {
    private(set) var sentKeys: Set<String>

    init(sentKeys: Set<String> = []) {
        self.sentKeys = sentKeys
    }

    func hasSent(_ key: String) -> Bool {
        sentKeys.contains(key)
    }

    mutating func markSent(_ key: String) {
        sentKeys.insert(key)
    }
}

struct TradeSignalNotificationRequest: Hashable {
    let key: String
    let title: String
    let body: String
    let item: TradeSignalItem
}

struct TradeSignalNotificationDecision {
    static func makeRequests(
        summary: TradeSignalSummary,
        settings: TradeSignalSettings,
        state: TradeSignalNotificationState,
        day: String
    ) -> [TradeSignalNotificationRequest] {
        guard settings.enabled, settings.localNotificationsEnabled else { return [] }
        return summary.items.compactMap { item in
            guard shouldNotify(item) else { return nil }
            let key = notificationKey(day: day, item: item)
            guard !state.hasSent(key) else { return nil }
            return TradeSignalNotificationRequest(
                key: key,
                title: "AI 操作观察：\(item.assetName)\(item.status.displayText)",
                body: notificationBody(for: item),
                item: item
            )
        }
    }

    static func notificationKey(day: String, item: TradeSignalItem) -> String {
        [
            day,
            item.assetKey ?? item.assetName,
            item.action.rawValue,
            item.status.rawValue
        ].joined(separator: "|")
    }

    private static func shouldNotify(_ item: TradeSignalItem) -> Bool {
        switch item.status {
        case .new, .approaching, .triggered, .invalidated, .upgraded:
            return true
        case .staleAnalysis:
            return false
        }
    }

    private static func notificationBody(for item: TradeSignalItem) -> String {
        let stale = item.isBasedOnStaleAnalysis ? "基于上次 AI 分析。" : ""
        return "\(item.action.displayText)：\(item.triggerSummary)。\(stale)打开工作台查看完整条件。"
    }
}

struct TradeSignalNotificationStateStore {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load(from fileURL: URL) throws -> TradeSignalNotificationState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return TradeSignalNotificationState()
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(TradeSignalNotificationState.self, from: data)
    }

    func save(_ state: TradeSignalNotificationState, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
```

- [ ] **Step 4: Run notification tests and verify GREEN**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter TradeSignalNotificationDecisionTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 3**

```bash
git add macos-app/Core/TradeSignalNotification.swift macos-app/Tests/QiemanDashboardTests/TradeSignalNotificationDecisionTests.swift
git commit -m "feat: add trade signal notification decision"
```

---

### Task 4: Prompt Builder Preference Injection

**Files:**
- Modify: `macos-app/Core/TrendPromptBuilder.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendPromptBuilderTests.swift`

**Interfaces:**
- Consumes:
  - `TradeSignalSettings`
- Produces:
  - `TrendPromptBuilder.build(context:settings:tradeSignalSettings:)`
  - `TrendPromptBuilder.buildChunk(context:chunkIndex:chunkCount:settings:tradeSignalSettings:)`
  - `TrendPromptBuilder.buildSynthesis(context:chunkReports:settings:tradeSignalSettings:)`

- [ ] **Step 1: Write failing prompt tests**

Append this test to `TrendPromptBuilderTests`:

```swift
func testPromptIncludesTradeSignalPreferencesWithoutChangingSchema() {
    let context = makeTrendPromptContext()
    let tradeSettings = TradeSignalSettings(
        enabled: true,
        localNotificationsEnabled: true,
        riskPreference: .conservative,
        primaryHorizon: .long,
        minimumConfidence: 72,
        allowBuySignals: true,
        allowSellSignals: false,
        useStaleAnalysis: true,
        assetPreferences: [
            TradeSignalAssetPreference(
                assetKey: "000001",
                mode: .raiseAttention,
                preferredHorizon: .short,
                notes: "核心标的"
            )
        ]
    )

    let prompt = TrendPromptBuilder().build(
        context: context,
        settings: TrendAnalysisSettings.default,
        tradeSignalSettings: tradeSettings
    )

    XCTAssertTrue(prompt.system.contains("AI 操作观察偏好"))
    XCTAssertTrue(prompt.system.contains("风险偏好：保守"))
    XCTAssertTrue(prompt.system.contains("主要观察周期：长期"))
    XCTAssertTrue(prompt.system.contains("最低关注置信度：72"))
    XCTAssertTrue(prompt.system.contains("允许关注卖出：否"))
    XCTAssertTrue(prompt.system.contains("000001：提高关注；周期：短期；备注：核心标的"))
    XCTAssertTrue(prompt.system.contains("Do not add fields outside this schema"))
}
```

- [ ] **Step 2: Run prompt test and verify RED**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter TrendPromptBuilderTests/testPromptIncludesTradeSignalPreferencesWithoutChangingSchema
```

Expected: FAIL because `build(context:settings:tradeSignalSettings:)` does not exist.

- [ ] **Step 3: Update `TrendPromptBuilder` signatures and preference text**

Modify the three public builder methods so their signatures include the defaulted parameter:

```swift
func build(
    context: TrendAnalysisContext,
    settings: TrendAnalysisSettings,
    tradeSignalSettings: TradeSignalSettings = .default
) -> TrendModelPrompt

func buildChunk(
    context: TrendAnalysisContext,
    chunkIndex: Int,
    chunkCount: Int,
    settings: TrendAnalysisSettings,
    tradeSignalSettings: TradeSignalSettings = .default
) -> TrendModelPrompt

func buildSynthesis(
    context: TrendAnalysisContext,
    chunkReports: [TrendAnalysisReport],
    settings: TrendAnalysisSettings,
    tradeSignalSettings: TradeSignalSettings = .default
) -> TrendModelPrompt
```

Change calls to `baseSystemPrompt(settings:)` inside those methods to:

```swift
baseSystemPrompt(settings: settings, tradeSignalSettings: tradeSignalSettings)
```

Replace the private signature and add the helper:

```swift
private func baseSystemPrompt(
    settings: TrendAnalysisSettings,
    tradeSignalSettings: TradeSignalSettings
) -> String {
    let externalSignalInstruction = settings.provider.supportsOnlineSearch
        ? "If the selected model has reliable external-signal access, include concise evidence. If access is partial, set externalSignalStatus to partial instead of inventing sources."
        : "The selected model is configured without online search. Set externalSignalStatus to unavailable or partial, and do not invent external sources."
    let tradeSignalInstruction = tradeSignalPreferenceInstruction(tradeSignalSettings)

    return """
    Return valid JSON only.
    Use the TrendAnalysisReport schema exactly.
    Follow the embedded Qieman investment trend analysis skill rules in this prompt.
    Analyze Qieman portfolio data from a personal research perspective.
    Focus on conditional trend judgment, broad market and sector direction, portfolio risk boundaries, counter-signals, and watch/review actions.
    Separate facts, model judgment, and action candidates.
    \(externalSignalInstruction)
    \(tradeSignalInstruction)
    Selected model: \(settings.provider.model).
    Do not invent sources.
    Do not guarantee returns.
    Do not use mandatory buy/sell language.
    Do not perform exhaustive online searches for every asset; use broad market, sector, policy, and clearly material asset-level signals only.
    marketOutlook must summarize 大盘 and major asset classes relevant to the portfolio, such as A-share broad indices, Hong Kong equities, US equities, bonds, commodities, and gold/黄金 when material.
    opportunities must capture still-actionable investment opportunities outside or across current holdings, including gold/黄金 when it has a clear conditional setup.
    assetTrends must include 每个已持有基金 from Context JSON, with a concise trend view and conditional buy/hold/sell execution guidance for each fund.
    keyAssets should focus on portfolio-relevant assets that materially affect trend judgment, concentration, pending cash, active plans, or risk.
    Do not force every Context JSON asset into keyAssets; use assetTrends, sectors, and warnings for low-importance or uncovered holdings.
    Every keyAsset and assetTrends impactText or rationale must include conditional buy/hold/sell execution guidance such as 分批买入, 持有观察, 暂停买入, 分批卖出, 再平衡复核, with trigger and counter-signal boundaries in horizons or counterSignals.
    Keep actions and evidence concise: actions are portfolio-level重点动作 only, preferably at most 5 actions in a final report and at most 3 actions in chunk reports; do not omit keyAssets just to keep actions short.
    Prefer one concise buy/hold/sell execution guidance per keyAsset over adding a separate action for every asset.
    Keep evidence concise: prefer at most 6 evidence items in a final report and at most 3 evidence items in chunk reports.
    If keyAssets.horizons is not empty, each item must use the same horizon object shape as top-level horizons: horizon, direction, confidence, rationale, and counterSignals.
    Always include counterSignals, confidence, dataAsOf, generatedAt, evidence, warnings, and disclaimer.
    Every action candidate must include triggerConditions and invalidatingConditions.
    Use conditional Chinese wording such as 可考虑, 关注, 等信号再动, 等待触发条件, and 若条件触发则执行观察动作.
    Do not use 必须买入, 必须卖出, 保证上涨, 保证收益, or 一定上涨.
    Required field names include portfolio, horizons, marketOutlook, sectors, opportunities, keyAssets, assetTrends, actions, evidence, warnings, disclaimer, counterSignals.
    Do not add fields outside this schema. Do not output totalMarketValue, totalCostValue, totalProfit, assetCount, or top-level confidence in the report.
    Use this exact JSON shape. Keep id fields as stable strings when included, and keep all non-id keys present:
    """
}

private func tradeSignalPreferenceInstruction(_ settings: TradeSignalSettings) -> String {
    let assetLines = settings.assetPreferences.map { preference in
        let horizon = preference.preferredHorizon.map { "；周期：\($0.displayText)" } ?? ""
        let notes = preference.notes.isEmpty ? "" : "；备注：\(preference.notes)"
        return "\(preference.assetKey)：\(preference.mode.displayText)\(horizon)\(notes)"
    }
    let assetText = assetLines.isEmpty ? "无单标的覆盖" : assetLines.joined(separator: "\n")
    return """
    AI 操作观察偏好：
    - 启用：\(settings.enabled ? "是" : "否")
    - 风险偏好：\(settings.riskPreference.displayText)
    - 主要观察周期：\(settings.primaryHorizon.displayText)
    - 最低关注置信度：\(settings.minimumConfidence)
    - 允许关注买入：\(settings.allowBuySignals ? "是" : "否")
    - 允许关注卖出：\(settings.allowSellSignals ? "是" : "否")
    - 单标的偏好：
    \(assetText)
    These preferences influence prioritization and wording only. They do not authorize automatic trading and must not change the required JSON schema.
    """
}
```

Keep the existing schema block below this prompt text unchanged after the `Use this exact JSON shape` line. The implementation must preserve all existing schema lines already present in `TrendPromptBuilder.swift`.

- [ ] **Step 4: Run prompt tests and verify GREEN**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter TrendPromptBuilderTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 4**

```bash
git add macos-app/Core/TrendPromptBuilder.swift macos-app/Tests/QiemanDashboardTests/TrendPromptBuilderTests.swift
git commit -m "feat: include trade signal preferences in trend prompts"
```

---

### Task 5: AppModel Wiring and Local Notification Dispatch

**Files:**
- Create: `macos-app/Core/AppModel/TradeSignals.swift`
- Modify: `macos-app/Core/AppModel/SubModels.swift`
- Modify: `macos-app/Core/AppModel/ComputedProperties.swift`
- Modify: `macos-app/Core/AppModel/EnhancementCenter.swift`
- Modify: `macos-app/Core/AppModel/PortfolioRefresh.swift`
- Modify: `macos-app/Core/AppModel/TrendAnalysis.swift`
- Modify: `macos-app/Core/Models.swift`
- Modify: `macos-app/Core/AppModel/ManagerWatch.swift`
- Test: add coverage in `macos-app/Tests/QiemanDashboardTests/TradeSignalNotificationDecisionTests.swift`

**Interfaces:**
- Consumes:
  - `TradeSignalSettingsStore`
  - `TradeSignalNotificationStateStore`
  - `TradeSignalSummary.make`
  - `TradeSignalNotificationDecision.makeRequests`
- Produces:
  - `AppModel.tradeSignalSummary`
  - `AppModel.saveTradeSignalSettings()`
  - `AppModel.evaluateTradeSignalNotifications(now:) async`
  - `NotificationDeepLinkType.workbenchTrend`

- [ ] **Step 1: Write the failing deep-link test**

Append this test to `TradeSignalNotificationDecisionTests`:

```swift
func testWorkbenchTrendDeepLinkPayloadRoundTrips() {
    let payload = NotificationDeepLinkPayload(type: .workbenchTrend, targetID: "trade-signals")

    let decoded = NotificationDeepLinkPayload(userInfo: payload.userInfo)

    XCTAssertEqual(decoded?.type, .workbenchTrend)
    XCTAssertEqual(decoded?.targetID, "trade-signals")
}
```

- [ ] **Step 2: Run deep-link test and verify RED**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter TradeSignalNotificationDecisionTests/testWorkbenchTrendDeepLinkPayloadRoundTrips
```

Expected: FAIL because `.workbenchTrend` is not defined.

- [ ] **Step 3: Add state, URLs, deep link, and AppModel trade-signal methods**

In `macos-app/Core/AppModel/SubModels.swift`, add these properties to `EnhancementState`:

```swift
@Published var tradeSignalSettings: TradeSignalSettings = .default
@Published var tradeSignalNotificationState = TradeSignalNotificationState()
```

In `macos-app/Core/AppModel.swift`, add proxies near other enhancement proxies:

```swift
var tradeSignalSettings: TradeSignalSettings {
    get { enhancementState.tradeSignalSettings }
    set { enhancementState.tradeSignalSettings = newValue }
}

var tradeSignalNotificationState: TradeSignalNotificationState {
    get { enhancementState.tradeSignalNotificationState }
    set { enhancementState.tradeSignalNotificationState = newValue }
}
```

In `macos-app/Core/AppModel/ComputedProperties.swift`, add:

```swift
var tradeSignalSettingsFileURL: URL? {
    dataDirectoryURL?.appendingPathComponent("trade-signal-settings.json", isDirectory: false)
}

var tradeSignalNotificationStateFileURL: URL? {
    dataDirectoryURL?.appendingPathComponent("trade-signal-notification-state.json", isDirectory: false)
}
```

In `macos-app/Core/Models.swift`, add the enum case:

```swift
case workbenchTrend = "workbench_trend"
```

In `macos-app/Core/AppModel/ManagerWatch.swift`, extend `handleNotificationDeepLink(_:)`:

```swift
case .workbenchTrend:
    openWorkbenchTrend()
```

Add the method in the same extension:

```swift
func openWorkbenchTrend() {
    selectedSection = .enhancement
    selectedEnhancementTab = .trend
    revealMainWindowIfNeeded()
}
```

Create `macos-app/Core/AppModel/TradeSignals.swift`:

```swift
import Foundation

extension AppModel {
    var tradeSignalSummary: TradeSignalSummary {
        TradeSignalSummary.make(
            report: trendReport,
            rows: personalAssetRows,
            settings: tradeSignalSettings,
            now: Self.timestampString()
        )
    }

    func loadTradeSignalState() {
        if let tradeSignalSettingsFileURL {
            do {
                tradeSignalSettings = try TradeSignalSettingsStore().load(from: tradeSignalSettingsFileURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        if let tradeSignalNotificationStateFileURL {
            do {
                tradeSignalNotificationState = try TradeSignalNotificationStateStore().load(from: tradeSignalNotificationStateFileURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func saveTradeSignalSettings() {
        guard let tradeSignalSettingsFileURL else { return }
        do {
            try TradeSignalSettingsStore().save(tradeSignalSettings, to: tradeSignalSettingsFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveTradeSignalNotificationState() {
        guard let tradeSignalNotificationStateFileURL else { return }
        do {
            try TradeSignalNotificationStateStore().save(tradeSignalNotificationState, to: tradeSignalNotificationStateFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func evaluateTradeSignalNotifications(now: String = Self.timestampString()) async {
        let summary = TradeSignalSummary.make(
            report: trendReport,
            rows: personalAssetRows,
            settings: tradeSignalSettings,
            now: now
        )
        let day = String(now.prefix(10))
        let requests = TradeSignalNotificationDecision.makeRequests(
            summary: summary,
            settings: tradeSignalSettings,
            state: tradeSignalNotificationState,
            day: day
        )
        guard !requests.isEmpty else { return }
        guard await notificationManager.requestAuthorizationIfNeeded() else { return }

        for request in requests.prefix(3) {
            await notificationManager.send(
                title: request.title,
                subtitle: request.item.action.displayText,
                body: request.body,
                deepLink: NotificationDeepLinkPayload(type: .workbenchTrend, targetID: request.item.id)
            )
            tradeSignalNotificationState.markSent(request.key)
        }
        saveTradeSignalNotificationState()
    }
}
```

In `macos-app/Core/AppModel/EnhancementCenter.swift`, update `loadEnhancementState()`:

```swift
func loadEnhancementState() {
    loadMonthlyReportExportMetadata()
    loadManagerWatchTimeline()
    loadImportUndoSnapshot()
    loadPortfolioInsightSnapshots()
    loadTrendAnalysisState()
    loadTradeSignalState()
}
```

In `macos-app/Core/AppModel/TrendAnalysis.swift`, change prompt builder calls to pass `tradeSignalSettings`:

```swift
prompt: promptBuilder.build(context: context, settings: settings, tradeSignalSettings: tradeSignalSettings)
```

```swift
prompt: promptBuilder.buildChunk(
    context: chunk,
    chunkIndex: index,
    chunkCount: chunks.count,
    settings: settings,
    tradeSignalSettings: tradeSignalSettings
)
```

```swift
prompt: promptBuilder.buildSynthesis(
    context: synthesisContext,
    chunkReports: chunkReports,
    settings: settings,
    tradeSignalSettings: tradeSignalSettings
)
```

After `appendTrendProgress("趋势分析完成")`, add:

```swift
Task { await evaluateTradeSignalNotifications(now: report.generatedAt) }
```

In `macos-app/Core/AppModel/PortfolioRefresh.swift`, after `await refreshMarketIndicesIfNeeded()` in the successful refresh path, add:

```swift
await evaluateTradeSignalNotifications(now: snapshot.refreshedAt)
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter TradeSignalNotificationDecisionTests
swift test --filter TrendPromptBuilderTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 5**

```bash
git add macos-app/Core/AppModel/TradeSignals.swift macos-app/Core/AppModel/SubModels.swift macos-app/Core/AppModel/ComputedProperties.swift macos-app/Core/AppModel/EnhancementCenter.swift macos-app/Core/AppModel/PortfolioRefresh.swift macos-app/Core/AppModel/TrendAnalysis.swift macos-app/Core/Models.swift macos-app/Core/AppModel/ManagerWatch.swift macos-app/Tests/QiemanDashboardTests/TradeSignalNotificationDecisionTests.swift
git commit -m "feat: wire trade signals into app model"
```

---

### Task 6: Workbench Presentation and Action Queue

**Files:**
- Modify: `macos-app/Core/EnhancementDashboardPresentation.swift`
- Modify: `macos-app/Views/EnhancementCenterView.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift`

**Interfaces:**
- Consumes:
  - `TradeSignalSummary`
  - `TradeSignalItem`
- Produces:
  - `EnhancementDashboardSummary.make(report:lastMonthlyReportExport:cookieAvailable:nativeConnectionAvailable:watchSummary:importSession:canUndoLatestImport:insightSummary:snapshotCount:trendStatus:tradeSignals:reminders:planSimulation:)`
  - Workbench `AI 操作观察` panel.

- [ ] **Step 1: Write failing presentation tests**

Append this test to `EnhancementDashboardPresentationTests`:

```swift
func testActionQueuePrioritizesTradeSignalsBeforeGenericReminders() {
    let tradeSignals = TradeSignalSummary(
        headline: "1 条 AI 操作观察",
        generatedAt: "2026-07-02 09:30:00",
        dataAsOf: "2026-07-03 15:00:00",
        triggeredCount: 1,
        staleAnalysis: true,
        items: [
            TradeSignalItem(
                id: "buy-000001",
                assetKey: "000001",
                assetName: "红利低波",
                assetCode: "000001",
                action: .watchBuy,
                status: .approaching,
                confidence: TrendConfidence(score: 78, label: "中"),
                title: "关注买入红利低波",
                reason: "基于上次 AI 分析：回撤未破坏中期逻辑。",
                triggerSummary: "继续回撤",
                invalidatingSummary: "趋势破位",
                dataAsOf: "2026-07-03 15:00:00",
                analysisGeneratedAt: "2026-07-02 09:30:00",
                isBasedOnStaleAnalysis: true,
                priority: 10
            )
        ]
    )
    let summary = makeDashboard(tradeSignals: tradeSignals)

    XCTAssertEqual(summary.actionQueue.first?.id, "trade-signal-buy-000001")
    XCTAssertEqual(summary.actionQueue.first?.title, "关注买入 · 红利低波")
    XCTAssertEqual(summary.actionQueue.first?.targetTab, .trend)
    XCTAssertEqual(summary.actionQueue.first?.kind, .selectTab)
    XCTAssertTrue(summary.actionQueue.first?.detail.contains("基于上次 AI 分析") == true)
}
```

Update the test helper signature and `EnhancementDashboardSummary.make` call in the same file:

```swift
tradeSignals: TradeSignalSummary = TradeSignalSummary(
    headline: "暂无 AI 操作观察",
    generatedAt: nil,
    dataAsOf: nil,
    triggeredCount: 0,
    staleAnalysis: false,
    items: []
)
```

Pass `tradeSignals: tradeSignals` into `EnhancementDashboardSummary.make`.

- [ ] **Step 2: Run presentation test and verify RED**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter EnhancementDashboardPresentationTests/testActionQueuePrioritizesTradeSignalsBeforeGenericReminders
```

Expected: FAIL because `EnhancementDashboardSummary.make` does not accept `tradeSignals`.

- [ ] **Step 3: Add trade signals to dashboard summary**

In `EnhancementDashboardSummary.make`, add parameter:

```swift
tradeSignals: TradeSignalSummary,
```

Thread it into `makeActionQueue`:

```swift
tradeSignals: tradeSignals,
```

In `makeActionQueue`, add parameter:

```swift
tradeSignals: TradeSignalSummary,
```

Insert this block after the trend external-signal item and before `reminders.items.prefix(3)`:

```swift
items.append(contentsOf: tradeSignals.items.prefix(3).map { signal in
    EnhancementActionItem(
        id: "trade-signal-\(signal.id)",
        title: "\(signal.action.displayText) · \(signal.assetName)",
        detail: signal.reason,
        metric: "\(signal.confidence.normalizedScore)",
        targetTab: .trend,
        kind: .selectTab,
        severity: signal.status == .invalidated ? .warning : (signal.action == .watchSell ? .warning : .info)
    )
})
```

In `EnhancementCenterView.dashboardSummary`, pass:

```swift
tradeSignals: model.tradeSignalSummary,
```

- [ ] **Step 4: Add workbench `AI 操作观察` panel**

In `EnhancementCenterView.reviewPanel`, insert `tradeSignalOverviewPanel` before `reportStatusStrip`:

```swift
tradeSignalOverviewPanel
```

Add this view inside `extension EnhancementCenterView`:

```swift
private var tradeSignalOverviewPanel: some View {
    let summary = model.tradeSignalSummary
    return VStack(alignment: .leading, spacing: AppPalette.spaceS) {
        HStack(alignment: .firstTextBaseline, spacing: AppPalette.spaceS) {
            Text("AI 操作观察")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            Text(summary.headline)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(summary.triggeredCount > 0 ? AppPalette.warning : AppPalette.muted)
            Spacer(minLength: 0)
            Button {
                model.selectedEnhancementTab = .trend
            } label: {
                Label("查看完整依据", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }

        if summary.items.isEmpty {
            compactFact("状态", summary.headline, tint: AppPalette.muted)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
                ForEach(summary.items.prefix(4)) { item in
                    tradeSignalCompactCard(item)
                }
            }
        }
    }
    .padding(AppPalette.spaceM)
    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    .overlay(
        RoundedRectangle(cornerRadius: AppPalette.cardRadius)
            .stroke(AppPalette.line.opacity(AppPalette.borderFaint), lineWidth: 1)
    )
}

private func tradeSignalCompactCard(_ item: TradeSignalItem) -> some View {
    let tint = tradeSignalTint(item)
    return VStack(alignment: .leading, spacing: 6) {
        HStack {
            Text(item.action.displayText)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Spacer(minLength: 4)
            Text("\(item.confidence.normalizedScore)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        Text(item.assetName)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AppPalette.ink)
            .lineLimit(1)
        Text(item.reason)
            .font(.system(size: 10))
            .foregroundStyle(AppPalette.muted)
            .lineLimit(2)
        Text("触发：\(item.triggerSummary)")
            .font(.system(size: 10))
            .foregroundStyle(AppPalette.info)
            .lineLimit(2)
    }
    .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
    .padding(AppPalette.spaceS)
    .background(tint.opacity(AppPalette.accentFill), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
    .overlay(
        RoundedRectangle(cornerRadius: AppPalette.controlRadius)
            .stroke(tint.opacity(AppPalette.accentBorder), lineWidth: 1)
    )
}

private func tradeSignalTint(_ item: TradeSignalItem) -> Color {
    switch item.action {
    case .watchBuy:
        return AppPalette.marketGain
    case .watchSell:
        return AppPalette.marketLoss
    case .rebalanceReview:
        return AppPalette.warning
    case .holdObserve, .waitForConfirmation:
        return AppPalette.info
    }
}
```

- [ ] **Step 5: Run presentation tests and verify GREEN**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter EnhancementDashboardPresentationTests
```

Expected: PASS.

- [ ] **Step 6: Commit Task 6**

```bash
git add macos-app/Core/EnhancementDashboardPresentation.swift macos-app/Views/EnhancementCenterView.swift macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift
git commit -m "feat: surface AI trade signals in workbench"
```

---

### Task 7: Trend Detail Panel, Settings Controls, and Full Verification

**Files:**
- Modify: `macos-app/Views/EnhancementTrendPanel.swift`
- Modify: `macos-app/Views/SettingsTrendPanel.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TradeSignalSettingsStoreTests.swift`

**Interfaces:**
- Consumes:
  - `AppModel.tradeSignalSummary`
  - `AppModel.tradeSignalSettings`
  - `AppModel.saveTradeSignalSettings()`
- Produces:
  - Trend-page detail view for all trade signals.
  - Trend settings controls for global preferences.

- [ ] **Step 1: Add a focused settings mutation test**

Append this test to `TradeSignalSettingsStoreTests`:

```swift
func testSettingsCanDisableBuyOrSellSignalFamilies() {
    var settings = TradeSignalSettings.default
    settings.allowBuySignals = false
    settings.allowSellSignals = true
    settings.localNotificationsEnabled = true

    XCTAssertFalse(settings.allowBuySignals)
    XCTAssertTrue(settings.allowSellSignals)
    XCTAssertTrue(settings.localNotificationsEnabled)
}
```

- [ ] **Step 2: Run the settings mutation test**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test --filter TradeSignalSettingsStoreTests/testSettingsCanDisableBuyOrSellSignalFamilies
```

Expected: PASS because Task 1 already made `TradeSignalSettings` mutable.

- [ ] **Step 3: Add trend-page signal detail**

In `EnhancementTrendPanel.swift`, add `tradeSignalDetailList` after `trendActionList(report.actions)` in `trendReportSidebarColumn(_:)`:

```swift
tradeSignalDetailList(model.tradeSignalSummary)
```

Add this helper in the same extension:

```swift
private func tradeSignalDetailList(_ summary: TradeSignalSummary) -> some View {
    trendBlock("操作观察", icon: "bell.badge") {
        if summary.items.isEmpty {
            trendEmptyState("暂无操作观察", detail: "生成趋势分析后，会根据 AI 动作候选和今日数据变化形成观察项。")
        } else {
            VStack(spacing: AppPalette.spaceS) {
                ForEach(summary.items) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.assetName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppPalette.ink)
                            Spacer(minLength: 4)
                            Text(item.action.displayText)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(tradeSignalTrendTint(item))
                        }
                        Text(item.reason)
                            .font(.system(size: 11))
                            .foregroundStyle(AppPalette.muted)
                        trendConditionRow(title: "触发", values: [item.triggerSummary])
                        trendConditionRow(title: "失效", values: [item.invalidatingSummary])
                        Text("\(item.status.displayText) · 置信 \(item.confidence.normalizedScore) · \(item.isBasedOnStaleAnalysis ? "基于上次 AI 分析" : "本轮 AI 分析")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppPalette.info)
                    }
                    .padding(11)
                    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                }
            }
        }
    }
}

private func tradeSignalTrendTint(_ item: TradeSignalItem) -> Color {
    switch item.action {
    case .watchBuy:
        return AppPalette.marketGain
    case .watchSell:
        return AppPalette.marketLoss
    case .rebalanceReview:
        return AppPalette.warning
    case .holdObserve, .waitForConfirmation:
        return AppPalette.info
    }
}
```

- [ ] **Step 4: Add settings controls**

In `SettingsTrendPanel.swift`, insert `tradeSignalPreferenceControls` after the daily time field and before `Picker("隐私模式", selection: trendPrivacyModeBinding)`:

```swift
tradeSignalPreferenceControls
SettingsDivider()
```

Add these helpers in `extension SettingsSectionView`:

```swift
private var tradeSignalPreferenceControls: some View {
    VStack(alignment: .leading, spacing: 12) {
        SettingsToggleRow(
            title: "AI 操作观察",
            detail: "基于趋势分析和今日数据变化生成关注项",
            icon: "bell.badge",
            tint: model.tradeSignalSettings.enabled ? AppPalette.positive : AppPalette.muted,
            isOn: tradeSignalEnabledBinding
        )
        SettingsToggleRow(
            title: "本地通知",
            detail: "同一标的同一信号当天限频提醒",
            icon: "bell.and.waves.left.and.right",
            tint: model.tradeSignalSettings.localNotificationsEnabled ? AppPalette.positive : AppPalette.muted,
            isOn: tradeSignalNotificationBinding
        )
        Picker("风险偏好", selection: tradeSignalRiskBinding) {
            ForEach(TradeSignalRiskPreference.allCases) { preference in
                Text(preference.displayText).tag(preference)
            }
        }
        .pickerStyle(.segmented)
        Picker("观察周期", selection: tradeSignalHorizonBinding) {
            ForEach(TradeSignalHorizonPreference.allCases) { horizon in
                Text(horizon.displayText).tag(horizon)
            }
        }
        .pickerStyle(.segmented)
        trendField("最低置信度", text: tradeSignalMinimumConfidenceBinding, placeholder: "60")
        HStack(spacing: AppPalette.spaceS) {
            Toggle("允许关注买入", isOn: tradeSignalAllowBuyBinding)
                .toggleStyle(.checkbox)
            Toggle("允许关注卖出", isOn: tradeSignalAllowSellBinding)
                .toggleStyle(.checkbox)
        }
        .font(.system(size: 11, weight: .medium))
    }
    .padding(.vertical, 13)
}

private var tradeSignalEnabledBinding: Binding<Bool> {
    Binding(
        get: { model.tradeSignalSettings.enabled },
        set: { value in
            model.tradeSignalSettings.enabled = value
            model.saveTradeSignalSettings()
        }
    )
}

private var tradeSignalNotificationBinding: Binding<Bool> {
    Binding(
        get: { model.tradeSignalSettings.localNotificationsEnabled },
        set: { value in
            model.tradeSignalSettings.localNotificationsEnabled = value
            model.saveTradeSignalSettings()
        }
    )
}

private var tradeSignalRiskBinding: Binding<TradeSignalRiskPreference> {
    Binding(
        get: { model.tradeSignalSettings.riskPreference },
        set: { value in
            model.tradeSignalSettings.riskPreference = value
            model.saveTradeSignalSettings()
        }
    )
}

private var tradeSignalHorizonBinding: Binding<TradeSignalHorizonPreference> {
    Binding(
        get: { model.tradeSignalSettings.primaryHorizon },
        set: { value in
            model.tradeSignalSettings.primaryHorizon = value
            model.saveTradeSignalSettings()
        }
    )
}

private var tradeSignalMinimumConfidenceBinding: Binding<String> {
    Binding(
        get: { "\(model.tradeSignalSettings.minimumConfidence)" },
        set: { rawValue in
            if let value = Int(rawValue) {
                model.tradeSignalSettings.minimumConfidence = min(100, max(0, value))
                model.saveTradeSignalSettings()
            }
        }
    )
}

private var tradeSignalAllowBuyBinding: Binding<Bool> {
    Binding(
        get: { model.tradeSignalSettings.allowBuySignals },
        set: { value in
            model.tradeSignalSettings.allowBuySignals = value
            model.saveTradeSignalSettings()
        }
    )
}

private var tradeSignalAllowSellBinding: Binding<Bool> {
    Binding(
        get: { model.tradeSignalSettings.allowSellSignals },
        set: { value in
            model.tradeSignalSettings.allowSellSignals = value
            model.saveTradeSignalSettings()
        }
    )
}
```

- [ ] **Step 5: Run full Swift tests**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test
```

Expected: PASS.

- [ ] **Step 6: Build the macOS app**

Run:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard
APP_VERSION=3.0.4 bash scripts/build_macos_app.sh
```

Expected: build completes and writes `dist/macos-app/QiemanDashboard.app`.

- [ ] **Step 7: Commit Task 7**

```bash
git add macos-app/Views/EnhancementTrendPanel.swift macos-app/Views/SettingsTrendPanel.swift macos-app/Tests/QiemanDashboardTests/TradeSignalSettingsStoreTests.swift
git commit -m "feat: add trade signal detail and settings UI"
```

---

## Final Verification

- [ ] Run all Swift tests:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/macos-app
swift test
```

- [ ] Build the app:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard
APP_VERSION=3.0.4 bash scripts/build_macos_app.sh
```

- [ ] Inspect changed files:

```bash
cd /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard
git status --short
git log --oneline -8
```

Expected: all task commits exist, no untracked `dist/`, `.build/`, or `.superpowers/` files are staged, and `swift test` plus build both passed.

## Self-Review Notes

- Spec coverage: settings, summary derivation, prompt preferences, workbench-first display, trend detail, today-data notification decision, stale report labeling, notification rate limiting, and tests are covered by Tasks 1-7.
- Type consistency: `TradeSignalSettings`, `TradeSignalSummary`, `TradeSignalNotificationDecision`, and `AppModel.tradeSignalSummary` names are stable across tasks.
- Scope check: this plan keeps the first version on existing `TrendAnalysisReport` fields and does not add a new model schema, external data source, or trading automation.
