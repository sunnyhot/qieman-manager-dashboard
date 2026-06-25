# AI Trend Summary Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface existing AI trend analysis on the Overview page as a compact combination of one-line conclusion, risk level, short/medium/long views, and sector views, while keeping asset-level AI interpretation in My Portfolio.

**Architecture:** Add a pure Core presentation model that derives Overview-ready data from `TrendAnalysisReport` and `EnhancementTrendStatus`. `OverviewSectionView` renders that model in a new `AITrendSummaryPanel`; `PortfolioSectionView` and asset detail continue to consume `TrendAssetTagIndex` for asset-level presentation.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, XCTest, Swift Package Manager in `macos-app/`.

## Global Constraints

- macOS app target remains macOS 14+ SwiftUI + AppKit.
- Python local service remains zero third-party dependencies; this plan does not touch Python.
- Chinese market convention remains red for gains and green for losses through `AppPalette`.
- Business calculation stays in Core; SwiftUI consumes presentation models.
- Reuse existing `TrendAnalysisReport`, `TrendAssetTagIndex`, `generateTrendAnalysis`, `EnhancementTrendStatus`, and `SectionCard`.
- Do not express AI output as deterministic investment advice; keep copy in candidate, observe, review, and conditional-trigger language.
- Do not write AI conclusions into raw portfolio data.
- Run tests from `macos-app/` with `swift test`.

---

## Scope Check

The approved spec covers one cohesive feature: surfacing the existing AI trend report in high-frequency views. It touches two user surfaces, but both consume the same `TrendAnalysisReport`; this does not need separate plans.

## File Structure

- Create `macos-app/Core/TrendDashboardSummary.swift`
  - Owns the pure presentation model for the Overview AI summary.
  - Contains text/tone mapping extensions for trend dashboard use.
- Create `macos-app/Tests/QiemanDashboardTests/TrendDashboardSummaryTests.swift`
  - Tests all summary states and report extraction.
- Modify `macos-app/Core/AppModel/TrendAnalysis.swift`
  - Adds `trendDashboardSummary` computed property.
- Modify `macos-app/Views/OverviewSectionView.swift`
  - Adds `AITrendSummaryPanel` and navigation/action handlers.
- Modify `macos-app/Views/PersonalAsset/PersonalAssetDetailSheet.swift`
  - Renames the asset detail trend section to `AI 观点` and keeps trigger/contradiction detail visible.
- Modify `macos-app/Tests/QiemanDashboardTests/PersonalAssetBrowserPresentationTests.swift`
  - Adds source-level guards for asset detail AI copy and existing trend table behavior.

## Task 1: Add Core Trend Dashboard Summary Model

**Files:**
- Create: `macos-app/Core/TrendDashboardSummary.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/TrendDashboardSummaryTests.swift`

**Interfaces:**
- Consumes: `TrendAnalysisReport`, `EnhancementTrendStatus`, `TrendGenerationState`, `TrendProgressLog`
- Produces:
  - `TrendDashboardSummary.make(report:trendStatus:generationState:lastError:progressLogs:) -> TrendDashboardSummary`
  - `TrendDashboardSummary.status: TrendDashboardStatus`
  - `TrendDashboardSummary.primaryAction.kind: TrendDashboardActionKind`
  - `TrendDashboardSummary.horizons: [TrendDashboardHorizonItem]`
  - `TrendDashboardSummary.sectors: [TrendDashboardSectorItem]`

- [ ] **Step 1: Write failing tests for dashboard summary states**

