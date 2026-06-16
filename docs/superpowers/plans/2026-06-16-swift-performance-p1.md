# Swift Performance P1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce redundant Swift refresh work and repeated derived-list computation while preserving current user-visible behavior.

**Architecture:** Keep `AppModel` as the `@MainActor` state container, but move expensive decision and presentation logic into small pure Swift types with XCTest coverage. Use the P0 telemetry already on this branch to compare repeated refresh, platform filtering, personal asset presentation, and menu bar entry work before later P2 Python changes.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, XCTest, existing `PerformanceTelemetry`, existing SPM and direct `swiftc` build paths.

---

## Files And Responsibilities

- Create `macos-app/Core/AppModel/RefreshDecision.swift`: pure refresh-decision helper for section-triggered refreshes and freshness reuse.
- Create `macos-app/Tests/QiemanDashboardTests/RefreshDecisionTests.swift`: XCTest coverage for manual, automatic, section, and in-flight refresh decisions.
- Modify `macos-app/Core/AppModel/Auth.swift`: route `refreshDataForSectionIfNeeded(_:)` through the decision helper so repeated section switching does not launch duplicate refresh tasks.
- Modify `macos-app/Core/AppModel.swift`: store latest successful refresh timestamps used by the decision helper.
- Create `macos-app/Core/PlatformActionPresentation.swift`: pure platform action filtering, counts, page slicing, total pages, and current-page clamping.
- Create `macos-app/Tests/QiemanDashboardTests/PlatformActionPresentationTests.swift`: XCTest coverage for side filter, search, counts, pagination, and page clamping.
- Modify `macos-app/Core/AppModel/PlatformFilters.swift`: expose one `platformActionPresentation` value and keep legacy computed properties as wrappers.
- Modify `macos-app/Views/PlatformSectionView.swift`: compute `platformActionPresentation` once per list render and use it for count, page count, current page, and rows.
- Modify `macos-app/Views/Filters/PlatformFilterBar.swift`: use the shared presentation counts instead of asking `AppModel` for counts multiple times.
- Create `macos-app/Core/PersonalAssetBrowserPresentation.swift`: pure `PersonalAssetBrowserPresentationModel` builder for counts, filtered/sorted rows, and comparison summary.
- Create `macos-app/Tests/QiemanDashboardTests/PersonalAssetBrowserPresentationTests.swift`: XCTest coverage with synthetic rows for search, scope counts, sort, and comparison pruning.
- Modify `macos-app/Views/PersonalAssetBrowser.swift`: replace view-local presentation logic with the pure presentation builder.

`scripts/build_macos_app.sh` discovers Swift sources automatically. Still run `swift build --package-path macos-app` because this repo supports both SPM validation and direct `swiftc` bundle builds.

## Task 1: Add Refresh Decision Helper

**Files:**
- Create: `macos-app/Core/AppModel/RefreshDecision.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/RefreshDecisionTests.swift`

- [ ] **Step 1: Write failing XCTest coverage**

Create `macos-app/Tests/QiemanDashboardTests/RefreshDecisionTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class RefreshDecisionTests: XCTestCase {
    func testOverviewSkipsWhenForumAndPlatformDataAreFresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        let decision = RefreshDecision.sectionTriggered(
            section: .overview,
            now: now,
            lastLatestRefreshAt: now.addingTimeInterval(-30),
            hasForumPosts: true,
            hasPlatformActions: true,
            hasPersonalPortfolio: true,
            hasPortfolioSnapshot: true,
            isRefreshingLatest: false,
            isRefreshingPortfolio: false
        )

        XCTAssertEqual(decision, .skip(reason: .freshDataAvailable))
    }

    func testOverviewRefreshesWhenRequiredDataIsMissingEvenIfLastRefreshIsFresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        let decision = RefreshDecision.sectionTriggered(
            section: .overview,
            now: now,
            lastLatestRefreshAt: now.addingTimeInterval(-30),
            hasForumPosts: true,
            hasPlatformActions: false,
            hasPersonalPortfolio: true,
            hasPortfolioSnapshot: true,
            isRefreshingLatest: false,
            isRefreshingPortfolio: false
        )

        XCTAssertEqual(decision, .refreshLatest)
    }

    func testOverviewRefreshesWhenDataIsStaleEvenIfExistingDataIsPresent() {
        let now = Date(timeIntervalSince1970: 1_000)
        let decision = RefreshDecision.sectionTriggered(
            section: .overview,
            now: now,
            lastLatestRefreshAt: now.addingTimeInterval(-600),
            hasForumPosts: true,
            hasPlatformActions: true,
            hasPersonalPortfolio: true,
            hasPortfolioSnapshot: true,
            isRefreshingLatest: false,
            isRefreshingPortfolio: false
        )

        XCTAssertEqual(decision, .refreshLatest)
    }

    func testPortfolioRefreshesWhenPortfolioSnapshotIsMissingOrStale() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            RefreshDecision.sectionTriggered(
                section: .portfolio,
                now: now,
                lastPortfolioRefreshAt: nil,
                hasForumPosts: false,
                hasPlatformActions: false,
                hasPersonalPortfolio: true,
                hasPortfolioSnapshot: false,
                isRefreshingLatest: false,
                isRefreshingPortfolio: false
            ),
            .refreshPortfolio
        )

        XCTAssertEqual(
            RefreshDecision.sectionTriggered(
                section: .portfolio,
                now: now,
                lastPortfolioRefreshAt: now.addingTimeInterval(-20),
                hasForumPosts: false,
                hasPlatformActions: false,
                hasPersonalPortfolio: true,
                hasPortfolioSnapshot: true,
                isRefreshingLatest: false,
                isRefreshingPortfolio: false
            ),
            .skip(reason: .freshDataAvailable)
        )

        XCTAssertEqual(
            RefreshDecision.sectionTriggered(
                section: .portfolio,
                now: now,
                lastPortfolioRefreshAt: now.addingTimeInterval(-600),
                hasForumPosts: false,
                hasPlatformActions: false,
                hasPersonalPortfolio: true,
                hasPortfolioSnapshot: true,
                isRefreshingLatest: false,
                isRefreshingPortfolio: false
            ),
            .refreshPortfolio
        )
    }

    func testRefreshSkipsWhenSameOperationIsAlreadyInFlight() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            RefreshDecision.sectionTriggered(
                section: .platform,
                now: now,
                hasForumPosts: false,
                hasPlatformActions: false,
                hasPersonalPortfolio: false,
                hasPortfolioSnapshot: false,
                isRefreshingLatest: true,
                isRefreshingPortfolio: false
            ),
            .skip(reason: .alreadyRefreshing)
        )

        XCTAssertEqual(
            RefreshDecision.sectionTriggered(
                section: .portfolio,
                now: now,
                hasForumPosts: false,
                hasPlatformActions: false,
                hasPersonalPortfolio: true,
                hasPortfolioSnapshot: false,
                isRefreshingLatest: false,
                isRefreshingPortfolio: true
            ),
            .skip(reason: .alreadyRefreshing)
        )
    }
}
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
(cd macos-app && swift test --filter RefreshDecisionTests)
```

