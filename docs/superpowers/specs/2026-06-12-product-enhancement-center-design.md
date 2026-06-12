# Product Enhancement Center Design

Date: 2026-06-12
Project: qieman-manager-dashboard
Target version: v2.8.0

## Goal

Add a unified product enhancement center to the macOS app in one release. The feature should turn four previously separate improvement ideas into a single user-facing workbench for portfolio review, watch status, import safety, and snapshot-based insight.

The enhancement center should help the user answer three practical questions:

- What happened to my portfolio this month?
- Which actions or data changes need my confirmation?
- Is my portfolio changing in a healthy and explainable way?

## Product Shape

Add a new first-level section named `增强` alongside the existing main app sections. The section is a review and safety workbench, not a replacement for the current overview, portfolio, platform, forum, or settings pages.

The enhancement center has four areas:

1. `复盘`: monthly report preview, Markdown copy, default archive export, and save-as export.
2. `巡检`: manager watch status timeline, including hits, failures, recoveries, and duplicate-notification suppression.
3. `导入`: import preview diff before portfolio data is written, plus undo for the latest successful import.
4. `洞察`: snapshot-based portfolio analysis using existing local data.

The first screen should show compact status summaries for all four areas, then let the user move into each area through tabs or a segmented control. This keeps the feature unified without forcing every workflow into one large page.

## Scope

### Included

- A new `增强` section in the SwiftUI app navigation.
- Monthly report Markdown preview, copy, default archive save, and save-as export.
- A persistent manager watch timeline with bounded local history.
- Import preview diff for portfolio-related imports before writing data.
- A one-step undo for the latest successful import.
- Portfolio insight summaries based on existing snapshots and current aggregated holdings.
- XCTest coverage for the new pure Core logic and failure/empty-state behavior.

### Excluded

- Full Keychain migration.
- Arbitrary multi-step import history rollback.
- A new charting dependency.
- Real historical backtesting.
- New external historical NAV API fetching.
- Large Python server refactors.
- Replacing existing portfolio, platform, forum, or settings sections.

## Architecture

The design adds a thin aggregation layer for the enhancement center and keeps business rules in Core files rather than SwiftUI views.

Proposed Core units:

- `EnhancementCenterSummary`
  - Aggregates the four area summaries for the top-level UI.
  - Depends on existing AppModel state, stores, and new focused summary builders.
  - Does not perform file writes or network calls.

- `MonthlyReportExporter`
  - Reuses `MonthlyReportSummary` for Markdown content.
  - Adds archive file naming, default report directory support, save-as support, and last-export metadata.

- `ManagerWatchTimeline`
  - Defines timeline event models and event summary logic.
  - Event types include watch started, speech hit, adjustment hit, duplicate notification suppressed, failed, and recovered.

- `ManagerWatchTimelineStore`
  - Persists lightweight timeline events as JSON.
  - Keeps the most recent 200 events or 90 days of events, whichever is smaller after pruning.

- `ImportPreviewSession`
  - Converts parsed import results into grouped diffs.
  - Groups include added, updated, unchanged, suspected duplicate, removed when applicable, and blocked.
  - Confirmation is disabled when blocked entries exist or undo snapshot persistence fails.

- `ImportUndoSnapshot`
  - Stores the pre-import state needed to revert the latest successful import.
  - Covers only affected portfolio assets, investment plans, and pending trades.

- `PortfolioSnapshotInsight`
  - Builds insight summaries from existing snapshots and current holdings.
  - Handles insufficient data with explicit empty-state summaries instead of synthetic trends.

`AppModel` should expose small entry points for UI orchestration, such as:

- `buildEnhancementSummary()`
- `exportMonthlyReport(...)`
- `recordManagerWatchEvent(...)`
- `prepareImportPreview(...)`
- `confirmImportPreview(...)`
- `undoLastImport()`

The implementation should avoid moving business calculations into `ContentView`, `EnhancementCenterView`, or existing large view files.

## Data Flow

### Monthly Report Export

1. The enhancement center asks existing monthly report logic to build `MonthlyReportSummary`.
2. `MonthlyReportExporter` renders Markdown from the summary.
3. Copy uses the existing clipboard behavior.
4. Default archive save writes to an app data subdirectory named `Reports/`.
5. Save-as uses a macOS save panel from the UI layer.
6. Successful export metadata records month, file URL, and export time.

Default archive file names use `YYYY-MM-portfolio-report.md`, for example `2026-06-portfolio-report.md`. Re-exporting the same month through the default archive action overwrites the existing archive file after a confirmation prompt. Save-as follows the path chosen in the macOS save panel.

### Manager Watch Timeline

1. Existing manager watch refresh and notification paths produce lightweight events.
2. Timeline event writes are best-effort and should not block watch refresh.
3. The store prunes old events after successful writes.
4. The UI displays events in reverse chronological order with type, manager, product, result, and optional failure reason.

Duplicate-notification suppression is represented as a normal timeline event, not as an error.

### Import Preview And Undo