Create `macos-app/Tests/QiemanDashboardTests/TrendDashboardSummaryTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class TrendDashboardSummaryTests: XCTestCase {
    func testUnconfiguredProviderShowsSettingsAction() {
        let summary = TrendDashboardSummary.make(
            report: nil,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: false,
                generationState: .idle,
                lastGeneratedAt: nil,
                headline: "尚未配置趋势分析模型",
                externalSignalStatus: nil,
                isStale: false
            ),
            generationState: .idle,
            lastError: "",
            progressLogs: []
        )

        XCTAssertEqual(summary.status, .unconfigured)
        XCTAssertEqual(summary.headline, "尚未配置趋势分析模型")
        XCTAssertEqual(summary.primaryAction.kind, .configure)
        XCTAssertEqual(summary.primaryAction.title, "配置模型")
        XCTAssertTrue(summary.horizons.isEmpty)
        XCTAssertTrue(summary.sectors.isEmpty)
    }

    func testConfiguredProviderWithoutReportShowsGenerateAction() {
        let summary = TrendDashboardSummary.make(
            report: nil,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .idle,
                lastGeneratedAt: nil,
                headline: "等待生成趋势分析",
                externalSignalStatus: nil,
                isStale: false
            ),
            generationState: .idle,
            lastError: "",
            progressLogs: []
        )

        XCTAssertEqual(summary.status, .empty)
        XCTAssertEqual(summary.primaryAction.kind, .generate)
        XCTAssertEqual(summary.primaryAction.title, "立即分析")
        XCTAssertNil(summary.secondaryAction)
    }

    func testGeneratedReportExtractsHeadlineRiskHorizonsAndSectors() {
        let report = TrendAnalysisReport.fixture(
            generatedAt: "2026-06-25 09:30:00",
            externalSignalStatus: .available
        )
        let summary = TrendDashboardSummary.make(
            report: report,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .succeeded,
                lastGeneratedAt: report.generatedAt,
                headline: report.portfolio.headline,
                externalSignalStatus: report.externalSignalStatus,
                isStale: false
            ),
            generationState: .succeeded,
            lastError: "",
            progressLogs: []
        )

        XCTAssertEqual(summary.status, .ready)
        XCTAssertEqual(summary.headline, report.portfolio.headline)
        XCTAssertEqual(summary.riskText, report.portfolio.riskLevel.dashboardText)
        XCTAssertEqual(summary.primaryAction.kind, .openReport)
        XCTAssertEqual(summary.secondaryAction?.kind, .refresh)
        XCTAssertEqual(summary.horizons.map(\.title), ["短期", "中期", "长期"])
        XCTAssertEqual(summary.sectors.count, min(4, report.sectors.count))
        XCTAssertEqual(summary.dataAsOf, report.dataAsOf)
        XCTAssertEqual(summary.externalSignalText, "外部信号可用")
    }

    func testStaleReportMarksRefreshAsPrimaryAction() {
        let report = TrendAnalysisReport.fixture(
            generatedAt: "2026-06-24 09:30:00",
            externalSignalStatus: .partial
        )
        let summary = TrendDashboardSummary.make(
            report: report,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .succeeded,
                lastGeneratedAt: report.generatedAt,
                headline: report.portfolio.headline,
                externalSignalStatus: report.externalSignalStatus,
                isStale: true
            ),
            generationState: .succeeded,
            lastError: "",
            progressLogs: []
        )

        XCTAssertEqual(summary.status, .stale)
        XCTAssertEqual(summary.stateText, "待更新")
        XCTAssertEqual(summary.primaryAction.kind, .refresh)
        XCTAssertEqual(summary.secondaryAction?.kind, .openReport)
    }

    func testFailedGenerationKeepsRecoveryActionAndShortError() {
        let summary = TrendDashboardSummary.make(
            report: nil,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .failed,
                lastGeneratedAt: nil,
                headline: "模型请求失败",
                externalSignalStatus: nil,
                isStale: false
            ),
            generationState: .failed,
            lastError: "趋势分析模型请求失败：HTTP 429。服务商提示余额不足或无可用资源包。",
            progressLogs: []
        )

        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.primaryAction.kind, .refresh)
        XCTAssertTrue(summary.detail.contains("HTTP 429"))
        XCTAssertLessThanOrEqual(summary.detail.count, 48)
    }

    func testGeneratingStateUsesLatestProgressLogAndDisablesPrimaryAction() {
        let summary = TrendDashboardSummary.make(
            report: nil,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .generating,
                lastGeneratedAt: nil,
                headline: "等待模型返回",
                externalSignalStatus: nil,
                isStale: false
            ),
            generationState: .generating,
            lastError: "",
            progressLogs: [
                TrendProgressLog(timestamp: "2026-06-25 09:30:00", message: "启动趋势模型"),
                TrendProgressLog(timestamp: "2026-06-25 09:31:00", message: "等待模型返回：模型分析 已等待 1m")
            ]
        )

        XCTAssertEqual(summary.status, .generating)
        XCTAssertEqual(summary.primaryAction.kind, .wait)
        XCTAssertTrue(summary.primaryAction.isDisabled)
        XCTAssertEqual(summary.detail, "等待模型返回：模型分析 已等待 1m")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd macos-app
swift test --filter TrendDashboardSummaryTests
```