Expected: compile fails with `cannot find 'RefreshDecision' in scope`.

- [ ] **Step 3: Implement `RefreshDecision`**

Create `macos-app/Core/AppModel/RefreshDecision.swift`:

```swift
import Foundation

enum RefreshDecision: Equatable {
    enum SkipReason: Equatable {
        case unsupportedSection
        case missingPortfolio
        case alreadyRefreshing
        case freshDataAvailable
    }

    case refreshLatest
    case refreshPortfolio
    case skip(reason: SkipReason)

    static let latestFreshnessInterval: TimeInterval = 120
    static let portfolioFreshnessInterval: TimeInterval = 120

    static func sectionTriggered(
        section: AppSection,
        now: Date = Date(),
        lastLatestRefreshAt: Date? = nil,
        lastPortfolioRefreshAt: Date? = nil,
        hasForumPosts: Bool,
        hasPlatformActions: Bool,
        hasPersonalPortfolio: Bool,
        hasPortfolioSnapshot: Bool,
        isRefreshingLatest: Bool,
        isRefreshingPortfolio: Bool
    ) -> RefreshDecision {
        switch section {
        case .overview:
            guard !isRefreshingLatest else { return .skip(reason: .alreadyRefreshing) }
            if hasForumPosts, hasPlatformActions {
                return hasFreshData(since: lastLatestRefreshAt, now: now, interval: latestFreshnessInterval)
                    ? .skip(reason: .freshDataAvailable)
                    : .refreshLatest
            }
            return .refreshLatest
        case .platform:
            guard !isRefreshingLatest else { return .skip(reason: .alreadyRefreshing) }
            if hasPlatformActions, hasFreshData(since: lastLatestRefreshAt, now: now, interval: latestFreshnessInterval) {
                return .skip(reason: .freshDataAvailable)
            }
            return .refreshLatest
        case .forum:
            guard !isRefreshingLatest else { return .skip(reason: .alreadyRefreshing) }
            if hasForumPosts, hasFreshData(since: lastLatestRefreshAt, now: now, interval: latestFreshnessInterval) {
                return .skip(reason: .freshDataAvailable)
            }
            return .refreshLatest
        case .portfolio:
            guard hasPersonalPortfolio else { return .skip(reason: .missingPortfolio) }
            guard !isRefreshingPortfolio else { return .skip(reason: .alreadyRefreshing) }
            if hasPortfolioSnapshot, hasFreshData(since: lastPortfolioRefreshAt, now: now, interval: portfolioFreshnessInterval) {
                return .skip(reason: .freshDataAvailable)
            }
            return .refreshPortfolio
        case .enhancement, .settings:
            return .skip(reason: .unsupportedSection)
        }
    }

    private static func hasFreshData(since date: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) < interval
    }
}
```

- [ ] **Step 4: Run focused refresh decision tests**

Run:

```bash
(cd macos-app && swift test --filter RefreshDecisionTests)
```

Expected: `RefreshDecisionTests` passes.

- [ ] **Step 5: Commit refresh decision helper**

```bash
git add macos-app/Core/AppModel/RefreshDecision.swift macos-app/Tests/QiemanDashboardTests/RefreshDecisionTests.swift
git commit -m "perf: add refresh decision helper"
```

