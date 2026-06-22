# Trend Analysis Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an AI-powered `趋势` tab in the enhancement center with local AI configuration discovery, privacy-controlled portfolio context, structured trend reports, report caching, and optional daily auto-generation.

**Architecture:** Add focused Swift Core files for trend settings, local AI config discovery, context building, prompt building, report decoding, validation, storage, and AppModel orchestration. UI stays in the existing enhancement and settings surfaces, with trend presentation derived from Core state so most behavior is covered by XCTest.

**Tech Stack:** Swift 5.9, SwiftUI, Foundation URLSession, Codable JSON stores, XCTest, existing AppPalette and enhancement-center presentation patterns.

---

## File Structure

- Create `macos-app/Core/TrendAnalysisModels.swift`
  - Trend settings, privacy mode, generation state, local config candidates, context payloads, report schema, validation result types.
- Create `macos-app/Core/TrendAnalysisStore.swift`
  - JSON load/save for settings, latest report envelope, and generation metadata.
- Create `macos-app/Core/LocalAIConfigurationDetector.swift`
  - Best-effort local config discovery for process environment, Codex config, Claude/cc config presence, and OpenAI-compatible endpoints.
- Create `macos-app/Core/TrendAnalysisContextBuilder.swift`
  - Builds sanitized and full-detail model context from portfolio rows, summaries, platform actions, watch timeline, and snapshots.
- Create `macos-app/Core/TrendPromptBuilder.swift`
  - Creates strict JSON-only model prompts.
- Create `macos-app/Core/TrendAnalysisValidator.swift`
  - Validates decoded report structure, action constraints, unsafe wording, and external evidence status.
- Create `macos-app/Core/TrendAIClient.swift`
  - OpenAI-compatible chat-completions request client plus fake-client protocol support.
- Create `macos-app/Core/AppModel/TrendAnalysis.swift`
  - AppModel file URLs, load/save, detection, import, generation, daily auto-run, and presentation helpers.
- Modify `macos-app/Core/AppModel/SubModels.swift`
  - Add trend fields to `EnhancementState`; add `.trend` tab.
- Modify `macos-app/Core/AppModel/ComputedProperties.swift`
  - Add trend settings/report file URLs.
- Modify `macos-app/Core/AppModel.swift`
  - Add proxy properties for trend fields and invoke daily auto-run after startup data is loaded.
- Modify `macos-app/Core/EnhancementDashboardPresentation.swift`
  - Add trend status card and trend action-queue items.
- Modify `macos-app/Views/EnhancementCenterView.swift`
  - Add trend tab panel rendering.
- Modify `macos-app/Views/SettingsSectionView.swift`
  - Add `AI趋势` settings focus card.
- Create `macos-app/Views/SettingsTrendPanel.swift`
  - Provider settings, detect/import local config, daily auto toggle, privacy default.
- Create tests:
  - `macos-app/Tests/QiemanDashboardTests/LocalAIConfigurationDetectorTests.swift`
  - `macos-app/Tests/QiemanDashboardTests/TrendAnalysisContextBuilderTests.swift`
  - `macos-app/Tests/QiemanDashboardTests/TrendPromptBuilderTests.swift`
  - `macos-app/Tests/QiemanDashboardTests/TrendAnalysisValidatorTests.swift`
  - `macos-app/Tests/QiemanDashboardTests/TrendAnalysisStoreTests.swift`
  - `macos-app/Tests/QiemanDashboardTests/TrendAnalysisAppModelTests.swift`

## Task 1: Trend Domain Models And Store

**Files:**
- Create: `macos-app/Core/TrendAnalysisModels.swift`
- Create: `macos-app/Core/TrendAnalysisStore.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendAnalysisStoreTests.swift`

- [ ] **Step 1: Write failing store and settings tests**

Add `macos-app/Tests/QiemanDashboardTests/TrendAnalysisStoreTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class TrendAnalysisStoreTests: XCTestCase {
    func testSettingsStoreReturnsDefaultWhenFileIsMissing() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("trend-settings.json")

        let settings = try TrendAnalysisSettingsStore().load(from: url)

        XCTAssertEqual(settings.provider.baseURL, "")
        XCTAssertEqual(settings.provider.model, "")
        XCTAssertEqual(settings.defaultPrivacyMode, .sanitized)
        XCTAssertFalse(settings.dailyAutoAnalysisEnabled)
    }

    func testSettingsStoreSavesAndLoadsProviderSettings() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("trend-settings.json")
        let settings = TrendAnalysisSettings(
            provider: TrendAIProviderSettings(
                providerName: "OpenRouter",
                baseURL: "https://openrouter.ai/api",
                model: "perplexity/sonar",
                apiKey: "sk-test-value",
                supportsOnlineSearch: true,
                timeoutSeconds: 45
            ),
            defaultPrivacyMode: .fullDetail,
            dailyAutoAnalysisEnabled: true,
            lastAutoAnalysisDay: "2026-06-22"
        )

        try TrendAnalysisSettingsStore().save(settings, to: url)
        let loaded = try TrendAnalysisSettingsStore().load(from: url)

        XCTAssertEqual(loaded, settings)
    }

    func testReportStoreKeepsLatestSuccessfulReport() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("trend-report.json")
        let report = TrendAnalysisReport.fixture(
            generatedAt: "2026-06-22 10:00:00",
            externalSignalStatus: .available
        )

        try TrendAnalysisReportStore().save(report, to: url)
        let loaded = try TrendAnalysisReportStore().load(from: url)

        XCTAssertEqual(loaded?.generatedAt, "2026-06-22 10:00:00")
        XCTAssertEqual(loaded?.externalSignalStatus, .available)
    }

    func testSameDayAutoAnalysisUsesShanghaiCalendarDay() {
        let settings = TrendAnalysisSettings(
            provider: .empty,
            defaultPrivacyMode: .sanitized,
            dailyAutoAnalysisEnabled: true,
            lastAutoAnalysisDay: "2026-06-22"
        )

        XCTAssertTrue(settings.hasAutoAnalyzed(on: "2026-06-22"))
        XCTAssertFalse(settings.hasAutoAnalyzed(on: "2026-06-23"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trend-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private extension TrendAnalysisReport {
    static func fixture(
        generatedAt: String,
        externalSignalStatus: TrendExternalSignalStatus
    ) -> TrendAnalysisReport {
        TrendAnalysisReport(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            generatedAt: generatedAt,
            dataAsOf: "2026-06-22 09:58:00",
            privacyMode: .sanitized,
            externalSignalStatus: externalSignalStatus,
            portfolio: TrendPortfolioSummary(
                headline: "组合偏中性",
                riskLevel: .medium,
                summary: "仓位集中度可控，外部信号需要继续观察。"
            ),
            horizons: [
                TrendHorizonView(
                    horizon: .short,
                    direction: .neutral,
                    confidence: TrendConfidence(score: 62, label: "中"),
                    rationale: "短期缺少明确突破信号。",
                    counterSignals: ["成交量放大后可能改变短期判断"]
                )
            ],
            sectors: [],
            keyAssets: [],
            actions: [],
            evidence: [],
            warnings: [],
            disclaimer: "非投资建议，仅供个人研究参考。"
        )
    }
}
```