Expected: FAIL with errors like `cannot find 'TrendDashboardSummary' in scope`.

- [ ] **Step 3: Add minimal Core model implementation**

Create `macos-app/Core/TrendDashboardSummary.swift`:

```swift
import Foundation

enum TrendDashboardTone: Hashable {
    case brand
    case positive
    case info
    case warning
    case danger
    case muted
}

enum TrendDashboardStatus: Hashable {
    case unconfigured
    case empty
    case generating
    case ready
    case stale
    case failed
    case rejected
}

enum TrendDashboardActionKind: Hashable {
    case configure
    case generate
    case refresh
    case openReport
    case wait
}

struct TrendDashboardAction: Hashable {
    let kind: TrendDashboardActionKind
    let title: String
    let systemImage: String
    let tone: TrendDashboardTone
    let isPrimary: Bool
    let isDisabled: Bool
}

struct TrendDashboardHorizonItem: Identifiable, Hashable {
    let id: TrendHorizon
    let title: String
    let directionText: String
    let confidenceText: String
    let rationale: String
    let tone: TrendDashboardTone
}

struct TrendDashboardSectorItem: Identifiable, Hashable {
    let id: String
    let name: String
    let exposureText: String
    let directionText: String
    let confidenceText: String
    let rationale: String
    let tone: TrendDashboardTone
}

struct TrendDashboardSummary: Hashable {
    let status: TrendDashboardStatus
    let stateText: String
    let headline: String
    let detail: String
    let riskLevel: TrendRiskLevel?
    let riskText: String
    let riskTone: TrendDashboardTone
    let generatedAt: String?
    let dataAsOf: String?
    let externalSignalText: String?
    let externalSignalTone: TrendDashboardTone
    let horizons: [TrendDashboardHorizonItem]
    let sectors: [TrendDashboardSectorItem]
    let primaryAction: TrendDashboardAction
    let secondaryAction: TrendDashboardAction?

    static func make(
        report: TrendAnalysisReport?,
        trendStatus: EnhancementTrendStatus,
        generationState: TrendGenerationState,
        lastError: String,
        progressLogs: [TrendProgressLog]
    ) -> TrendDashboardSummary {
        if !trendStatus.isProviderConfigured {
            return empty(
                status: .unconfigured,
                stateText: "未配置",
                headline: "尚未配置趋势分析模型",
                detail: "先在设置中填写模型地址、模型名称和 API Key。",
                primaryAction: action(.configure, title: "配置模型", systemImage: "gearshape", tone: .warning)
            )
        }

        if generationState == .generating {
            return from(
                report: report,
                status: .generating,
                stateText: "生成中",
                fallbackHeadline: "正在生成 AI 趋势分析",
                detail: progressLogs.last?.message ?? "正在等待模型返回",
                primaryAction: action(.wait, title: "生成中", systemImage: "hourglass", tone: .info, isDisabled: true),
                secondaryAction: report == nil ? nil : action(.openReport, title: "查看旧报告", systemImage: "doc.text.magnifyingglass", tone: .info, isPrimary: false)
            )
        }

        if generationState == .failed {
            return from(
                report: report,
                status: .failed,
                stateText: "失败",
                fallbackHeadline: "AI 趋势分析生成失败",
                detail: clipped(lastError, fallback: "查看增强页了解失败原因"),
                primaryAction: action(.refresh, title: "重新分析", systemImage: "arrow.clockwise", tone: .warning),
                secondaryAction: report == nil ? nil : action(.openReport, title: "查看旧报告", systemImage: "doc.text.magnifyingglass", tone: .info, isPrimary: false)
            )
        }

        if generationState == .rejected {
            return from(
                report: report,
                status: .rejected,
                stateText: "已拦截",
                fallbackHeadline: "AI 趋势报告未通过安全校验",
                detail: clipped(lastError, fallback: "报告结构或措辞不符合展示规则"),
                primaryAction: action(.refresh, title: "重新分析", systemImage: "arrow.clockwise", tone: .warning),
                secondaryAction: report == nil ? nil : action(.openReport, title: "查看旧报告", systemImage: "doc.text.magnifyingglass", tone: .info, isPrimary: false)
            )
        }

        guard let report else {
            return empty(
                status: .empty,
                stateText: "未生成",
                headline: "等待生成 AI 趋势分析",
                detail: "将结合本地持仓、平台动态和模型可用的外部信号生成组合判断。",
                primaryAction: action(.generate, title: "立即分析", systemImage: "wand.and.stars", tone: .brand)
            )
        }

        if trendStatus.isStale {
            return from(
                report: report,
                status: .stale,
                stateText: "待更新",
                fallbackHeadline: report.portfolio.headline,
                detail: "这份报告不是今天生成，建议刷新后再用于复核。",
                primaryAction: action(.refresh, title: "重新分析", systemImage: "arrow.clockwise", tone: .warning),
                secondaryAction: action(.openReport, title: "查看完整报告", systemImage: "doc.text.magnifyingglass", tone: .info, isPrimary: false)
            )
        }

        return from(
            report: report,
            status: .ready,
            stateText: "已生成",
            fallbackHeadline: report.portfolio.headline,
            detail: report.portfolio.summary,
            primaryAction: action(.openReport, title: "查看完整报告", systemImage: "doc.text.magnifyingglass", tone: .brand),
            secondaryAction: action(.refresh, title: "重新分析", systemImage: "arrow.clockwise", tone: .info, isPrimary: false)
        )
    }

    private static func empty(
        status: TrendDashboardStatus,
        stateText: String,
        headline: String,
        detail: String,
        primaryAction: TrendDashboardAction
    ) -> TrendDashboardSummary {
        TrendDashboardSummary(
            status: status,
            stateText: stateText,
            headline: headline,
            detail: detail,
            riskLevel: nil,
            riskText: "风险未知",
            riskTone: .muted,
            generatedAt: nil,
            dataAsOf: nil,
            externalSignalText: nil,
            externalSignalTone: .muted,
            horizons: [],
            sectors: [],
            primaryAction: primaryAction,
            secondaryAction: nil
        )
    }

    private static func from(
        report: TrendAnalysisReport?,
        status: TrendDashboardStatus,
        stateText: String,
        fallbackHeadline: String,
        detail: String,
        primaryAction: TrendDashboardAction,
        secondaryAction: TrendDashboardAction?
    ) -> TrendDashboardSummary {
        let riskLevel = report?.portfolio.riskLevel
        let externalSignal = report?.externalSignalStatus
        return TrendDashboardSummary(
            status: status,
            stateText: stateText,
            headline: report?.portfolio.headline ?? fallbackHeadline,
            detail: clipped(detail, fallback: report?.portfolio.summary ?? fallbackHeadline),
            riskLevel: riskLevel,
            riskText: riskLevel?.dashboardText ?? "风险未知",
            riskTone: riskLevel?.dashboardTone ?? .muted,
            generatedAt: report?.generatedAt,
            dataAsOf: report?.dataAsOf,
            externalSignalText: externalSignal.map { "外部信号\($0.dashboardText)" },
            externalSignalTone: externalSignal?.dashboardTone ?? .muted,
            horizons: makeHorizons(report?.horizons ?? []),
            sectors: makeSectors(report?.sectors ?? []),
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        )
    }

    private static func makeHorizons(_ horizons: [TrendHorizonView]) -> [TrendDashboardHorizonItem] {
        TrendHorizon.allCases.map { horizon in
            if let item = horizons.first(where: { $0.horizon == horizon }) {
                return TrendDashboardHorizonItem(
                    id: horizon,
                    title: horizon.dashboardText,
                    directionText: item.direction.dashboardText,
                    confidenceText: "\(item.confidence.label)信心",
                    rationale: clipped(item.rationale, fallback: "暂无判断依据", maxLength: 72),
                    tone: item.direction.dashboardTone
                )
            }
            return TrendDashboardHorizonItem(
                id: horizon,
                title: horizon.dashboardText,
                directionText: "暂无判断",
                confidenceText: "低信心",
                rationale: "本次报告没有返回\(horizon.dashboardText)观点。",
                tone: .muted
            )
        }
    }

    private static func makeSectors(_ sectors: [TrendSectorView]) -> [TrendDashboardSectorItem] {
        sectors.prefix(4).map { sector in
            TrendDashboardSectorItem(
                id: sector.id,
                name: sector.name,
                exposureText: sector.exposureText,
                directionText: sector.direction.dashboardText,
                confidenceText: "\(sector.confidence.label)信心",
                rationale: clipped(sector.rationale, fallback: "暂无板块依据", maxLength: 72),
                tone: sector.direction.dashboardTone
            )
        }
    }

    private static func action(
        _ kind: TrendDashboardActionKind,
        title: String,
        systemImage: String,
        tone: TrendDashboardTone,
        isPrimary: Bool = true,
        isDisabled: Bool = false
    ) -> TrendDashboardAction {
        TrendDashboardAction(
            kind: kind,
            title: title,
            systemImage: systemImage,
            tone: tone,
            isPrimary: isPrimary,
            isDisabled: isDisabled
        )
    }

    private static func clipped(_ value: String, fallback: String, maxLength: Int = 48) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? fallback : trimmed
        guard source.count > maxLength else { return source }
        return "\(source.prefix(maxLength - 1))…"
    }
}

extension TrendRiskLevel {
    var dashboardText: String {
        switch self {
        case .low:
            return "低风险"
        case .medium:
            return "中风险"
        case .high:
            return "高风险"
        case .unknown:
            return "风险未知"
        }
    }

    var dashboardTone: TrendDashboardTone {
        switch self {
        case .low:
            return .positive
        case .medium:
            return .warning
        case .high:
            return .danger
        case .unknown:
            return .muted
        }
    }
}

extension TrendExternalSignalStatus {
    var dashboardText: String {
        switch self {
        case .available:
            return "可用"
        case .unavailable:
            return "不可用"
        case .partial:
            return "部分可用"
        case .stale:
            return "可能过期"
        }
    }

    var dashboardTone: TrendDashboardTone {
        switch self {
        case .available:
            return .positive
        case .unavailable:
            return .warning
        case .partial:
            return .info
        case .stale:
            return .warning
        }
    }
}

extension TrendHorizon {
    var dashboardText: String {
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

extension TrendDirection {
    var dashboardText: String {
        switch self {
        case .bullish:
            return "偏强"
        case .neutralPositive:
            return "中性偏强"
        case .neutral:
            return "中性"
        case .neutralNegative:
            return "中性偏弱"
        case .bearish:
            return "偏弱"
        case .uncertain:
            return "不确定"
        }
    }

    var dashboardTone: TrendDashboardTone {
        switch self {
        case .bullish, .neutralPositive:
            return .positive
        case .neutral:
            return .info
        case .neutralNegative, .bearish:
            return .warning
        case .uncertain:
            return .muted
        }
    }
}
```