## Task 2: Wire Section Refresh Decisions

**Files:**
- Modify: `macos-app/Core/AppModel.swift`
- Modify: `macos-app/Core/AppModel/Auth.swift`
- Modify: `macos-app/Core/AppModel/PortfolioRefresh.swift`

- [ ] **Step 1: Track latest successful refresh times**

In `macos-app/Core/AppModel.swift`, add these properties next to the existing refresh state properties:

```swift
    var lastLatestRefreshAt: Date?
    var lastPortfolioRefreshAt: Date?
```

In `refreshLatest(persist:updateNotice:)`, add this immediately after `rebuildNativeStatus()` and before the guard that throws when both refreshes fail:

```swift
        if refreshedSnapshot != nil || refreshedPlatform != nil {
            lastLatestRefreshAt = Date()
        }
```

In `macos-app/Core/AppModel/PortfolioRefresh.swift`, add this after `recordPortfolioInsightSnapshotIfPossible(createdAt: snapshot.refreshedAt)`:

```swift
            lastPortfolioRefreshAt = Date()
```

- [ ] **Step 2: Replace section refresh branching with `RefreshDecision`**

Replace the body of `refreshDataForSectionIfNeeded(_:)` in `macos-app/Core/AppModel/Auth.swift` with:

```swift
    func refreshDataForSectionIfNeeded(_ section: AppSection) {
        let decision = RefreshDecision.sectionTriggered(
            section: section,
            lastLatestRefreshAt: lastLatestRefreshAt,
            lastPortfolioRefreshAt: lastPortfolioRefreshAt,
            hasForumPosts: hasForumPosts,
            hasPlatformActions: hasPlatformActions,
            hasPersonalPortfolio: hasPersonalPortfolio,
            hasPortfolioSnapshot: userPortfolioSnapshot != nil,
            isRefreshingLatest: isRefreshing,
            isRefreshingPortfolio: isRefreshingPortfolio
        )

        switch decision {
        case .skip:
            if section == .forum, hasForumPosts {
                ensureSelectedForumPost()
            }
            return
        case .refreshPortfolio:
            Task { try? await refreshUserPortfolio(updateNotice: false) }
        case .refreshLatest:
            if (section == .overview || section == .forum), !form.mode.producesPostRecords {
                form.mode = cookieAvailable ? .followingPosts : .groupManager
            }
            Task { try? await refreshLatest(persist: false, updateNotice: false) }
        }
    }
```

- [ ] **Step 3: Run focused tests**

Run:

```bash
(cd macos-app && swift test --filter RefreshDecisionTests)
```

Expected: tests pass.

- [ ] **Step 4: Run related app tests**

Run:

```bash
(cd macos-app && swift test --filter AppLaunchPresentationPolicyTests)
```

Expected: tests pass. These do not directly cover refresh decisions, but verify app target compile with the new state fields.

- [ ] **Step 5: Commit refresh decision wiring**

```bash
git add macos-app/Core/AppModel.swift macos-app/Core/AppModel/Auth.swift macos-app/Core/AppModel/PortfolioRefresh.swift
git commit -m "perf: reuse fresh section refresh data"
```

## Task 3: Add Platform Action Presentation Model

**Files:**
- Create: `macos-app/Core/PlatformActionPresentation.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/PlatformActionPresentationTests.swift`

- [ ] **Step 1: Write failing platform presentation tests**

Create `macos-app/Tests/QiemanDashboardTests/PlatformActionPresentationTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class PlatformActionPresentationTests: XCTestCase {
    func testPresentationFiltersBySideAndSearchAndPaginatesOnce() throws {
        let actions = [
            action(id: "buy-wide", side: "buy", fundName: "沪深300", fundCode: "000300", title: "买入宽基"),
            action(id: "sell-bond", side: "sell", fundName: "债券基金", fundCode: "000001", title: "卖出债券"),
            action(id: "buy-dividend", side: "buy", fundName: "红利低波", fundCode: "000922", title: "买入红利")
        ]

        let presentation = PlatformActionPresentation.make(
            actions: actions,
            sideFilter: .buy,
            searchText: "红利",
            currentPage: 0,
            pageSize: 10
        )

        XCTAssertEqual(presentation.counts.all, 3)
        XCTAssertEqual(presentation.counts.buy, 2)
        XCTAssertEqual(presentation.counts.sell, 1)
        XCTAssertEqual(presentation.filteredActions.map(\.id), ["buy-dividend"])
        XCTAssertEqual(presentation.pageActions.map(\.id), ["buy-dividend"])
        XCTAssertEqual(presentation.totalPages, 1)
        XCTAssertEqual(presentation.currentPage, 0)
    }

    func testPresentationClampsOutOfRangePage() {
        let actions = (0..<23).map {
            action(id: "action-\($0)", side: $0.isMultiple(of: 2) ? "buy" : "sell", fundName: "基金\($0)", fundCode: "\($0)", title: "调仓\($0)")
        }

        let presentation = PlatformActionPresentation.make(
            actions: actions,
            sideFilter: .all,
            searchText: "",
            currentPage: 9,
            pageSize: 10
        )

        XCTAssertEqual(presentation.totalPages, 3)
        XCTAssertEqual(presentation.currentPage, 2)
        XCTAssertEqual(presentation.pageActions.map(\.id), ["action-20", "action-21", "action-22"])
    }

    private func action(
        id: String,
        side: String,
        fundName: String,
        fundCode: String,
        title: String
    ) -> PlatformActionPayload {
        PlatformActionPayload(
            actionKey: id,
            adjustmentId: nil,
            adjustmentTitle: title,
            title: title,
            actionTitle: title,
            fundName: fundName,
            fundCode: fundCode,
            side: side,
            action: side,
            tradeUnit: nil,
            postPlanUnit: nil,
            createdAt: nil,
            txnDate: nil,
            createdTs: nil,
            txnTs: nil,
            articleUrl: nil,
            comment: nil,
            strategyType: nil,
            largeClass: nil,
            buyDate: nil,
            nav: nil,
            navDate: nil,
            orderCountInAdjustment: nil,
            tradeValuation: nil,
            tradeValuationDate: nil,
            tradeValuationSource: nil,
            currentValuation: nil,
            currentValuationTime: nil,
            currentValuationSource: nil,
            valuationChangeAmount: nil,
            valuationChangePct: nil
        )
    }
}
```

