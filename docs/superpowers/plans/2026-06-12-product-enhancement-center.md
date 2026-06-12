# Product Enhancement Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v2.8.0 `增强` product enhancement center with monthly report export, manager watch timeline, safe import preview/undo, and snapshot-based portfolio insights.

**Architecture:** Keep new business logic in focused Core files and expose only small AppModel orchestration entry points. The SwiftUI enhancement center consumes summary models and calls AppModel actions; it does not compute portfolio, timeline, export, or import rules.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, XCTest, JSON file stores, existing AppPalette and AppModel patterns, existing `swift test` and `swift build --package-path macos-app` validation.

---

## Files And Responsibilities

- Create `macos-app/Core/MonthlyReportExporter.swift`: archive/save-as file writing, export metadata, overwrite confirmation error.
- Create `macos-app/Tests/QiemanDashboardTests/MonthlyReportExporterTests.swift`: archive naming, overwrite guard, save-as, write failure behavior.
- Create `macos-app/Core/ManagerWatchTimeline.swift`: timeline event models, summaries, pruning, JSON store.
- Create `macos-app/Tests/QiemanDashboardTests/ManagerWatchTimelineTests.swift`: ordering, pruning, duplicate suppression, failure/recovery summaries.
- Create `macos-app/Core/ImportPreviewSession.swift`: import diff models, preview builders, undo snapshot, undo store, stable data fingerprint.
- Modify `macos-app/Core/UserPortfolioStore.swift`: expose preview merge key through an internal method.
- Modify `macos-app/Core/PendingTradesStore.swift`: expose preview merge key through an internal method.
- Modify `macos-app/Core/InvestmentPlansStore.swift`: expose preview merge key through an internal method.
- Create `macos-app/Tests/QiemanDashboardTests/ImportPreviewSessionTests.swift`: diff grouping, blocked sessions, undo snapshot validity.
- Create `macos-app/Core/PortfolioSnapshotInsight.swift`: compact portfolio insight snapshots, insight store, summary cards.
- Create `macos-app/Tests/QiemanDashboardTests/PortfolioSnapshotInsightTests.swift`: insufficient history, asset change, concentration drift, plan and pending impact, sign classification.
- Modify `macos-app/Core/AppModel/SubModels.swift`: add `EnhancementState`.
- Modify `macos-app/Core/AppModel.swift`: add enhancement state proxy and objectWillChange forwarding.
- Modify `macos-app/Core/AppModel/ComputedProperties.swift`: add enhancement store URLs.
- Modify `macos-app/Core/AppModel/DataDirectory.swift`: load enhancement persisted state during startup and data directory changes.
- Create `macos-app/Core/AppModel/EnhancementCenter.swift`: AppModel orchestration for export, timeline, import preview/confirm/undo, and insight snapshot recording.
- Modify `macos-app/Core/AppModel/ManagerWatch.swift`: record watch timeline events during polls.
- Modify `macos-app/Core/AppModel/PortfolioRefresh.swift`: record compact insight snapshots after successful portfolio refresh.
- Modify `macos-app/Core/AppModel/PortfolioCRUD.swift`, `macos-app/Core/AppModel/PendingTrade.swift`, and `macos-app/Core/AppModel/InvestmentPlan.swift`: invalidate undo availability after manual edits that change affected data.
- Modify `macos-app/Core/Models.swift`: add `AppSection.enhancement`.
- Modify `macos-app/Views/ContentView.swift`: route `增强` to `EnhancementCenterView` and keep query toolbar hidden there.
- Create `macos-app/Views/EnhancementCenterView.swift`: unified workbench UI with `复盘`, `巡检`, `导入`, and `洞察` tabs.
- Modify `macos-app/Views/PortfolioSectionView.swift`: route monthly report export actions through AppModel and keep copy behavior.

## Task 1: Monthly Report Export Core

**Files:**
- Create: `macos-app/Core/MonthlyReportExporter.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/MonthlyReportExporterTests.swift`

- [ ] **Step 1: Add failing exporter tests**

Create `macos-app/Tests/QiemanDashboardTests/MonthlyReportExporterTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class MonthlyReportExporterTests: XCTestCase {
    func testDefaultArchiveURLUsesMonthFileNameInsideReportsDirectory() throws {
        let directory = try temporaryDirectory()
        let report = sampleReport(month: "2026-06")
        let exporter = MonthlyReportExporter()

        let url = exporter.defaultArchiveURL(for: report, in: directory)

        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Reports")
        XCTAssertEqual(url.lastPathComponent, "2026-06-portfolio-report.md")
    }

    func testArchiveWritesMarkdownAndMetadata() throws {
        let directory = try temporaryDirectory()
        let report = sampleReport(month: "2026-06")
        let exporter = MonthlyReportExporter()

        let metadata = try exporter.archive(report: report, in: directory, exportedAt: "2026-06-12 10:30:00", overwriteConfirmed: false)
        let content = try String(contentsOf: URL(fileURLWithPath: metadata.filePath), encoding: .utf8)

        XCTAssertEqual(content, report.markdown)
        XCTAssertEqual(metadata.monthText, "2026-06")
        XCTAssertEqual(metadata.exportedAt, "2026-06-12 10:30:00")
    }

    func testArchiveRequiresConfirmationBeforeOverwritingSameMonth() throws {
        let directory = try temporaryDirectory()
        let report = sampleReport(month: "2026-06")
        let exporter = MonthlyReportExporter()
        _ = try exporter.archive(report: report, in: directory, exportedAt: "2026-06-12 10:30:00", overwriteConfirmed: false)

        XCTAssertThrowsError(
            try exporter.archive(report: report, in: directory, exportedAt: "2026-06-12 10:31:00", overwriteConfirmed: false)
        ) { error in
            guard case MonthlyReportExportError.archiveAlreadyExists(let url) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(url.lastPathComponent, "2026-06-portfolio-report.md")
        }
    }

    func testArchiveOverwritesWhenConfirmed() throws {
        let directory = try temporaryDirectory()
        let first = sampleReport(month: "2026-06", markdown: "# First")
        let second = sampleReport(month: "2026-06", markdown: "# Second")
        let exporter = MonthlyReportExporter()
        _ = try exporter.archive(report: first, in: directory, exportedAt: "2026-06-12 10:30:00", overwriteConfirmed: false)

        let metadata = try exporter.archive(report: second, in: directory, exportedAt: "2026-06-12 10:31:00", overwriteConfirmed: true)
        let content = try String(contentsOf: URL(fileURLWithPath: metadata.filePath), encoding: .utf8)

        XCTAssertEqual(content, "# Second")
    }

    func testSaveAsWritesToChosenURL() throws {
        let directory = try temporaryDirectory()
        let targetURL = directory.appendingPathComponent("custom-report.md")
        let report = sampleReport(month: "2026-06")
        let exporter = MonthlyReportExporter()

        let metadata = try exporter.saveAs(report: report, to: targetURL, exportedAt: "2026-06-12 10:30:00")

        XCTAssertEqual(metadata.filePath, targetURL.path)
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), report.markdown)
    }

    func testMarkdownRemainsAvailableAfterWriteFailure() throws {
        let directory = try temporaryDirectory()
        let targetURL = directory.appendingPathComponent("missing").appendingPathComponent("report.md")
        let report = sampleReport(month: "2026-06", markdown: "# Still Available")
        let exporter = MonthlyReportExporter()

        XCTAssertThrowsError(try exporter.saveAs(report: report, to: targetURL, exportedAt: "2026-06-12 10:30:00"))
        XCTAssertEqual(report.markdown, "# Still Available")
    }

    private func sampleReport(month: String, markdown: String = "# Report") -> MonthlyReportSummary {
        MonthlyReportSummary(
            title: "且慢主理人看板月报 \(month)",
            monthText: month,
            generatedAt: "\(month)-12 10:30:00",
            markdown: markdown
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("monthly-report-exporter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
(cd macos-app && swift test --filter MonthlyReportExporterTests)
```

Expected: FAIL because `MonthlyReportExporter`, `MonthlyReportExportError`, and `MonthlyReportExportMetadata` do not exist.

- [ ] **Step 3: Add exporter implementation**

Create `macos-app/Core/MonthlyReportExporter.swift`:

```swift
import Foundation

struct MonthlyReportExportMetadata: Codable, Hashable {
    let monthText: String
    let filePath: String
    let exportedAt: String
}

enum MonthlyReportExportError: LocalizedError {
    case archiveAlreadyExists(URL)

    var errorDescription: String? {
        switch self {
        case .archiveAlreadyExists(let url):
            return "月报归档已存在：\(url.path)。确认覆盖后可重新保存。"
        }
    }
}

struct MonthlyReportExporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func reportsDirectory(in dataDirectoryURL: URL) -> URL {
        dataDirectoryURL.appendingPathComponent("Reports", isDirectory: true)
    }

    func defaultArchiveURL(for report: MonthlyReportSummary, in dataDirectoryURL: URL) -> URL {
        reportsDirectory(in: dataDirectoryURL)
            .appendingPathComponent("\(safeMonthText(report.monthText))-portfolio-report.md", isDirectory: false)
    }

    func archive(
        report: MonthlyReportSummary,
        in dataDirectoryURL: URL,
        exportedAt: String,
        overwriteConfirmed: Bool
    ) throws -> MonthlyReportExportMetadata {
        let directory = reportsDirectory(in: dataDirectoryURL)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let targetURL = defaultArchiveURL(for: report, in: dataDirectoryURL)
        if fileManager.fileExists(atPath: targetURL.path), !overwriteConfirmed {
            throw MonthlyReportExportError.archiveAlreadyExists(targetURL)
        }
        return try write(report: report, to: targetURL, exportedAt: exportedAt)
    }

    func saveAs(report: MonthlyReportSummary, to targetURL: URL, exportedAt: String) throws -> MonthlyReportExportMetadata {
        try write(report: report, to: targetURL, exportedAt: exportedAt)
    }

    private func write(report: MonthlyReportSummary, to targetURL: URL, exportedAt: String) throws -> MonthlyReportExportMetadata {
        try report.markdown.write(to: targetURL, atomically: true, encoding: .utf8)
        return MonthlyReportExportMetadata(
            monthText: report.monthText,
            filePath: targetURL.path,
            exportedAt: exportedAt
        )
    }

    private func safeMonthText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil else {
            return "current-month"
        }
        return trimmed
    }
}

struct MonthlyReportExportMetadataStore {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load(from fileURL: URL) throws -> MonthlyReportExportMetadata? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(MonthlyReportExportMetadata.self, from: data)
    }

    func save(_ metadata: MonthlyReportExportMetadata, to fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(metadata)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run the exporter tests**

Run:

```bash
(cd macos-app && swift test --filter MonthlyReportExporterTests)
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Core/MonthlyReportExporter.swift macos-app/Tests/QiemanDashboardTests/MonthlyReportExporterTests.swift
git commit -m "feat: add monthly report exporter"
```

## Task 2: Manager Watch Timeline Core

**Files:**
- Create: `macos-app/Core/ManagerWatchTimeline.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/ManagerWatchTimelineTests.swift`

- [ ] **Step 1: Add failing timeline tests**

Create `macos-app/Tests/QiemanDashboardTests/ManagerWatchTimelineTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class ManagerWatchTimelineTests: XCTestCase {
    func testSummaryOrdersEventsNewestFirst() {
        let old = event(kind: .pollStarted, occurredAt: date("2026-06-12T01:00:00Z"), title: "旧")
        let new = event(kind: .platformHit, occurredAt: date("2026-06-12T02:00:00Z"), title: "新")

        let summary = ManagerWatchTimelineSummary.make(events: [old, new])

        XCTAssertEqual(summary.events.map(\.title), ["新", "旧"])
        XCTAssertEqual(summary.latestStatusText, "新")
    }

    func testPruneKeepsMaxCountAndAge() {
        let now = date("2026-06-12T00:00:00Z")
        var events: [ManagerWatchTimelineEvent] = []
        for offset in 0..<205 {
            events.append(event(kind: .pollStarted, occurredAt: now.addingTimeInterval(TimeInterval(-offset * 60)), title: "\(offset)"))
        }
        events.append(event(kind: .failed, occurredAt: date("2026-02-01T00:00:00Z"), title: "过期"))

        let pruned = ManagerWatchTimelineStore.pruned(events, now: now, maxCount: 200, maxAgeDays: 90)

        XCTAssertEqual(pruned.count, 200)
        XCTAssertFalse(pruned.contains { $0.title == "过期" })
        XCTAssertEqual(pruned.first?.title, "0")
    }

    func testDuplicateSuppressionIsNotFailure() {
        let summary = ManagerWatchTimelineSummary.make(events: [
            event(kind: .duplicateSuppressed, title: "没有新发言")
        ])

        XCTAssertEqual(summary.failureCount, 0)
        XCTAssertEqual(summary.events.first?.tone, .info)
    }

    func testFailureAndRecoveryAffectSummary() {
        let failed = event(kind: .failed, occurredAt: date("2026-06-12T01:00:00Z"), title: "巡检失败", errorMessage: "网络错误")
        let recovered = event(kind: .recovered, occurredAt: date("2026-06-12T02:00:00Z"), title: "巡检恢复")

        let summary = ManagerWatchTimelineSummary.make(events: [failed, recovered])

        XCTAssertEqual(summary.latestStatusText, "巡检恢复")
        XCTAssertEqual(summary.failureCount, 1)
        XCTAssertEqual(summary.events.first?.tone, .positive)
        XCTAssertEqual(summary.events.last?.errorMessage, "网络错误")
    }

    func testStoreAppendPersistsAndPrunes() throws {
        let fileURL = try temporaryDirectory().appendingPathComponent("manager-watch-timeline.json")
        let store = ManagerWatchTimelineStore()

        try store.append(event(kind: .pollStarted, title: "开始"), to: fileURL, now: date("2026-06-12T00:00:00Z"))
        try store.append(event(kind: .platformHit, title: "命中调仓"), to: fileURL, now: date("2026-06-12T00:01:00Z"))

        let loaded = try store.load(from: fileURL)

        XCTAssertEqual(loaded.map(\.title), ["命中调仓", "开始"])
    }

    private func event(
        kind: ManagerWatchTimelineEventKind,
        occurredAt: Date = Date(timeIntervalSince1970: 1_781_217_600),
        title: String,
        errorMessage: String? = nil
    ) -> ManagerWatchTimelineEvent {
        ManagerWatchTimelineEvent(
            kind: kind,
            occurredAt: occurredAt,
            prodCode: "LONG_WIN",
            managerName: "ETF拯救世界",
            title: title,
            detail: "详情",
            targetID: nil,
            errorMessage: errorMessage
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manager-watch-timeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [ ] **Step 2: Run the failing timeline tests**

Run:

```bash
(cd macos-app && swift test --filter ManagerWatchTimelineTests)
```

Expected: FAIL because timeline types do not exist.

- [ ] **Step 3: Add timeline model and store**

Create `macos-app/Core/ManagerWatchTimeline.swift`:

```swift
import Foundation

enum ManagerWatchTimelineEventKind: String, Codable, CaseIterable, Hashable {
    case pollStarted
    case forumHit
    case platformHit
    case duplicateSuppressed
    case noUpdates
    case failed
    case recovered
}

enum ManagerWatchTimelineTone: String, Codable, Hashable {
    case info
    case positive
    case warning
}

struct ManagerWatchTimelineEvent: Codable, Identifiable, Hashable {
    let id: UUID
    let kind: ManagerWatchTimelineEventKind
    let occurredAt: Date
    let prodCode: String
    let managerName: String
    let title: String
    let detail: String
    let targetID: String?
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        kind: ManagerWatchTimelineEventKind,
        occurredAt: Date = Date(),
        prodCode: String,
        managerName: String,
        title: String,
        detail: String,
        targetID: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.prodCode = prodCode
        self.managerName = managerName
        self.title = title
        self.detail = detail
        self.targetID = targetID
        self.errorMessage = errorMessage
    }

    var tone: ManagerWatchTimelineTone {
        switch kind {
        case .forumHit, .platformHit, .recovered:
            return .positive
        case .failed:
            return .warning
        case .pollStarted, .duplicateSuppressed, .noUpdates:
            return .info
        }
    }
}

struct ManagerWatchTimelineSummary: Hashable {
    let events: [ManagerWatchTimelineEvent]
    let latestStatusText: String
    let failureCount: Int

    static func make(events: [ManagerWatchTimelineEvent]) -> ManagerWatchTimelineSummary {
        let sorted = events.sorted { left, right in
            if left.occurredAt != right.occurredAt {
                return left.occurredAt > right.occurredAt
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
        return ManagerWatchTimelineSummary(
            events: sorted,
            latestStatusText: sorted.first?.title ?? "暂无巡检记录",
            failureCount: sorted.filter { $0.kind == .failed }.count
        )
    }
}

struct ManagerWatchTimelineStore {
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load(from fileURL: URL) throws -> [ManagerWatchTimelineEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([ManagerWatchTimelineEvent].self, from: data)
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    func save(_ events: [ManagerWatchTimelineEvent], to fileURL: URL, now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(Self.pruned(events, now: now))
        try data.write(to: fileURL, options: .atomic)
    }

    func append(_ event: ManagerWatchTimelineEvent, to fileURL: URL, now: Date = Date()) throws {
        let nextEvents = try load(from: fileURL) + [event]
        try save(nextEvents, to: fileURL, now: now)
    }

    static func pruned(
        _ events: [ManagerWatchTimelineEvent],
        now: Date = Date(),
        maxCount: Int = 200,
        maxAgeDays: Int = 90
    ) -> [ManagerWatchTimelineEvent] {
        let ageLimit = now.addingTimeInterval(TimeInterval(-maxAgeDays * 24 * 60 * 60))
        return events
            .filter { $0.occurredAt >= ageLimit }
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(maxCount)
            .map { $0 }
    }
}
```

- [ ] **Step 4: Run the timeline tests**

Run:

```bash
(cd macos-app && swift test --filter ManagerWatchTimelineTests)
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Core/ManagerWatchTimeline.swift macos-app/Tests/QiemanDashboardTests/ManagerWatchTimelineTests.swift
git commit -m "feat: add manager watch timeline model"
```

## Task 3: Import Preview And Undo Core

**Files:**
- Create: `macos-app/Core/ImportPreviewSession.swift`
- Modify: `macos-app/Core/Models.swift`
- Modify: `macos-app/Core/UserPortfolioStore.swift`
- Modify: `macos-app/Core/PendingTradesStore.swift`
- Modify: `macos-app/Core/InvestmentPlansStore.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/ImportPreviewSessionTests.swift`

- [ ] **Step 1: Add failing import preview tests**

Create `macos-app/Tests/QiemanDashboardTests/ImportPreviewSessionTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class ImportPreviewSessionTests: XCTestCase {
    func testHoldingsPreviewGroupsAddedUpdatedUnchangedAndDuplicate() {
        let store = UserPortfolioStore()
        let existing = [
            holding(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, code: "000001", units: 100, cost: 1),
            holding(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, code: "000002", units: 200, cost: 2)
        ]
        let imported = [
            holding(code: "000001", units: 150, cost: 1),
            holding(code: "000002", units: 200, cost: 2),
            holding(code: "000003", units: 300, cost: 3),
            holding(code: "000003", units: 300, cost: 3)
        ]

        let session = ImportPreviewSession.makeHoldings(imported: imported, existing: existing, mode: .merge, store: store)

        XCTAssertEqual(session.count(for: .updated), 1)
        XCTAssertEqual(session.count(for: .unchanged), 1)
        XCTAssertEqual(session.count(for: .added), 1)
        XCTAssertEqual(session.count(for: .duplicate), 1)
        XCTAssertTrue(session.canConfirm)
    }

    func testReplacePreviewMarksRemovedExistingRows() {
        let store = PendingTradesStore()
        let existing = [
            trade(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, code: "000001", amount: "100.00元"),
            trade(id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, code: "000002", amount: "200.00元")
        ]
        let imported = [
            trade(code: "000001", amount: "150.00元")
        ]

        let session = ImportPreviewSession.makePendingTrades(imported: imported, existing: existing, mode: .replace, store: store)

        XCTAssertEqual(session.count(for: .updated), 1)
        XCTAssertEqual(session.count(for: .removed), 1)
    }

    func testEmptyImportIsBlocked() {
        let session = ImportPreviewSession.makeInvestmentPlans(
            imported: [],
            existing: [],
            mode: .merge,
            store: InvestmentPlansStore()
        )

        XCTAssertFalse(session.canConfirm)
        XCTAssertEqual(session.count(for: .blocked), 1)
    }

    func testUndoSnapshotIsValidOnlyForExpectedAfterState() {
        let beforeHoldings = [holding(code: "000001", units: 100, cost: 1)]
        let afterHoldings = [holding(code: "000001", units: 150, cost: 1)]
        let snapshot = ImportUndoSnapshot.make(
            target: .holdings,
            mode: .merge,
            createdAt: "2026-06-12 10:30:00",
            beforeHoldings: beforeHoldings,
            beforePendingTrades: [],
            beforeInvestmentPlans: [],
            afterHoldings: afterHoldings,
            afterPendingTrades: [],
            afterInvestmentPlans: []
        )

        XCTAssertTrue(snapshot.isValid(currentHoldings: afterHoldings, currentPendingTrades: [], currentInvestmentPlans: []))
        XCTAssertFalse(snapshot.isValid(currentHoldings: beforeHoldings, currentPendingTrades: [], currentInvestmentPlans: []))
        XCTAssertEqual(snapshot.restoreHoldings, beforeHoldings)
    }

    private func holding(id: UUID = UUID(), code: String, units: Double, cost: Double) -> UserPortfolioHolding {
        UserPortfolioHolding(id: id, fundCode: code, assetType: .fund, units: units, costPrice: cost, displayName: "基金\(code)")
    }

    private func trade(id: UUID = UUID(), code: String, amount: String) -> PersonalPendingTrade {
        PersonalPendingTrade(
            id: id,
            occurredAt: "2026-06-12 10:00:00",
            actionLabel: "买入",
            fundName: "基金\(code)",
            fundCode: code,
            amountText: amount,
            amountValue: Double(amount.replacingOccurrences(of: "元", with: "")),
            status: "交易进行中"
        )
    }
}
```

- [ ] **Step 2: Run the failing import preview tests**

Run:

```bash
(cd macos-app && swift test --filter ImportPreviewSessionTests)
```

Expected: FAIL because `ImportPreviewSession`, `ImportPreviewChangeKind`, and `ImportUndoSnapshot` do not exist and store preview keys are not exposed.

- [ ] **Step 3: Make import enums codable and expose preview keys in stores**

In `macos-app/Core/Models.swift`, update these enum declarations:

```swift
enum PersonalDataImportTarget: String, CaseIterable, Identifiable, Codable {
```

```swift
enum PersonalDataSaveMode: String, CaseIterable, Identifiable, Codable {
```

In `macos-app/Core/UserPortfolioStore.swift`, add this method inside `struct UserPortfolioStore` before `private func parseLine`:

```swift
    func previewKey(for holding: UserPortfolioHolding) -> String {
        mergeKey(for: holding)
    }
```

In `macos-app/Core/PendingTradesStore.swift`, add this method inside `struct PendingTradesStore` before `func delete(at fileURL: URL)`:

```swift
    func previewKey(for trade: PersonalPendingTrade) -> String {
        mergeKey(for: trade)
    }
```

In `macos-app/Core/InvestmentPlansStore.swift`, add this method inside `struct InvestmentPlansStore` before `func delete(at fileURL: URL)`:

```swift
    func previewKey(for plan: PersonalInvestmentPlan) -> String {
        mergeKey(for: plan)
    }
```

- [ ] **Step 4: Add import preview and undo implementation**

Create `macos-app/Core/ImportPreviewSession.swift`:

```swift
import Foundation

enum ImportPreviewChangeKind: String, Codable, CaseIterable, Hashable {
    case added
    case updated
    case unchanged
    case duplicate
    case removed
    case blocked
}

struct ImportPreviewRow: Identifiable, Codable, Hashable {
    let id: String
    let kind: ImportPreviewChangeKind
    let title: String
    let detail: String
    let beforeSummary: String?
    let afterSummary: String?
}

struct ImportPreviewSession: Identifiable, Codable, Hashable {
    let id: UUID
    let target: PersonalDataImportTarget
    let mode: PersonalDataSaveMode
    let createdAt: String
    let rows: [ImportPreviewRow]

    init(id: UUID = UUID(), target: PersonalDataImportTarget, mode: PersonalDataSaveMode, createdAt: String = "", rows: [ImportPreviewRow]) {
        self.id = id
        self.target = target
        self.mode = mode
        self.createdAt = createdAt
        self.rows = rows
    }

    var canConfirm: Bool {
        !rows.isEmpty && !rows.contains { $0.kind == .blocked }
    }

    func count(for kind: ImportPreviewChangeKind) -> Int {
        rows.filter { $0.kind == kind }.count
    }

    static func makeHoldings(
        imported: [UserPortfolioHolding],
        existing: [UserPortfolioHolding],
        mode: PersonalDataSaveMode,
        store: UserPortfolioStore,
        createdAt: String = ""
    ) -> ImportPreviewSession {
        make(
            target: .holdings,
            imported: imported,
            existing: existing,
            mode: mode,
            createdAt: createdAt,
            key: store.previewKey(for:),
            title: { $0.normalizedName ?? $0.normalizedFundCode },
            summary: { "代码 \($0.normalizedFundCode) · 份额 \(decimalText($0.units)) · 成本 \($0.costPrice.map(decimalText) ?? "—")" }
        )
    }

    static func makePendingTrades(
        imported: [PersonalPendingTrade],
        existing: [PersonalPendingTrade],
        mode: PersonalDataSaveMode,
        store: PendingTradesStore,
        createdAt: String = ""
    ) -> ImportPreviewSession {
        make(
            target: .pendingTrades,
            imported: imported,
            existing: existing,
            mode: mode,
            createdAt: createdAt,
            key: store.previewKey(for:),
            title: { $0.displayTitle },
            summary: { "\($0.occurredAt) · \($0.actionLabel) · \($0.amountText) · \($0.status)" }
        )
    }

    static func makeInvestmentPlans(
        imported: [PersonalInvestmentPlan],
        existing: [PersonalInvestmentPlan],
        mode: PersonalDataSaveMode,
        store: InvestmentPlansStore,
        createdAt: String = ""
    ) -> ImportPreviewSession {
        make(
            target: .investmentPlans,
            imported: imported,
            existing: existing,
            mode: mode,
            createdAt: createdAt,
            key: store.previewKey(for:),
            title: { $0.displayTitle },
            summary: { "\($0.planTypeLabel) · \($0.scheduleText) · \($0.amountText) · \($0.status)" }
        )
    }

    private static func make<T: Hashable>(
        target: PersonalDataImportTarget,
        imported: [T],
        existing: [T],
        mode: PersonalDataSaveMode,
        createdAt: String,
        key: (T) -> String,
        title: (T) -> String,
        summary: (T) -> String
    ) -> ImportPreviewSession {
        guard !imported.isEmpty else {
            return ImportPreviewSession(
                target: target,
                mode: mode,
                createdAt: createdAt,
                rows: [
                    ImportPreviewRow(
                        id: "\(target.id)-blocked-empty",
                        kind: .blocked,
                        title: "没有可导入记录",
                        detail: "请先导入或粘贴有效草稿。",
                        beforeSummary: nil,
                        afterSummary: nil
                    )
                ]
            )
        }

        let existingByKey = Dictionary(existing.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        let importedKeys = imported.map(key)
        var seenImportedKeys: Set<String> = []
        var rows: [ImportPreviewRow] = []

        for item in imported {
            let itemKey = key(item)
            let itemTitle = title(item)
            let after = summary(item)
            if seenImportedKeys.contains(itemKey) {
                rows.append(ImportPreviewRow(
                    id: "\(target.id)-duplicate-\(itemKey)-\(rows.count)",
                    kind: .duplicate,
                    title: itemTitle,
                    detail: "导入草稿中存在重复记录，确认后按现有合并规则处理。",
                    beforeSummary: nil,
                    afterSummary: after
                ))
                continue
            }
            seenImportedKeys.insert(itemKey)

            if let existingItem = existingByKey[itemKey] {
                let before = summary(existingItem)
                rows.append(ImportPreviewRow(
                    id: "\(target.id)-\(itemKey)",
                    kind: before == after ? .unchanged : .updated,
                    title: itemTitle,
                    detail: before == after ? "本地记录无需变化" : "本地记录将更新",
                    beforeSummary: before,
                    afterSummary: after
                ))
            } else {
                rows.append(ImportPreviewRow(
                    id: "\(target.id)-\(itemKey)",
                    kind: .added,
                    title: itemTitle,
                    detail: "将新增到本地数据",
                    beforeSummary: nil,
                    afterSummary: after
                ))
            }
        }

        if mode == .replace {
            let importedKeySet = Set(importedKeys)
            for item in existing where !importedKeySet.contains(key(item)) {
                rows.append(ImportPreviewRow(
                    id: "\(target.id)-removed-\(key(item))",
                    kind: .removed,
                    title: title(item),
                    detail: "替换模式会移除这条本地记录",
                    beforeSummary: summary(item),
                    afterSummary: nil
                ))
            }
        }

        return ImportPreviewSession(target: target, mode: mode, createdAt: createdAt, rows: rows)
    }
}

struct ImportUndoSnapshot: Codable, Hashable {
    let target: PersonalDataImportTarget
    let mode: PersonalDataSaveMode
    let createdAt: String
    let beforeHoldings: [UserPortfolioHolding]
    let beforePendingTrades: [PersonalPendingTrade]
    let beforeInvestmentPlans: [PersonalInvestmentPlan]
    let afterFingerprint: ImportDataFingerprint

    var restoreHoldings: [UserPortfolioHolding] { beforeHoldings }
    var restorePendingTrades: [PersonalPendingTrade] { beforePendingTrades }
    var restoreInvestmentPlans: [PersonalInvestmentPlan] { beforeInvestmentPlans }

    static func make(
        target: PersonalDataImportTarget,
        mode: PersonalDataSaveMode,
        createdAt: String,
        beforeHoldings: [UserPortfolioHolding],
        beforePendingTrades: [PersonalPendingTrade],
        beforeInvestmentPlans: [PersonalInvestmentPlan],
        afterHoldings: [UserPortfolioHolding],
        afterPendingTrades: [PersonalPendingTrade],
        afterInvestmentPlans: [PersonalInvestmentPlan]
    ) -> ImportUndoSnapshot {
        ImportUndoSnapshot(
            target: target,
            mode: mode,
            createdAt: createdAt,
            beforeHoldings: beforeHoldings,
            beforePendingTrades: beforePendingTrades,
            beforeInvestmentPlans: beforeInvestmentPlans,
            afterFingerprint: ImportDataFingerprint.make(
                holdings: afterHoldings,
                pendingTrades: afterPendingTrades,
                investmentPlans: afterInvestmentPlans
            )
        )
    }

    func isValid(
        currentHoldings: [UserPortfolioHolding],
        currentPendingTrades: [PersonalPendingTrade],
        currentInvestmentPlans: [PersonalInvestmentPlan]
    ) -> Bool {
        afterFingerprint == ImportDataFingerprint.make(
            holdings: currentHoldings,
            pendingTrades: currentPendingTrades,
            investmentPlans: currentInvestmentPlans
        )
    }
}

struct ImportDataFingerprint: Codable, Hashable {
    let holdings: String
    let pendingTrades: String
    let investmentPlans: String

    static func make(
        holdings: [UserPortfolioHolding],
        pendingTrades: [PersonalPendingTrade],
        investmentPlans: [PersonalInvestmentPlan]
    ) -> ImportDataFingerprint {
        ImportDataFingerprint(
            holdings: encodedString(holdings),
            pendingTrades: encodedString(pendingTrades),
            investmentPlans: encodedString(investmentPlans)
        )
    }

    private static func encodedString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(value),
            let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return text
    }
}

struct ImportUndoSnapshotStore {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load(from fileURL: URL) throws -> ImportUndoSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ImportUndoSnapshot.self, from: data)
    }

    func save(_ snapshot: ImportUndoSnapshot, to fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    func delete(at fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
```

- [ ] **Step 5: Run import preview tests**

Run:

```bash
(cd macos-app && swift test --filter ImportPreviewSessionTests)
```

Expected: PASS, 4 tests.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Core/ImportPreviewSession.swift macos-app/Core/Models.swift macos-app/Core/UserPortfolioStore.swift macos-app/Core/PendingTradesStore.swift macos-app/Core/InvestmentPlansStore.swift macos-app/Tests/QiemanDashboardTests/ImportPreviewSessionTests.swift
git commit -m "feat: add import preview and undo models"
```

## Task 4: Portfolio Snapshot Insight Core

**Files:**
- Create: `macos-app/Core/PortfolioSnapshotInsight.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/PortfolioSnapshotInsightTests.swift`

- [ ] **Step 1: Add failing insight tests**

Create `macos-app/Tests/QiemanDashboardTests/PortfolioSnapshotInsightTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class PortfolioSnapshotInsightTests: XCTestCase {
    func testSummaryReportsInsufficientHistory() {
        let summary = PortfolioSnapshotInsightSummary.make(snapshots: [], currentRows: [])

        XCTAssertFalse(summary.hasEnoughHistory)
        XCTAssertEqual(summary.headline, "等待组合快照")
        XCTAssertTrue(summary.cards.contains { $0.kind == .coverage })
    }

    func testSummaryComputesAssetChangeAndGainTone() {
        let snapshots = [
            snapshot(createdAt: "2026-06-11 15:00:00", totalExposure: 10_000, topWeight: 60),
            snapshot(createdAt: "2026-06-12 15:00:00", totalExposure: 12_500, topWeight: 55)
        ]

        let summary = PortfolioSnapshotInsightSummary.make(snapshots: snapshots, currentRows: [])

        XCTAssertTrue(summary.hasEnoughHistory)
        XCTAssertEqual(summary.headline, "组合占用增加 ¥2,500.00")
        XCTAssertEqual(summary.cards.first { $0.kind == .assetChange }?.tone, .gain)
    }

    func testSummaryComputesConcentrationDrift() {
        let snapshots = [
            snapshot(createdAt: "2026-06-11 15:00:00", totalExposure: 10_000, topWeight: 35),
            snapshot(createdAt: "2026-06-12 15:00:00", totalExposure: 10_000, topWeight: 48)
        ]

        let summary = PortfolioSnapshotInsightSummary.make(snapshots: snapshots, currentRows: [])

        XCTAssertEqual(summary.cards.first { $0.kind == .concentrationDrift }?.metric, "+13.00 pct")
        XCTAssertEqual(summary.cards.first { $0.kind == .concentrationDrift }?.tone, .warning)
    }

    func testSummaryIncludesPlanAndPendingImpactFromCurrentRows() {
        let rows = [
            row(name: "核心宽基", code: "000001", pendingAmount: 500, nextPlanAmount: 200)
        ]
        let snapshots = [
            snapshot(createdAt: "2026-06-11 15:00:00", totalExposure: 10_000, topWeight: 40),
            snapshot(createdAt: "2026-06-12 15:00:00", totalExposure: 10_700, topWeight: 41)
        ]

        let summary = PortfolioSnapshotInsightSummary.make(snapshots: snapshots, currentRows: rows)

        XCTAssertEqual(summary.cards.first { $0.kind == .pendingImpact }?.metric, "¥500.00")
        XCTAssertEqual(summary.cards.first { $0.kind == .planImpact }?.metric, "¥200.00")
    }

    func testStoreRecordsAndPrunesSnapshots() throws {
        let fileURL = try temporaryDirectory().appendingPathComponent("portfolio-insight-snapshots.json")
        let store = PortfolioSnapshotInsightStore()
        var snapshots: [PortfolioInsightSnapshot] = []
        for index in 0..<40 {
            snapshots.append(snapshot(createdAt: String(format: "2026-06-%02d 15:00:00", index + 1), totalExposure: Double(index), topWeight: 10))
        }

        try store.save(snapshots, to: fileURL)
        let loaded = try store.load(from: fileURL)

        XCTAssertEqual(loaded.count, 30)
        XCTAssertEqual(loaded.last?.createdAt, "2026-06-11 15:00:00")
    }

    private func snapshot(createdAt: String, totalExposure: Double, topWeight: Double) -> PortfolioInsightSnapshot {
        PortfolioInsightSnapshot(
            createdAt: createdAt,
            totalExposure: totalExposure,
            totalMarketValue: totalExposure,
            pendingAmount: 0,
            nextPlanAmount: 0,
            topHoldingName: "核心宽基",
            topHoldingWeightPct: topWeight,
            holdingCount: 1
        )
    }

    private func row(name: String, code: String, pendingAmount: Double, nextPlanAmount: Double) -> PersonalAssetAggregateRow {
        let holding = UserPortfolioHolding(fundCode: code, assetType: .fund, units: 100, costPrice: 1, displayName: name)
        let pendingTrades = [
            PersonalPendingTrade(
                occurredAt: "2026-06-12",
                actionLabel: "买入",
                fundName: name,
                fundCode: code,
                amountText: "\(pendingAmount)",
                amountValue: pendingAmount,
                status: "交易进行中"
            )
        ]
        let plans = [
            PersonalInvestmentPlan(
                planTypeLabel: "定投",
                fundName: name,
                fundCode: code,
                scheduleText: "每周三",
                amountText: "\(nextPlanAmount)",
                minAmount: nextPlanAmount,
                maxAmount: nextPlanAmount,
                nextExecutionDate: "2026-06-17",
                status: "进行中"
            )
        ]
        return PersonalAssetAggregateRow(
            key: code,
            assetType: .fund,
            fundName: name,
            fundCode: code,
            holdingRow: nil,
            rawHolding: holding,
            archivedHolding: nil,
            pendingTrades: pendingTrades,
            plans: plans
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("portfolio-snapshot-insight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [ ] **Step 2: Run the failing insight tests**

Run:

```bash
(cd macos-app && swift test --filter PortfolioSnapshotInsightTests)
```

Expected: FAIL because `PortfolioInsightSnapshot`, `PortfolioSnapshotInsightSummary`, and `PortfolioSnapshotInsightStore` do not exist.

- [ ] **Step 3: Add insight implementation**

Create `macos-app/Core/PortfolioSnapshotInsight.swift`:

```swift
import Foundation

struct PortfolioInsightSnapshot: Codable, Hashable, Identifiable {
    var id: String { createdAt }
    let createdAt: String
    let totalExposure: Double
    let totalMarketValue: Double
    let pendingAmount: Double
    let nextPlanAmount: Double
    let topHoldingName: String?
    let topHoldingWeightPct: Double
    let holdingCount: Int

    static func make(rows: [PersonalAssetAggregateRow], createdAt: String) -> PortfolioInsightSnapshot {
        let totalExposure = rows.reduce(0) { $0 + $1.effectiveHoldingAmount }
        let totalMarketValue = rows.reduce(0) { $0 + ($1.marketValue ?? 0) }
        let pendingAmount = rows.reduce(0) { $0 + $1.pendingCashAmount }
        let nextPlanAmount = rows.reduce(0) { $0 + $1.estimatedNextPlanAmount }
        let top = rows.max { $0.effectiveHoldingAmount < $1.effectiveHoldingAmount }
        let topWeight = totalExposure > 0 ? (top?.effectiveHoldingAmount ?? 0) / totalExposure * 100 : 0
        return PortfolioInsightSnapshot(
            createdAt: createdAt,
            totalExposure: totalExposure,
            totalMarketValue: totalMarketValue,
            pendingAmount: pendingAmount,
            nextPlanAmount: nextPlanAmount,
            topHoldingName: top?.fundName,
            topHoldingWeightPct: topWeight,
            holdingCount: rows.filter(\.hasHolding).count
        )
    }
}

enum PortfolioSnapshotInsightKind: String, Codable, Hashable {
    case assetChange
    case concentrationDrift
    case pendingImpact
    case planImpact
    case coverage
}

enum PortfolioSnapshotInsightTone: String, Codable, Hashable {
    case gain
    case loss
    case warning
    case info
    case neutral
}

struct PortfolioSnapshotInsightCard: Identifiable, Hashable {
    let kind: PortfolioSnapshotInsightKind
    let title: String
    let metric: String
    let detail: String
    let tone: PortfolioSnapshotInsightTone

    var id: PortfolioSnapshotInsightKind { kind }
}

struct PortfolioSnapshotInsightSummary: Hashable {
    let headline: String
    let hasEnoughHistory: Bool
    let cards: [PortfolioSnapshotInsightCard]

    static func make(snapshots: [PortfolioInsightSnapshot], currentRows: [PersonalAssetAggregateRow]) -> PortfolioSnapshotInsightSummary {
        let sorted = snapshots.sorted { $0.createdAt < $1.createdAt }
        let pendingAmount = currentRows.reduce(0) { $0 + $1.pendingCashAmount }
        let nextPlanAmount = currentRows.reduce(0) { $0 + $1.estimatedNextPlanAmount }

        guard sorted.count >= 2, let previous = sorted.dropLast().last, let latest = sorted.last else {
            return PortfolioSnapshotInsightSummary(
                headline: "等待组合快照",
                hasEnoughHistory: false,
                cards: [
                    PortfolioSnapshotInsightCard(
                        kind: .coverage,
                        title: "数据覆盖",
                        metric: "\(sorted.count) / 2",
                        detail: "至少需要两次组合快照才能生成变化洞察",
                        tone: .info
                    )
                ]
            )
        }

        let exposureDelta = latest.totalExposure - previous.totalExposure
        let topWeightDelta = latest.topHoldingWeightPct - previous.topHoldingWeightPct
        let headlineVerb = exposureDelta >= 0 ? "增加" : "减少"
        let headline = "组合占用\(headlineVerb) \(currencyText(abs(exposureDelta)))"
        let driftMetric = String(format: "%+.2f pct", topWeightDelta)

        return PortfolioSnapshotInsightSummary(
            headline: headline,
            hasEnoughHistory: true,
            cards: [
                PortfolioSnapshotInsightCard(
                    kind: .assetChange,
                    title: "资产变化",
                    metric: signedCurrencyText(exposureDelta),
                    detail: "\(previous.createdAt) 到 \(latest.createdAt)",
                    tone: exposureDelta > 0 ? .gain : (exposureDelta < 0 ? .loss : .neutral)
                ),
                PortfolioSnapshotInsightCard(
                    kind: .concentrationDrift,
                    title: "集中度漂移",
                    metric: driftMetric,
                    detail: latest.topHoldingName.map { "第一大标的：\($0)" } ?? "暂无第一大标的",
                    tone: abs(topWeightDelta) >= 10 ? .warning : .info
                ),
                PortfolioSnapshotInsightCard(
                    kind: .pendingImpact,
                    title: "待确认影响",
                    metric: currencyText(pendingAmount),
                    detail: pendingAmount > 0 ? "买入中或转换记录会影响实际敞口" : "暂无待确认交易影响",
                    tone: pendingAmount > 0 ? .warning : .neutral
                ),
                PortfolioSnapshotInsightCard(
                    kind: .planImpact,
                    title: "计划影响",
                    metric: currencyText(nextPlanAmount),
                    detail: nextPlanAmount > 0 ? "下一次计划投入估算" : "暂无进行中计划投入",
                    tone: nextPlanAmount > 0 ? .info : .neutral
                ),
                PortfolioSnapshotInsightCard(
                    kind: .coverage,
                    title: "快照覆盖",
                    metric: "\(sorted.count) 次",
                    detail: "最近快照：\(latest.createdAt)",
                    tone: .info
                )
            ]
        )
    }
}

struct PortfolioSnapshotInsightStore {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder
    private let maxCount: Int

    init(maxCount: Int = 30) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.maxCount = maxCount
    }

    func load(from fileURL: URL) throws -> [PortfolioInsightSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([PortfolioInsightSnapshot].self, from: data)
            .sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ snapshots: [PortfolioInsightSnapshot], to fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pruned = Array(snapshots.sorted { $0.createdAt < $1.createdAt }.suffix(maxCount))
        let data = try encoder.encode(pruned)
        try data.write(to: fileURL, options: .atomic)
    }

    func append(_ snapshot: PortfolioInsightSnapshot, to fileURL: URL) throws {
        let existing = try load(from: fileURL)
        var withoutSameTimestamp = existing.filter { $0.createdAt != snapshot.createdAt }
        withoutSameTimestamp.append(snapshot)
        try save(withoutSameTimestamp, to: fileURL)
    }
}
```

- [ ] **Step 4: Run insight tests**

Run:

```bash
(cd macos-app && swift test --filter PortfolioSnapshotInsightTests)
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Core/PortfolioSnapshotInsight.swift macos-app/Tests/QiemanDashboardTests/PortfolioSnapshotInsightTests.swift
git commit -m "feat: add portfolio snapshot insights"
```

## Task 5: Enhancement AppModel State And Persistence

**Files:**
- Modify: `macos-app/Core/AppModel/SubModels.swift`
- Modify: `macos-app/Core/AppModel.swift`
- Modify: `macos-app/Core/AppModel/ComputedProperties.swift`
- Modify: `macos-app/Core/AppModel/DataDirectory.swift`
- Create: `macos-app/Core/AppModel/EnhancementCenter.swift`

This task implements the design's thin `EnhancementCenterSummary` layer as AppModel summary computed properties: `managerWatchTimelineSummary`, `portfolioSnapshotInsightSummary`, current `monthlyReportSummary`, current `activeImportPreviewSession`, and current `canUndoLatestImport`. Do not create a separate summary type unless later UI code repeats the same four-field aggregation in more than one view.

- [ ] **Step 1: Add EnhancementState**

In `macos-app/Core/AppModel/SubModels.swift`, after `UpdateState`, add:

```swift
// MARK: - EnhancementState

@MainActor
final class EnhancementState: ObservableObject {
    @Published var selectedTab: EnhancementCenterTab = .review
    @Published var lastMonthlyReportExport: MonthlyReportExportMetadata?
    @Published var managerWatchTimelineEvents: [ManagerWatchTimelineEvent] = []
    @Published var activeImportPreviewSession: ImportPreviewSession?
    @Published var importUndoSnapshot: ImportUndoSnapshot?
    @Published var portfolioInsightSnapshots: [PortfolioInsightSnapshot] = []
    @Published var pendingOverwriteReportURL: URL?
}

enum EnhancementCenterTab: String, CaseIterable, Identifiable {
    case review = "复盘"
    case watch = "巡检"
    case importPreview = "导入"
    case insight = "洞察"

    var id: String { rawValue }
}
```

- [ ] **Step 2: Add AppModel enhancement proxies**

In `macos-app/Core/AppModel.swift`, add this property next to the other sub-model properties:

```swift
    @Published private(set) var enhancementState = EnhancementState()
```

Add these proxy properties after the update state proxies:

```swift
    var selectedEnhancementTab: EnhancementCenterTab {
        get { enhancementState.selectedTab }
        set { enhancementState.selectedTab = newValue }
    }

    var lastMonthlyReportExport: MonthlyReportExportMetadata? {
        get { enhancementState.lastMonthlyReportExport }
        set { enhancementState.lastMonthlyReportExport = newValue }
    }

    var managerWatchTimelineEvents: [ManagerWatchTimelineEvent] {
        get { enhancementState.managerWatchTimelineEvents }
        set { enhancementState.managerWatchTimelineEvents = newValue }
    }

    var activeImportPreviewSession: ImportPreviewSession? {
        get { enhancementState.activeImportPreviewSession }
        set { enhancementState.activeImportPreviewSession = newValue }
    }

    var importUndoSnapshot: ImportUndoSnapshot? {
        get { enhancementState.importUndoSnapshot }
        set { enhancementState.importUndoSnapshot = newValue }
    }

    var portfolioInsightSnapshots: [PortfolioInsightSnapshot] {
        get { enhancementState.portfolioInsightSnapshots }
        set { enhancementState.portfolioInsightSnapshots = newValue }
    }

    var pendingOverwriteReportURL: URL? {
        get { enhancementState.pendingOverwriteReportURL }
        set { enhancementState.pendingOverwriteReportURL = newValue }
    }
```

In `init()`, after `updateState.objectWillChange`, add:

```swift
        enhancementState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
```

- [ ] **Step 3: Add persisted enhancement URLs**

In `macos-app/Core/AppModel/ComputedProperties.swift`, add these computed properties next to other data file URLs:

```swift
    var monthlyReportExportMetadataURL: URL? {
        dataDirectoryURL?.appendingPathComponent("monthly-report-export.json", isDirectory: false)
    }

    var managerWatchTimelineFileURL: URL? {
        dataDirectoryURL?.appendingPathComponent("manager-watch-timeline.json", isDirectory: false)
    }

    var importUndoSnapshotFileURL: URL? {
        dataDirectoryURL?.appendingPathComponent("latest-import-undo.json", isDirectory: false)
    }

    var portfolioInsightSnapshotsFileURL: URL? {
        dataDirectoryURL?.appendingPathComponent("portfolio-insight-snapshots.json", isDirectory: false)
    }
```

- [ ] **Step 4: Add enhancement orchestration file**

Create `macos-app/Core/AppModel/EnhancementCenter.swift`:

```swift
import AppKit
import Foundation

extension AppModel {
    var managerWatchTimelineSummary: ManagerWatchTimelineSummary {
        ManagerWatchTimelineSummary.make(events: managerWatchTimelineEvents)
    }

    var portfolioSnapshotInsightSummary: PortfolioSnapshotInsightSummary {
        PortfolioSnapshotInsightSummary.make(
            snapshots: portfolioInsightSnapshots,
            currentRows: personalAssetRows
        )
    }

    func loadEnhancementState() {
        loadMonthlyReportExportMetadata()
        loadManagerWatchTimeline()
        loadImportUndoSnapshot()
        loadPortfolioInsightSnapshots()
    }

    func loadMonthlyReportExportMetadata() {
        guard let monthlyReportExportMetadataURL else { return }
        do {
            lastMonthlyReportExport = try MonthlyReportExportMetadataStore().load(from: monthlyReportExportMetadataURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadManagerWatchTimeline() {
        guard let managerWatchTimelineFileURL else { return }
        do {
            managerWatchTimelineEvents = try ManagerWatchTimelineStore().load(from: managerWatchTimelineFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadImportUndoSnapshot() {
        guard let importUndoSnapshotFileURL else { return }
        do {
            importUndoSnapshot = try ImportUndoSnapshotStore().load(from: importUndoSnapshotFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPortfolioInsightSnapshots() {
        guard let portfolioInsightSnapshotsFileURL else { return }
        do {
            portfolioInsightSnapshots = try PortfolioSnapshotInsightStore().load(from: portfolioInsightSnapshotsFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyMonthlyReportToPasteboard(_ report: MonthlyReportSummary) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report.markdown, forType: .string)
        noticeMessage = "已复制月报 Markdown。"
    }

    func archiveMonthlyReport(overwriteConfirmed: Bool = false) {
        guard let dataDirectoryURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法导出月报。"
            return
        }
        do {
            let metadata = try MonthlyReportExporter().archive(
                report: monthlyReportSummary,
                in: dataDirectoryURL,
                exportedAt: Self.timestampString(),
                overwriteConfirmed: overwriteConfirmed
            )
            try persistMonthlyReportExportMetadata(metadata)
            pendingOverwriteReportURL = nil
            noticeMessage = "已导出月报：\(URL(fileURLWithPath: metadata.filePath).lastPathComponent)"
        } catch MonthlyReportExportError.archiveAlreadyExists(let url) {
            pendingOverwriteReportURL = url
            errorMessage = "月报已存在，确认覆盖后可重新导出：\(url.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveMonthlyReportAs(to url: URL) {
        do {
            let metadata = try MonthlyReportExporter().saveAs(
                report: monthlyReportSummary,
                to: url,
                exportedAt: Self.timestampString()
            )
            try persistMonthlyReportExportMetadata(metadata)
            noticeMessage = "已另存月报：\(url.lastPathComponent)"
        } catch {
            errorMessage = "月报写入失败：\(url.path)；\(error.localizedDescription)"
        }
    }

    private func persistMonthlyReportExportMetadata(_ metadata: MonthlyReportExportMetadata) throws {
        guard let monthlyReportExportMetadataURL else { return }
        try MonthlyReportExportMetadataStore().save(metadata, to: monthlyReportExportMetadataURL)
        lastMonthlyReportExport = metadata
    }

    func recordManagerWatchTimelineEvent(_ event: ManagerWatchTimelineEvent) {
        guard let managerWatchTimelineFileURL else { return }
        do {
            try ManagerWatchTimelineStore().append(event, to: managerWatchTimelineFileURL)
            managerWatchTimelineEvents = try ManagerWatchTimelineStore().load(from: managerWatchTimelineFileURL)
        } catch {
            managerWatchTimelineEvents = ManagerWatchTimelineStore.pruned(managerWatchTimelineEvents + [event])
        }
    }

    func recordPortfolioInsightSnapshotIfPossible(createdAt: String = Self.timestampString()) {
        guard let portfolioInsightSnapshotsFileURL, !personalAssetRows.isEmpty else { return }
        let snapshot = PortfolioInsightSnapshot.make(rows: personalAssetRows, createdAt: createdAt)
        do {
            try PortfolioSnapshotInsightStore().append(snapshot, to: portfolioInsightSnapshotsFileURL)
            portfolioInsightSnapshots = try PortfolioSnapshotInsightStore().load(from: portfolioInsightSnapshotsFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 5: Load enhancement state on startup**

In `macos-app/Core/AppModel/DataDirectory.swift`, call `loadEnhancementState()` immediately after `loadManagerWatchSettings()` in both data-directory initialization paths. The changed block should look like:

```swift
            loadManagerWatchSettings()
            loadEnhancementState()
```

- [ ] **Step 6: Run build check**

Run:

```bash
swift build --package-path macos-app
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add macos-app/Core/AppModel/SubModels.swift macos-app/Core/AppModel.swift macos-app/Core/AppModel/ComputedProperties.swift macos-app/Core/AppModel/DataDirectory.swift macos-app/Core/AppModel/EnhancementCenter.swift
git commit -m "feat: add enhancement center state"
```

## Task 6: Wire Manager Watch Timeline Events

**Files:**
- Modify: `macos-app/Core/AppModel/ManagerWatch.swift`
- Modify: `macos-app/Core/AppModel/PortfolioRefresh.swift`

- [ ] **Step 1: Record portfolio insight snapshots after refresh**

In `macos-app/Core/AppModel/PortfolioRefresh.swift`, after the successful assignment to `userPortfolioSnapshot` and after `rebuildAssetRows()`, add:

```swift
            recordPortfolioInsightSnapshotIfPossible(createdAt: snapshot.refreshedAt)
```

Run:

```bash
swift build --package-path macos-app
```

Expected: PASS.

- [ ] **Step 2: Record watch poll start and validation failures**

In `performManagerWatchPoll(sendNotifications:manual:)`, after `prodCode` and `managerName` are computed and after both guard checks pass, add:

```swift
        recordManagerWatchTimelineEvent(
            ManagerWatchTimelineEvent(
                kind: .pollStarted,
                prodCode: prodCode,
                managerName: managerName,
                title: manual ? "手动巡检开始" : "自动巡检开始",
                detail: managerWatchScopeText
            )
        )
```

For the missing-target guard, before `return`, add:

```swift
            recordManagerWatchTimelineEvent(
                ManagerWatchTimelineEvent(
                    kind: .failed,
                    prodCode: prodCode,
                    managerName: managerName,
                    title: "巡检目标缺失",
                    detail: "通知巡检需要产品代码和主理人名称。",
                    errorMessage: "通知巡检需要产品代码和主理人名称。"
                )
            )
```

For the no-scope guard, before `return`, add:

```swift
            recordManagerWatchTimelineEvent(
                ManagerWatchTimelineEvent(
                    kind: .failed,
                    prodCode: prodCode,
                    managerName: managerName,
                    title: "巡检范围为空",
                    detail: "至少要开启调仓或发言其中一项。",
                    errorMessage: "通知巡检至少要开启调仓或发言其中一项。"
                )
            )
```

- [ ] **Step 3: Record forum and platform events**

Inside the forum watch success block, after `let newRecords = unseenItems(...)`, add:

```swift
                if previousID != nil, newRecords.isEmpty {
                    recordManagerWatchTimelineEvent(
                        ManagerWatchTimelineEvent(
                            kind: .duplicateSuppressed,
                            prodCode: prodCode,
                            managerName: managerName,
                            title: "发言无新增",
                            detail: "最新发言已在巡检基线内，未重复通知。"
                        )
                    )
                }
```

Inside the `if previousID != nil, !newRecords.isEmpty, sendNotifications` block, after `updateTitles.append("新发言 \(newRecords.count) 条")`, add:

```swift
                    recordManagerWatchTimelineEvent(
                        ManagerWatchTimelineEvent(
                            kind: .forumHit,
                            prodCode: prodCode,
                            managerName: managerName,
                            title: "命中新发言 \(newRecords.count) 条",
                            detail: newRecords.first?.titleText ?? "发现新的主理人发言",
                            targetID: newRecords.first?.id
                        )
                    )
```

Inside the forum `catch`, after `encounteredErrors.append(...)`, add:

```swift
                recordManagerWatchTimelineEvent(
                    ManagerWatchTimelineEvent(
                        kind: .failed,
                        prodCode: prodCode,
                        managerName: managerName,
                        title: "发言巡检失败",
                        detail: error.localizedDescription,
                        errorMessage: error.localizedDescription
                    )
                )
```

Inside the platform watch success block, after `let newActions = unseenItems(...)`, add:

```swift
                if previousID != nil, newActions.isEmpty {
                    recordManagerWatchTimelineEvent(
                        ManagerWatchTimelineEvent(
                            kind: .duplicateSuppressed,
                            prodCode: prodCode,
                            managerName: managerName,
                            title: "调仓无新增",
                            detail: "最新调仓已在巡检基线内，未重复通知。"
                        )
                    )
                }
```

Inside the `if previousID != nil, !newActions.isEmpty, sendNotifications` block, after `updateTitles.append("新调仓 \(newActions.count) 条")`, add:

```swift
                    recordManagerWatchTimelineEvent(
                        ManagerWatchTimelineEvent(
                            kind: .platformHit,
                            prodCode: prodCode,
                            managerName: managerName,
                            title: "命中新调仓 \(newActions.count) 条",
                            detail: newActions.first.map(platformNotificationBody(for:)) ?? "发现新的平台调仓",
                            targetID: newActions.first?.id
                        )
                    )
```

Inside the platform `catch`, after `encounteredErrors.append(...)`, add:

```swift
                recordManagerWatchTimelineEvent(
                    ManagerWatchTimelineEvent(
                        kind: .failed,
                        prodCode: prodCode,
                        managerName: managerName,
                        title: "调仓巡检失败",
                        detail: error.localizedDescription,
                        errorMessage: error.localizedDescription
                    )
                )
```

- [ ] **Step 4: Record recovery and no-update events**

Before the `if encounteredErrors.isEmpty` block mutates `lastErrorMessage`, capture the previous error:

```swift
        let previousErrorMessage = managerWatchSettings.lastErrorMessage
```

Inside the `if encounteredErrors.isEmpty` branch, after `managerWatchSettings.lastErrorMessage = nil`, add:

```swift
            if previousErrorMessage?.isEmpty == false {
                recordManagerWatchTimelineEvent(
                    ManagerWatchTimelineEvent(
                        kind: .recovered,
                        prodCode: prodCode,
                        managerName: managerName,
                        title: "巡检恢复",
                        detail: "上次失败后，本次巡检已恢复成功。"
                    )
                )
            } else if updateTitles.isEmpty {
                recordManagerWatchTimelineEvent(
                    ManagerWatchTimelineEvent(
                        kind: .noUpdates,
                        prodCode: prodCode,
                        managerName: managerName,
                        title: "巡检完成，无新增",
                        detail: managerWatchScopeText
                    )
                )
            }
```

- [ ] **Step 5: Build and run timeline tests**

Run:

```bash
swift build --package-path macos-app
(cd macos-app && swift test --filter ManagerWatchTimelineTests)
```

Expected: both commands PASS.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Core/AppModel/ManagerWatch.swift macos-app/Core/AppModel/PortfolioRefresh.swift
git commit -m "feat: record enhancement timeline events"
```

## Task 7: AppModel Import Preview, Confirm, And Undo

**Files:**
- Modify: `macos-app/Core/AppModel/EnhancementCenter.swift`
- Modify: `macos-app/Core/AppModel/PortfolioCRUD.swift`
- Modify: `macos-app/Core/AppModel/PendingTrade.swift`
- Modify: `macos-app/Core/AppModel/InvestmentPlan.swift`

- [ ] **Step 1: Add import preview methods to EnhancementCenter.swift**

Append this code inside the `extension AppModel` in `macos-app/Core/AppModel/EnhancementCenter.swift`:

```swift
    func prepareImportPreview(target: PersonalDataImportTarget, mode: PersonalDataSaveMode) {
        do {
            let createdAt = Self.timestampString()
            switch target {
            case .holdings:
                let imported = try importedPortfolioHoldings(from: portfolioDraft)
                activeImportPreviewSession = ImportPreviewSession.makeHoldings(
                    imported: imported,
                    existing: userPortfolioHoldings,
                    mode: mode,
                    store: portfolioStore,
                    createdAt: createdAt
                )
            case .pendingTrades:
                let imported = try importedPendingTrades(from: pendingTradesDraft)
                activeImportPreviewSession = ImportPreviewSession.makePendingTrades(
                    imported: imported,
                    existing: pendingTrades,
                    mode: mode,
                    store: pendingTradesStore,
                    createdAt: createdAt
                )
            case .investmentPlans:
                let imported = try importedInvestmentPlans(from: investmentPlansDraft)
                activeImportPreviewSession = ImportPreviewSession.makeInvestmentPlans(
                    imported: imported,
                    existing: investmentPlans,
                    mode: mode,
                    store: investmentPlansStore,
                    createdAt: createdAt
                )
            }
            selectedEnhancementTab = .importPreview
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmActiveImportPreview() {
        guard let session = activeImportPreviewSession, session.canConfirm else {
            errorMessage = "当前导入预览存在阻塞项，不能确认写入。"
            return
        }
        do {
            switch session.target {
            case .holdings:
                try confirmHoldingsImportPreview(mode: session.mode, createdAt: session.createdAt)
            case .pendingTrades:
                try confirmPendingTradesImportPreview(mode: session.mode, createdAt: session.createdAt)
            case .investmentPlans:
                try confirmInvestmentPlansImportPreview(mode: session.mode, createdAt: session.createdAt)
            }
            activeImportPreviewSession = nil
            selectedEnhancementTab = .importPreview
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmHoldingsImportPreview(mode: PersonalDataSaveMode, createdAt: String) throws {
        guard let portfolioFileURL, let importUndoSnapshotFileURL else {
            throw LiveRefreshError(message: "应用数据目录还没准备好，暂时无法保存持仓。")
        }
        let imported = try importedPortfolioHoldings(from: portfolioDraft)
        let nextHoldings = mode == .merge ? portfolioStore.merging(imported, into: userPortfolioHoldings) : imported
        let snapshot = ImportUndoSnapshot.make(
            target: .holdings,
            mode: mode,
            createdAt: createdAt.isEmpty ? Self.timestampString() : createdAt,
            beforeHoldings: userPortfolioHoldings,
            beforePendingTrades: pendingTrades,
            beforeInvestmentPlans: investmentPlans,
            afterHoldings: nextHoldings,
            afterPendingTrades: pendingTrades,
            afterInvestmentPlans: investmentPlans
        )
        try ImportUndoSnapshotStore().save(snapshot, to: importUndoSnapshotFileURL)
        userPortfolioHoldings = nextHoldings
        userPortfolioSnapshot = nil
        rebuildAssetRows()
        try portfolioStore.save(nextHoldings, to: portfolioFileURL)
        portfolioDraft = ""
        importUndoSnapshot = snapshot
        noticeMessage = "已\(mode.actionText)保存 \(imported.count) 条个人持仓，正在按代码补全名称。"
        Task {
            let resolvedCount = await resolveAndPersistPortfolioNames()
            try? await refreshUserPortfolio(updateNotice: false)
            if resolvedCount > 0 {
                noticeMessage = "已\(mode.actionText)保存 \(imported.count) 条个人持仓，并通过代码补全 \(resolvedCount) 个名称。"
            } else {
                noticeMessage = "已\(mode.actionText)保存 \(imported.count) 条个人持仓。"
            }
        }
    }

    private func confirmPendingTradesImportPreview(mode: PersonalDataSaveMode, createdAt: String) throws {
        guard let pendingTradeFileURL, let importUndoSnapshotFileURL else {
            throw LiveRefreshError(message: "应用数据目录还没准备好，暂时无法保存买入中记录。")
        }
        let imported = try importedPendingTrades(from: pendingTradesDraft)
        let nextTrades = mode == .merge ? pendingTradesStore.merging(imported, into: pendingTrades) : imported.sorted { $0.occurredAt > $1.occurredAt }
        let snapshot = ImportUndoSnapshot.make(
            target: .pendingTrades,
            mode: mode,
            createdAt: createdAt.isEmpty ? Self.timestampString() : createdAt,
            beforeHoldings: userPortfolioHoldings,
            beforePendingTrades: pendingTrades,
            beforeInvestmentPlans: investmentPlans,
            afterHoldings: userPortfolioHoldings,
            afterPendingTrades: nextTrades,
            afterInvestmentPlans: investmentPlans
        )
        try ImportUndoSnapshotStore().save(snapshot, to: importUndoSnapshotFileURL)
        pendingTrades = nextTrades
        pendingTradesDraft = ""
        clearPendingTradeCaches()
        rebuildAssetRows()
        try pendingTradesStore.save(nextTrades, to: pendingTradeFileURL)
        importUndoSnapshot = snapshot
        noticeMessage = "已\(mode.actionText)保存 \(imported.count) 条买入中记录。"
        Task { await applyPersonalAssetAutomation() }
    }

    private func confirmInvestmentPlansImportPreview(mode: PersonalDataSaveMode, createdAt: String) throws {
        guard let investmentPlanFileURL, let importUndoSnapshotFileURL else {
            throw LiveRefreshError(message: "应用数据目录还没准备好，暂时无法保存定投计划。")
        }
        let imported = try importedInvestmentPlans(from: investmentPlansDraft)
        let nextPlans = mode == .merge ? investmentPlansStore.merging(imported, into: investmentPlans).sorted(by: sortInvestmentPlans) : imported.sorted(by: sortInvestmentPlans)
        let snapshot = ImportUndoSnapshot.make(
            target: .investmentPlans,
            mode: mode,
            createdAt: createdAt.isEmpty ? Self.timestampString() : createdAt,
            beforeHoldings: userPortfolioHoldings,
            beforePendingTrades: pendingTrades,
            beforeInvestmentPlans: investmentPlans,
            afterHoldings: userPortfolioHoldings,
            afterPendingTrades: pendingTrades,
            afterInvestmentPlans: nextPlans
        )
        try ImportUndoSnapshotStore().save(snapshot, to: importUndoSnapshotFileURL)
        investmentPlans = nextPlans
        investmentPlansDraft = ""
        clearInvestmentPlanCaches()
        rebuildAssetRows()
        try investmentPlansStore.save(nextPlans, to: investmentPlanFileURL)
        importUndoSnapshot = snapshot
        noticeMessage = "已\(mode.actionText)保存 \(imported.count) 条定投计划。"
        Task { await applyPersonalAssetAutomation() }
    }
```

- [ ] **Step 2: Add undo methods to EnhancementCenter.swift**

Append this code inside the same `extension AppModel`:

```swift
    var canUndoLatestImport: Bool {
        guard let importUndoSnapshot else { return false }
        return importUndoSnapshot.isValid(
            currentHoldings: userPortfolioHoldings,
            currentPendingTrades: pendingTrades,
            currentInvestmentPlans: investmentPlans
        )
    }

    func undoLatestImport() {
        guard let snapshot = importUndoSnapshot else {
            errorMessage = "没有可撤销的导入。"
            return
        }
        guard snapshot.isValid(currentHoldings: userPortfolioHoldings, currentPendingTrades: pendingTrades, currentInvestmentPlans: investmentPlans) else {
            invalidateLatestImportUndo()
            errorMessage = "本地数据已变化，无法安全撤销上次导入。"
            return
        }
        do {
            if let portfolioFileURL {
                userPortfolioHoldings = snapshot.restoreHoldings
                if userPortfolioHoldings.isEmpty {
                    try portfolioStore.delete(at: portfolioFileURL)
                } else {
                    try portfolioStore.save(userPortfolioHoldings, to: portfolioFileURL)
                }
                userPortfolioSnapshot = nil
            }
            if let pendingTradeFileURL {
                pendingTrades = snapshot.restorePendingTrades.sorted { $0.occurredAt > $1.occurredAt }
                if pendingTrades.isEmpty {
                    try pendingTradesStore.delete(at: pendingTradeFileURL)
                } else {
                    try pendingTradesStore.save(pendingTrades, to: pendingTradeFileURL)
                }
            }
            if let investmentPlanFileURL {
                investmentPlans = snapshot.restoreInvestmentPlans.sorted(by: sortInvestmentPlans)
                if investmentPlans.isEmpty {
                    try investmentPlansStore.delete(at: investmentPlanFileURL)
                } else {
                    try investmentPlansStore.save(investmentPlans, to: investmentPlanFileURL)
                }
            }
            clearCachedComputedProperties()
            rebuildAssetRows()
            invalidateLatestImportUndo()
            noticeMessage = "已撤销上次导入。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func invalidateLatestImportUndo() {
        importUndoSnapshot = nil
        guard let importUndoSnapshotFileURL else { return }
        try? ImportUndoSnapshotStore().delete(at: importUndoSnapshotFileURL)
    }
```

- [ ] **Step 3: Invalidate undo after manual edits**

In the following mutating methods, add `invalidateLatestImportUndo()` immediately after the method confirms it will write changed personal data and before returning success:

- `deletePersonalAssetEntry(_:scope:)`
- `updatePersonalAssetHolding(_:codeText:unitsText:costPriceText:displayNameText:)`
- `addPersonalAssetHolding(assetType:codeText:unitsText:costPriceText:displayName:stockMarket:fundMarket:)`
- `archivePersonalAssetHolding(_:)`
- `restoreArchivedHolding(_:)`
- `adjustPersonalAssetUnits(_:mode:unitsText:unitNetValueText:)`
- `addPendingTrade(...)`
- `updatePendingTrade(_:...)`
- `deletePendingTrade(_:)`
- `addInvestmentPlan(...)`
- `updateInvestmentPlan(...)`
- `deleteInvestmentPlan(_:)`
- `updateInvestmentPlansStatus(_:status:activeOnly:archivedOnly:)`

Use this exact line:

```swift
            invalidateLatestImportUndo()
```

Run:

```bash
swift build --package-path macos-app
```

Expected: PASS. If a method is not throwing and does not have an indented `do` block, add the same line after the successful store save and before setting `noticeMessage`.

- [ ] **Step 4: Build and test import preview**

Run:

```bash
swift build --package-path macos-app
(cd macos-app && swift test --filter ImportPreviewSessionTests)
```

Expected: both commands PASS.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Core/AppModel/EnhancementCenter.swift macos-app/Core/AppModel/PortfolioCRUD.swift macos-app/Core/AppModel/PendingTrade.swift macos-app/Core/AppModel/InvestmentPlan.swift
git commit -m "feat: wire import preview and undo"
```

## Task 8: Enhancement Center Navigation And UI

**Files:**
- Modify: `macos-app/Core/Models.swift`
- Modify: `macos-app/Views/ContentView.swift`
- Create: `macos-app/Views/EnhancementCenterView.swift`
- Modify: `macos-app/Views/PortfolioSectionView.swift`

- [ ] **Step 1: Add `增强` navigation section**

In `macos-app/Core/Models.swift`, update `AppSection`:

```swift
enum AppSection: String, CaseIterable, Identifiable {
    case overview = "总览"
    case portfolio = "我的持仓"
    case platform = "平台调仓"
    case forum = "论坛发言"
    case enhancement = "增强"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview:
            return "rectangle.grid.2x2"
        case .portfolio:
            return "briefcase"
        case .settings:
            return "gearshape"
        case .platform:
            return "chart.bar.xaxis"
        case .forum:
            return "text.bubble"
        case .enhancement:
            return "sparkles"
        }
    }
}
```

In `macos-app/Views/ContentView.swift`, update `shouldShowQueryToolbar` so `.enhancement` is grouped with non-query sections:

```swift
        case .overview, .portfolio, .enhancement, .settings:
            return false
```

Update the `detailPanel` switch in `ContentView.swift` so `.enhancement` displays the new view:

```swift
        case .enhancement:
            EnhancementCenterView()
```

- [ ] **Step 2: Create EnhancementCenterView**

Create `macos-app/Views/EnhancementCenterView.swift`:

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EnhancementCenterView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importTarget: PersonalDataImportTarget = .holdings
    @State private var importMode: PersonalDataSaveMode = .merge
    @State private var didCopyReport = false
    @State private var isImportingFile = false
    @State private var importSource: PersonalDataImportSource = .table

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                summaryGrid

                Picker("增强中心", selection: $model.selectedEnhancementTab) {
                    ForEach(EnhancementCenterTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch model.selectedEnhancementTab {
                case .review:
                    reviewPanel
                case .watch:
                    watchPanel
                case .importPreview:
                    importPanel
                case .insight:
                    insightPanel
                }
            }
            .padding(18)
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: importSource == .image ? [.image] : [.commaSeparatedText, .plainText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await model.importExternalFile(at: url, source: importSource, target: importTarget) }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
        .alert("覆盖已有月报？", isPresented: overwriteReportBinding) {
            Button("覆盖", role: .destructive) {
                model.archiveMonthlyReport(overwriteConfirmed: true)
            }
            Button("取消", role: .cancel) {
                model.pendingOverwriteReportURL = nil
            }
        } message: {
            Text(model.pendingOverwriteReportURL?.lastPathComponent ?? "同月月报已存在。")
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            MetricCard(
                title: "本月复盘",
                value: model.monthlyReportSummary.monthText,
                subtitle: model.lastMonthlyReportExport.map { "已导出 \($0.exportedAt)" } ?? "可复制或归档 Markdown",
                icon: "doc.text",
                accent: AppPalette.brand
            )
            MetricCard(
                title: "巡检",
                value: model.managerWatchTimelineSummary.latestStatusText,
                subtitle: "\(model.managerWatchTimelineEvents.count) 条时间线记录",
                icon: "bell.badge",
                accent: model.managerWatchTimelineSummary.failureCount > 0 ? AppPalette.warning : AppPalette.positive
            )
            MetricCard(
                title: "导入安全",
                value: model.canUndoLatestImport ? "可撤销" : "无待撤销",
                subtitle: model.activeImportPreviewSession.map { "\($0.rows.count) 条预览变更" } ?? "先预览，再写入",
                icon: "arrow.triangle.2.circlepath",
                accent: model.canUndoLatestImport ? AppPalette.warning : AppPalette.info
            )
            MetricCard(
                title: "组合洞察",
                value: model.portfolioSnapshotInsightSummary.hasEnoughHistory ? "已生成" : "待快照",
                subtitle: model.portfolioSnapshotInsightSummary.headline,
                icon: "chart.xyaxis.line",
                accent: model.portfolioSnapshotInsightSummary.hasEnoughHistory ? AppPalette.positive : AppPalette.muted
            )
        }
    }

    private var reviewPanel: some View {
        SectionCard(title: "复盘", subtitle: model.monthlyReportSummary.title, icon: "doc.text") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        model.copyMonthlyReportToPasteboard(model.monthlyReportSummary)
                        didCopyReport = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopyReport = false }
                    } label: {
                        Label(didCopyReport ? "已复制" : "复制 Markdown", systemImage: didCopyReport ? "checkmark.circle" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.archiveMonthlyReport()
                    } label: {
                        Label("保存到归档", systemImage: "archivebox")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.brand)

                    Button {
                        presentSavePanel()
                    } label: {
                        Label("另存为", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                if let export = model.lastMonthlyReportExport {
                    Text("最近导出：\(URL(fileURLWithPath: export.filePath).lastPathComponent) · \(export.exportedAt)")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }

                Text(model.monthlyReportSummary.markdown)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppPalette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            }
        }
    }

    private var watchPanel: some View {
        SectionCard(title: "巡检", subtitle: model.managerWatchTimelineSummary.latestStatusText, icon: "bell.badge") {
            if model.managerWatchTimelineEvents.isEmpty {
                emptyState("暂无巡检时间线", detail: "开启主理人提醒或点击立即巡检后，这里会记录命中、失败和重复通知抑制。")
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.managerWatchTimelineSummary.events) { event in
                        timelineRow(event)
                    }
                }
            }
        }
    }

    private var importPanel: some View {
        SectionCard(title: "导入预演", subtitle: "先预览变更，再确认写入", icon: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Picker("目标", selection: $importTarget) {
                        ForEach(PersonalDataImportTarget.allCases) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                    Picker("模式", selection: $importMode) {
                        ForEach(PersonalDataSaveMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Button {
                        importSource = .table
                        isImportingFile = true
                    } label: {
                        Label("导入表格", systemImage: "tablecells")
                    }
                    Button {
                        importSource = .image
                        isImportingFile = true
                    } label: {
                        Label("识别图片", systemImage: "photo")
                    }
                    Spacer()
                }

                TextEditor(text: draftBinding)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))

                HStack(spacing: 10) {
                    Button {
                        model.prepareImportPreview(target: importTarget, mode: importMode)
                    } label: {
                        Label("生成预览", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.brand)

                    Button {
                        model.confirmActiveImportPreview()
                    } label: {
                        Label("确认写入", systemImage: "checkmark.circle")
                    }
                    .disabled(model.activeImportPreviewSession?.canConfirm != true)
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        model.undoLatestImport()
                    } label: {
                        Label("撤销上次导入", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!model.canUndoLatestImport)

                    Spacer()
                }

                if let session = model.activeImportPreviewSession {
                    importPreviewRows(session)
                } else {
                    emptyState("暂无导入预览", detail: "粘贴草稿或导入文件后点击生成预览。")
                }
            }
        }
    }

    private var insightPanel: some View {
        SectionCard(title: "洞察", subtitle: model.portfolioSnapshotInsightSummary.headline, icon: "chart.xyaxis.line") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(model.portfolioSnapshotInsightSummary.cards) { card in
                    insightCard(card)
                }
            }
        }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { model.draft(for: importTarget) },
            set: { model.updateDraft($0, for: importTarget) }
        )
    }

    private var overwriteReportBinding: Binding<Bool> {
        Binding(
            get: { model.pendingOverwriteReportURL != nil },
            set: { if !$0 { model.pendingOverwriteReportURL = nil } }
        )
    }

    private func presentSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.nameFieldStringValue = "\(model.monthlyReportSummary.monthText)-portfolio-report.md"
        if panel.runModal() == .OK, let url = panel.url {
            model.saveMonthlyReportAs(to: url)
        }
    }

    private func timelineRow(_ event: ManagerWatchTimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint(for: event.tone))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text(event.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
                if let error = event.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.warning)
                }
            }
            Spacer()
            Text(event.occurredAt.formatted(date: .numeric, time: .shortened))
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(10)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }

    private func importPreviewRows(_ session: ImportPreviewSession) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(ImportPreviewChangeKind.allCases, id: \.self) { kind in
                let rows = session.rows.filter { $0.kind == kind }
                if !rows.isEmpty {
                    Text("\(label(for: kind)) \(rows.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint(for: kind))
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppPalette.ink)
                            Text(row.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(AppPalette.muted)
                            if let before = row.beforeSummary {
                                Text("原：\(before)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppPalette.muted)
                            }
                            if let after = row.afterSummary {
                                Text("新：\(after)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppPalette.ink)
                            }
                        }
                        .padding(10)
                        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
                    }
                }
            }
        }
    }

    private func insightCard(_ card: PortfolioSnapshotInsightCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
            Text(card.metric)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint(for: card.tone))
            Text(card.detail)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .padding(12)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }

    private func tint(for tone: ManagerWatchTimelineTone) -> Color {
        switch tone {
        case .info:
            return AppPalette.info
        case .positive:
            return AppPalette.positive
        case .warning:
            return AppPalette.warning
        }
    }

    private func tint(for tone: PortfolioSnapshotInsightTone) -> Color {
        switch tone {
        case .gain:
            return AppPalette.marketGain
        case .loss:
            return AppPalette.marketLoss
        case .warning:
            return AppPalette.warning
        case .info:
            return AppPalette.info
        case .neutral:
            return AppPalette.muted
        }
    }

    private func tint(for kind: ImportPreviewChangeKind) -> Color {
        switch kind {
        case .added:
            return AppPalette.positive
        case .updated:
            return AppPalette.info
        case .unchanged:
            return AppPalette.muted
        case .duplicate:
            return AppPalette.warning
        case .removed, .blocked:
            return AppPalette.warning
        }
    }

    private func label(for kind: ImportPreviewChangeKind) -> String {
        switch kind {
        case .added:
            return "新增"
        case .updated:
            return "更新"
        case .unchanged:
            return "不变"
        case .duplicate:
            return "疑似重复"
        case .removed:
            return "移除"
        case .blocked:
            return "阻塞"
        }
    }
}
```

- [ ] **Step 3: Route portfolio monthly report buttons through AppModel**

In `macos-app/Views/PortfolioSectionView.swift`, replace the private `copyMonthlyReport(_:)` body with:

```swift
    private func copyMonthlyReport(_ report: MonthlyReportSummary) {
        model.copyMonthlyReportToPasteboard(report)
        didCopyMonthlyReport = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopyMonthlyReport = false
        }
    }
```

Leave `MonthlyReportPanel` copy-only in this task. The full export controls live in `EnhancementCenterView`.

- [ ] **Step 4: Build UI**

Run:

```bash
swift build --package-path macos-app
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Core/Models.swift macos-app/Views/ContentView.swift macos-app/Views/EnhancementCenterView.swift macos-app/Views/PortfolioSectionView.swift
git commit -m "feat: add enhancement center UI"
```

## Task 9: Verification And Packaging

**Files:**
- No planned file edits before running verification.
- Modify the enhancement files from Tasks 1 through 8 only when a verification command exposes a compile or test failure.

- [ ] **Step 1: Run focused tests**

Run:

```bash
(cd macos-app && swift test --filter MonthlyReportExporterTests)
(cd macos-app && swift test --filter ManagerWatchTimelineTests)
(cd macos-app && swift test --filter ImportPreviewSessionTests)
(cd macos-app && swift test --filter PortfolioSnapshotInsightTests)
```

Expected: all four commands PASS.

- [ ] **Step 2: Run full Swift tests**

Run:

```bash
(cd macos-app && swift test)
```

Expected: PASS for the full XCTest suite.

- [ ] **Step 3: Run Swift build**

Run:

```bash
swift build --package-path macos-app
```

Expected: PASS.

- [ ] **Step 4: Run Python syntax validation**

Run:

```bash
python3 -m compileall -q dashboard qieman_scraper.py qieman_community_scraper.py scripts
```

Expected: PASS with no output.

- [ ] **Step 5: Build v2.8.0 app package**

Run:

```bash
APP_VERSION=2.8.0 bash scripts/build_macos_app.sh
```

Expected: PASS and prints:

```text
App 已生成: /Users/xufan65/WorkSpace/code/ai/qieman-manager-dashboard/dist/macos-app/QiemanDashboard.app
压缩包: /tmp/QiemanDashboard-2.8.0.zip
```

- [ ] **Step 6: Inspect final diff**

Run:

```bash
git status --short
git diff --stat HEAD
```

Expected: only product enhancement center files and related tests are changed since the last implementation commit.

- [ ] **Step 7: Commit verification fixes or record clean verification**

When Step 1 through Step 5 required compile or test fixes after Task 8, commit them:

```bash
git add macos-app/Core macos-app/Views macos-app/Tests
git commit -m "fix: stabilize enhancement center build"
```

When there were no changes after Task 8, run this command and keep its output for the final report:

```bash
git status --short
```

## Execution Notes

- Keep every task buildable before committing.
- Do not move existing monthly report, diagnostics, attribution, or plan simulation logic into SwiftUI views.
- Do not add a charting dependency.
- Do not call new external historical NAV APIs.
- Preserve red-gain and green-loss semantics through `AppPalette.marketGain`, `AppPalette.marketLoss`, and `AppPalette.marketTint(for:)`.
- `ImportUndoSnapshot` depends on `UserPortfolioHolding`, `PersonalPendingTrade`, and `PersonalInvestmentPlan` remaining `Codable`; verify this by running `swift test --filter ImportPreviewSessionTests` before wiring UI.
- Use `[.plainText, .text]` for save panel content types and keep the `.md` filename extension in the default save name.