- [ ] **Step 4: Run model tests to verify they pass**

Run:

```bash
cd macos-app
swift test --filter TrendDashboardSummaryTests
```

Expected: PASS for all `TrendDashboardSummaryTests`.

- [ ] **Step 5: Commit Task 1**

```bash
git add macos-app/Core/TrendDashboardSummary.swift macos-app/Tests/QiemanDashboardTests/TrendDashboardSummaryTests.swift
git commit -m "feat: derive trend dashboard summary"
```

## Task 2: Expose Trend Dashboard Summary Through AppModel

**Files:**
- Modify: `macos-app/Core/AppModel/TrendAnalysis.swift`
- Modify: `macos-app/Tests/QiemanDashboardTests/TrendAnalysisAppModelTests.swift`

**Interfaces:**
- Consumes: `TrendDashboardSummary.make(report:trendStatus:generationState:lastError:progressLogs:)`
- Produces: `AppModel.trendDashboardSummary: TrendDashboardSummary`

- [ ] **Step 1: Write failing AppModel test**

Append this test inside `TrendAnalysisAppModelTests`:

```swift
func testTrendDashboardSummaryReflectsCurrentTrendState() {
    let model = AppModel()
    let generatedAt = "\(String(AppModel.timestampString().prefix(10))) 09:30:00"
    let report = TrendAnalysisReport.fixture(
        generatedAt: generatedAt,
        externalSignalStatus: .available
    )
    model.trendSettings = makeProviderSettings()
    model.trendReport = report
    model.lastTrendGeneratedAt = report.generatedAt
    model.trendGenerationState = .succeeded

    let summary = model.trendDashboardSummary

    XCTAssertEqual(summary.status, .ready)
    XCTAssertEqual(summary.headline, report.portfolio.headline)
    XCTAssertEqual(summary.primaryAction.kind, .openReport)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd macos-app
swift test --filter TrendAnalysisAppModelTests/testTrendDashboardSummaryReflectsCurrentTrendState
```