- [ ] **Step 2: Run focused test and confirm it fails**

Run:

```bash
(cd macos-app && swift test --filter PlatformActionPresentationTests)
```

Expected: compile fails with `cannot find 'PlatformActionPresentation' in scope` or initializer access errors for `PlatformActionPayload`. If initializer access errors occur, add the initializer in Step 3 as shown.

- [ ] **Step 3: Add testable initializer for `PlatformActionPayload`**

In `macos-app/Core/Models.swift`, inside `struct PlatformActionPayload`, add this initializer after the stored properties:

```swift
    init(
        actionKey: String?,
        adjustmentId: Int?,
        adjustmentTitle: String?,
        title: String?,
        actionTitle: String?,
        fundName: String?,
        fundCode: String?,
        side: String?,
        action: String?,
        tradeUnit: Int?,
        postPlanUnit: Int?,
        createdAt: String?,
        txnDate: String?,
        createdTs: Int?,
        txnTs: Int?,
        articleUrl: String?,
        comment: String?,
        strategyType: String?,
        largeClass: String?,
        buyDate: String?,
        nav: Double?,
        navDate: String?,
        orderCountInAdjustment: Int?,
        tradeValuation: Double?,
        tradeValuationDate: String?,
        tradeValuationSource: String?,
        currentValuation: Double?,
        currentValuationTime: String?,
        currentValuationSource: String?,
        valuationChangeAmount: Double?,
        valuationChangePct: Double?
    ) {
        self.actionKey = actionKey
        self.adjustmentId = adjustmentId
        self.adjustmentTitle = adjustmentTitle
        self.title = title
        self.actionTitle = actionTitle
        self.fundName = fundName
        self.fundCode = fundCode
        self.side = side
        self.action = action
        self.tradeUnit = tradeUnit
        self.postPlanUnit = postPlanUnit
        self.createdAt = createdAt
        self.txnDate = txnDate
        self.createdTs = createdTs
        self.txnTs = txnTs
        self.articleUrl = articleUrl
        self.comment = comment
        self.strategyType = strategyType
        self.largeClass = largeClass
        self.buyDate = buyDate
        self.nav = nav
        self.navDate = navDate
        self.orderCountInAdjustment = orderCountInAdjustment
        self.tradeValuation = tradeValuation
        self.tradeValuationDate = tradeValuationDate
        self.tradeValuationSource = tradeValuationSource
        self.currentValuation = currentValuation
        self.currentValuationTime = currentValuationTime
        self.currentValuationSource = currentValuationSource
        self.valuationChangeAmount = valuationChangeAmount
        self.valuationChangePct = valuationChangePct
    }
```

- [ ] **Step 4: Implement platform presentation model**

Create `macos-app/Core/PlatformActionPresentation.swift`:

```swift
import Foundation

struct PlatformActionCounts: Equatable {
    let all: Int
    let buy: Int
    let sell: Int
}

struct PlatformActionPresentation: Equatable {
    let counts: PlatformActionCounts
    let filteredActions: [PlatformActionPayload]
    let pageActions: [PlatformActionPayload]
    let totalPages: Int
    let currentPage: Int

    static func make(
        actions: [PlatformActionPayload],
        sideFilter: PlatformSideFilter,
        searchText: String,
        currentPage: Int,
        pageSize: Int
    ) -> PlatformActionPresentation {
        let counts = PlatformActionCounts(
            all: actions.count,
            buy: actions.filter { isBuy($0) }.count,
            sell: actions.filter { !isBuy($0) }.count
        )

        var filtered = actions
        switch sideFilter {
        case .all:
            break
        case .buy:
            filtered = filtered.filter { isBuy($0) }
        case .sell:
            filtered = filtered.filter { !isBuy($0) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            filtered = filtered.filter { action in
                (action.fundName ?? "").lowercased().contains(query)
                    || (action.fundCode ?? "").lowercased().contains(query)
                    || action.displayTitle.lowercased().contains(query)
                    || (action.adjustmentTitle ?? "").lowercased().contains(query)
            }
        }

        let safePageSize = max(1, pageSize)
        let totalPages = max(1, (filtered.count + safePageSize - 1) / safePageSize)
        let clampedPage = min(max(0, currentPage), totalPages - 1)
        let start = clampedPage * safePageSize
        let end = min(start + safePageSize, filtered.count)
        let pageActions = start < filtered.count ? Array(filtered[start ..< end]) : []

        return PlatformActionPresentation(
            counts: counts,
            filteredActions: filtered,
            pageActions: pageActions,
            totalPages: totalPages,
            currentPage: clampedPage
        )
    }

    private static func isBuy(_ action: PlatformActionPayload) -> Bool {
        (action.side ?? "").lowercased().contains("buy")
    }
}
```

