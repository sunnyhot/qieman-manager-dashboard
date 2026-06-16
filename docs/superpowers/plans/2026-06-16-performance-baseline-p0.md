# Performance Baseline P0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe, lightweight timing instrumentation for the Swift app and Python dashboard so future performance changes have before/after evidence.

**Architecture:** Add one small Swift telemetry utility and one small Python telemetry module, then wire them into existing launch, refresh, derived-presentation, menu bar, request, fetch, and render paths. Telemetry records operation name, elapsed milliseconds, and safe low-cardinality metadata; it never logs cookies, authorization headers, full payloads, or personal position details.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, XCTest, Python 3 standard library `unittest`, existing SPM and `swiftc` build paths.

---

## Files And Responsibilities

- Create `macos-app/Core/PerformanceTelemetry.swift`: Swift timing utility, event formatting, metadata sanitization, `os.Logger` output, and test sink support.
- Create `macos-app/Tests/QiemanDashboardTests/PerformanceTelemetryTests.swift`: XCTest coverage for sync timing, async timing, deterministic formatting, and sensitive metadata redaction.
- Modify `macos-app/QiemanDashboardApp.swift`: measure app delegate launch/configure and menu bar title rendering.
- Modify `macos-app/Core/AppModel.swift`: measure `start()` and `refreshLatest(persist:updateNotice:)`.
- Modify `macos-app/Core/AppModel/PortfolioRefresh.swift`: measure portfolio and market-index refreshes.
- Modify `macos-app/Core/MenuBarTicker/MenuBarTickerEntries.swift`: measure menu bar ticker entry building.
- Modify `macos-app/Views/PersonalAssetBrowser.swift`: measure personal asset browser presentation building.
- Modify `macos-app/Core/AppModel/PlatformFilters.swift`: measure platform filtering and pagination.
- Create `dashboard/performance.py`: Python timing utility, environment-gated logging, decorator support, and sensitive metadata sanitization.
- Create `tests/test_performance_logging.py`: Python standard-library tests for disabled logging, enabled logging, redaction, and decorator timing.
- Modify `dashboard/server.py`: measure full HTTP request handling through `handle_one_request`.
- Modify `dashboard/platform_fetcher.py`: measure platform trade fetches and cache hits/misses.
- Modify `dashboard/fund_fetcher.py`: measure fund history and quote fetches and cache hits/misses.
- Modify `dashboard/html_pages.py`: measure home, platform, forum, and timeline render functions.

`scripts/build_macos_app.sh` already discovers Swift sources with `find "$ROOT_DIR/macos-app" -name '*.swift'`, so the new Swift file does not need a manual source-list edit. The release script still must be validated with `swift build --package-path macos-app` because this repository has both SPM and direct `swiftc` paths.

## Task 1: Add Swift Telemetry Utility

**Files:**
- Create: `macos-app/Core/PerformanceTelemetry.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/PerformanceTelemetryTests.swift`

- [ ] **Step 1: Write failing XCTest coverage for the Swift utility**

Create `macos-app/Tests/QiemanDashboardTests/PerformanceTelemetryTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class PerformanceTelemetryTests: XCTestCase {
    func testMeasureEmitsEventWithMetadata() {
        var events: [PerformanceTelemetryEvent] = []

        let value = PerformanceTelemetry.withSink({ events.append($0) }) {
            PerformanceTelemetry.measure("unit.sync", metadata: ["rowCount": "3"]) {
                "finished"
            }
        }

        XCTAssertEqual(value, "finished")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.name, "unit.sync")
        XCTAssertEqual(events.first?.metadata["rowCount"], "3")
        XCTAssertGreaterThanOrEqual(events.first?.elapsedMilliseconds ?? -1, 0)
    }

    func testMeasureAsyncEmitsEvent() async {
        var events: [PerformanceTelemetryEvent] = []

        let value = await PerformanceTelemetry.withSink({ events.append($0) }) {
            await PerformanceTelemetry.measureAsync("unit.async", metadata: ["operation": "refresh"]) {
                "ok"
            }
        }

        XCTAssertEqual(value, "ok")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.name, "unit.async")
        XCTAssertEqual(events.first?.metadata["operation"], "refresh")
    }

    func testMessageRedactsSensitiveMetadataAndSortsKeys() {
        let event = PerformanceTelemetryEvent(
            name: "unit.redaction",
            elapsedMilliseconds: 12.34,
            metadata: [
                "rowCount": "2",
                "cookie": "access_token=secret",
                "authorization": "Bearer secret",
                "note": String(repeating: "x", count: 90)
            ]
        )

        XCTAssertTrue(event.message.contains("unit.redaction 12.3ms"))
        XCTAssertTrue(event.message.contains("authorization=<redacted>"))
        XCTAssertTrue(event.message.contains("cookie=<redacted>"))
        XCTAssertTrue(event.message.contains("rowCount=2"))
        XCTAssertFalse(event.message.contains("access_token=secret"))
        XCTAssertFalse(event.message.contains("Bearer secret"))
        XCTAssertLessThan(event.message.count, 190)
    }
}
```