Expected: FAIL with `value of type 'AppModel' has no member 'trendDashboardSummary'`.

- [ ] **Step 3: Add computed property**

In `macos-app/Core/AppModel/TrendAnalysis.swift`, add this property near `enhancementTrendStatus`:

```swift
var trendDashboardSummary: TrendDashboardSummary {
    TrendDashboardSummary.make(
        report: trendReport,
        trendStatus: enhancementTrendStatus,
        generationState: trendGenerationState,
        lastError: lastTrendError,
        progressLogs: trendProgressLogs
    )
}
```

- [ ] **Step 4: Run AppModel test**

Run:

```bash
cd macos-app
swift test --filter TrendAnalysisAppModelTests/testTrendDashboardSummaryReflectsCurrentTrendState
```

Expected: PASS.

- [ ] **Step 5: Run dashboard summary tests again**

Run:

```bash
cd macos-app
swift test --filter TrendDashboardSummaryTests
```

Expected: PASS.

- [ ] **Step 6: Commit Task 2**

```bash
git add macos-app/Core/AppModel/TrendAnalysis.swift macos-app/Tests/QiemanDashboardTests/TrendAnalysisAppModelTests.swift
git commit -m "feat: expose trend dashboard summary"
```

## Task 3: Add Overview AI Trend Summary Panel