1. Import parsing produces candidate portfolio assets, investment plans, and pending trades.
2. `ImportPreviewSession` compares candidates with current stored data and groups the diff.
3. Before confirmation, no portfolio data is mutated.
4. On confirmation, an undo snapshot is persisted first.
5. Existing AppModel CRUD and store methods apply the confirmed changes.
6. Undo restores only the latest successful import snapshot.
7. The undo option expires after another import or after manual edits touch the affected data domains.

If the undo snapshot cannot be saved, the confirmation action is disabled and the UI explains why.

### Portfolio Snapshot Insight

1. The insight builder reads existing local snapshots and current asset aggregation.
2. It computes only values supported by available data:
   - asset value changes across recent snapshots,
   - holding weight drift,
   - profit attribution summary where local values support it,
   - concentration changes,
   - pending trade impact,
   - investment plan impact,
   - data coverage and freshness.
3. If there are too few snapshots, the UI shows an empty state and tells the user what data is missing.

The first version should not call new external APIs for historical NAV data.

## UI Design

Add `EnhancementCenterView.swift`. Split repeated sections into focused component files when a section exceeds roughly 250 lines or starts carrying non-trivial local state. The view should use existing visual conventions from the app and keep dense operational information scannable.

Top area:

- Four compact status summaries:
  - monthly report status,
  - latest watch status,
  - import safety status,
  - snapshot insight coverage.

Main areas:

- `复盘`
  - Markdown preview.
  - Actions: copy Markdown, save to archive, save as.
  - Last export file and time.

- `巡检`
  - Reverse chronological event timeline.
  - The first version does not add event-type filtering. It relies on bounded history, clear labels, and reverse chronological ordering.

- `导入`
  - Diff groups with counts and representative rows.
  - Confirm action only when safe.
  - Undo latest import action is visible only when a valid undo snapshot exists.

- `洞察`
  - Compact cards for asset changes, attribution, concentration drift, plan impact, pending trade impact, and data coverage.
  - Gains use red and losses use green through `AppPalette`, following the app's Chinese market convention.

The existing portfolio, platform, and forum pages remain the primary places for daily browsing. The enhancement center is for review, confirmation, export, and cross-cutting explanation.

## Error Handling

- Monthly report export failures should not lose the generated Markdown. The UI should keep the preview available and show the file write error.
- Timeline persistence failures should not block manager watch refresh or notifications.
- Import confirmation should fail closed if undo snapshot persistence fails.
- Undo should verify that the snapshot is still valid for the current data domain before applying.
- Snapshot insights should degrade to explicit empty states when data is insufficient.
- File write errors should include the attempted path for archive exports and save-as exports.
- All new persisted JSON should tolerate missing optional fields for forward compatibility.

## Testing Plan

Add focused XCTest coverage for Core logic before relying on UI behavior.

Required test areas:

- `MonthlyReportExporterTests`
  - default archive file naming,
  - same-month default archive overwrite confirmation requirement,
  - last-export metadata creation,
  - generated Markdown remains available after a file write failure.

- `ManagerWatchTimelineTests`
  - event ordering,
  - pruning by count and age,
  - duplicate notification suppression event summaries,
  - failure and recovery event display data.

- `ImportPreviewSessionTests`
  - added, updated, unchanged, duplicate, and blocked groups,
  - confirmation disabled when blocked entries exist,
  - undo snapshot creation before applying changes,
  - undo invalidation after another import or manual edit marker.

- `PortfolioSnapshotInsightTests`
  - insufficient snapshot empty state,
  - asset change summary,
  - concentration drift summary,
  - plan and pending trade impact summaries,
  - gain/loss sign classification that the UI can map to the existing red-gain and green-loss palette.

Full verification commands:

```bash
swift test
swift build --package-path macos-app
APP_VERSION=2.8.0 bash scripts/build_macos_app.sh
```

Python validation remains useful for release confidence even though this design is primarily Swift-side:

```bash
python3 -m compileall -q dashboard qieman_scraper.py qieman_community_scraper.py scripts
```

## Rollout

This is one product release with internal implementation milestones:

1. Add Core models, stores, and tests for the four areas.
2. Add AppModel orchestration entry points.
3. Add the enhancement center UI and navigation entry.
4. Wire existing monthly report, watch, import, and snapshot flows into the new Core units.
5. Run full verification and package as `v2.8.0`.

Although the feature ships as one version, each milestone should keep the app buildable and tests passing.

## Success Criteria

- The app has a first-level `增强` section.
- A user can preview and save a monthly Markdown report.
- A user can inspect recent manager watch activity and understand duplicate notification suppression.
- A user can preview import changes before they are written.
- A user can undo the latest successful import when the snapshot is still valid.
- A user can see portfolio insight summaries when snapshots exist and clear empty states when they do not.
- New business logic is covered by XCTest.
- Existing main workflows still build and test successfully.

## Relationship To Existing Optimization Plan

This design corresponds to the Batch C product direction from `2026-06-12-comprehensive-optimization-design.md`, but chooses a unified product workbench rather than four isolated feature additions.

Batch A quality-baseline work should remain intact. Batch B architecture work is helpful but not a strict prerequisite as long as this implementation keeps logic in new focused Core units and avoids growing existing large SwiftUI files unnecessarily.