- [ ] **Step 2: Run the focused test and confirm it fails before implementation**

Run:

```bash
(cd macos-app && swift test --filter PerformanceTelemetryTests)
```

Expected: the command fails to compile with errors that include `cannot find 'PerformanceTelemetryEvent' in scope` or `cannot find 'PerformanceTelemetry' in scope`.

- [ ] **Step 3: Implement the Swift telemetry utility**

Create `macos-app/Core/PerformanceTelemetry.swift`:

```swift
import Foundation
import os

struct PerformanceTelemetryEvent: Equatable {
    let name: String
    let elapsedMilliseconds: Double
    let metadata: [String: String]

    var message: String {
        let base = "\(name) \(String(format: "%.1f", elapsedMilliseconds))ms"
        let metadataText = metadata
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(Self.safeMetadataValue(key: key, value: value))"
            }
            .joined(separator: " ")
        return metadataText.isEmpty ? base : "\(base) \(metadataText)"
    }

    private static func safeMetadataValue(key: String, value: String) -> String {
        if isSensitive(key) || isSensitive(value) {
            return "<redacted>"
        }
        if value.count > 80 {
            return String(value.prefix(77)) + "..."
        }
        return value
    }

    private static func isSensitive(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.contains("cookie")
            || lowercased.contains("authorization")
            || lowercased.contains("token")
    }
}

enum PerformanceTelemetry {
    typealias EventSink = (PerformanceTelemetryEvent) -> Void

    private static let lock = NSLock()
    private static var eventSink: EventSink?
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.sunnyhot.qieman.manager.dashboard",
        category: "performance"
    )

    static func start() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func record(
        _ name: String,
        startedAt startTime: UInt64,
        metadata: [String: String] = [:]
    ) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000.0
        emit(PerformanceTelemetryEvent(name: name, elapsedMilliseconds: elapsed, metadata: metadata))
    }

    @discardableResult
    static func measure<T>(
        _ name: String,
        metadata: [String: String] = [:],
        operation: () throws -> T
    ) rethrows -> T {
        let startedAt = start()
        defer { record(name, startedAt: startedAt, metadata: metadata) }
        return try operation()
    }

    @discardableResult
    static func measureAsync<T>(
        _ name: String,
        metadata: [String: String] = [:],
        operation: () async throws -> T
    ) async rethrows -> T {
        let startedAt = start()
        defer { record(name, startedAt: startedAt, metadata: metadata) }
        return try await operation()
    }

    @discardableResult
    static func withSink<T>(_ sink: @escaping EventSink, run: () throws -> T) rethrows -> T {
        let previousSink = swapSink(sink)
        defer { _ = swapSink(previousSink) }
        return try run()
    }

    @discardableResult
    static func withSink<T>(_ sink: @escaping EventSink, run: () async throws -> T) async rethrows -> T {
        let previousSink = swapSink(sink)
        defer { _ = swapSink(previousSink) }
        return try await run()
    }

    private static func swapSink(_ sink: EventSink?) -> EventSink? {
        lock.lock()
        defer { lock.unlock() }
        let previous = eventSink
        eventSink = sink
        return previous
    }

    private static func currentSink() -> EventSink? {
        lock.lock()
        defer { lock.unlock() }
        return eventSink
    }

    private static func emit(_ event: PerformanceTelemetryEvent) {
        if let sink = currentSink() {
            sink(event)
            return
        }
        guard shouldLogToOS else { return }
        logger.info("[perf] \(event.message, privacy: .public)")
    }

    private static var shouldLogToOS: Bool {
        ProcessInfo.processInfo.environment["QIEMAN_PERF_LOG"] == "1"
            || _isDebugAssertConfiguration()
    }
}
```