- [ ] **Step 2: Run the store tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter TrendAnalysisStoreTests
```

Expected: compile failure because `TrendAnalysisSettings`, `TrendAnalysisReport`, and the stores do not exist.

- [ ] **Step 3: Add the domain model file**

Create `macos-app/Core/TrendAnalysisModels.swift` with:

```swift
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
        guard trimmed.count > 8 else { return trimmed.isEmpty ? "" : "••••" }
        return "\(trimmed.prefix(3))…\(trimmed.suffix(4))"
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
            && (apiKey != nil || apiKeySource != nil)
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
```

- [ ] **Step 4: Add the JSON stores**

Create `macos-app/Core/TrendAnalysisStore.swift` with:

```swift
import Foundation

struct TrendAnalysisSettingsStore {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load(from fileURL: URL) throws -> TrendAnalysisSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(TrendAnalysisSettings.self, from: data)
    }

    func save(_ settings: TrendAnalysisSettings, to fileURL: URL) throws {
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

struct TrendAnalysisReportStore {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load(from fileURL: URL) throws -> TrendAnalysisReport? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(TrendAnalysisReport.self, from: data)
    }

    func save(_ report: TrendAnalysisReport, to fileURL: URL) throws {
        let data = try encoder.encode(report)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 5: Run the store tests to verify they pass**

Run:

```bash
swift test --package-path macos-app --filter TrendAnalysisStoreTests
```

Expected: all `TrendAnalysisStoreTests` pass.

- [ ] **Step 6: Commit domain models and store**

```bash
git add macos-app/Core/TrendAnalysisModels.swift macos-app/Core/TrendAnalysisStore.swift macos-app/Tests/QiemanDashboardTests/TrendAnalysisStoreTests.swift
git commit -m "feat: add trend analysis domain store"
```

## Task 2: Local AI Configuration Detection

**Files:**
- Create: `macos-app/Core/LocalAIConfigurationDetector.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/LocalAIConfigurationDetectorTests.swift`

- [ ] **Step 1: Write failing detector tests**

Add `macos-app/Tests/QiemanDashboardTests/LocalAIConfigurationDetectorTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class LocalAIConfigurationDetectorTests: XCTestCase {
    func testDetectsOpenAICompatibleEnvironmentCandidate() throws {
        let detector = LocalAIConfigurationDetector(
            homeDirectory: try temporaryDirectory(),
            environment: [
                "OPENAI_API_KEY": "sk-live-secret",
                "OPENAI_BASE_URL": "https://api.openai.com/v1",
                "OPENAI_MODEL": "gpt-4.1"
            ]
        )

        let candidates = detector.detect()

        let candidate = try XCTUnwrap(candidates.first { $0.id == "env-openai" })
        XCTAssertTrue(candidate.canImport)
        XCTAssertEqual(candidate.providerName, "OpenAI-compatible environment")
        XCTAssertEqual(candidate.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(candidate.model, "gpt-4.1")
        XCTAssertEqual(candidate.maskedAPIKey, "sk-…cret")
        XCTAssertFalse(candidate.sourceDescription.contains("sk-live-secret"))
    }

    func testDetectsCodexConfigWithoutExposingEnvSecret() throws {
        let home = try temporaryDirectory()
        let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try """
        model = "openai/gpt-4.1"
        [model_providers.openrouter]
        base_url = "https://openrouter.ai/api/v1"
        env_key = "OPENROUTER_API_KEY"
        """.write(to: codexDirectory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let detector = LocalAIConfigurationDetector(
            homeDirectory: home,
            environment: ["OPENROUTER_API_KEY": "sk-or-secret"]
        )

        let candidates = detector.detect()

        let candidate = try XCTUnwrap(candidates.first { $0.id == "codex-openrouter" })
        XCTAssertTrue(candidate.canImport)
        XCTAssertEqual(candidate.baseURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(candidate.apiKeySource, "OPENROUTER_API_KEY")
        XCTAssertEqual(candidate.maskedAPIKey, "sk-…cret")
    }

    func testClaudeConfigIsDetectedButNotImportableForOpenAICompatibleClient() throws {
        let home = try temporaryDirectory()
        try "{}".write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)

        let detector = LocalAIConfigurationDetector(
            homeDirectory: home,
            environment: ["ANTHROPIC_API_KEY": "sk-ant-secret"]
        )

        let candidates = detector.detect()

        let candidate = try XCTUnwrap(candidates.first { $0.id == "claude-direct" })
        XCTAssertFalse(candidate.canImport)
        XCTAssertEqual(candidate.compatibility, .needsCompatibleEndpoint)
        XCTAssertEqual(candidate.maskedAPIKey, "sk-…cret")
        XCTAssertTrue(candidate.warning?.contains("OpenAI-compatible") == true)
    }

    func testDetectorReturnsStableOrderByConfidence() throws {
        let home = try temporaryDirectory()
        let detector = LocalAIConfigurationDetector(
            homeDirectory: home,
            environment: [
                "ANTHROPIC_API_KEY": "sk-ant-secret",
                "OPENAI_API_KEY": "sk-openai-secret",
                "OPENAI_BASE_URL": "https://api.openai.com/v1",
                "OPENAI_MODEL": "gpt-4.1"
            ]
        )

        let candidates = detector.detect()

        XCTAssertEqual(candidates.first?.id, "env-openai")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-ai-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [ ] **Step 2: Run the detector tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter LocalAIConfigurationDetectorTests
```

Expected: compile failure because `LocalAIConfigurationDetector` does not exist.

- [ ] **Step 3: Add the detector**

Create `macos-app/Core/LocalAIConfigurationDetector.swift`:

```swift
import Foundation

struct LocalAIConfigurationDetector {
    let homeDirectory: URL
    let environment: [String: String]
    let fileManager: FileManager

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.fileManager = fileManager
    }

    func detect() -> [LocalAIConfigurationCandidate] {
        var candidates: [LocalAIConfigurationCandidate] = []
        if let envCandidate = openAIEnvironmentCandidate() {
            candidates.append(envCandidate)
        }
        candidates.append(contentsOf: codexCandidates())
        if let claudeCandidate = claudeCandidate() {
            candidates.append(claudeCandidate)
        }
        return candidates
            .uniquedByID()
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.providerName < rhs.providerName
                }
                return lhs.confidence > rhs.confidence
            }
    }

    private func openAIEnvironmentCandidate() -> LocalAIConfigurationCandidate? {
        guard let apiKey = environment["OPENAI_API_KEY"], !apiKey.isEmpty else { return nil }
        let baseURL = environment["OPENAI_BASE_URL"] ?? environment["OPENAI_API_BASE"] ?? "https://api.openai.com/v1"
        let model = environment["OPENAI_MODEL"] ?? environment["MODEL"] ?? ""
        return LocalAIConfigurationCandidate(
            id: "env-openai",
            providerName: "OpenAI-compatible environment",
            sourceDescription: "Process environment: OPENAI_API_KEY",
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            apiKeySource: "OPENAI_API_KEY",
            compatibility: model.isEmpty ? .incomplete : .openAICompatible,
            confidence: model.isEmpty ? 60 : 95,
            warning: model.isEmpty ? "检测到 API Key，但缺少 OPENAI_MODEL。" : nil
        )
    }

    private func codexCandidates() -> [LocalAIConfigurationCandidate] {
        let configURL = homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)
        guard
            fileManager.fileExists(atPath: configURL.path),
            let content = try? String(contentsOf: configURL, encoding: .utf8)
        else {
            return []
        }

        let globalModel = firstQuotedValue(named: "model", in: content)
        let providerBlocks = parseProviderBlocks(content)
        return providerBlocks.compactMap { block in
            guard let baseURL = firstQuotedValue(named: "base_url", in: block.body) else { return nil }
            let envKey = firstQuotedValue(named: "env_key", in: block.body)
            let apiKey = envKey.flatMap { environment[$0] }
            let model = firstQuotedValue(named: "model", in: block.body) ?? globalModel ?? ""
            let isCompatible = baseURL.contains("/v1") || baseURL.contains("openai") || baseURL.contains("openrouter")
            return LocalAIConfigurationCandidate(
                id: "codex-\(block.name)",
                providerName: "Codex \(block.name)",
                sourceDescription: "~/.codex/config.toml",
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                apiKeySource: envKey,
                compatibility: isCompatible && !model.isEmpty ? .openAICompatible : .incomplete,
                confidence: isCompatible && apiKey != nil && !model.isEmpty ? 90 : 55,
                warning: apiKey == nil && envKey != nil ? "检测到 \(envKey!) 引用，但当前 App 进程没有这个环境变量。" : nil
            )
        }
    }

    private func claudeCandidate() -> LocalAIConfigurationCandidate? {
        let claudeJSON = homeDirectory.appendingPathComponent(".claude.json", isDirectory: false)
        let claudeDirectory = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        let hasClaudeConfig = fileManager.fileExists(atPath: claudeJSON.path) || fileManager.fileExists(atPath: claudeDirectory.path)
        guard hasClaudeConfig || environment["ANTHROPIC_API_KEY"] != nil else { return nil }
        return LocalAIConfigurationCandidate(
            id: "claude-direct",
            providerName: "Claude/cc direct",
            sourceDescription: hasClaudeConfig ? "Claude local config" : "Process environment: ANTHROPIC_API_KEY",
            baseURL: environment["ANTHROPIC_BASE_URL"],
            model: environment["ANTHROPIC_MODEL"],
            apiKey: environment["ANTHROPIC_API_KEY"],
            apiKeySource: "ANTHROPIC_API_KEY",
            compatibility: .needsCompatibleEndpoint,
            confidence: 50,
            warning: "检测到 Claude/cc 配置；首版趋势分析只直接支持 OpenAI-compatible endpoint。"
        )
    }

    private func firstQuotedValue(named name: String, in content: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?m)^\\s*\(escapedName)\\s*=\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              let valueRange = Range(match.range(at: 1), in: content) else {
            return nil
        }
        return String(content[valueRange])
    }

    private func parseProviderBlocks(_ content: String) -> [(name: String, body: String)] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [(name: String, body: [String])] = []
        var currentName: String?
        var currentBody: [String] = []

        for line in lines {
            if let name = providerName(from: line) {
                if let currentName {
                    blocks.append((currentName, currentBody))
                }
                currentName = name
                currentBody = []
            } else if currentName != nil {
                currentBody.append(line)
            }
        }
        if let currentName {
            blocks.append((currentName, currentBody))
        }

        return blocks.map { ($0.name, $0.body.joined(separator: "\n")) }
    }

    private func providerName(from line: String) -> String? {
        let pattern = #"^\s*\[model_providers\.([^\]]+)\]\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[valueRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}

private extension Array where Element == LocalAIConfigurationCandidate {
    func uniquedByID() -> [LocalAIConfigurationCandidate] {
        var seen = Set<String>()
        var result: [LocalAIConfigurationCandidate] = []
        for candidate in self where !seen.contains(candidate.id) {
            seen.insert(candidate.id)
            result.append(candidate)
        }
        return result
    }
}
```

- [ ] **Step 4: Run detector tests**

Run:

```bash
swift test --package-path macos-app --filter LocalAIConfigurationDetectorTests
```

Expected: all detector tests pass.

- [ ] **Step 5: Commit detector**

```bash
git add macos-app/Core/LocalAIConfigurationDetector.swift macos-app/Tests/QiemanDashboardTests/LocalAIConfigurationDetectorTests.swift
git commit -m "feat: detect local ai provider settings"
```

## Task 3: Trend Context Builder

**Files:**
- Create: `macos-app/Core/TrendAnalysisContextBuilder.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendAnalysisContextBuilderTests.swift`

- [ ] **Step 1: Write failing context tests**

Add tests that build two `PersonalAssetAggregateRow` values using `UserPortfolioValuationRow` and assert sanitized context excludes real amounts while full-detail context includes them:

```swift
import XCTest
@testable import QiemanDashboard

final class TrendAnalysisContextBuilderTests: XCTestCase {
    func testSanitizedContextExcludesRealAmounts() {
        let rows = [
            aggregateRow(code: "510300", name: "沪深300ETF", marketValue: 120_000, costValue: 100_000, profitAmount: 20_000, profitPct: 20, estimateChangePct: 1.2),
            aggregateRow(code: "513100", name: "纳指ETF", marketValue: 80_000, costValue: 90_000, profitAmount: -10_000, profitPct: -11.1, estimateChangePct: -0.8)
        ]

        let context = TrendAnalysisContextBuilder().build(
            rows: rows,
            summary: PersonalAssetAggregateSummary(
                fundCount: 2,
                holdingFundCount: 2,
                pendingFundCount: 0,
                activePlanFundCount: 0,
                totalMarketValue: 200_000,
                totalPendingCashAmount: 0,
                totalActivePlanCount: 0,
                totalPausedPlanCount: 0,
                totalEndedPlanCount: 0,
                totalCumulativePlanAmount: 0,
                totalEstimatedNextPlanAmount: 0,
                totalEffectiveHoldingAmount: 200_000
            ),
            platformActions: [],
            watchSummary: ManagerWatchTimelineSummary.make(events: []),
            insightSummary: PortfolioSnapshotInsightSummary(headline: "已记录快照", hasEnoughHistory: true, cards: []),
            privacyMode: .sanitized,
            createdAt: "2026-06-22 11:00:00"
        )

        let encoded = context.debugJSONString()
        XCTAssertFalse(encoded.contains("120000"))
        XCTAssertFalse(encoded.contains("100000"))
        XCTAssertFalse(encoded.contains("20000"))
        XCTAssertTrue(encoded.contains("60.00%"))
        XCTAssertTrue(encoded.contains("510300"))
    }

    func testFullDetailContextIncludesRealAmountsAfterSelection() {
        let row = aggregateRow(code: "510300", name: "沪深300ETF", marketValue: 120_000, costValue: 100_000, profitAmount: 20_000, profitPct: 20, estimateChangePct: 1.2)

        let context = TrendAnalysisContextBuilder().build(
            rows: [row],
            summary: nil,
            platformActions: [],
            watchSummary: ManagerWatchTimelineSummary.make(events: []),
            insightSummary: PortfolioSnapshotInsightSummary(headline: "等待组合快照", hasEnoughHistory: false, cards: []),
            privacyMode: .fullDetail,
            createdAt: "2026-06-22 11:00:00"
        )

        let encoded = context.debugJSONString()
        XCTAssertTrue(encoded.contains("120000"))
        XCTAssertTrue(encoded.contains("100000"))
        XCTAssertTrue(encoded.contains("20000"))
    }

    func testSectorGroupingUsesAssetTypeAndMarketHints() {
        let rows = [
            aggregateRow(code: "510300", name: "沪深300ETF", marketValue: 120_000, costValue: 100_000, profitAmount: 20_000, profitPct: 20, estimateChangePct: 1.2),
            aggregateRow(code: "AAPL", name: "Apple", assetType: .stock, stockMarket: .us, marketValue: 50_000, costValue: 40_000, profitAmount: 10_000, profitPct: 25, estimateChangePct: 0.4)
        ]

        let context = TrendAnalysisContextBuilder().build(
            rows: rows,
            summary: nil,
            platformActions: [],
            watchSummary: ManagerWatchTimelineSummary.make(events: []),
            insightSummary: PortfolioSnapshotInsightSummary(headline: "等待组合快照", hasEnoughHistory: false, cards: []),
            privacyMode: .sanitized,
            createdAt: "2026-06-22 11:00:00"
        )

        XCTAssertTrue(context.sectors.contains { $0.name == "场内基金" })
        XCTAssertTrue(context.sectors.contains { $0.name == "美股" })
    }
}
```

Add these helper functions at the bottom of the same test file:

```swift
private func aggregateRow(
    code: String,
    name: String,
    assetType: PersonalAssetType = .fund,
    stockMarket: StockMarket? = nil,
    fundMarket: FundMarket? = .onExchange,
    marketValue: Double,
    costValue: Double,
    profitAmount: Double,
    profitPct: Double,
    estimateChangePct: Double
) -> PersonalAssetAggregateRow {
    let units = 100.0
    let holding = UserPortfolioHolding(
        fundCode: code,
        assetType: assetType,
        units: units,
        costPrice: costValue / units,
        displayName: name,
        stockMarket: stockMarket,
        fundMarket: assetType == .fund ? fundMarket : nil
    )
    let valuation = UserPortfolioValuationRow(
        holding: holding,
        fundName: name,
        currentPrice: marketValue / units,
        priceTime: "2026-06-22 10:00:00",
        priceSource: "测试估值",
        officialNav: nil,
        officialNavDate: nil,
        estimatePrice: marketValue / units,
        estimatePriceTime: "2026-06-22 10:00:00",
        marketValue: marketValue,
        costValue: costValue,
        profitAmount: profitAmount,
        profitPct: profitPct,
        estimateChangePct: estimateChangePct
    )
    return PersonalAssetAggregateRow(
        key: "\(assetType.rawValue)-\(code)",
        assetType: assetType,
        fundName: name,
        fundCode: code,
        holdingRow: valuation,
        rawHolding: holding,
        archivedHolding: nil,
        pendingTrades: [],
        plans: []
    )
}
```

- [ ] **Step 2: Run context tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter TrendAnalysisContextBuilderTests
```

Expected: compile failure because `TrendAnalysisContextBuilder` and context payload types do not exist.

- [ ] **Step 3: Add context payload models and builder**

Append context structs to `TrendAnalysisModels.swift` and create `TrendAnalysisContextBuilder.swift`. The builder must calculate `weightText` only in sanitized mode and must not include `marketValue`, `costValue`, `profitAmount`, `pendingCashAmount`, `estimatedNextPlanAmount`, or `totalCumulativePlanAmount` unless privacy mode is `.fullDetail`.

Key implementation shape:

```swift
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
```

`TrendAnalysisContextBuilder.build(...)` should:

- sort assets by `effectiveHoldingAmount` descending;
- compute sanitized weight as `row.effectiveHoldingAmount / totalEffectiveAmount`;
- include `profitPct`, `estimateChangePct`, plan counts, pending trade counts, and status text in both modes;
- include actual amount fields only in `.fullDetail`;
- map sectors with these first-version rules:
  - stock market `.us` -> `美股`;
  - stock market `.hk` -> `港股`;
  - stock market `.aShare` -> `A股`;
  - fund market `.onExchange` -> `场内基金`;
  - fund market `.offExchange` -> `场外基金`;
  - no known market -> asset type display name.

- [ ] **Step 4: Run context tests**

Run:

```bash
swift test --package-path macos-app --filter TrendAnalysisContextBuilderTests
```

Expected: all context builder tests pass.

- [ ] **Step 5: Commit context builder**

```bash
git add macos-app/Core/TrendAnalysisModels.swift macos-app/Core/TrendAnalysisContextBuilder.swift macos-app/Tests/QiemanDashboardTests/TrendAnalysisContextBuilderTests.swift
git commit -m "feat: build privacy-aware trend context"
```

## Task 4: Prompt Builder And Report Validator

**Files:**
- Create: `macos-app/Core/TrendPromptBuilder.swift`
- Create: `macos-app/Core/TrendAnalysisValidator.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendPromptBuilderTests.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendAnalysisValidatorTests.swift`

- [ ] **Step 1: Write failing prompt tests**

Add `TrendPromptBuilderTests` asserting the prompt contains:

```swift
XCTAssertTrue(prompt.system.contains("Return valid JSON only"))
XCTAssertTrue(prompt.system.contains("Do not guarantee returns"))
XCTAssertTrue(prompt.system.contains("Do not use mandatory buy/sell language"))
XCTAssertTrue(prompt.system.contains("counterSignals"))
XCTAssertTrue(prompt.user.contains("\"privacyMode\":\"sanitized\""))
```

- [ ] **Step 2: Write failing validator tests**

Add `TrendAnalysisValidatorTests`:

```swift
func testRejectsMandatoryBuySellLanguage() {
    var report = TrendAnalysisReport.fixture(generatedAt: "2026-06-22 12:00:00", externalSignalStatus: .available)
    report = report.replacingActions([
        TrendActionCandidate(
            id: "buy-now",
            kind: .considerIncrease,
            title: "必须买入沪深300",
            detail: "保证上涨。",
            targetName: "沪深300ETF",
            confidence: TrendConfidence(score: 90, label: "高"),
            triggerConditions: ["放量突破"],
            invalidatingConditions: ["跌破均线"]
        )
    ])

    let result = TrendAnalysisValidator().validate(report)

    XCTAssertFalse(result.isValid)
    XCTAssertTrue(result.messages.contains { $0.contains("absolute") || $0.contains("强制") })
}

func testRejectsActionWithoutConditions() {
    var report = TrendAnalysisReport.fixture(generatedAt: "2026-06-22 12:00:00", externalSignalStatus: .available)
    report = report.replacingActions([
        TrendActionCandidate(
            id: "watch",
            kind: .watch,
            title: "关注纳指",
            detail: "波动加大。",
            targetName: "纳指ETF",
            confidence: TrendConfidence(score: 60, label: "中"),
            triggerConditions: [],
            invalidatingConditions: ["美元流动性改善"]
        )
    ])

    let result = TrendAnalysisValidator().validate(report)

    XCTAssertFalse(result.isValid)
    XCTAssertTrue(result.messages.contains { $0.contains("trigger") || $0.contains("触发") })
}
```

- [ ] **Step 3: Run prompt and validator tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter TrendPromptBuilderTests
swift test --package-path macos-app --filter TrendAnalysisValidatorTests
```

Expected: compile failure because builder and validator do not exist.

- [ ] **Step 4: Implement prompt builder**

Create `TrendPromptBuilder.swift` with a `TrendModelPrompt` struct and `build(context:settings:)` method. The system prompt must include the exact English constraints from the prompt tests and Chinese investment-boundary wording for the model output.

- [ ] **Step 5: Implement validator**

Create `TrendAnalysisValidator.swift`:

```swift
import Foundation

struct TrendValidationResult: Hashable {
    let isValid: Bool
    let messages: [String]

    static let valid = TrendValidationResult(isValid: true, messages: [])
}

struct TrendAnalysisValidator {
    private let forbiddenTerms = ["必须买入", "必须卖出", "一定上涨", "一定卖出", "保证上涨", "保证收益"]

    func validate(_ report: TrendAnalysisReport) -> TrendValidationResult {
        var messages: [String] = []
        if report.horizons.isEmpty {
            messages.append("缺少短中长期趋势。")
        }
        if report.disclaimer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("缺少非投资建议声明。")
        }
        for action in report.actions {
            if action.triggerConditions.isEmpty {
                messages.append("行动候选缺少 trigger/触发条件：\(action.title)")
            }
            if action.invalidatingConditions.isEmpty {
                messages.append("行动候选缺少 invalidating/反证条件：\(action.title)")
            }
        }
        let searchableText = ([report.portfolio.headline, report.portfolio.summary, report.disclaimer]
            + report.actions.flatMap { [$0.title, $0.detail] }
            + report.horizons.flatMap { [$0.rationale] + $0.counterSignals })
            .joined(separator: "\n")
        for term in forbiddenTerms where searchableText.contains(term) {
            messages.append("包含强制或 absolute 表述：\(term)")
        }
        return messages.isEmpty ? .valid : TrendValidationResult(isValid: false, messages: messages)
    }
}
```

- [ ] **Step 6: Run prompt and validator tests**

Run:

```bash
swift test --package-path macos-app --filter TrendPromptBuilderTests
swift test --package-path macos-app --filter TrendAnalysisValidatorTests
```

Expected: all prompt and validator tests pass.

- [ ] **Step 7: Commit prompt and validator**

```bash
git add macos-app/Core/TrendPromptBuilder.swift macos-app/Core/TrendAnalysisValidator.swift macos-app/Tests/QiemanDashboardTests/TrendPromptBuilderTests.swift macos-app/Tests/QiemanDashboardTests/TrendAnalysisValidatorTests.swift
git commit -m "feat: constrain trend model output"
```

## Task 5: OpenAI-Compatible Client With Fake Client Testing

**Files:**
- Create: `macos-app/Core/TrendAIClient.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendAIClientTests.swift`

- [ ] **Step 1: Write failing request-building tests**

Add tests that inject a fake `URLProtocol` or request handler and assert:

- URL is `baseURL + /chat/completions` when baseURL already ends in `/v1`;
- `Authorization` header is `Bearer <apiKey>`;
- body contains `model` and two messages;
- response content decodes into `TrendAnalysisReport`.

- [ ] **Step 2: Run client tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter TrendAIClientTests
```

Expected: compile failure because `TrendAIClient` does not exist.

- [ ] **Step 3: Add protocol and URLSession client**

Create `TrendAIClient.swift` with:

```swift
import Foundation

protocol TrendAIClientProtocol {
    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport
}

struct TrendAIClient: TrendAIClientProtocol {
    let session: URLSession
    let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport {
        let url = try chatCompletionsURL(baseURL: settings.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.timeoutSeconds
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TrendChatCompletionRequest(
            model: settings.model,
            messages: [
                TrendChatMessage(role: "system", content: prompt.system),
                TrendChatMessage(role: "user", content: prompt.user)
            ],
            temperature: 0.2
        ))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TrendAIClientError.requestFailed
        }
        let completion = try decoder.decode(TrendChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content.data(using: .utf8) else {
            throw TrendAIClientError.emptyContent
        }
        return try decoder.decode(TrendAnalysisReport.self, from: content)
    }

    private func chatCompletionsURL(baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/chat/completions") else {
            throw TrendAIClientError.invalidBaseURL
        }
        return url
    }
}
```

Also add private request/response DTOs and `TrendAIClientError` in the same file.

- [ ] **Step 4: Run client tests**

Run:

```bash
swift test --package-path macos-app --filter TrendAIClientTests
```

Expected: all client tests pass without any real network call.

- [ ] **Step 5: Commit client**

```bash
git add macos-app/Core/TrendAIClient.swift macos-app/Tests/QiemanDashboardTests/TrendAIClientTests.swift
git commit -m "feat: add openai compatible trend client"
```

## Task 6: AppModel Trend State And Orchestration

**Files:**
- Modify: `macos-app/Core/AppModel/SubModels.swift`
- Modify: `macos-app/Core/AppModel/ComputedProperties.swift`
- Modify: `macos-app/Core/AppModel.swift`
- Create: `macos-app/Core/AppModel/TrendAnalysis.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendAnalysisAppModelTests.swift`

- [ ] **Step 1: Write failing AppModel tests**

Add tests with a fake client:

```swift
@MainActor
final class TrendAnalysisAppModelTests: XCTestCase {
    func testImportingLocalCandidateUpdatesSettings() {
        let model = AppModel()
        let candidate = LocalAIConfigurationCandidate(
            id: "env-openai",
            providerName: "OpenAI-compatible environment",
            sourceDescription: "Process environment",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4.1",
            apiKey: "sk-test",
            apiKeySource: "OPENAI_API_KEY",
            compatibility: .openAICompatible,
            confidence: 95,
            warning: nil
        )

        model.importTrendProvider(candidate)

        XCTAssertEqual(model.trendSettings.provider.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(model.trendSettings.provider.model, "gpt-4.1")
        XCTAssertEqual(model.trendSettings.provider.apiKey, "sk-test")
    }

    func testSuccessfulGenerationStoresReport() async {
        let model = AppModel()
        model.trendSettings = TrendAnalysisSettings(
            provider: TrendAIProviderSettings(
                providerName: "Test",
                baseURL: "https://example.com/v1",
                model: "test-model",
                apiKey: "sk-test",
                supportsOnlineSearch: true,
                timeoutSeconds: 30
            ),
            defaultPrivacyMode: .sanitized,
            dailyAutoAnalysisEnabled: false,
            lastAutoAnalysisDay: nil
        )
        model.trendAIClient = FakeTrendAIClient(report: .fixture(generatedAt: "2026-06-22 12:00:00", externalSignalStatus: .available))

        await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")

        XCTAssertEqual(model.trendGenerationState, .succeeded)
        XCTAssertEqual(model.trendReport?.generatedAt, "2026-06-22 12:00:00")
    }
}
```

- [ ] **Step 2: Run AppModel tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter TrendAnalysisAppModelTests
```

Expected: compile failure because trend AppModel fields and methods do not exist.

- [ ] **Step 3: Add EnhancementState fields and proxies**

Modify `EnhancementState`:

```swift
@Published var selectedTab: EnhancementCenterTab = .review
@Published var trendReport: TrendAnalysisReport?
@Published var trendSettings: TrendAnalysisSettings = .default
@Published var trendGenerationState: TrendGenerationState = .idle
@Published var trendPrivacyMode: TrendPrivacyMode = .sanitized
@Published var trendLocalCandidates: [LocalAIConfigurationCandidate] = []
@Published var lastTrendGeneratedAt: String?
@Published var lastTrendError: String?
```

Modify `EnhancementCenterTab` to include:

```swift
case trend = "趋势"
```

Add AppModel proxies matching the existing enhancement proxy style.

- [ ] **Step 4: Add trend file URLs**

Modify `ComputedProperties.swift`:

```swift
var trendAnalysisSettingsFileURL: URL? {
    dataDirectoryURL?.appendingPathComponent("trend-analysis-settings.json", isDirectory: false)
}

var trendAnalysisReportFileURL: URL? {
    dataDirectoryURL?.appendingPathComponent("trend-analysis-report.json", isDirectory: false)
}
```

- [ ] **Step 5: Add AppModel trend extension**

Create `macos-app/Core/AppModel/TrendAnalysis.swift` with:

```swift
import Foundation

extension AppModel {
    func loadTrendAnalysisState() {
        if let trendAnalysisSettingsFileURL {
            trendSettings = (try? TrendAnalysisSettingsStore().load(from: trendAnalysisSettingsFileURL)) ?? .default
            trendPrivacyMode = trendSettings.defaultPrivacyMode
        }
        if let trendAnalysisReportFileURL {
            trendReport = try? TrendAnalysisReportStore().load(from: trendAnalysisReportFileURL)
            lastTrendGeneratedAt = trendReport?.generatedAt
        }
    }

    func saveTrendAnalysisSettings() {
        guard let trendAnalysisSettingsFileURL else { return }
        do {
            try TrendAnalysisSettingsStore().save(trendSettings, to: trendAnalysisSettingsFileURL)
        } catch {
            errorMessage = "趋势设置保存失败：\(error.localizedDescription)"
        }
    }

    func detectLocalAIConfigurations() {
        trendLocalCandidates = LocalAIConfigurationDetector().detect()
    }

    func importTrendProvider(_ candidate: LocalAIConfigurationCandidate) {
        guard let imported = candidate.importedSettings() else {
            lastTrendError = candidate.warning ?? "该配置不能直接用于 OpenAI-compatible 趋势分析。"
            return
        }
        trendSettings.provider = imported
        saveTrendAnalysisSettings()
        noticeMessage = "已导入趋势分析模型配置。"
    }
}
```

Then add generation and auto-run methods using `TrendAnalysisContextBuilder`, `TrendPromptBuilder`, `trendAIClient`, and `TrendAnalysisValidator`.

- [ ] **Step 6: Wire load and startup**

Modify `loadEnhancementState()` to call `loadTrendAnalysisState()`. After startup data refresh and automation setup in `start()`, call:

```swift
await runDailyTrendAnalysisIfNeeded()
```

Run this after portfolio rows have had a chance to refresh so daily analysis has useful context.

- [ ] **Step 7: Run AppModel tests**

Run:

```bash
swift test --package-path macos-app --filter TrendAnalysisAppModelTests
```

Expected: all trend AppModel tests pass.

- [ ] **Step 8: Commit AppModel orchestration**

```bash
git add macos-app/Core/AppModel.swift macos-app/Core/AppModel/SubModels.swift macos-app/Core/AppModel/ComputedProperties.swift macos-app/Core/AppModel/EnhancementCenter.swift macos-app/Core/AppModel/TrendAnalysis.swift macos-app/Tests/QiemanDashboardTests/TrendAnalysisAppModelTests.swift
git commit -m "feat: wire trend analysis state"
```

## Task 7: Enhancement Presentation Integration

**Files:**
- Modify: `macos-app/Core/EnhancementDashboardPresentation.swift`
- Modify: `macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift`

- [ ] **Step 1: Add failing presentation tests**

Extend `EnhancementDashboardPresentationTests` to assert:

```swift
func testStatusCardsIncludeTrendTab() {
    let summary = makeDashboard(
        trendStatus: EnhancementTrendStatus(
            state: .missingConfiguration,
            value: "未配置",
            detail: "缺少模型配置",
            nextAction: "配置模型",
            severity: .warning
        )
    )

    XCTAssertEqual(summary.statusCards.map(\.tab), [.review, .watch, .importPreview, .insight, .trend])
    XCTAssertEqual(summary.statusCards.first { $0.tab == .trend }?.title, "趋势研判")
}
```

Add another test for stale report or failed auto-analysis producing an action-queue item targeting `.trend`.

- [ ] **Step 2: Run presentation tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter EnhancementDashboardPresentationTests
```

Expected: compile or assertion failure because trend presentation fields are not wired.

- [ ] **Step 3: Add trend presentation model**

In `EnhancementDashboardPresentation.swift`, add:

```swift
enum EnhancementTrendState: Hashable {
    case missingConfiguration
    case neverGenerated
    case ready
    case stale
    case failed
    case externalSignalsUnavailable
}

struct EnhancementTrendStatus: Hashable {
    let state: EnhancementTrendState
    let value: String
    let detail: String
    let nextAction: String
    let severity: EnhancementPresentationSeverity
}
```

Modify `EnhancementDashboardSummary.make(...)` to accept `trendStatus: EnhancementTrendStatus`, append a `.trend` card, and append trend action-queue items for missing config, stale/never generated, failed, and external signal unavailable states.

- [ ] **Step 4: Update call sites**

Update `EnhancementCenterView.dashboardSummary` to pass `model.enhancementTrendStatus`.

- [ ] **Step 5: Run presentation tests**

Run:

```bash
swift test --package-path macos-app --filter EnhancementDashboardPresentationTests
```

Expected: all enhancement presentation tests pass.

- [ ] **Step 6: Commit presentation integration**

```bash
git add macos-app/Core/EnhancementDashboardPresentation.swift macos-app/Views/EnhancementCenterView.swift macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift
git commit -m "feat: add trend status to enhancement workbench"
```

## Task 8: Settings UI For AI Trend Provider And Local Detection

**Files:**
- Modify: `macos-app/Views/SettingsSectionView.swift`
- Create: `macos-app/Views/SettingsTrendPanel.swift`

- [ ] **Step 1: Add settings focus**

Modify `SettingsFocus`:

```swift
case trend
```

Add a settings metric card:

```swift
SettingsMetric(
    title: "AI趋势",
    value: model.trendSettings.provider.isConfigured ? "已配置" : "未配置",
    detail: model.trendSettings.provider.model.isEmpty ? "配置模型后可生成趋势" : model.trendSettings.provider.model,
    icon: "sparkles.rectangle.stack",
    tint: model.trendSettings.provider.isConfigured ? AppPalette.positive : AppPalette.warning,
    isSelected: selectedSettingsFocus == .trend
)
```

Add `.trend: trendPanel` to `selectedSettingsPanel`.

- [ ] **Step 2: Add settings panel view**

Create `SettingsTrendPanel.swift` as an extension on `SettingsSectionView`. Include:

- text fields for provider name, base URL, model, API key;
- toggle for online search;
- toggle for daily auto-analysis;
- picker for default privacy mode;
- `检测本机配置` button calling `model.detectLocalAIConfigurations()`;
- candidate rows showing provider, source, compatibility, masked key, warning;
- import button disabled when `candidate.canImport == false`.

Use `SecureField` for API key and never render `model.trendSettings.provider.apiKey` as normal text.

- [ ] **Step 3: Smoke-build UI**

Run:

```bash
swift build --package-path macos-app
```

Expected: build succeeds.

- [ ] **Step 4: Commit settings UI**

```bash
git add macos-app/Views/SettingsSectionView.swift macos-app/Views/SettingsTrendPanel.swift
git commit -m "feat: add trend ai settings panel"
```

## Task 9: Trend Tab UI

**Files:**
- Modify: `macos-app/Views/EnhancementCenterView.swift`

- [ ] **Step 1: Add trend panel branch**

Modify `selectedWorkflowPanel`:

```swift
case .trend:
    trendPanel
```

- [ ] **Step 2: Add trend panel sections**

Add private computed views in `EnhancementCenterView`:

- `trendPanel`
- `trendRunStateSection`
- `trendPortfolioSection`
- `trendSectorSection`
- `trendKeyAssetSection`
- `trendActionCandidateSection`
- `trendEvidenceSection`

The generate button calls:

```swift
Task { await model.generateTrendAnalysis(userInitiated: true) }
```

The privacy picker binds to `model.trendPrivacyMode`. If the user switches to `.fullDetail`, present an alert explaining that real amounts, costs, profits, plans, and pending trades will be sent to the configured model.

- [ ] **Step 3: Build UI**

Run:

```bash
swift build --package-path macos-app
```

Expected: build succeeds.

- [ ] **Step 4: Commit trend tab UI**

```bash
git add macos-app/Views/EnhancementCenterView.swift
git commit -m "feat: add trend analysis tab"
```

## Task 10: Final Verification

**Files:**
- No new files.

- [ ] **Step 1: Run focused test groups**

Run:

```bash
swift test --package-path macos-app --filter TrendAnalysis
swift test --package-path macos-app --filter LocalAIConfigurationDetectorTests
swift test --package-path macos-app --filter EnhancementDashboardPresentationTests
```

Expected: all focused tests pass.

- [ ] **Step 2: Run full Swift test suite**

Run:

```bash
swift test --package-path macos-app
```

Expected: full test suite passes.

- [ ] **Step 3: Run release-style build smoke**

Run:

```bash
APP_VERSION=2.8.9 SIGN_IDENTITY="-" TARGET_ARCH="$(uname -m)" bash scripts/build_macos_app.sh
```

Expected: app bundle and zip are created, zip integrity check passes.

- [ ] **Step 4: Inspect git status**

Run:

```bash
git status --short --branch
```

Expected: clean working tree on the implementation branch, ahead by the feature commits.

## Self-Review Notes

- Spec coverage:
  - New `趋势` tab: Tasks 7 and 9.
  - OpenAI-compatible provider: Tasks 1, 5, 6, 8.
  - Local cc/Codex/OpenAI-compatible detection: Task 2 and Task 8.
  - Privacy mode: Tasks 1, 3, 8, 9.
  - Structured JSON, validation, unsafe wording: Task 4.
  - Report persistence: Task 1 and Task 6.
  - Daily auto-generation: Task 6 and Task 7.
  - Tests and verification: all tasks use RED/GREEN and Task 10 closes the suite.
- Type consistency:
  - `TrendPrivacyMode`, `TrendAnalysisSettings`, `TrendAnalysisReport`, and `LocalAIConfigurationCandidate` are introduced before use.
  - AppModel methods referenced by UI are introduced in Task 6 before UI tasks.
- Scope control:
  - No standalone search API.
  - No direct Anthropic client in first version.
  - No automatic trading or plan mutation.