- [ ] **Step 5: Run focused platform presentation tests**

Run:

```bash
(cd macos-app && swift test --filter PlatformActionPresentationTests)
```

Expected: tests pass.

- [ ] **Step 6: Commit platform presentation model**

```bash
git add macos-app/Core/Models.swift macos-app/Core/PlatformActionPresentation.swift macos-app/Tests/QiemanDashboardTests/PlatformActionPresentationTests.swift
git commit -m "perf: add platform action presentation model"
```

## Task 4: Wire Platform Presentation Into Views

**Files:**
- Modify: `macos-app/Core/AppModel/PlatformFilters.swift`
- Modify: `macos-app/Views/PlatformSectionView.swift`
- Modify: `macos-app/Views/Filters/PlatformFilterBar.swift`

- [ ] **Step 1: Expose one shared presentation on `AppModel`**

Replace the contents of `macos-app/Core/AppModel/PlatformFilters.swift` with:

```swift
import Foundation

// MARK: - Platform Filter Computed Properties

extension AppModel {
    var platformActionPresentation: PlatformActionPresentation {
        let telemetryStart = PerformanceTelemetry.start()
        let actions = platformPayload?.actions ?? []
        let presentation = PlatformActionPresentation.make(
            actions: actions,
            sideFilter: filterState.sideFilter,
            searchText: filterState.debouncedSearchText,
            currentPage: filterState.currentPage,
            pageSize: filterState.pageSize
        )
        PerformanceTelemetry.record(
            "platform.actions.presentation",
            startedAt: telemetryStart,
            metadata: [
                "inputCount": "\(actions.count)",
                "filteredCount": "\(presentation.filteredActions.count)",
                "pageCount": "\(presentation.pageActions.count)",
                "sideFilter": filterState.sideFilter.rawValue,
                "hasQuery": "\(!filterState.debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)"
            ]
        )
        return presentation
    }

    var filteredPlatformActions: [PlatformActionPayload] {
        platformActionPresentation.filteredActions
    }

    var platformActionCounts: PlatformActionCounts {
        platformActionPresentation.counts
    }

    var paginatedPlatformActions: [PlatformActionPayload] {
        platformActionPresentation.pageActions
    }

    var totalPlatformPages: Int {
        platformActionPresentation.totalPages
    }
}
```

- [ ] **Step 2: Use one presentation in `PlatformSectionView`**

In `macos-app/Views/PlatformSectionView.swift`, replace the local values at the start of `platformListPanel(isCompact:scrollProxy:)`:

```swift
        let allActions = model.filteredPlatformActions
        let totalCount = allActions.count
        let totalPages = model.totalPlatformPages
        let currentPage = min(model.filterState.currentPage, totalPages - 1)
        let pageActions = model.paginatedPlatformActions
```

with:

```swift
        let presentation = model.platformActionPresentation
        let totalCount = presentation.filteredActions.count
        let totalPages = presentation.totalPages
        let currentPage = presentation.currentPage
        let pageActions = presentation.pageActions
```

- [ ] **Step 3: Use one presentation in `PlatformFilterBar`**

In `macos-app/Views/Filters/PlatformFilterBar.swift`, add this local value at the start of `body`:

```swift
        let presentation = model.platformActionPresentation
```

Then change `wideLayout`, `narrowLayout`, and `compactLayout` from computed properties to functions:

```swift
            wideLayout(counts: presentation.counts)
            narrowLayout(counts: presentation.counts)
            compactLayout(counts: presentation.counts)
```

Replace `private var wideLayout: some View` with:

```swift
    private func wideLayout(counts: PlatformActionCounts) -> some View {
```

Replace `counts: model.platformActionCounts` inside `wideLayout` with `counts: counts`.

Replace `private var narrowLayout: some View` with:

```swift
    private func narrowLayout(counts: PlatformActionCounts) -> some View {
```

Replace `counts: model.platformActionCounts` inside `narrowLayout` with `counts: counts`.

Replace `private var compactLayout: some View` with:

```swift
    private func compactLayout(counts: PlatformActionCounts) -> some View {
```

Replace the menu label call:

```swift
                        Label(menuLabel(for: filter), systemImage: filter.systemImage)
```

with:

```swift
                        Label(menuLabel(for: filter, counts: counts), systemImage: filter.systemImage)
```

Replace `private func menuLabel(for filter: PlatformSideFilter) -> String` with:

```swift
    private func menuLabel(for filter: PlatformSideFilter, counts: PlatformActionCounts) -> String {
```

Inside that function, replace each `model.platformActionCounts` access with `counts`.

- [ ] **Step 4: Run focused and related tests**

Run:

```bash
(cd macos-app && swift test --filter PlatformActionPresentationTests)
swift build --package-path macos-app
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit platform view wiring**

```bash
git add macos-app/Core/AppModel/PlatformFilters.swift macos-app/Views/PlatformSectionView.swift macos-app/Views/Filters/PlatformFilterBar.swift
git commit -m "perf: share platform action presentation"
```

## Task 5: Add Personal Asset Browser Presentation Model

**Files:**
- Create: `macos-app/Core/PersonalAssetBrowserPresentation.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/PersonalAssetBrowserPresentationTests.swift`

- [ ] **Step 1: Write failing personal asset presentation tests**

Create `macos-app/Tests/QiemanDashboardTests/PersonalAssetBrowserPresentationTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class PersonalAssetBrowserPresentationTests: XCTestCase {
    func testPresentationBuildsCountsAndVisibleRowsFromScopeSearchAndSort() {
        let rows = [
            row(key: "wide", name: "沪深300", code: "000300", marketValue: 30_000, pendingAmount: 0),
            row(key: "dividend", name: "红利低波", code: "000922", marketValue: 10_000, pendingAmount: 500),
            row(key: "pending", name: "等待确认", code: "000001", marketValue: nil, pendingAmount: 800)
        ]

        let presentation = PersonalAssetBrowserPresentationModel.make(
            rows: rows,
            keyword: "000",
            filterScope: .pending,
            sortOption: .pendingAmount,
            comparisonSelection: ["pending", "wide"],
            comparisonMaxCount: 4
        )

        XCTAssertEqual(presentation.filterCounts[.all], 3)
        XCTAssertEqual(presentation.filterCounts[.holding], 2)
        XCTAssertEqual(presentation.filterCounts[.pending], 2)
        XCTAssertEqual(presentation.visibleRows.map(\.id), ["pending", "dividend"])
        XCTAssertEqual(presentation.comparisonSummary.items.map(\.id), ["pending", "wide"])
    }

    func testPresentationPrunesInvalidComparisonSelection() {
        let rows = [
            row(key: "wide", name: "沪深300", code: "000300", marketValue: 30_000, pendingAmount: 0)
        ]

        let presentation = PersonalAssetBrowserPresentationModel.make(
            rows: rows,
            keyword: "",
            filterScope: .all,
            sortOption: .name,
            comparisonSelection: ["missing", "wide"],
            comparisonMaxCount: 4
        )

        XCTAssertEqual(presentation.validComparisonSelection, ["wide"])
        XCTAssertEqual(presentation.comparisonSummary.items.map(\.id), ["wide"])
    }

    private func row(
        key: String,
        name: String,
        code: String,
        marketValue: Double?,
        pendingAmount: Double
    ) -> PersonalAssetAggregateRow {
        let holding = marketValue.map { _ in
            UserPortfolioHolding(fundCode: code, assetType: .fund, units: 10_000, costPrice: 1, displayName: name)
        }
        let valuationRow = holding.map {
            UserPortfolioValuationRow(
                holding: $0,
                fundName: name,
                currentPrice: nil,
                priceTime: nil,
                priceSource: nil,
                officialNav: nil,
                officialNavDate: nil,
                estimatePrice: nil,
                estimatePriceTime: nil,
                marketValue: marketValue,
                costValue: nil,
                profitAmount: nil,
                profitPct: nil,
                estimateChangePct: nil
            )
        }
        let pendingTrades = pendingAmount > 0
            ? [
                PersonalPendingTrade(
                    occurredAt: "2026-06-05",
                    actionLabel: "买入",
                    fundName: name,
                    fundCode: code,
                    amountText: "\(pendingAmount)",
                    amountValue: pendingAmount,
                    status: "待确认"
                )
            ]
            : []
        return PersonalAssetAggregateRow(
            key: key,
            assetType: .fund,
            fundName: name,
            fundCode: code,
            holdingRow: valuationRow,
            rawHolding: holding,
            archivedHolding: nil,
            pendingTrades: pendingTrades,
            plans: []
        )
    }
}
```

- [ ] **Step 2: Run focused test and confirm it fails**

Run:

```bash
(cd macos-app && swift test --filter PersonalAssetBrowserPresentationTests)
```

Expected: compile fails with `cannot find 'PersonalAssetBrowserPresentationModel' in scope`.

- [ ] **Step 3: Implement personal asset presentation model**

Create `macos-app/Core/PersonalAssetBrowserPresentation.swift`:

```swift
import Foundation

struct PersonalAssetBrowserPresentationModel: Equatable {
    let visibleRows: [PersonalAssetAggregateRow]
    let filterCounts: [PersonalAssetFilterScope: Int]
    let comparisonSummary: PersonalAssetComparisonSummary
    let validComparisonSelection: [String]