- [ ] **Step 4: Run the focused Swift telemetry test**

Run:

```bash
(cd macos-app && swift test --filter PerformanceTelemetryTests)
```

Expected: `PerformanceTelemetryTests` passes.

- [ ] **Step 5: Verify the new Swift file is accepted by the package build**

Run:

```bash
swift build --package-path macos-app
```

Expected: command exits 0.

- [ ] **Step 6: Commit the Swift telemetry utility**

```bash
git add macos-app/Core/PerformanceTelemetry.swift macos-app/Tests/QiemanDashboardTests/PerformanceTelemetryTests.swift
git commit -m "perf: add swift telemetry utility"
```

## Task 2: Wire Swift Performance Measurement Points

**Files:**
- Modify: `macos-app/QiemanDashboardApp.swift`
- Modify: `macos-app/Core/AppModel.swift`
- Modify: `macos-app/Core/AppModel/PortfolioRefresh.swift`
- Modify: `macos-app/Core/MenuBarTicker/MenuBarTickerEntries.swift`
- Modify: `macos-app/Views/PersonalAssetBrowser.swift`
- Modify: `macos-app/Core/AppModel/PlatformFilters.swift`

- [ ] **Step 1: Measure app delegate launch and configure**

In `macos-app/QiemanDashboardApp.swift`, add this at the start of `applicationDidFinishLaunching(_:)`, immediately after the opening brace:

```swift
let telemetryStart = PerformanceTelemetry.start()
defer {
    PerformanceTelemetry.record(
        "app.delegate.finishLaunching",
        startedAt: telemetryStart
    )
}
```

In `configure(model:)`, add this immediately after `didConfigure = true`:

```swift
let telemetryStart = PerformanceTelemetry.start()
defer {
    PerformanceTelemetry.record(
        "app.delegate.configure",
        startedAt: telemetryStart,
        metadata: [
            "menuBarEnabled": "\(model.menuBarTickerSettings.isEnabled)"
        ]
    )
}
```

In `updateTitle()`, add this immediately after `guard let model, let button = statusItem.button else { return }`:

```swift
let telemetryStart = PerformanceTelemetry.start()
var renderedEntryCount = 0
defer {
    PerformanceTelemetry.record(
        "menuBar.title.render",
        startedAt: telemetryStart,
        metadata: [
            "entryCount": "\(renderedEntryCount)",
            "enabled": "\(model.menuBarTickerSettings.isEnabled)"
        ]
    )
}
```

Still in `updateTitle()`, add this immediately after `let displayEntries = Array(allEntries[start..<end])`:

```swift
renderedEntryCount = displayEntries.count
```

- [ ] **Step 2: Measure app model startup and latest refresh**

In `macos-app/Core/AppModel.swift`, add this in `start()`, immediately after `didStart = true`:

```swift
let telemetryStart = PerformanceTelemetry.start()
defer {
    PerformanceTelemetry.record(
        "app.start",
        startedAt: telemetryStart,
        metadata: [
            "hasPortfolio": "\(hasPersonalPortfolio)",
            "menuBarEnabled": "\(menuBarTickerSettings.isEnabled)"
        ]
    )
}
```

In `refreshLatest(persist:updateNotice:)`, add this at the start of the function body, before `isRefreshing = true`:

```swift
let telemetryStart = PerformanceTelemetry.start()
var telemetryResult = "completed"
defer {
    PerformanceTelemetry.record(
        "refresh.latest",
        startedAt: telemetryStart,
        metadata: [
            "persist": "\(persist)",
            "result": telemetryResult,
            "snapshotRecords": "\(currentSnapshot?.records.count ?? 0)",
            "platformActions": "\(platformPayload?.actions?.count ?? 0)"
        ]
    )
}
```

In the `guard refreshedSnapshot != nil || refreshedPlatform != nil else` block in `refreshLatest(persist:updateNotice:)`, add this before `errorMessage = message`:

```swift
telemetryResult = "failed"
```

In the partial-failure `else` branch after `if failures.isEmpty`, add this before `errorMessage = failures.joined(separator: "；")`:

```swift
telemetryResult = "partial"
```

- [ ] **Step 3: Measure portfolio and market-index refreshes**

