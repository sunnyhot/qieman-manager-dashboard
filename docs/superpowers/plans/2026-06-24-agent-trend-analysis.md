# Agent-Based Trend Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace direct OpenAI-compatible trend generation with local agent execution through Claude CLI, Codex CLI, and configurable external agent commands.

**Architecture:** Keep the existing `TrendAnalysisReport`, `TrendAnalysisContextBuilder`, and `TrendAnalysisValidator` as the stable report contract. Introduce a local agent boundary that builds an isolated run packet, invokes a selected CLI process, decodes the resulting JSON, and lets `AppModel` render the same trend UI from validated reports.

**Tech Stack:** SwiftUI, Foundation `Process`, Swift Codable stores, XCTest, repository-local skill resources under `skills/investment-trend-analysis`, macOS 14+, Swift Package Manager tests.

## Global Constraints

- macOS native SwiftUI app, macOS 14+.
- Python local server remains zero third-party dependencies and is not part of this feature.
- AppModel remains the `@MainActor ObservableObject` state container.
- Direct OpenAI-compatible base URL/API key trend generation is removed from the product surface.
- Claude CLI and Codex CLI are first-class local agents.
- OpenClaw, Hermes, and future tools use configurable external command templates until their exact CLI contracts are verified.
- Trend analysis is a research assistant only; it must not execute trades, mutate plans, or present guaranteed investment advice.
- Sanitized privacy mode must not write real holding amount, cost amount, profit amount, pending trade amount, or plan amount into the agent run packet.
- Full-detail mode may include those values only after explicit user selection.
- Every generated report must decode into `TrendAnalysisReport` and pass `TrendAnalysisValidator` before rendering.
- The last successful report remains visible when a new agent run fails.

---

## File Structure

Create or modify these files:

- Create `macos-app/Core/TrendAgentModels.swift`
  - `TrendAgentKind`, `TrendAgentSettings`, `TrendAgentCandidate`, `TrendAgentCapability`, `TrendAgentCheckResult`, and `TrendAgentRunResult`.
- Modify `macos-app/Core/TrendAnalysisModels.swift`
  - Move direct provider settings out of the active settings path and keep report models stable.
- Modify `macos-app/Core/TrendAnalysisStore.swift`
  - Save/load new agent settings and migrate legacy direct-provider JSON.
- Create `macos-app/Core/TrendAgentDetector.swift`
  - Detect command availability for Claude, Codex, OpenClaw, Hermes, and configured custom paths.
- Create `macos-app/Core/TrendRunWorkspace.swift`
  - Write per-run input, skill, schema, prompt, and output files.
- Create `macos-app/Core/TrendAgentProcess.swift`
  - Small testable wrapper around `Process`.
- Create `macos-app/Core/TrendAgentRunners.swift`
  - Claude, Codex, and external command runners.
- Modify `macos-app/Core/AppModel.swift`
  - Replace `trendAIClient` dependency with local agent runner/detector dependencies.
- Modify `macos-app/Core/AppModel/TrendAnalysis.swift`
  - Replace direct model calls with agent run packet execution.
- Modify `macos-app/Core/EnhancementDashboardPresentation.swift`
  - Replace model-config copy with agent-config copy.
- Modify `macos-app/Views/SettingsTrendPanel.swift`
  - Replace base URL/API key form with local agent detection, selection, and custom command settings.
- Modify `macos-app/Views/EnhancementTrendPanel.swift`
  - Replace "模型" wording with "Agent" wording and status values.
- Create `skills/investment-trend-analysis/SKILL.md`
- Create `skills/investment-trend-analysis/references/domain-rules.md`
- Create `skills/investment-trend-analysis/references/output-contract.md`
- Create `skills/investment-trend-analysis/assets/trend-report.schema.json`
- Create `skills/investment-trend-analysis/assets/examples.json`
- Modify `scripts/build_macos_app.sh`
  - Already copies `skills/`; add a verification check that the investment trend skill files are present in the bundle.
- Create `macos-app/Tests/QiemanDashboardTests/TrendAgentSettingsTests.swift`
- Create `macos-app/Tests/QiemanDashboardTests/TrendAgentDetectorTests.swift`
- Create `macos-app/Tests/QiemanDashboardTests/TrendRunWorkspaceTests.swift`
- Create `macos-app/Tests/QiemanDashboardTests/TrendAgentRunnerTests.swift`
- Modify `macos-app/Tests/QiemanDashboardTests/TrendAnalysisStoreTests.swift`
- Modify `macos-app/Tests/QiemanDashboardTests/TrendAnalysisAppModelTests.swift`
- Remove `macos-app/Tests/QiemanDashboardTests/TrendAIClientTests.swift` when the direct client is deleted.
- Modify or remove `macos-app/Tests/QiemanDashboardTests/LocalAIConfigurationDetectorTests.swift` when the old detector is deleted.

---

### Task 1: Agent Settings And Legacy Store Migration

**Files:**
- Create: `macos-app/Core/TrendAgentModels.swift`
- Modify: `macos-app/Core/TrendAnalysisModels.swift`
- Modify: `macos-app/Core/TrendAnalysisStore.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendAgentSettingsTests.swift`
- Modify test: `macos-app/Tests/QiemanDashboardTests/TrendAnalysisStoreTests.swift`

**Interfaces:**
- Produces: `TrendAgentKind`, `TrendAgentSettings`, `TrendAgentCandidate`, `TrendAgentCheckResult`.
- Produces: `TrendAnalysisSettings.agent`.
- Consumes later: `TrendAgentDetector.detect() -> [TrendAgentCandidate]`.

- [ ] **Step 1: Write failing agent settings tests**

Create `macos-app/Tests/QiemanDashboardTests/TrendAgentSettingsTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class TrendAgentSettingsTests: XCTestCase {
    func testDefaultAgentSettingsUseAutomaticSelection() {
        let settings = TrendAgentSettings.default

        XCTAssertEqual(settings.kind, .automatic)
        XCTAssertEqual(settings.commandPath, "")
        XCTAssertEqual(settings.model, "")
        XCTAssertEqual(settings.profile, "")
        XCTAssertEqual(settings.timeoutSeconds, 300)
        XCTAssertEqual(settings.customCommandTemplate, "")
    }

    func testConfiguredAgentRequiresConcreteCommandForCustomKind() {
        var settings = TrendAgentSettings(
            kind: .custom,
            commandPath: "",
            model: "",
            profile: "",
            timeoutSeconds: 300,
            customCommandTemplate: "{{command}} {{promptFile}} {{schemaFile}} {{outputFile}} {{runDir}}"
        )

        XCTAssertFalse(settings.isRunnable(with: []))

        settings.commandPath = "/usr/local/bin/hermes"

        XCTAssertTrue(settings.isRunnable(with: []))
    }

    func testAutomaticAgentUsesFirstRunnableCandidate() {
        let settings = TrendAgentSettings.default
        let candidates = [
            TrendAgentCandidate(
                id: "claude",
                kind: .claudeCLI,
                displayName: "Claude CLI",
                commandPath: "/Users/test/.local/bin/claude",
                version: "1.0.0",
                isInstalled: true,
                isExecutable: true,
                capabilities: [.jsonSchema, .nonInteractive],
                warning: nil
            )
        ]

        XCTAssertTrue(settings.isRunnable(with: candidates))
        XCTAssertEqual(settings.resolvedCandidate(from: candidates)?.kind, .claudeCLI)
    }
}
```

- [ ] **Step 2: Write failing store migration tests**

In `macos-app/Tests/QiemanDashboardTests/TrendAnalysisStoreTests.swift`, replace the provider-specific assertions with agent-specific assertions and add a legacy migration test:

```swift
func testSettingsStoreReturnsDefaultAgentWhenFileIsMissing() throws {
    let directory = try temporaryDirectory()
    let url = directory.appendingPathComponent("trend-settings.json")

    let settings = try TrendAnalysisSettingsStore().load(from: url)

    XCTAssertEqual(settings.agent.kind, .automatic)
    XCTAssertEqual(settings.agent.timeoutSeconds, 300)
    XCTAssertEqual(settings.defaultPrivacyMode, .sanitized)
    XCTAssertFalse(settings.dailyAutoAnalysisEnabled)
}

func testSettingsStoreSavesAndLoadsAgentSettings() throws {
    let directory = try temporaryDirectory()
    let url = directory.appendingPathComponent("trend-settings.json")
    let settings = TrendAnalysisSettings(
        agent: TrendAgentSettings(
            kind: .claudeCLI,
            commandPath: "/Users/test/.local/bin/claude",
            model: "sonnet",
            profile: "",
            timeoutSeconds: 180,
            customCommandTemplate: ""
        ),
        defaultPrivacyMode: .fullDetail,
        dailyAutoAnalysisEnabled: true,
        lastAutoAnalysisDay: "2026-06-22"
    )

    try TrendAnalysisSettingsStore().save(settings, to: url)
    let loaded = try TrendAnalysisSettingsStore().load(from: url)

    XCTAssertEqual(loaded.agent.kind, .claudeCLI)
    XCTAssertEqual(loaded.agent.commandPath, "/Users/test/.local/bin/claude")
    XCTAssertEqual(loaded.agent.model, "sonnet")
    XCTAssertEqual(loaded.agent.timeoutSeconds, 180)
    XCTAssertEqual(loaded.defaultPrivacyMode, .fullDetail)
    XCTAssertTrue(loaded.dailyAutoAnalysisEnabled)
    XCTAssertEqual(loaded.lastAutoAnalysisDay, "2026-06-22")
}

func testSettingsStoreMigratesLegacyProviderSettingsToAutomaticAgent() throws {
    let directory = try temporaryDirectory()
    let url = directory.appendingPathComponent("trend-settings.json")
    try """
    {
      "dailyAutoAnalysisEnabled": true,
      "defaultPrivacyMode": "完整明细",
      "lastAutoAnalysisDay": "2026-06-22",
      "provider": {
        "apiKey": "sk-test-value",
        "baseURL": "https://open.bigmodel.cn/api/coding/paas/v4",
        "model": "glm-5.2",
        "providerName": "智谱",
        "supportsOnlineSearch": true,
        "timeoutSeconds": 60
      }
    }
    """.write(to: url, atomically: true, encoding: .utf8)

    let loaded = try TrendAnalysisSettingsStore().load(from: url)

    XCTAssertEqual(loaded.agent.kind, .automatic)
    XCTAssertEqual(loaded.agent.timeoutSeconds, 300)
    XCTAssertEqual(loaded.defaultPrivacyMode, .fullDetail)
    XCTAssertTrue(loaded.dailyAutoAnalysisEnabled)
    XCTAssertEqual(loaded.lastAutoAnalysisDay, "2026-06-22")
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter 'TrendAgentSettingsTests|TrendAnalysisStoreTests'
```

Expected: compile failures for missing `TrendAgentSettings`, missing `TrendAgentCandidate`, and missing `TrendAnalysisSettings.agent`.

- [ ] **Step 4: Add agent settings models**

Create `macos-app/Core/TrendAgentModels.swift` with:

```swift
import Foundation

enum TrendAgentKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case automatic
    case claudeCLI
    case codexCLI
    case openClaw
    case hermes
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "自动选择"
        case .claudeCLI: return "Claude CLI"
        case .codexCLI: return "Codex CLI"
        case .openClaw: return "OpenClaw"
        case .hermes: return "Hermes"
        case .custom: return "自定义"
        }
    }
}

enum TrendAgentCapability: String, Codable, Hashable {
    case nonInteractive
    case jsonSchema
    case outputFile
}

struct TrendAgentSettings: Codable, Hashable {
    var kind: TrendAgentKind
    var commandPath: String
    var model: String
    var profile: String
    var timeoutSeconds: Double
    var customCommandTemplate: String

    static let defaultTimeoutSeconds: Double = 300

    static let `default` = TrendAgentSettings(
        kind: .automatic,
        commandPath: "",
        model: "",
        profile: "",
        timeoutSeconds: defaultTimeoutSeconds,
        customCommandTemplate: ""
    )

    func resolvedCandidate(from candidates: [TrendAgentCandidate]) -> TrendAgentCandidate? {
        let installed = candidates.filter { $0.isRunnable }
        switch kind {
        case .automatic:
            return installed.first
        case .custom:
            return nil
        default:
            return installed.first { $0.kind == kind }
        }
    }

    func isRunnable(with candidates: [TrendAgentCandidate]) -> Bool {
        if kind == .custom {
            return !commandPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return resolvedCandidate(from: candidates) != nil
    }
}

struct TrendAgentCandidate: Identifiable, Codable, Hashable {
    let id: String
    let kind: TrendAgentKind
    let displayName: String
    let commandPath: String
    let version: String?
    let isInstalled: Bool
    let isExecutable: Bool
    let capabilities: [TrendAgentCapability]
    let warning: String?

    var isRunnable: Bool {
        isInstalled && isExecutable
    }
}

struct TrendAgentCheckResult: Codable, Hashable {
    let agentName: String
    let commandPath: String
    let preview: String
}

struct TrendAgentRunResult: Codable, Hashable {
    let reportJSON: String
    let agentName: String
    let commandPath: String
    let durationSeconds: Double
}
```

- [ ] **Step 5: Update trend settings and store migration**

Modify `TrendAnalysisSettings` in `macos-app/Core/TrendAnalysisModels.swift`:

```swift
struct TrendAnalysisSettings: Codable, Hashable {
    var agent: TrendAgentSettings
    var defaultPrivacyMode: TrendPrivacyMode
    var dailyAutoAnalysisEnabled: Bool
    var lastAutoAnalysisDay: String?

    static let `default` = TrendAnalysisSettings(
        agent: .default,
        defaultPrivacyMode: .sanitized,
        dailyAutoAnalysisEnabled: false,
        lastAutoAnalysisDay: nil
    )

    func hasAutoAnalyzed(on day: String) -> Bool {
        lastAutoAnalysisDay == day
    }
}
```

Modify `TrendAnalysisSettingsStore.load(from:)` in `macos-app/Core/TrendAnalysisStore.swift`:

```swift
func load(from fileURL: URL) throws -> TrendAnalysisSettings {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return .default
    }
    let data = try Data(contentsOf: fileURL)
    if let settings = try? decoder.decode(TrendAnalysisSettings.self, from: data) {
        return settings
    }
    let legacy = try decoder.decode(LegacyTrendAnalysisSettings.self, from: data)
    return TrendAnalysisSettings(
        agent: .default,
        defaultPrivacyMode: legacy.defaultPrivacyMode,
        dailyAutoAnalysisEnabled: legacy.dailyAutoAnalysisEnabled,
        lastAutoAnalysisDay: legacy.lastAutoAnalysisDay
    )
}
```

Add this private legacy type at the bottom of `TrendAnalysisStore.swift`:

```swift
private struct LegacyTrendAnalysisSettings: Decodable {
    let defaultPrivacyMode: TrendPrivacyMode
    let dailyAutoAnalysisEnabled: Bool
    let lastAutoAnalysisDay: String?
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run:

```bash
swift test --package-path macos-app --filter 'TrendAgentSettingsTests|TrendAnalysisStoreTests'
```

Expected: tests pass.

- [ ] **Step 7: Commit**

```bash
git add macos-app/Core/TrendAgentModels.swift macos-app/Core/TrendAnalysisModels.swift macos-app/Core/TrendAnalysisStore.swift macos-app/Tests/QiemanDashboardTests/TrendAgentSettingsTests.swift macos-app/Tests/QiemanDashboardTests/TrendAnalysisStoreTests.swift
git commit -m "feat: add trend agent settings"
```

---

### Task 2: Agent Detection

**Files:**
- Create: `macos-app/Core/TrendAgentDetector.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendAgentDetectorTests.swift`

**Interfaces:**
- Consumes: `TrendAgentKind`, `TrendAgentCandidate`, `TrendAgentCapability`.
- Produces: `TrendAgentDetector.detect() -> [TrendAgentCandidate]`.

- [ ] **Step 1: Write failing detector tests**

Create `macos-app/Tests/QiemanDashboardTests/TrendAgentDetectorTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class TrendAgentDetectorTests: XCTestCase {
    func testDetectsExecutableClaudeAndCodexFromSearchPaths() throws {
        let directory = try temporaryDirectory()
        let claude = try makeExecutable(named: "claude", in: directory)
        let codex = try makeExecutable(named: "codex", in: directory)

        let candidates = TrendAgentDetector(
            searchPaths: [directory.path],
            fileManager: .default
        ).detect()

        XCTAssertTrue(candidates.contains { $0.kind == .claudeCLI && $0.commandPath == claude.path })
        XCTAssertTrue(candidates.contains { $0.kind == .codexCLI && $0.commandPath == codex.path })
    }

    func testMissingAgentReturnsInstalledFalseCandidate() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-agent-\(UUID().uuidString)", isDirectory: true)

        let candidates = TrendAgentDetector(
            searchPaths: [directory.path],
            fileManager: .default
        ).detect()

        let claude = candidates.first { $0.kind == .claudeCLI }
        XCTAssertEqual(claude?.isInstalled, false)
        XCTAssertEqual(claude?.isExecutable, false)
    }

    func testDetectionOrderPrefersClaudeThenCodexThenExternalAgents() throws {
        let directory = try temporaryDirectory()
        _ = try makeExecutable(named: "hermes", in: directory)
        _ = try makeExecutable(named: "codex", in: directory)
        _ = try makeExecutable(named: "claude", in: directory)

        let kinds = TrendAgentDetector(
            searchPaths: [directory.path],
            fileManager: .default
        ).detect().map(\.kind)

        XCTAssertLessThan(kinds.firstIndex(of: .claudeCLI)!, kinds.firstIndex(of: .codexCLI)!)
        XCTAssertLessThan(kinds.firstIndex(of: .codexCLI)!, kinds.firstIndex(of: .hermes)!)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trend-agent-detector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutable(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "#!/usr/bin/env bash\necho \(name)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter TrendAgentDetectorTests
```

Expected: compile failure for missing `TrendAgentDetector`.

- [ ] **Step 3: Implement detector**

Create `macos-app/Core/TrendAgentDetector.swift`:

```swift
import Foundation

struct TrendAgentDetector {
    var searchPaths: [String]
    var fileManager: FileManager

    init(
        searchPaths: [String] = TrendAgentDetector.defaultSearchPaths(),
        fileManager: FileManager = .default
    ) {
        self.searchPaths = searchPaths
        self.fileManager = fileManager
    }

    func detect() -> [TrendAgentCandidate] {
        [
            candidate(kind: .claudeCLI, command: "claude", capabilities: [.nonInteractive, .jsonSchema]),
            candidate(kind: .codexCLI, command: "codex", capabilities: [.nonInteractive, .jsonSchema, .outputFile]),
            candidate(kind: .openClaw, command: "openclaw", capabilities: [.nonInteractive, .outputFile]),
            candidate(kind: .hermes, command: "hermes", capabilities: [.nonInteractive, .outputFile])
        ]
    }

    private func candidate(
        kind: TrendAgentKind,
        command: String,
        capabilities: [TrendAgentCapability]
    ) -> TrendAgentCandidate {
        let resolved = resolve(command)
        let installed = resolved != nil
        let executable = resolved.map { fileManager.isExecutableFile(atPath: $0) } ?? false
        return TrendAgentCandidate(
            id: kind.rawValue,
            kind: kind,
            displayName: kind.displayName,
            commandPath: resolved ?? command,
            version: nil,
            isInstalled: installed,
            isExecutable: executable,
            capabilities: capabilities,
            warning: installed ? nil : "未在 PATH 或常见位置检测到 \(command)"
        )
    }

    private func resolve(_ command: String) -> String? {
        for directory in searchPaths {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(command).path
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func defaultSearchPaths() -> [String] {
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var paths = pathValue.split(separator: ":").map(String.init)
        paths.append("/opt/homebrew/bin")
        paths.append("/usr/local/bin")
        paths.append("/Users/\(NSUserName())/.local/bin")
        paths.append("/Applications/Codex.app/Contents/Resources")
        return Array(NSOrderedSet(array: paths)) as? [String] ?? paths
    }
}
```

- [ ] **Step 4: Run detector tests**

Run:

```bash
swift test --package-path macos-app --filter TrendAgentDetectorTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Core/TrendAgentDetector.swift macos-app/Tests/QiemanDashboardTests/TrendAgentDetectorTests.swift
git commit -m "feat: detect local trend agents"
```

---

### Task 3: Trend Skill Pack And Run Workspace

**Files:**
- Create: `macos-app/Core/TrendRunWorkspace.swift`
- Create: `skills/investment-trend-analysis/SKILL.md`
- Create: `skills/investment-trend-analysis/references/domain-rules.md`
- Create: `skills/investment-trend-analysis/references/output-contract.md`
- Create: `skills/investment-trend-analysis/assets/trend-report.schema.json`
- Create: `skills/investment-trend-analysis/assets/examples.json`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendRunWorkspaceTests.swift`

**Interfaces:**
- Consumes: `TrendAnalysisContext`, `TrendModelPrompt`, `TrendAnalysisReport`.
- Produces: `TrendRunWorkspace.prepare(context:prompt:) -> TrendRunPacket`.

- [ ] **Step 1: Write failing workspace tests**

Create `macos-app/Tests/QiemanDashboardTests/TrendRunWorkspaceTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class TrendRunWorkspaceTests: XCTestCase {
    func testPrepareWritesPromptContextSchemaSkillAndOutputDirectory() throws {
        let root = try temporaryDirectory()
        let skillRoot = try makeSkillPack()
        let workspace = TrendRunWorkspace(rootDirectory: root, skillRoot: skillRoot)
        let context = makeTrendContext(privacyMode: .sanitized)
        let prompt = TrendModelPrompt(system: "system instructions", user: "user instructions")

        let packet = try workspace.prepare(context: context, prompt: prompt)

        XCTAssertTrue(FileManager.default.fileExists(atPath: packet.promptURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packet.contextURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packet.schemaURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packet.outputURL.deletingLastPathComponent().path))

        let promptText = try String(contentsOf: packet.promptURL)
        XCTAssertTrue(promptText.contains("system instructions"))
        XCTAssertTrue(promptText.contains("user instructions"))
    }

    func testSanitizedContextDoesNotWriteRealAmounts() throws {
        let root = try temporaryDirectory()
        let skillRoot = try makeSkillPack()
        let workspace = TrendRunWorkspace(rootDirectory: root, skillRoot: skillRoot)
        let context = makeTrendContext(privacyMode: .sanitized)

        let packet = try workspace.prepare(context: context, prompt: TrendModelPrompt(system: "s", user: "u"))
        let contextText = try String(contentsOf: packet.contextURL)

        XCTAssertFalse(contextText.contains("123456.78"))
        XCTAssertTrue(contextText.contains("\"privacyMode\""))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trend-run-workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSkillPack() throws -> URL {
        let root = try temporaryDirectory().appendingPathComponent("skill", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("references"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try "Use investment trend analysis.".write(to: root.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "Domain rules".write(to: root.appendingPathComponent("references/domain-rules.md"), atomically: true, encoding: .utf8)
        try "Output contract".write(to: root.appendingPathComponent("references/output-contract.md"), atomically: true, encoding: .utf8)
        try #"{"type":"object"}"#.write(to: root.appendingPathComponent("assets/trend-report.schema.json"), atomically: true, encoding: .utf8)
        try "[]".write(to: root.appendingPathComponent("assets/examples.json"), atomically: true, encoding: .utf8)
        return root
    }

    private func makeTrendContext(privacyMode: TrendPrivacyMode) -> TrendAnalysisContext {
        TrendAnalysisContext(
            generatedAt: "2026-06-24 10:00:00",
            dataAsOf: "2026-06-24 10:00:00",
            privacyMode: privacyMode,
            portfolio: TrendContextPortfolio(
                totalMarketValueText: privacyMode == .sanitized ? "已脱敏" : "123456.78",
                totalCostText: privacyMode == .sanitized ? "已脱敏" : "100000.00",
                totalProfitText: privacyMode == .sanitized ? "已脱敏" : "23456.78",
                totalProfitPctText: "23.45%",
                assetCount: 1
            ),
            sectors: [],
            assets: [],
            platformActions: [],
            watchSummary: nil,
            insightSummary: nil
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter TrendRunWorkspaceTests
```

Expected: compile failure for missing `TrendRunWorkspace` and `TrendRunPacket`.

- [ ] **Step 3: Create repository skill pack**

Create `skills/investment-trend-analysis/SKILL.md`:

```markdown
---
name: investment-trend-analysis
description: Analyze a local investment portfolio trend packet and return a strict JSON trend report. Use when an agent receives qieman-manager-dashboard portfolio context, platform signals, watch events, and a trend-report schema and must produce structured portfolio, horizon, sector, key-asset, evidence, warning, and action-candidate analysis.
---

# Investment Trend Analysis

Read the provided run packet files. Produce only JSON matching `schema/trend-report.schema.json`.

Use `skill/domain-rules.md` for portfolio interpretation rules and `skill/output-contract.md` for required report behavior. Do not execute trades, mutate files outside `output/trend-report.json`, or guarantee returns.
```

Create `skills/investment-trend-analysis/references/domain-rules.md`:

```markdown
# Domain Rules

- Treat the report as personal research, not investment advice.
- Chinese market color convention is red for gains and green for losses.
- Distinguish facts from judgment.
- Use short, medium, and long horizon reasoning.
- Prefer conditional action candidates with triggers and invalidating conditions.
- Do not claim guaranteed returns.
- If external information is unavailable, set `externalSignalStatus` to `unavailable` or `partial`.
```

Create `skills/investment-trend-analysis/references/output-contract.md`:

```markdown
# Output Contract

Return a single JSON object. Required top-level fields are:

- `generatedAt`
- `dataAsOf`
- `privacyMode`
- `externalSignalStatus`
- `portfolio`
- `horizons`
- `sectors`
- `keyAssets`
- `actions`
- `evidence`
- `warnings`
- `disclaimer`

Every top-level horizon must include `rationale` and `counterSignals`. Every action must include `triggerConditions` and `invalidatingConditions`. Do not include markdown fences.
```

Create `skills/investment-trend-analysis/assets/trend-report.schema.json` with a strict object schema that requires the top-level fields from `TrendAnalysisReport`. Use enum values from Swift raw values, including `脱敏摘要` and `完整明细` for `privacyMode`.

Create `skills/investment-trend-analysis/assets/examples.json`:

```json
[
  {
    "generatedAt": "2026-06-24 10:00:00",
    "dataAsOf": "2026-06-24 10:00:00",
    "privacyMode": "脱敏摘要",
    "externalSignalStatus": "partial",
    "portfolio": {
      "headline": "组合中性偏积极",
      "riskLevel": "medium",
      "summary": "组合需要继续观察科技与红利暴露的分化。"
    },
    "horizons": [
      {
        "horizon": "short",
        "direction": "neutral",
        "confidence": { "score": 62, "label": "中" },
        "rationale": "短期信号未形成一致方向。",
        "counterSignals": ["若成交量放大并突破压力位，短期判断需要上修。"]
      }
    ],
    "sectors": [],
    "keyAssets": [],
    "actions": [],
    "evidence": [],
    "warnings": [],
    "disclaimer": "非投资建议，仅供个人研究参考。"
  }
]
```

- [ ] **Step 4: Implement run workspace**

Create `macos-app/Core/TrendRunWorkspace.swift`:

```swift
import Foundation

struct TrendRunPacket: Hashable {
    let runDirectory: URL
    let promptURL: URL
    let contextURL: URL
    let schemaURL: URL
    let outputURL: URL
    let logURL: URL
}

struct TrendRunWorkspace {
    let rootDirectory: URL
    let skillRoot: URL
    var fileManager: FileManager = .default

    func prepare(context: TrendAnalysisContext, prompt: TrendModelPrompt) throws -> TrendRunPacket {
        let runDirectory = rootDirectory.appendingPathComponent("trend-run-\(UUID().uuidString)", isDirectory: true)
        let inputDirectory = runDirectory.appendingPathComponent("input", isDirectory: true)
        let skillDirectory = runDirectory.appendingPathComponent("skill", isDirectory: true)
        let schemaDirectory = runDirectory.appendingPathComponent("schema", isDirectory: true)
        let outputDirectory = runDirectory.appendingPathComponent("output", isDirectory: true)

        try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: schemaDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let contextURL = inputDirectory.appendingPathComponent("portfolio-context.json")
        let promptURL = runDirectory.appendingPathComponent("prompt.md")
        let schemaURL = schemaDirectory.appendingPathComponent("trend-report.schema.json")
        let outputURL = outputDirectory.appendingPathComponent("trend-report.json")
        let logURL = outputDirectory.appendingPathComponent("agent-log.txt")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(context).write(to: contextURL, options: .atomic)
        try """
        # System

        \(prompt.system)

        # User

        \(prompt.user)

        # Files

        - Context: input/portfolio-context.json
        - Domain rules: skill/domain-rules.md
        - Output contract: skill/output-contract.md
        - Schema: schema/trend-report.schema.json
        - Write final JSON to: output/trend-report.json
        """.write(to: promptURL, atomically: true, encoding: .utf8)

        try copySkillFile("references/domain-rules.md", to: skillDirectory.appendingPathComponent("domain-rules.md"))
        try copySkillFile("references/output-contract.md", to: skillDirectory.appendingPathComponent("output-contract.md"))
        try copySkillFile("assets/examples.json", to: skillDirectory.appendingPathComponent("examples.json"))
        try copySkillFile("assets/trend-report.schema.json", to: schemaURL)

        return TrendRunPacket(
            runDirectory: runDirectory,
            promptURL: promptURL,
            contextURL: contextURL,
            schemaURL: schemaURL,
            outputURL: outputURL,
            logURL: logURL
        )
    }

    private func copySkillFile(_ relativePath: String, to destination: URL) throws {
        let source = skillRoot.appendingPathComponent(relativePath)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}
```

- [ ] **Step 5: Run workspace tests**

Run:

```bash
swift test --package-path macos-app --filter TrendRunWorkspaceTests
```

Expected: tests pass.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Core/TrendRunWorkspace.swift macos-app/Tests/QiemanDashboardTests/TrendRunWorkspaceTests.swift skills/investment-trend-analysis
git commit -m "feat: create trend agent run workspace"
```

---

### Task 4: Process Wrapper And Agent Runner Contracts

**Files:**
- Create: `macos-app/Core/TrendAgentProcess.swift`
- Create: `macos-app/Core/TrendAgentRunners.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendAgentRunnerTests.swift`

**Interfaces:**
- Consumes: `TrendAgentSettings`, `TrendRunPacket`.
- Produces: `TrendAgentRunnerProtocol.generateReport(packet:settings:candidates:) async throws -> TrendAgentRunResult`.
- Produces: `TrendAgentRunnerProtocol.check(settings:candidates:) async throws -> TrendAgentCheckResult`.

- [ ] **Step 1: Write failing runner contract tests**

Create `macos-app/Tests/QiemanDashboardTests/TrendAgentRunnerTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class TrendAgentRunnerTests: XCTestCase {
    func testProcessClientCapturesStdoutAndExitCode() async throws {
        let executable = try makeExecutable(
            body: """
            #!/usr/bin/env bash
            echo '{"ok":true}'
            """
        )

        let result = try await TrendAgentProcessClient().run(
            executableURL: executable,
            arguments: [],
            currentDirectoryURL: executable.deletingLastPathComponent(),
            standardInput: nil,
            timeoutSeconds: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains(#""ok":true"#))
    }

    func testProcessClientReportsNonZeroExit() async throws {
        let executable = try makeExecutable(
            body: """
            #!/usr/bin/env bash
            echo 'bad' >&2
            exit 7
            """
        )

        let result = try await TrendAgentProcessClient().run(
            executableURL: executable,
            arguments: [],
            currentDirectoryURL: executable.deletingLastPathComponent(),
            standardInput: nil,
            timeoutSeconds: 5
        )

        XCTAssertEqual(result.exitCode, 7)
        XCTAssertTrue(result.stderr.contains("bad"))
    }

    private func makeExecutable(body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trend-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fake-agent")
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter TrendAgentRunnerTests
```

Expected: compile failure for missing `TrendAgentProcessClient`.

- [ ] **Step 3: Implement process wrapper**

Create `macos-app/Core/TrendAgentProcess.swift`:

```swift
import Foundation

struct TrendAgentProcessResult: Hashable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct TrendAgentProcessClient {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        standardInput: String?,
        timeoutSeconds: Double
    ) async throws -> TrendAgentProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if let standardInput {
                let inputPipe = Pipe()
                process.standardInput = inputPipe
                inputPipe.fileHandleForWriting.write(Data(standardInput.utf8))
                try? inputPipe.fileHandleForWriting.close()
            }

            let lock = NSLock()
            var resumed = false
            func finish(_ result: Result<TrendAgentProcessResult, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            process.terminationHandler = { terminated in
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                finish(.success(TrendAgentProcessResult(
                    exitCode: terminated.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                )))
            }

            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(1, timeoutSeconds) * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}
```

- [ ] **Step 4: Add runner protocol and errors**

Create `macos-app/Core/TrendAgentRunners.swift` with the shared protocol and errors first:

```swift
import Foundation

protocol TrendAgentRunnerProtocol {
    func generateReport(
        packet: TrendRunPacket,
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentRunResult

    func check(
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentCheckResult
}

enum TrendAgentRunnerError: LocalizedError {
    case noRunnableAgent
    case commandFailed(String)
    case emptyOutput
    case missingOutputFile(String)

    var errorDescription: String? {
        switch self {
        case .noRunnableAgent:
            return "未找到可运行的本地趋势分析 Agent。"
        case .commandFailed(let detail):
            return "本地 Agent 执行失败：\(detail)"
        case .emptyOutput:
            return "本地 Agent 没有返回趋势分析 JSON。"
        case .missingOutputFile(let path):
            return "本地 Agent 未生成结果文件：\(path)"
        }
    }
}
```

- [ ] **Step 5: Run process tests**

Run:

```bash
swift test --package-path macos-app --filter TrendAgentRunnerTests
```

Expected: tests pass.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Core/TrendAgentProcess.swift macos-app/Core/TrendAgentRunners.swift macos-app/Tests/QiemanDashboardTests/TrendAgentRunnerTests.swift
git commit -m "feat: add trend agent process runner"
```

---

### Task 5: Claude, Codex, And External Agent Runners

**Files:**
- Modify: `macos-app/Core/TrendAgentRunners.swift`
- Modify test: `macos-app/Tests/QiemanDashboardTests/TrendAgentRunnerTests.swift`

**Interfaces:**
- Consumes: `TrendAgentRunnerProtocol`, `TrendAgentProcessClient`.
- Produces: `TrendAgentRunner` facade that chooses Claude, Codex, or external command execution.

- [ ] **Step 1: Add failing runner selection tests**

Append these tests to `TrendAgentRunnerTests`:

```swift
func testExternalRunnerReadsOutputFileFromCommand() async throws {
    let executable = try makeExecutable(
        body: """
        #!/usr/bin/env bash
        output="$3"
        cat > "$output" <<'JSON'
        {"generatedAt":"2026-06-24 10:00:00","dataAsOf":"2026-06-24 10:00:00","privacyMode":"脱敏摘要","externalSignalStatus":"partial","portfolio":{"headline":"测试","riskLevel":"medium","summary":"测试摘要"},"horizons":[{"horizon":"short","direction":"neutral","confidence":{"score":60,"label":"中"},"rationale":"测试判断","counterSignals":["测试反证"]}],"sectors":[],"keyAssets":[],"actions":[],"evidence":[],"warnings":[],"disclaimer":"非投资建议，仅供个人研究参考。"}
        JSON
        """
    )
    let packet = try makePacket()
    let settings = TrendAgentSettings(
        kind: .custom,
        commandPath: executable.path,
        model: "",
        profile: "",
        timeoutSeconds: 5,
        customCommandTemplate: "{{command}} {{promptFile}} {{outputFile}}"
    )

    let result = try await TrendAgentRunner(processClient: TrendAgentProcessClient()).generateReport(
        packet: packet,
        settings: settings,
        candidates: []
    )

    XCTAssertTrue(result.reportJSON.contains(#""headline":"测试""#))
    XCTAssertEqual(result.commandPath, executable.path)
}

func testAutomaticRunnerFailsWhenNoCandidatesAreRunnable() async {
    let packet = try! makePacket()
    let settings = TrendAgentSettings.default

    do {
        _ = try await TrendAgentRunner(processClient: TrendAgentProcessClient()).generateReport(
            packet: packet,
            settings: settings,
            candidates: []
        )
        XCTFail("Expected no runnable agent error")
    } catch {
        XCTAssertTrue(error.localizedDescription.contains("未找到可运行"))
    }
}
```

Add helper:

```swift
private func makePacket() throws -> TrendRunPacket {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("trend-packet-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("output"), withIntermediateDirectories: true)
    let promptURL = directory.appendingPathComponent("prompt.md")
    let contextURL = directory.appendingPathComponent("input.json")
    let schemaURL = directory.appendingPathComponent("schema.json")
    let outputURL = directory.appendingPathComponent("output/trend-report.json")
    let logURL = directory.appendingPathComponent("output/agent-log.txt")
    try "prompt".write(to: promptURL, atomically: true, encoding: .utf8)
    try "{}".write(to: contextURL, atomically: true, encoding: .utf8)
    try "{}".write(to: schemaURL, atomically: true, encoding: .utf8)
    return TrendRunPacket(
        runDirectory: directory,
        promptURL: promptURL,
        contextURL: contextURL,
        schemaURL: schemaURL,
        outputURL: outputURL,
        logURL: logURL
    )
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter TrendAgentRunnerTests
```

Expected: compile failure for missing `TrendAgentRunner`.

- [ ] **Step 3: Implement runner facade and command expansion**

Append to `macos-app/Core/TrendAgentRunners.swift`:

```swift
struct TrendAgentRunner: TrendAgentRunnerProtocol {
    let processClient: TrendAgentProcessClient

    init(processClient: TrendAgentProcessClient = TrendAgentProcessClient()) {
        self.processClient = processClient
    }

    func generateReport(
        packet: TrendRunPacket,
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentRunResult {
        let start = Date()
        let command = try resolvedCommand(settings: settings, candidates: candidates)
        let result: TrendAgentProcessResult
        switch command.kind {
        case .claudeCLI:
            result = try await runClaude(command: command.path, packet: packet, settings: settings)
        case .codexCLI:
            result = try await runCodex(command: command.path, packet: packet, settings: settings)
        case .custom, .openClaw, .hermes:
            result = try await runExternal(command: command.path, packet: packet, settings: settings)
        case .automatic:
            throw TrendAgentRunnerError.noRunnableAgent
        }

        guard result.exitCode == 0 else {
            throw TrendAgentRunnerError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }

        let outputText: String
        if FileManager.default.fileExists(atPath: packet.outputURL.path) {
            outputText = try String(contentsOf: packet.outputURL)
        } else {
            outputText = result.stdout
        }
        let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TrendAgentRunnerError.emptyOutput
        }

        return TrendAgentRunResult(
            reportJSON: trimmed,
            agentName: command.kind.displayName,
            commandPath: command.path,
            durationSeconds: Date().timeIntervalSince(start)
        )
    }

    func check(
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentCheckResult {
        let command = try resolvedCommand(settings: settings, candidates: candidates)
        return TrendAgentCheckResult(
            agentName: command.kind.displayName,
            commandPath: command.path,
            preview: "可执行"
        )
    }

    private func resolvedCommand(
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) throws -> (kind: TrendAgentKind, path: String) {
        if settings.kind == .custom {
            let path = settings.commandPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { throw TrendAgentRunnerError.noRunnableAgent }
            return (.custom, path)
        }
        guard let candidate = settings.resolvedCandidate(from: candidates) else {
            throw TrendAgentRunnerError.noRunnableAgent
        }
        return (candidate.kind, candidate.commandPath)
    }

    private func runClaude(command: String, packet: TrendRunPacket, settings: TrendAgentSettings) async throws -> TrendAgentProcessResult {
        var arguments = [
            "-p",
            "--output-format", "json",
            "--json-schema", packet.schemaURL.path,
            "--no-session-persistence",
            "--tools", "",
            "--add-dir", packet.runDirectory.path
        ]
        if !settings.model.isEmpty {
            arguments.append(contentsOf: ["--model", settings.model])
        }
        arguments.append(try String(contentsOf: packet.promptURL))
        return try await processClient.run(
            executableURL: URL(fileURLWithPath: command),
            arguments: arguments,
            currentDirectoryURL: packet.runDirectory,
            standardInput: nil,
            timeoutSeconds: settings.timeoutSeconds
        )
    }

    private func runCodex(command: String, packet: TrendRunPacket, settings: TrendAgentSettings) async throws -> TrendAgentProcessResult {
        var arguments = [
            "exec",
            "--ephemeral",
            "--sandbox", "read-only",
            "--ask-for-approval", "never",
            "--cd", packet.runDirectory.path,
            "--output-schema", packet.schemaURL.path,
            "--output-last-message", packet.outputURL.path,
            "-"
        ]
        if !settings.model.isEmpty {
            arguments.insert(contentsOf: ["--model", settings.model], at: 1)
        }
        return try await processClient.run(
            executableURL: URL(fileURLWithPath: command),
            arguments: arguments,
            currentDirectoryURL: packet.runDirectory,
            standardInput: try String(contentsOf: packet.promptURL),
            timeoutSeconds: settings.timeoutSeconds
        )
    }

    private func runExternal(command: String, packet: TrendRunPacket, settings: TrendAgentSettings) async throws -> TrendAgentProcessResult {
        let template = settings.customCommandTemplate.isEmpty
            ? "{{command}} {{promptFile}} {{schemaFile}} {{outputFile}} {{runDir}}"
            : settings.customCommandTemplate
        let parts = expand(template: template, command: command, packet: packet)
        guard let executable = parts.first else { throw TrendAgentRunnerError.noRunnableAgent }
        return try await processClient.run(
            executableURL: URL(fileURLWithPath: executable),
            arguments: Array(parts.dropFirst()),
            currentDirectoryURL: packet.runDirectory,
            standardInput: nil,
            timeoutSeconds: settings.timeoutSeconds
        )
    }

    private func expand(template: String, command: String, packet: TrendRunPacket) -> [String] {
        template
            .replacingOccurrences(of: "{{command}}", with: command)
            .replacingOccurrences(of: "{{promptFile}}", with: packet.promptURL.path)
            .replacingOccurrences(of: "{{schemaFile}}", with: packet.schemaURL.path)
            .replacingOccurrences(of: "{{outputFile}}", with: packet.outputURL.path)
            .replacingOccurrences(of: "{{runDir}}", with: packet.runDirectory.path)
            .split(separator: " ")
            .map(String.init)
    }
}
```

- [ ] **Step 4: Run runner tests**

Run:

```bash
swift test --package-path macos-app --filter TrendAgentRunnerTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Core/TrendAgentRunners.swift macos-app/Tests/QiemanDashboardTests/TrendAgentRunnerTests.swift
git commit -m "feat: run trend analysis through local agents"
```

---

### Task 6: Wire AppModel To Agent Runs

**Files:**
- Modify: `macos-app/Core/AppModel.swift`
- Modify: `macos-app/Core/AppModel/TrendAnalysis.swift`
- Modify test: `macos-app/Tests/QiemanDashboardTests/TrendAnalysisAppModelTests.swift`

**Interfaces:**
- Consumes: `TrendAgentDetector.detect()`, `TrendAgentRunnerProtocol.generateReport`.
- Produces: `AppModel.detectTrendAgents()`, `AppModel.checkTrendAgentConnection()`, and agent-backed `generateTrendAnalysis`.

- [ ] **Step 1: Write failing AppModel tests for agent-backed generation**

In `TrendAnalysisAppModelTests`, replace fake `TrendAIClient` tests with fake agent runner tests:

```swift
func testSuccessfulAgentGenerationStoresReport() async {
    let model = AppModel()
    model.trendSettings = TrendAnalysisSettings(
        agent: TrendAgentSettings(
            kind: .custom,
            commandPath: "/tmp/fake-agent",
            model: "",
            profile: "",
            timeoutSeconds: 30,
            customCommandTemplate: ""
        ),
        defaultPrivacyMode: .sanitized,
        dailyAutoAnalysisEnabled: false,
        lastAutoAnalysisDay: nil
    )
    model.trendAgentRunner = FakeTrendAgentRunner(
        reportJSON: TrendAnalysisReport.fixture(
            generatedAt: "2026-06-24 12:00:00",
            externalSignalStatus: .partial
        ).jsonString()
    )

    await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-24 12:00:00")

    XCTAssertEqual(model.trendGenerationState, .succeeded)
    XCTAssertEqual(model.trendReport?.generatedAt, "2026-06-24 12:00:00")
}

func testAgentGenerationFailureKeepsLastSuccessfulReport() async {
    let model = AppModel()
    let previous = TrendAnalysisReport.fixture(
        generatedAt: "2026-06-23 12:00:00",
        externalSignalStatus: .partial
    )
    model.trendReport = previous
    model.trendSettings = TrendAnalysisSettings(
        agent: TrendAgentSettings(
            kind: .custom,
            commandPath: "/tmp/fake-agent",
            model: "",
            profile: "",
            timeoutSeconds: 30,
            customCommandTemplate: ""
        ),
        defaultPrivacyMode: .sanitized,
        dailyAutoAnalysisEnabled: false,
        lastAutoAnalysisDay: nil
    )
    model.trendAgentRunner = FailingTrendAgentRunner()

    await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-24 12:00:00")

    XCTAssertEqual(model.trendGenerationState, .failed)
    XCTAssertEqual(model.trendReport?.generatedAt, "2026-06-23 12:00:00")
    XCTAssertFalse(model.lastTrendError.isEmpty)
}
```

Add helpers:

```swift
private struct FakeTrendAgentRunner: TrendAgentRunnerProtocol {
    let reportJSON: String

    func generateReport(packet: TrendRunPacket, settings: TrendAgentSettings, candidates: [TrendAgentCandidate]) async throws -> TrendAgentRunResult {
        TrendAgentRunResult(
            reportJSON: reportJSON,
            agentName: "Fake",
            commandPath: "/tmp/fake-agent",
            durationSeconds: 0.1
        )
    }

    func check(settings: TrendAgentSettings, candidates: [TrendAgentCandidate]) async throws -> TrendAgentCheckResult {
        TrendAgentCheckResult(agentName: "Fake", commandPath: "/tmp/fake-agent", preview: "OK")
    }
}

private struct FailingTrendAgentRunner: TrendAgentRunnerProtocol {
    func generateReport(packet: TrendRunPacket, settings: TrendAgentSettings, candidates: [TrendAgentCandidate]) async throws -> TrendAgentRunResult {
        throw TrendAgentRunnerError.commandFailed("boom")
    }

    func check(settings: TrendAgentSettings, candidates: [TrendAgentCandidate]) async throws -> TrendAgentCheckResult {
        throw TrendAgentRunnerError.commandFailed("boom")
    }
}

private extension TrendAnalysisReport {
    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(self)
        return String(data: data, encoding: .utf8)!
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --package-path macos-app --filter TrendAnalysisAppModelTests
```

Expected: compile failures for missing `trendAgentRunner` and old provider references.

- [ ] **Step 3: Add AppModel dependencies**

Modify `macos-app/Core/AppModel.swift`:

```swift
var trendAgentRunner: any TrendAgentRunnerProtocol = TrendAgentRunner()
var trendAgentDetector = TrendAgentDetector()
```

Replace `trendLocalCandidates` with:

```swift
var trendAgentCandidates: [TrendAgentCandidate] {
    state.enhancement.trendAgentCandidates
}
```

Add `@Published var trendAgentCandidates: [TrendAgentCandidate] = []` to the enhancement submodel in `macos-app/Core/AppModel/SubModels.swift`.

- [ ] **Step 4: Replace AppModel trend generation methods**

In `macos-app/Core/AppModel/TrendAnalysis.swift`:

- Rename `detectLocalAIConfigurations()` to `detectTrendAgents()`.
- Rename `checkTrendAIConnection()` to `checkTrendAgentConnection()`.
- Replace provider guard with `trendSettings.agent.isRunnable(with: trendAgentCandidates)`.
- Build one run packet per analysis.
- Decode `TrendAnalysisReport` from `TrendAgentRunResult.reportJSON`.

Use this decode helper inside the extension:

```swift
private func decodeTrendReportJSON(_ json: String) throws -> TrendAnalysisReport {
    let data = Data(json.utf8)
    return try JSONDecoder().decode(TrendAnalysisReport.self, from: data)
}
```

Use this request helper:

```swift
private func requestTrendReport(
    context: TrendAnalysisContext,
    settings: TrendAnalysisSettings,
    phase: String
) async throws -> TrendAnalysisReport {
    let prompt = TrendPromptBuilder().build(context: context, settings: settings)
    let skillRoot = projectRootURL.appendingPathComponent("skills/investment-trend-analysis", isDirectory: true)
    let workspace = TrendRunWorkspace(rootDirectory: FileManager.default.temporaryDirectory, skillRoot: skillRoot)
    let packet = try workspace.prepare(context: context, prompt: prompt)
    appendTrendProgress("启动本地 Agent：\(settings.agent.kind.displayName)")
    let heartbeatTask = startTrendProgressHeartbeat(phase: phase)
    defer { heartbeatTask.cancel() }
    let result = try await trendAgentRunner.generateReport(
        packet: packet,
        settings: settings.agent,
        candidates: trendAgentCandidates
    )
    appendTrendProgress("收到 Agent 报告：\(result.agentName) · \(String(format: "%.1f", result.durationSeconds))s")
    return try decodeTrendReportJSON(result.reportJSON)
}
```

If `projectRootURL` is not already available in `AppModel`, add a computed helper that points to the bundled project payload in app bundle builds and the repository root during tests.

- [ ] **Step 5: Update prompt builder signature**

Modify `TrendPromptBuilder` so `build(context:settings:)` reads agent settings instead of provider settings. Replace direct references to `settings.provider.supportsOnlineSearch` with wording based on local agent context:

```swift
let externalSignalInstruction = "If the selected local agent has reliable external-signal access, include it with evidence. If not, set externalSignalStatus to partial or unavailable."
```

- [ ] **Step 6: Run AppModel tests**

Run:

```bash
swift test --package-path macos-app --filter TrendAnalysisAppModelTests
```

Expected: tests pass.

- [ ] **Step 7: Commit**

```bash
git add macos-app/Core/AppModel.swift macos-app/Core/AppModel/SubModels.swift macos-app/Core/AppModel/TrendAnalysis.swift macos-app/Core/TrendPromptBuilder.swift macos-app/Tests/QiemanDashboardTests/TrendAnalysisAppModelTests.swift
git commit -m "feat: generate trends with local agents"
```

---

### Task 7: Replace Settings And Trend UI Copy

**Files:**
- Modify: `macos-app/Views/SettingsTrendPanel.swift`
- Modify: `macos-app/Views/EnhancementTrendPanel.swift`
- Modify: `macos-app/Core/EnhancementDashboardPresentation.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift`

**Interfaces:**
- Consumes: `trendSettings.agent`, `trendAgentCandidates`, `detectTrendAgents()`, `checkTrendAgentConnection()`.
- Produces: UI with no direct API key/base URL controls.

- [ ] **Step 1: Write failing presentation test**

In `EnhancementDashboardPresentationTests`, update the missing-provider test:

```swift
func testTrendMissingAgentAddsActionQueueItem() {
    let status = EnhancementTrendStatus(
        isProviderConfigured: false,
        generationState: .idle,
        lastGeneratedAt: nil,
        headline: "尚未配置本地 Agent",
        externalSignalStatus: nil,
        isStale: false
    )

    let item = EnhancementDashboardPresentation.actionQueue(
        review: .empty,
        watch: .empty,
        importSession: .empty,
        insight: .empty,
        trend: status
    ).first { $0.kind == .runTrendAnalysis }

    XCTAssertEqual(item?.title, "配置趋势分析 Agent")
    XCTAssertTrue(item?.detail.contains("Claude CLI") == true)
}
```

- [ ] **Step 2: Run presentation test to verify it fails**

Run:

```bash
swift test --package-path macos-app --filter EnhancementDashboardPresentationTests/testTrendMissingAgentAddsActionQueueItem
```

Expected: fails because copy still mentions OpenAI-compatible model.

- [ ] **Step 3: Replace settings panel controls**

Modify `SettingsTrendPanel.swift`:

- Change subtitle to `选择本地 Agent 生成趋势分析`.
- Remove service name, Base URL, model endpoint, API key, and online search controls.
- Add `Picker("默认 Agent", selection: trendAgentKindBinding)` over `TrendAgentKind.allCases`.
- Show `trendAgentCandidates` rows with install status and command path.
- Add custom command fields bound to `trendSettings.agent.commandPath`, `trendSettings.agent.customCommandTemplate`, and `trendSettings.agent.timeoutSeconds`.
- Replace buttons:
  - `检测本地 Agent` calls `model.detectTrendAgents()`.
  - `检测 Agent` calls `await model.checkTrendAgentConnection()`.

Use row copy:

```swift
SettingsRow(
    title: "当前 Agent",
    value: model.trendSettings.agent.kind.displayName,
    detail: model.enhancementTrendStatus.detailText,
    icon: "terminal",
    tint: model.enhancementTrendStatus.severity.settingsTint
)
```

- [ ] **Step 4: Replace trend panel wording**

Modify `EnhancementTrendPanel.swift`:

- Status card label `模型配置` becomes `Agent`.
- Empty state title `未连接模型` becomes `未配置 Agent`.
- Empty state detail becomes `先在设置中选择 Claude CLI、Codex CLI 或自定义本地 Agent。`
- Detection button text becomes `检测 Agent`.
- Generate button disables when `!model.trendSettings.agent.isRunnable(with: model.trendAgentCandidates)`.

- [ ] **Step 5: Replace dashboard presentation copy**

Modify `EnhancementDashboardPresentation.swift` so trend action copy references `本地 Agent`, `Claude CLI`, and `Codex CLI`.

- [ ] **Step 6: Run UI-adjacent tests**

Run:

```bash
swift test --package-path macos-app --filter 'EnhancementDashboardPresentationTests|TrendAnalysisAppModelTests'
```

Expected: tests pass.

- [ ] **Step 7: Commit**

```bash
git add macos-app/Views/SettingsTrendPanel.swift macos-app/Views/EnhancementTrendPanel.swift macos-app/Core/EnhancementDashboardPresentation.swift macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift
git commit -m "feat: switch trend settings to local agents"
```

---

### Task 8: Remove Direct Client And Old Config Detector

**Files:**
- Delete: `macos-app/Core/TrendAIClient.swift`
- Delete or replace: `macos-app/Core/LocalAIConfigurationDetector.swift`
- Delete: `macos-app/Tests/QiemanDashboardTests/TrendAIClientTests.swift`
- Delete or replace: `macos-app/Tests/QiemanDashboardTests/LocalAIConfigurationDetectorTests.swift`
- Modify all files found by `rg "TrendAI|OpenAI-compatible|apiKey|baseURL|LocalAIConfiguration" macos-app`.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: no active direct-model path in the app.

- [ ] **Step 1: Find remaining direct-model references**

Run:

```bash
rg -n "TrendAI|OpenAI-compatible|apiKey|baseURL|LocalAIConfiguration|chat/completions" macos-app
```

Expected before cleanup: references in direct client, old tests, and UI copy.

- [ ] **Step 2: Delete direct client and obsolete tests**

Run:

```bash
rm macos-app/Core/TrendAIClient.swift
rm macos-app/Tests/QiemanDashboardTests/TrendAIClientTests.swift
rm macos-app/Core/LocalAIConfigurationDetector.swift
rm macos-app/Tests/QiemanDashboardTests/LocalAIConfigurationDetectorTests.swift
```

- [ ] **Step 3: Remove obsolete provider model**

Remove `TrendAIProviderSettings`, `LocalAIConfigurationCompatibility`, and `LocalAIConfigurationCandidate` from `TrendAnalysisModels.swift`.

- [ ] **Step 4: Update remaining references**

Replace old property and method names:

```text
trendLocalCandidates -> trendAgentCandidates
detectLocalAIConfigurations() -> detectTrendAgents()
importTrendProvider(_:) -> remove call sites
checkTrendAIConnection() -> checkTrendAgentConnection()
trendSettings.provider -> trendSettings.agent
```

- [ ] **Step 5: Run reference scan**

Run:

```bash
rg -n "TrendAI|OpenAI-compatible|apiKey|LocalAIConfiguration|chat/completions" macos-app || true
```

Expected: no output. `baseURL` may remain in unrelated dashboard/server clients and is allowed there.

- [ ] **Step 6: Run full Swift tests**

Run:

```bash
swift test --package-path macos-app
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add macos-app
git commit -m "refactor: remove direct trend model client"
```

---

### Task 9: Bundle Verification And Manual Agent Smoke Tests

**Files:**
- Modify: `scripts/build_macos_app.sh`
- Test by command: `swift test --package-path macos-app`
- Test by command: `APP_VERSION=2.7.10 bash scripts/build_macos_app.sh`

**Interfaces:**
- Consumes: `skills/investment-trend-analysis` files.
- Produces: app bundle containing the skill pack.

- [ ] **Step 1: Add build script skill-pack check**

In `scripts/build_macos_app.sh`, after `cp -R "$ROOT_DIR/skills" "$PAYLOAD_DIR/"`, add:

```bash
for required in \
  "$PAYLOAD_DIR/skills/investment-trend-analysis/SKILL.md" \
  "$PAYLOAD_DIR/skills/investment-trend-analysis/references/domain-rules.md" \
  "$PAYLOAD_DIR/skills/investment-trend-analysis/references/output-contract.md" \
  "$PAYLOAD_DIR/skills/investment-trend-analysis/assets/trend-report.schema.json" \
  "$PAYLOAD_DIR/skills/investment-trend-analysis/assets/examples.json"
do
  if [ ! -f "$required" ]; then
    echo "❌ 验证失败: 趋势分析 skill 缺失 ($required)"
    exit 1
  fi
done
```

- [ ] **Step 2: Run full tests**

Run:

```bash
swift test --package-path macos-app
```

Expected: all tests pass.

- [ ] **Step 3: Build app**

Run:

```bash
APP_VERSION=2.7.10 bash scripts/build_macos_app.sh
```

Expected: build completes, app bundle exists, zip validation passes. Gatekeeper may report rejected because the build is local ad-hoc signed.

- [ ] **Step 4: Smoke-test local detection commands**

Run:

```bash
command -v claude || true
command -v codex || true
command -v openclaw || true
command -v hermes || true
```

Expected on the current machine: `claude` and `codex` are found; `openclaw` and `hermes` may be absent and should appear as not installed in the UI.

- [ ] **Step 5: Launch app for manual test**

Run:

```bash
osascript -e 'quit app "QiemanDashboard"' || true
open "/Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/dist/macos-app/QiemanDashboard.app"
```

Expected: App launches. In `设置 -> 趋势分析`, the UI shows local agent choices and no API key field.

- [ ] **Step 6: Commit**

```bash
git add scripts/build_macos_app.sh
git commit -m "test: verify bundled trend skill pack"
```

---

## Self-Review

Spec coverage:

- Local agent replacement is covered by Tasks 1, 2, 4, 5, 6, 7, and 8.
- Claude CLI and Codex CLI first-class support is covered by Task 5.
- OpenClaw, Hermes, and future agents through custom command templates are covered by Tasks 2 and 5.
- Skill pack and run packet are covered by Task 3.
- Privacy packet behavior is covered by Task 3 tests and Global Constraints.
- Settings UI replacement is covered by Task 7.
- Direct client deletion is covered by Task 8.
- Bundle and manual verification are covered by Task 9.

Type consistency:

- `TrendAnalysisSettings.agent` is introduced in Task 1 and used in Tasks 6 and 7.
- `TrendAgentCandidate` is introduced in Task 1 and produced by `TrendAgentDetector` in Task 2.
- `TrendRunPacket` is introduced in Task 3 and consumed by runners in Tasks 4 and 5.
- `TrendAgentRunnerProtocol` is introduced in Task 4 and injected into `AppModel` in Task 6.

Execution notes:

- Each task ends with focused tests and a commit.
- Full suite and app build happen after the direct client is removed.
- The intermediate tasks intentionally keep old direct-client code until Task 8 so the app can remain buildable while the new path is introduced.