    static func make(
        rows: [PersonalAssetAggregateRow],
        keyword: String,
        filterScope: PersonalAssetFilterScope,
        sortOption: PersonalAssetSortOption,
        comparisonSelection: [String],
        comparisonMaxCount: Int
    ) -> PersonalAssetBrowserPresentationModel {
        let normalizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var counts: [PersonalAssetFilterScope: Int] = [:]
        var visibleRows: [PersonalAssetAggregateRow] = []

        for row in rows {
            incrementCounts(for: row, counts: &counts)
            if matchesSearch(row, keyword: normalizedKeyword) && filterScopeMatch(filterScope, row: row) {
                visibleRows.append(row)
            }
        }

        let sortedVisibleRows = PersonalAssetRowSorter.sorted(visibleRows, by: sortOption)
        let validIDs = Set(rows.map(\.id))
        let validSelection = comparisonSelection.filter { validIDs.contains($0) }
        let comparisonSummary = PersonalAssetComparisonSummary.make(
            rows: rows,
            selectedIDs: validSelection,
            maxCount: comparisonMaxCount
        )

        return PersonalAssetBrowserPresentationModel(
            visibleRows: sortedVisibleRows,
            filterCounts: counts,
            comparisonSummary: comparisonSummary,
            validComparisonSelection: validSelection
        )
    }

    private static func incrementCounts(
        for row: PersonalAssetAggregateRow,
        counts: inout [PersonalAssetFilterScope: Int]
    ) {
        counts[.all, default: 0] += 1
        if row.hasHolding {
            counts[.holding, default: 0] += 1
        }
        if row.hasArchivedHolding {
            counts[.archivedHolding, default: 0] += 1
        }
        if row.hasPending {
            counts[.pending, default: 0] += 1
        }
        if row.activePlanCount > 0 {
            counts[.activePlan, default: 0] += 1
        }
        if row.pausedPlanCount > 0 || row.endedPlanCount > 0 {
            counts[.archivedPlan, default: 0] += 1
        }
        if row.hasDrawdownPlan {
            counts[.drawdownMode, default: 0] += 1
        }
    }

    private static func matchesSearch(_ row: PersonalAssetAggregateRow, keyword: String) -> Bool {
        guard !keyword.isEmpty else { return true }
        return row.fundName.lowercased().contains(keyword)
            || (row.fundCode?.lowercased().contains(keyword) ?? false)
    }

    private static func filterScopeMatch(_ scope: PersonalAssetFilterScope, row: PersonalAssetAggregateRow) -> Bool {
        switch scope {
        case .all:
            return true
        case .holding:
            return row.hasHolding
        case .archivedHolding:
            return row.hasArchivedHolding
        case .pending:
            return row.hasPending
        case .activePlan:
            return row.activePlanCount > 0
        case .archivedPlan:
            return row.pausedPlanCount > 0 || row.endedPlanCount > 0
        case .drawdownMode:
            return row.hasDrawdownPlan
        }
    }
}
```

- [ ] **Step 4: Run focused personal asset presentation tests**

Run:

```bash
(cd macos-app && swift test --filter PersonalAssetBrowserPresentationTests)
```

Expected: tests pass.

- [ ] **Step 5: Commit personal asset presentation model**

```bash
git add macos-app/Core/PersonalAssetBrowserPresentation.swift macos-app/Tests/QiemanDashboardTests/PersonalAssetBrowserPresentationTests.swift
git commit -m "perf: add personal asset presentation model"
```

## Task 6: Wire Personal Asset Presentation Into Browser View

**Files:**
- Modify: `macos-app/Views/PersonalAssetBrowser.swift`

- [ ] **Step 1: Remove view-local presentation structs and helpers**

In `macos-app/Views/PersonalAssetBrowser.swift`, delete this private struct at the top:

```swift
private struct PersonalAssetBrowserPresentation {
    let visibleRows: [PersonalAssetAggregateRow]
    let filterCounts: [PersonalAssetFilterScope: Int]
}
```

Delete this exact private method from `PersonalAssetBrowser`:

```swift
    private func makePresentation(keyword: String) -> PersonalAssetBrowserPresentation {
        var counts: [PersonalAssetFilterScope: Int] = [:]
        var visibleRows: [PersonalAssetAggregateRow] = []
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

        for row in rows {
            counts[.all, default: 0] += 1
            if row.hasHolding {
                counts[.holding, default: 0] += 1
            }
            if row.hasArchivedHolding {
                counts[.archivedHolding, default: 0] += 1
            }
            if row.hasPending {
                counts[.pending, default: 0] += 1
            }
            if row.activePlanCount > 0 {
                counts[.activePlan, default: 0] += 1
            }
            if row.pausedPlanCount > 0 || row.endedPlanCount > 0 {
                counts[.archivedPlan, default: 0] += 1
            }
            if row.hasDrawdownPlan {
                counts[.drawdownMode, default: 0] += 1
            }
            if matchesSearch(row, keyword: keyword) && filterScopeMatch(filterScope, row: row) {
                visibleRows.append(row)
            }
        }

        return PersonalAssetBrowserPresentation(
            visibleRows: PersonalAssetRowSorter.sorted(visibleRows, by: sortOption),
            filterCounts: counts
        )
    }