In `macos-app/Core/AppModel/PortfolioRefresh.swift`, replace the first lines of `refreshUserPortfolio(updateNotice:)` with this block:

```swift
let holdings = activeUserPortfolioHoldings
let telemetryStart = PerformanceTelemetry.start()
var telemetryResult = "completed"
defer {
    PerformanceTelemetry.record(
        "refresh.portfolio",
        startedAt: telemetryStart,
        metadata: [
            "holdingCount": "\(holdings.count)",
            "rowCount": "\(userPortfolioSnapshot?.rows.count ?? 0)",
            "result": telemetryResult,
            "updateNotice": "\(updateNotice)"
        ]
    )
}
guard !holdings.isEmpty else {
    telemetryResult = "empty"
    userPortfolioSnapshot = nil
    rebuildAssetRows()
    await refreshMarketIndicesIfNeeded()
    return
}
guard !isRefreshingPortfolio else {
    telemetryResult = "alreadyRefreshing"
    return
}
```

This replaces the existing `let holdings = activeUserPortfolioHoldings`, empty-holdings guard, and `isRefreshingPortfolio` guard. Leave the rest of the function unchanged.

In `refreshMarketIndices(kinds:updateNotice:)`, add this at the start of the function body, before `let kinds = requestedKinds ?? selectedMenuBarMarketIndexKinds`:

```swift
let telemetryStart = PerformanceTelemetry.start()
var telemetryKindCount = 0
var telemetryResult = "completed"
defer {
    PerformanceTelemetry.record(
        "refresh.marketIndices",
        startedAt: telemetryStart,
        metadata: [
            "kindCount": "\(telemetryKindCount)",
            "quoteCount": "\(marketIndexQuotes.count)",
            "result": telemetryResult",
            "updateNotice": "\(updateNotice)"
        ]
    )
}
```

Immediately after `let kinds = requestedKinds ?? selectedMenuBarMarketIndexKinds`, add:

```swift
telemetryKindCount = kinds.count
```

Replace the existing guard in `refreshMarketIndices(kinds:updateNotice:)`:

```swift
guard !kinds.isEmpty, !isRefreshingMarketIndices else { return }
```

with:

```swift
guard !kinds.isEmpty else {
    telemetryResult = "empty"
    return
}
guard !isRefreshingMarketIndices else {
    telemetryResult = "alreadyRefreshing"
    return
}
```

In the `else if updateNotice` branch where no quotes are returned, add this before `errorMessage = "大盘行情暂时没有拉到可用数据。"`:

```swift
telemetryResult = "emptyResponse"
```

Still in `refreshUserPortfolio(updateNotice:)`, replace this existing block:

```swift
let snapshot = try await platformClient.fetchUserPortfolioSnapshot(holdings: holdings)
userPortfolioSnapshot = snapshot
rebuildAssetRows()
recordPortfolioInsightSnapshotIfPossible(createdAt: snapshot.refreshedAt)
if updateNotice {
    noticeMessage = "个人持仓估值已刷新。"
}
await refreshMarketIndicesIfNeeded()
```

with:

```swift
do {
    let snapshot = try await platformClient.fetchUserPortfolioSnapshot(holdings: holdings)
    userPortfolioSnapshot = snapshot
    rebuildAssetRows()
    recordPortfolioInsightSnapshotIfPossible(createdAt: snapshot.refreshedAt)
    if updateNotice {
        noticeMessage = "个人持仓估值已刷新。"
    }
    await refreshMarketIndicesIfNeeded()
} catch {
    telemetryResult = "failed"
    throw error
}
```

- [ ] **Step 4: Measure menu bar ticker entry building**

In `macos-app/Core/MenuBarTicker/MenuBarTickerEntries.swift`, add this at the start of `menuBarTickerCandidateEntries(settings:)`, before `var entries: [MenuBarTickerEntry] = []`:

```swift
let telemetryStart = PerformanceTelemetry.start()
```

After `var entries: [MenuBarTickerEntry] = []`, add:

```swift
defer {
    PerformanceTelemetry.record(
        "menuBar.entries.build",
        startedAt: telemetryStart,
        metadata: [
            "selectionCount": "\(settings.selections.count)",
            "rowCount": "\(userPortfolioSnapshot?.rows.count ?? 0)",
            "entryCount": "\(entries.count)"
        ]
    )
}
```