**Files:**
- Modify: `macos-app/Views/OverviewSectionView.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendDashboardSummaryTests.swift`

**Interfaces:**
- Consumes: `model.trendDashboardSummary`
- Uses actions:
  - `.configure` sets `model.selectedSection = .settings`
  - `.generate` and `.refresh` call `await model.generateTrendAnalysis(userInitiated: true)`
  - `.openReport` sets `model.selectedEnhancementTab = .trend` and `model.selectedSection = .enhancement`
  - `.wait` does nothing
- Produces: `AITrendSummaryPanel` SwiftUI view inside `OverviewSectionView.swift`

- [ ] **Step 1: Add source-level rendering guard test**

Append this test to `TrendDashboardSummaryTests`:

```swift
func testOverviewSourceRendersAITrendSummaryPanel() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Views/OverviewSectionView.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    XCTAssertTrue(source.contains("AITrendSummaryPanel("))
    XCTAssertTrue(source.contains("summary: model.trendDashboardSummary"))
    XCTAssertTrue(source.contains("model.selectedEnhancementTab = .trend"))
    XCTAssertTrue(source.contains("await model.generateTrendAnalysis(userInitiated: true)"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd macos-app
swift test --filter TrendDashboardSummaryTests/testOverviewSourceRendersAITrendSummaryPanel
```

Expected: FAIL because `OverviewSectionView.swift` does not contain `AITrendSummaryPanel`.

- [ ] **Step 3: Insert the panel in the Overview content stack**

In `macos-app/Views/OverviewSectionView.swift`, update the body stack so the top section reads:

```swift
VStack(alignment: .leading, spacing: 14) {
    OverviewHeroCard()
    TodayBriefPanel(items: model.todayBriefItems, action: openBrief)
    AITrendSummaryPanel(
        summary: model.trendDashboardSummary,
        action: handleTrendDashboardAction
    )
    DashboardInsightPanel(
        managerSummary: model.managerActivitySummary,
        freshnessSummary: model.dashboardFreshnessSummary,
        managerAction: openManagerActivity,
        freshnessAction: openFreshness
    )
```

- [ ] **Step 4: Add action handler to `OverviewSectionView`**

Add this method near the other `open...` helpers:

```swift
private func handleTrendDashboardAction(_ action: TrendDashboardAction) {
    guard !action.isDisabled else { return }
    switch action.kind {
    case .configure:
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
            model.selectedSection = .settings
        }
    case .generate, .refresh:
        Task {
            await model.generateTrendAnalysis(userInitiated: true)
        }
    case .openReport:
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
            model.selectedEnhancementTab = .trend
            model.selectedSection = .enhancement
        }
    case .wait:
        break
    }
}
```

- [ ] **Step 5: Add panel and helper views at file scope**

Add these SwiftUI views below `DashboardInsightPanel` helpers in `OverviewSectionView.swift`:

