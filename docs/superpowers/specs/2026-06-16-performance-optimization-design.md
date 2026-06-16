# Performance Optimization Design

Date: 2026-06-16
Project: qieman-manager-dashboard

## Goal

Improve perceived and measurable performance across the whole Qieman Manager Dashboard without destabilizing the existing SwiftUI app, menu bar widget, Python fallback dashboard, or dual data-channel contract.

The optimization work will be delivered in three ordered batches:

1. P0: add a lightweight performance baseline so later improvements have evidence.
2. P1: optimize Swift app hot paths, especially refresh scheduling, derived list computation, platform filtering, and menu bar updates.
3. P2: optimize Python dashboard request and rendering paths while keeping the zero-third-party-dependency rule.

The first implementation plan should cover P0 only unless the user explicitly asks to combine batches. P1 and P2 remain documented here so the baseline does not block later product-facing performance work.

## Current Context

The repository contains a macOS SwiftUI app, a Python standard-library HTTP dashboard, scraper scripts, GitHub release automation, and project skills.

Recent inspection found these facts:

- The worktree was clean before this design document was written.
- Recent commits are focused on v2.8.x release updates, launch behavior, and the Enhancement Center.
- The app already has some performance safeguards:
  - `RefreshThrottle` throttles market-index refreshes.
  - `AppModel` caches several asset and platform summaries.
  - Personal asset search uses a short debounce.
  - Platform filter search uses a debounced filter state.
  - Swift platform/fund quote fetching has in-memory TTL caches.
  - Python fund, quote, and platform fetchers already use module-level caches.
- The likely risk is repeated derived computation and repeated refresh triggers rather than a total absence of caching.

Project constraints still apply:

- `AppModel` is the `@MainActor` global state container.
- Swift native clients are the primary data path; Python local HTTP remains fallback and debugging support.
- Python code must keep zero third-party dependencies.
- Cookie contents and local runtime data under `output/` must not be printed in logs or committed.
- UI changes must preserve the Chinese market convention: red for gains and green for losses.

## Scope

This design covers five performance areas:

1. App launch and first useful screen.
2. Manual and automatic refresh of holdings, valuations, platform data, and market indices.
3. Personal asset browser search, filter, sort, comparison, and table presentation.
4. Menu bar widget refresh and expansion behavior.
5. Python dashboard page and API performance for platform, forum, and timeline views.

The batches should avoid broad visual redesign, release-flow changes, and large architectural rewrites unless measurements show they are necessary.

## Batch P0: Performance Baseline

P0 adds small, local timing instrumentation and baseline tests. It does not change user-visible behavior.

### Measurement Points

Add a tiny performance logging utility that can measure async and sync blocks using the standard library.

Recommended Swift measurement points:

- App launch initialization around the existing app/model startup path.
- `refreshLatest(persist:updateNotice:)`.
- `refreshUserPortfolio(updateNotice:)`.
- `refreshMarketIndices(kinds:updateNotice:)`.
- Personal asset browser presentation building.
- Platform action filtering and pagination.
- Menu bar portfolio entries refresh.

Recommended Python measurement points:

- `dashboard.server` request handling for `/`, `/platform`, `/forum`, and `/timeline`.
- Platform payload fetch and normalization.
- Fund quote/history fetch paths that use TTL caches.
- Expensive HTML page assembly functions.

### Logging Rules

Logs should be concise and safe:

- Include operation name, elapsed milliseconds, and small counts such as row count or action count.
- Do not include raw cookies, authorization headers, personal position details, or full payloads.
- Keep logs disabled or minimal in normal release usage if an existing debug flag or build configuration is available.
- Prefer `os.Logger` on the Swift side if it can be introduced without extra dependencies; otherwise use a small internal utility.
- Use the Python standard library only.

### P0 Success Criteria

- A developer can run a refresh or open a dashboard page and see coarse timing for the relevant operation.
- Timing code is small enough to remove or gate later.
- Existing tests still pass.
- No sensitive local data appears in timing output.

## Batch P1: Swift App Hot Paths

P1 uses the P0 baseline to make narrow Swift changes.

### Refresh Scheduling

Unify and de-duplicate refresh triggers that currently come from launch, section switching, toolbar buttons, auto refresh, and menu bar visibility.

Target behavior:

- Manual refresh should still run immediately unless the exact same operation is already in progress.
- Automatic or section-triggered refresh should reuse recent successful data when it is fresh enough.
- Market index refresh should continue using throttle behavior, but callers should avoid launching redundant tasks when an operation is already in flight.
- Errors should continue surfacing through existing `noticeMessage` and `errorMessage` paths.

### Derived Data And Lists

Optimize high-frequency derived computations:

- Personal asset browser presentation should avoid rebuilding counts, search results, sorted rows, and comparison summaries more often than necessary.
- Platform filtering should avoid recalculating `filteredPlatformActions` separately for pagination, page count, and view rendering during the same render pass.
- Any new derived model should be plain data, testable, and small. It should not move business calculations into SwiftUI view bodies.

### Menu Bar Widget

Reduce redundant work when the menu bar ticker is enabled:

- Reuse portfolio rows already rebuilt by `AppModel` where possible.
- Coalesce portfolio and market-index refreshes when the menu opens or auto-refresh fires.
- Keep the widget responsive when quote fetching fails or returns partial data.

### P1 Success Criteria

- Repeated section switching does not start unnecessary duplicate network refreshes.
- Personal asset search/filter/sort remains responsive with a larger synthetic row set.
- Platform pagination and page-count rendering share one filtered result per state change.
- Menu bar refresh still updates holdings and selected market indices, with fewer redundant operations in logs.
- Focused XCTest coverage exists for new pure derived models or refresh decision helpers.

## Batch P2: Python Dashboard Hot Paths

P2 optimizes the local Python fallback dashboard after Swift hot paths are protected.

### Request And Render Paths

Review `/platform`, `/forum`, `/timeline`, and home page assembly for repeated work inside a single request.

Target changes:

- Reuse cached platform payloads and normalized summaries when request inputs have not changed.
- Avoid recomputing expensive monthly or timeline summaries multiple times while rendering one page.
- Keep cache keys explicit and small.
- Keep TTL values conservative so the dashboard still feels current.

### Fetching And Fallbacks

Preserve existing data behavior:

- Fund valuation can still use intraday estimates with latest-NAV fallback.
- Platform trade history remains the source for platform adjustments.
- Auth checks stay non-sticky and must not expose cookie contents.

### P2 Success Criteria

- Python compile checks still pass.
- Representative dashboard pages render with lower measured elapsed time or fewer repeated expensive calls.
- Cache invalidation is simple enough to reason about from request parameters and snapshot name.
- No pip dependencies are added.

## Data Flow

Production data flow remains unchanged:

- Swift native clients remain the main path for app data.
- Python local HTTP remains fallback and debug support.
- Stores continue to own persisted portfolio, plan, pending-trade, watch, and snapshot data.
- The performance baseline observes and reports timing; it does not become a new source of truth.

Any new derived presentation model should be downstream of existing model data and should be rebuildable from current `AppModel` state.

## Error Handling

Performance changes must preserve existing failure behavior:

- Measurement failures should not fail user workflows.
- Refresh de-duplication must not swallow the last meaningful error when a user manually refreshes.
- Cache misses should fall back to existing computation paths.
- Python cache errors should degrade to recomputation, not blank pages.

## Testing Plan

P0 verification:

- `swift test`
- `swift build --package-path macos-app`
- `python3 -m compileall -q dashboard qieman_scraper.py qieman_community_scraper.py scripts`
- Manual smoke: run the app or focused refresh path and inspect safe timing output.

P1 verification:

- Add or update XCTest coverage for refresh decision helpers and pure presentation builders.
- Add synthetic-row tests for personal asset browser presentation if the logic moves out of the view.
- Add platform filter/pagination tests if the cached presentation surface is extracted.
- Re-run the P0 commands.

P2 verification:

- Add lightweight Python `unittest` coverage for cache-key or summary helper behavior when helpers are extracted.
- Run the Python compile command.
- Manually request the relevant local dashboard pages and compare P0 timing output before and after.

## Rollout

Roll out in separate changes:

1. P0 baseline only.
2. P1 Swift app optimizations in one or more small patches.
3. P2 Python dashboard optimizations after Swift hot paths are stable.

Each batch should include before/after timing notes in the final work summary when measurements are available.

## Non-Goals

- No full AppModel rewrite.
- No large SwiftUI visual redesign.
- No new third-party Swift or Python dependencies.
- No Keychain migration as part of performance work.
- No release automation changes.
- No broad file splits unless a measured hot path requires a small extraction.
- No network API contract changes.