- [ ] **Step 5: Measure personal asset browser presentation building**

In `macos-app/Views/PersonalAssetBrowser.swift`, add this inside `makePresentation(keyword:)`, immediately after `var visibleRows: [PersonalAssetAggregateRow] = []`:

```swift
let telemetryStart = PerformanceTelemetry.start()
defer {
    PerformanceTelemetry.record(
        "personalAsset.presentation",
        startedAt: telemetryStart,
        metadata: [
            "rowCount": "\(rows.count)",
            "visibleCount": "\(visibleRows.count)",
            "filter": filterScope.rawValue,
            "sort": sortOption.rawValue,
            "hasKeyword": "\(!keyword.isEmpty)"
        ]
    )
}
```

- [ ] **Step 6: Measure platform filtering and pagination**

In `macos-app/Core/AppModel/PlatformFilters.swift`, add this inside `filteredPlatformActions`, immediately after `var actions = platformPayload?.actions ?? []`:

```swift
let telemetryStart = PerformanceTelemetry.start()
let originalCount = actions.count
defer {
    PerformanceTelemetry.record(
        "platform.actions.filter",
        startedAt: telemetryStart,
        metadata: [
            "inputCount": "\(originalCount)",
            "outputCount": "\(actions.count)",
            "sideFilter": filterState.sideFilter.rawValue,
            "hasQuery": "\(!filterState.debouncedSearchText.trimmingCharacters(in: .whitespaces).isEmpty)"
        ]
    )
}
```

In `paginatedPlatformActions`, add this at the start of the computed property:

```swift
let telemetryStart = PerformanceTelemetry.start()
```

Replace the final return logic:

```swift
guard start < filtered.count else { return [] }
return Array(filtered[start ..< end])
```

with:

```swift
let pageActions: [PlatformActionPayload]
if start < filtered.count {
    pageActions = Array(filtered[start ..< end])
} else {
    pageActions = []
}
PerformanceTelemetry.record(
    "platform.actions.paginate",
    startedAt: telemetryStart,
    metadata: [
        "filteredCount": "\(filtered.count)",
        "page": "\(filterState.currentPage)",
        "pageSize": "\(filterState.pageSize)",
        "pageCount": "\(pageActions.count)"
    ]
)
return pageActions
```

- [ ] **Step 7: Run Swift tests and build**

Run:

```bash
(cd macos-app && swift test --filter PerformanceTelemetryTests)
swift build --package-path macos-app
```

Expected: both commands exit 0.

- [ ] **Step 8: Commit Swift instrumentation**

```bash
git add macos-app/QiemanDashboardApp.swift macos-app/Core/AppModel.swift macos-app/Core/AppModel/PortfolioRefresh.swift macos-app/Core/MenuBarTicker/MenuBarTickerEntries.swift macos-app/Views/PersonalAssetBrowser.swift macos-app/Core/AppModel/PlatformFilters.swift
git commit -m "perf: instrument swift hot paths"
```

## Task 3: Add Python Telemetry Utility

**Files:**
- Create: `dashboard/performance.py`
- Create: `tests/test_performance_logging.py`

- [ ] **Step 1: Write failing Python tests for the telemetry module**

Create `tests/test_performance_logging.py`:

```python
import io
import os
import unittest
from contextlib import redirect_stderr
from unittest.mock import patch

from dashboard.performance import measure, performance_start, record_performance, timed


class PerformanceLoggingTests(unittest.TestCase):
    def test_logging_is_disabled_without_environment_flag(self) -> None:
        stream = io.StringIO()

        with patch.dict(os.environ, {}, clear=True), redirect_stderr(stream):
            started_at = performance_start()
            record_performance("dashboard.disabled", started_at, route="/platform")

        self.assertEqual(stream.getvalue(), "")

    def test_measure_logs_elapsed_time_and_redacts_sensitive_metadata(self) -> None:
        stream = io.StringIO()

        with patch.dict(os.environ, {"QIEMAN_PERF_LOG": "1"}, clear=True), redirect_stderr(stream):
            with measure(
                "dashboard.request",
                route="/platform",
                row_count=3,
                cookie="access_token=secret",
                authorization="Bearer secret",
            ):
                pass

        output = stream.getvalue()
        self.assertIn("[perf] dashboard.request", output)
        self.assertIn("route=/platform", output)
        self.assertIn("row_count=3", output)
        self.assertIn("cookie=<redacted>", output)
        self.assertIn("authorization=<redacted>", output)
        self.assertNotIn("access_token=secret", output)
        self.assertNotIn("Bearer secret", output)

    def test_timed_decorator_preserves_return_value(self) -> None:
        stream = io.StringIO()

        @timed("decorated.operation")
        def sample(value: str) -> str:
            return f"{value}-done"

        with patch.dict(os.environ, {"QIEMAN_PERF_LOG": "1"}, clear=True), redirect_stderr(stream):
            self.assertEqual(sample("refresh"), "refresh-done")

        self.assertIn("[perf] decorated.operation", stream.getvalue())


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the focused Python test and confirm it fails before implementation**

Run:

```bash
python3 -m unittest tests.test_performance_logging
```

Expected: the command fails with `ModuleNotFoundError: No module named 'dashboard.performance'`.

- [ ] **Step 3: Implement the Python telemetry module**

Create `dashboard/performance.py`:

```python
from __future__ import annotations

import os
import sys
import time
from contextlib import contextmanager
from functools import wraps
from typing import Any, Callable, Dict, Iterator, TypeVar


T = TypeVar("T")
SENSITIVE_MARKERS = ("cookie", "authorization", "token")


def performance_start() -> float:
    return time.perf_counter()


def performance_logging_enabled() -> bool:
    return os.environ.get("QIEMAN_PERF_LOG") == "1"


def record_performance(name: str, started_at: float, **metadata: Any) -> None:
    if not performance_logging_enabled():
        return
    elapsed_ms = (time.perf_counter() - started_at) * 1000
    metadata_text = _format_metadata(metadata)
    suffix = f" {metadata_text}" if metadata_text else ""
    print(f"[perf] {name} {elapsed_ms:.1f}ms{suffix}", file=sys.stderr, flush=True)


@contextmanager
def measure(name: str, **metadata: Any) -> Iterator[None]:
    started_at = performance_start()
    try:
        yield
    finally:
        record_performance(name, started_at, **metadata)


def timed(name: str) -> Callable[[Callable[..., T]], Callable[..., T]]:
    def decorator(function: Callable[..., T]) -> Callable[..., T]:
        @wraps(function)
        def wrapper(*args: Any, **kwargs: Any) -> T:
            started_at = performance_start()
            try:
                return function(*args, **kwargs)
            finally:
                record_performance(name, started_at)

        return wrapper

    return decorator


def _format_metadata(metadata: Dict[str, Any]) -> str:
    parts = []
    for key in sorted(metadata):
        parts.append(f"{key}={_safe_metadata_value(key, metadata[key])}")
    return " ".join(parts)


def _safe_metadata_value(key: str, value: Any) -> str:
    text = str(value)
    if _is_sensitive(key) or _is_sensitive(text):
        return "<redacted>"
    if len(text) > 80:
        return text[:77] + "..."
    return text


def _is_sensitive(value: str) -> bool:
    lower = value.lower()
    return any(marker in lower for marker in SENSITIVE_MARKERS)
```

- [ ] **Step 4: Run the focused Python telemetry test**

Run:

```bash
python3 -m unittest tests.test_performance_logging
```

Expected: `PerformanceLoggingTests` passes.

- [ ] **Step 5: Run Python compile check for the new module**

Run:

```bash
python3 -m compileall -q dashboard tests
```

Expected: command exits 0 with no output.

- [ ] **Step 6: Commit the Python telemetry utility**

```bash
git add dashboard/performance.py tests/test_performance_logging.py
git commit -m "perf: add python telemetry utility"
```

## Task 4: Wire Python Performance Measurement Points

**Files:**
- Modify: `dashboard/server.py`
- Modify: `dashboard/platform_fetcher.py`
- Modify: `dashboard/fund_fetcher.py`
- Modify: `dashboard/html_pages.py`

- [ ] **Step 1: Measure full HTTP request handling**

In `dashboard/server.py`, add this import with the existing dashboard imports:

```python
from .performance import performance_start, record_performance
```

Inside `class DashboardHandler(BaseHTTPRequestHandler):`, add this method before `do_GET`:

```python
    def handle_one_request(self) -> None:
        started_at = performance_start()
        try:
            super().handle_one_request()
        finally:
            raw_path = getattr(self, "path", "")
            parsed = urlparse(raw_path) if raw_path else None
            record_performance(
                "dashboard.request",
                started_at,
                method=getattr(self, "command", ""),
                route=parsed.path if parsed else "<unknown>",
            )