```swift
struct AITrendSummaryPanel: View {
    let summary: TrendDashboardSummary
    let action: (TrendDashboardAction) -> Void

    var body: some View {
        SectionCard(title: "AI 趋势摘要", subtitle: subtitle, icon: "sparkles", trailing: {
            Spacer()
            ToolbarBadge(title: summary.stateText, tint: summary.status.tint)
            ToolbarBadge(title: summary.riskText, tint: summary.riskTone.color)
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(summary.riskTone.color)
                        .frame(width: 3, height: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary.headline)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(summary.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(AppPalette.muted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))

                if !summary.horizons.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                        ForEach(summary.horizons) { horizon in
                            AITrendHorizonCard(item: horizon)
                        }
                    }
                }

                if !summary.sectors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("板块观点")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                            ForEach(summary.sectors) { sector in
                                AITrendSectorCard(item: sector)
                            }
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        trendActionButton(summary.primaryAction)
                        if let secondaryAction = summary.secondaryAction {
                            trendActionButton(secondaryAction)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        trendActionButton(summary.primaryAction)
                        if let secondaryAction = summary.secondaryAction {
                            trendActionButton(secondaryAction)
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        [
            summary.dataAsOf.map { "数据 \($0)" },
            summary.externalSignalText,
            summary.generatedAt.map { "生成 \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    @ViewBuilder
    private func trendActionButton(_ item: TrendDashboardAction) -> some View {
        if item.isPrimary {
            Button {
                action(item)
            } label: {
                Label(item.title, systemImage: item.systemImage)
            }
            .buttonStyle(.borderedProminent)
            .tint(item.tone.color)
            .controlSize(.small)
            .disabled(item.isDisabled)
        } else {
            Button {
                action(item)
            } label: {
                Label(item.title, systemImage: item.systemImage)
            }
            .buttonStyle(.bordered)
            .tint(item.tone.color)
            .controlSize(.small)
            .disabled(item.isDisabled)
        }
    }
}

private struct AITrendHorizonCard: View {
    let item: TrendDashboardHorizonItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                Spacer(minLength: 4)
                Text(item.directionText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(item.tone.color)
            }
            Text(item.confidenceText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(item.tone.color)
            Text(item.rationale)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(AppPalette.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(item.tone.color.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct AITrendSectorCard: View {
    let item: TrendDashboardSectorItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(item.exposureText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.info)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(item.directionText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(item.tone.color)
                Text(item.confidenceText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
            }
            Text(item.rationale)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(item.tone.color.opacity(0.14), lineWidth: 1)
        )
    }
}

private extension TrendDashboardStatus {
    var tint: Color {
        switch self {
        case .unconfigured, .stale, .rejected:
            return AppPalette.warning
        case .empty, .generating:
            return AppPalette.info
        case .ready:
            return AppPalette.positive
        case .failed:
            return AppPalette.danger
        }
    }
}

private extension TrendDashboardTone {
    var color: Color {
        switch self {
        case .brand:
            return AppPalette.brand
        case .positive:
            return AppPalette.positive
        case .info:
            return AppPalette.info
        case .warning:
            return AppPalette.warning
        case .danger:
            return AppPalette.danger
        case .muted:
            return AppPalette.muted
        }
    }
}
```

- [ ] **Step 6: Run Overview source test**

Run:

```bash
cd macos-app
swift test --filter TrendDashboardSummaryTests/testOverviewSourceRendersAITrendSummaryPanel
```

Expected: PASS.

- [ ] **Step 7: Run dashboard summary test suite**

Run:

```bash
cd macos-app
swift test --filter TrendDashboardSummaryTests
```

Expected: PASS.

- [ ] **Step 8: Commit Task 3**

```bash
git add macos-app/Views/OverviewSectionView.swift macos-app/Tests/QiemanDashboardTests/TrendDashboardSummaryTests.swift
git commit -m "feat: show ai trend summary on overview"
```

## Task 4: Polish My Portfolio Asset-Level AI Presentation

**Files:**
- Modify: `macos-app/Views/PersonalAsset/PersonalAssetDetailSheet.swift`
- Modify: `macos-app/Tests/QiemanDashboardTests/PersonalAssetBrowserPresentationTests.swift`

**Interfaces:**
- Consumes: existing `TrendAssetTagSummary`, `TrendAssetTradePlan`, `TrendAssetInlineTag`
- Produces: Asset detail section labeled `AI 观点` with existing `trendTradePlanCard`, trigger conditions, contradiction conditions, and data timestamp.

- [ ] **Step 1: Add source-level tests for asset AI presentation**

Append these tests to `PersonalAssetBrowserPresentationTests`:

```swift
func testAssetDetailUsesAIOpinionCopyAndKeepsConditionsVisible() throws {
    let source = try String(contentsOf: personalAssetDetailSourceURL(), encoding: .utf8)

    XCTAssertTrue(source.contains("detailSection(title: \"AI 观点\", icon: \"sparkles\")"))
    XCTAssertTrue(source.contains("trendTradePlanCard(summary.tradePlan)"))
    XCTAssertTrue(source.contains("trendTradePlanList(title: \"触发\""))
    XCTAssertTrue(source.contains("trendTradePlanList(title: \"反证\""))
    XCTAssertTrue(source.contains("Text(\"数据 \\(summary.dataAsOf)\""))
}

func testTableRowKeepsTrendSignalBlockForAssetTags() throws {
    let source = try String(contentsOf: personalAssetTableRowSourceURL(), encoding: .utf8)

    XCTAssertTrue(source.contains("if let trendSummary"))
    XCTAssertTrue(source.contains("trendSignalBlock(trendSummary)"))
    XCTAssertTrue(source.contains("summary.tradePlan.label"))
    XCTAssertTrue(source.contains("summary.primaryConfidence.label"))
}
```

Add helper methods to the same test class:

```swift
private func personalAssetDetailSourceURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Views/PersonalAsset/PersonalAssetDetailSheet.swift")
}

private func personalAssetTableRowSourceURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Views/PersonalAsset/PersonalAssetTableRow.swift")
}
```

- [ ] **Step 2: Run tests to verify the copy test fails**

Run:

```bash
cd macos-app
swift test --filter PersonalAssetBrowserPresentationTests/testAssetDetailUsesAIOpinionCopyAndKeepsConditionsVisible
```

Expected: FAIL because the current section title is `趋势分析`.

- [ ] **Step 3: Rename the asset detail section**

In `macos-app/Views/PersonalAsset/PersonalAssetDetailSheet.swift`, change:

```swift
detailSection(title: "趋势分析", icon: "sparkles") {
```

to:

```swift
detailSection(title: "AI 观点", icon: "sparkles") {
```

- [ ] **Step 4: Run portfolio presentation tests**

Run:

```bash
cd macos-app
swift test --filter PersonalAssetBrowserPresentationTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 4**

```bash
git add macos-app/Views/PersonalAsset/PersonalAssetDetailSheet.swift macos-app/Tests/QiemanDashboardTests/PersonalAssetBrowserPresentationTests.swift
git commit -m "feat: label asset trend detail as ai opinion"
```

## Task 5: Final Verification

**Files:**
- Verify: `docs/superpowers/specs/2026-06-25-ai-trend-summary-design.md`
- Verify: `macos-app/Core/TrendDashboardSummary.swift`
- Verify: `macos-app/Views/OverviewSectionView.swift`
- Verify: `macos-app/Views/PersonalAsset/PersonalAssetDetailSheet.swift`

**Interfaces:**
- Confirms all previous task outputs work together.

- [ ] **Step 1: Run focused tests**

Run:

```bash
cd macos-app
swift test --filter TrendDashboardSummaryTests
swift test --filter TrendAnalysisAppModelTests/testTrendDashboardSummaryReflectsCurrentTrendState
swift test --filter PersonalAssetBrowserPresentationTests
```

Expected: PASS for all focused tests.

- [ ] **Step 2: Run full Swift test suite**

Run:

```bash
cd macos-app
swift test
```

Expected: PASS.

- [ ] **Step 3: Check working tree and staged changes**

Run:

```bash
git status --short
```

Expected: only unrelated pre-existing user changes remain, or a clean tree if the executor worked in an isolated worktree.

- [ ] **Step 4: Commit verification-only cleanup if needed**

If Step 2 exposed formatting or compile cleanup that was fixed after the task commits, commit only those feature-related files:

```bash
git add macos-app/Core/TrendDashboardSummary.swift macos-app/Core/AppModel/TrendAnalysis.swift macos-app/Views/OverviewSectionView.swift macos-app/Views/PersonalAsset/PersonalAssetDetailSheet.swift macos-app/Tests/QiemanDashboardTests/TrendDashboardSummaryTests.swift macos-app/Tests/QiemanDashboardTests/TrendAnalysisAppModelTests.swift macos-app/Tests/QiemanDashboardTests/PersonalAssetBrowserPresentationTests.swift
git commit -m "test: verify ai trend summary surfaces"
```

Expected: commit succeeds only if cleanup changes exist.