```

Delete these exact private helper methods from `PersonalAssetBrowser`:

```swift
    private func matchesSearch(_ row: PersonalAssetAggregateRow, keyword: String) -> Bool {
        guard !keyword.isEmpty else { return true }
        return row.fundName.lowercased().contains(keyword)
            || (row.fundCode?.lowercased().contains(keyword) ?? false)
    }

    private func filterScopeMatch(_ scope: PersonalAssetFilterScope, row: PersonalAssetAggregateRow) -> Bool {
        switch scope {
        case .all:
            return true
        case .holding:
            return row.hasHolding
        case .archivedHolding:
            return row.hasArchivedHolding
        case .pending:
            return row.hasPending
        case .activePlan:
            return row.activePlanCount > 0
        case .archivedPlan:
            return row.pausedPlanCount > 0 || row.endedPlanCount > 0
        case .drawdownMode:
            return row.hasDrawdownPlan
        }
    }
```

- [ ] **Step 2: Use the new presentation builder in `body`**

Replace this block in `body`:

```swift
        let presentation = makePresentation(keyword: debouncedSearchText)
        let comparisonSummary = PersonalAssetComparisonSummary.make(
            rows: rows,
            selectedIDs: comparisonSelection,
            maxCount: comparisonMaxCount
        )
```

with:

```swift
        let telemetryStart = PerformanceTelemetry.start()
        let presentation = PersonalAssetBrowserPresentationModel.make(
            rows: rows,
            keyword: debouncedSearchText,
            filterScope: filterScope,
            sortOption: sortOption,
            comparisonSelection: comparisonSelection,
            comparisonMaxCount: comparisonMaxCount
        )
        PerformanceTelemetry.record(
            "personalAsset.presentation",
            startedAt: telemetryStart,
            metadata: [
                "rowCount": "\(rows.count)",
                "visibleCount": "\(presentation.visibleRows.count)",
                "filter": filterScope.rawValue,
                "sort": sortOption.rawValue,
                "hasKeyword": "\(!debouncedSearchText.isEmpty)"
            ]
        )
```

Replace every `comparisonSummary` reference in the body with `presentation.comparisonSummary`.

- [ ] **Step 3: Prune invalid comparison selection using the presentation result**

Replace the existing `.onChange(of: rows.map(\.id))` modifier:

```swift
        .onChange(of: rows.map(\.id)) { _, validIDs in
            comparisonSelection.removeAll { !validIDs.contains($0) }
        }
```

with:

```swift
        .onChange(of: presentation.validComparisonSelection) { _, validSelection in
            comparisonSelection = validSelection
        }
```

- [ ] **Step 4: Run focused and related tests**

Run:

```bash
(cd macos-app && swift test --filter PersonalAssetBrowserPresentationTests)
(cd macos-app && swift test --filter PersonalAssetComparisonTests)
swift build --package-path macos-app
```

Expected: all three commands exit 0.

- [ ] **Step 5: Commit personal asset browser wiring**

```bash
git add macos-app/Views/PersonalAssetBrowser.swift
git commit -m "perf: share personal asset browser presentation"
```

## Task 7: Final P1 Verification And Smoke

**Files:**
- Inspect all files changed in Tasks 1-6.

- [ ] **Step 1: Run full Swift validation**

Run:

```bash
(cd macos-app && swift test)
swift build --package-path macos-app
```

Expected: `swift test` reports all XCTest tests passing and build exits 0.

- [ ] **Step 2: Run Python validation to guard shared repo commands**

Run:

```bash
python3 -m compileall -q dashboard_server.py dashboard qieman_scraper.py qieman_community_scraper.py scripts tests
python3 -m unittest discover -s tests -p 'test_*.py'
```

Expected: both commands exit 0.

- [ ] **Step 3: Check whitespace**

Run:

```bash
git diff --check
```

Expected: command exits 0 with no output.

- [ ] **Step 4: Manual telemetry smoke for Swift presentation work**

Run the app bundle executable with telemetry enabled:

```bash
QIEMAN_PERF_LOG=1 dist/macos-app/QiemanDashboard.app/Contents/MacOS/QiemanDashboard
```

If the bundle has not been rebuilt since P1 changes, run this first:

```bash
APP_VERSION=2.8.1 SIGN_IDENTITY=- TARGET_ARCH=$(uname -m) bash scripts/build_macos_app.sh
```

Expected: at least one safe `[perf]` line appears. If platform or portfolio data is visible, opening the platform or portfolio section should emit `platform.actions.presentation` or `personalAsset.presentation`. No line should contain raw cookies, authorization headers, or full payloads.

- [ ] **Step 5: Commit any verification-only fixes**

If Steps 1-4 required small fixes, commit them:

```bash
git add macos-app
git commit -m "perf: finish swift performance verification"
```

If no fixes were required, skip this commit.

## Final Expected Verification

Before marking P1 complete, these commands must pass:

```bash
(cd macos-app && swift test)
swift build --package-path macos-app
python3 -m compileall -q dashboard_server.py dashboard qieman_scraper.py qieman_community_scraper.py scripts tests
python3 -m unittest discover -s tests -p 'test_*.py'
git diff --check
```

Manual smoke should confirm at least one safe Swift `[perf]` line and, where possible, one `platform.actions.presentation` or `personalAsset.presentation` line.