```

- [ ] **Step 2: Measure platform trade fetches and cache state**

In `dashboard/platform_fetcher.py`, add this import with the existing relative imports:

```python
from .performance import performance_start, record_performance
```

In `fetch_platform_trade_data(prod_code: str, timeout_seconds: int = 10)`, add this immediately after the `from .config import PLATFORM_FETCH_TIMEOUT_SECONDS` line:

```python
    started_at = performance_start()
    cache_status = "miss"
```

Replace the empty-target return block:

```python
    if not target:
        return {
            "supported": False,
            "error": "没有产品代码，无法直拉平台调仓记录。",
            "prod_code": "",
        }
```

with:

```python
    if not target:
        cache_status = "empty"
        try:
            return {
                "supported": False,
                "error": "没有产品代码，无法直拉平台调仓记录。",
                "prod_code": "",
            }
        finally:
            record_performance("platform.fetch", started_at, prod_code="<empty>", cache=cache_status)
```

After the cache hit condition:

```python
    if cached and now - float(cached.get("ts", 0)) < PLATFORM_TRADE_TTL_SECONDS:
```

add this before `return cached["data"]`:

```python
        cache_status = "hit"
        record_performance("platform.fetch", started_at, prod_code=target, cache=cache_status)
```

At the end of `fetch_platform_trade_data`, immediately before `return data`, add:

```python
    record_performance(
        "platform.fetch",
        started_at,
        prod_code=target,
        cache=cache_status,
        supported=bool(data.get("supported")),
        action_count=len(data.get("actions") or []),
    )
```

- [ ] **Step 3: Measure fund history and quote fetches**

In `dashboard/fund_fetcher.py`, add this import with the existing relative imports:

```python
from .performance import performance_start, record_performance
```

In `fetch_fund_history_series(fund_code: str)`, add this immediately before `target = normalize_text(fund_code)`:

```python
    started_at = performance_start()
    cache_status = "miss"
```

Replace the empty-target guard:

```python
    if not target:
        return {}
```

with:

```python
    if not target:
        cache_status = "empty"
        try:
            return {}
        finally:
            record_performance("fund.history", started_at, has_code=False, cache=cache_status)
```

After the cache hit condition:

```python
    if cached and now - safe_float(cached.get("loaded_at")) < FUND_HISTORY_TTL_SECONDS:
```

add this before `return cached`:

```python
        cache_status = "hit"
        record_performance("fund.history", started_at, has_code=True, cache=cache_status)
```

At the end of `fetch_fund_history_series`, immediately before `return result`, add:

```python
    record_performance(
        "fund.history",
        started_at,
        has_code=True,
        cache=cache_status,
        series_count=len(result.get("series") or []),
    )
```

In `fetch_fund_quote(fund_code: str)`, add this immediately before `target = normalize_text(fund_code)`:

```python
    started_at = performance_start()
    cache_status = "miss"
    price_source = ""
```

Replace the empty-target guard:

```python
    if not target:
        return {}
```

with:

```python
    if not target:
        cache_status = "empty"
        try:
            return {}
        finally:
            record_performance("fund.quote", started_at, has_code=False, cache=cache_status)
```

After the quote cache hit condition:

```python
    if cached and now - safe_float(cached.get("loaded_at")) < FUND_QUOTE_TTL_SECONDS:
```

add this before `return cached`:

```python
        cache_status = "hit"
        record_performance(
            "fund.quote",
            started_at,
            has_code=True,
            cache=cache_status,
            source=normalize_text(cached.get("price_source")),
        )
```

After `FUND_QUOTE_CACHE[target] = result`, add:

```python
    price_source = normalize_text(result.get("price_source"))
    record_performance(
        "fund.quote",
        started_at,
        has_code=True,
        cache=cache_status,
        source=price_source,
    )
```

- [ ] **Step 4: Measure dashboard page render functions**

In `dashboard/html_pages.py`, add this import with the existing relative imports:

```python
from .performance import timed
```

Add these decorators immediately above each function:

```python
@timed("render.dashboard")
def render_dashboard_page(
```

```python
@timed("render.platform")
def render_platform_page(
```

```python
@timed("render.forum")
def render_forum_page(
```

```python
@timed("render.timeline")
def render_timeline_page(
```

- [ ] **Step 5: Run focused Python tests and compile check**

Run:

```bash
python3 -m unittest tests.test_performance_logging
python3 -m compileall -q dashboard_server.py dashboard qieman_scraper.py qieman_community_scraper.py scripts tests
```

Expected: both commands exit 0.

- [ ] **Step 6: Run all Python tests**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

Expected: all Python tests pass.

- [ ] **Step 7: Commit Python instrumentation**

```bash
git add dashboard/server.py dashboard/platform_fetcher.py dashboard/fund_fetcher.py dashboard/html_pages.py
git commit -m "perf: instrument python dashboard paths"
```

## Task 5: Final Verification And Smoke Checks

**Files:**
- Inspect: all files changed in Tasks 1-4

- [ ] **Step 1: Run the full Swift validation set**

Run:

```bash
(cd macos-app && swift test)
swift build --package-path macos-app
```

Expected: both commands exit 0.

- [ ] **Step 2: Run the full Python validation set**

Run:

```bash
python3 -m compileall -q dashboard_server.py dashboard qieman_scraper.py qieman_community_scraper.py scripts tests
python3 -m unittest discover -s tests -p 'test_*.py'
```

Expected: both commands exit 0.

- [ ] **Step 3: Check for whitespace errors**

Run:

```bash
git diff --check
```

Expected: command exits 0 with no output.

- [ ] **Step 4: Smoke-test Python timing output**

Run the server in one terminal:

```bash
QIEMAN_PERF_LOG=1 python3 dashboard_server.py --host 127.0.0.1 --port 8766
```

In another terminal, run:

```bash
curl -fsS "http://127.0.0.1:8766/api/status" >/tmp/qieman-status.json
curl -fsS "http://127.0.0.1:8766/platform?prod_code=LONG_WIN" >/tmp/qieman-platform.html
```

Expected: the server terminal prints lines shaped like these, with elapsed values that vary by machine:

```text
[perf] dashboard.request 1.2ms method=GET route=/api/status
[perf] platform.fetch 35.0ms action_count=2 cache=miss prod_code=LONG_WIN supported=True
[perf] render.platform 4.0ms
[perf] dashboard.request 42.0ms method=GET route=/platform
```

Expected: no output line contains `qieman.cookie`, `access_token`, `authorization`, or a raw cookie value.

- [ ] **Step 5: Smoke-test Swift timing output**

Run:

```bash
(cd macos-app && QIEMAN_PERF_LOG=1 swift run QiemanDashboard)
```

Expected: the macOS app opens. After the app starts and the first refresh completes or fails, the terminal includes `[perf]` lines for operations such as:

```text
[perf] app.delegate.finishLaunching 3.0ms
[perf] app.start 120.0ms hasPortfolio=true menuBarEnabled=true
[perf] refresh.latest 850.0ms persist=false platformActions=0 result=partial snapshotRecords=5
```

Expected: no output line contains raw cookies, authorization headers, or full payloads. Quit the app after the smoke check.

- [ ] **Step 6: Capture before/after baseline notes**

Create a short local note for the final response using the smoke-test output:

```text
Swift smoke: app.start and refresh.latest timing lines appeared with safe metadata.
Python smoke: dashboard.request, platform.fetch, and render.platform timing lines appeared with safe metadata.
```

Do not commit this note as a file. Use it in the final work summary.

- [ ] **Step 7: Commit any verification-only fixes**

If Steps 1-5 required small fixes, commit those fixes:

```bash
git add macos-app dashboard tests
git commit -m "perf: finish performance baseline verification"
```

If no fixes were required, skip this commit and leave the previous task commits as the complete P0 change set.

## Final Expected Verification

Before marking P0 complete, these commands must pass:

```bash
(cd macos-app && swift test)
swift build --package-path macos-app
python3 -m compileall -q dashboard_server.py dashboard qieman_scraper.py qieman_community_scraper.py scripts tests
python3 -m unittest discover -s tests -p 'test_*.py'
git diff --check
```

Manual smoke evidence must include at least one safe Swift `[perf]` line and one safe Python `[perf]` line.
