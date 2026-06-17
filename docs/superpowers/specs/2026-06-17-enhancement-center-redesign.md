# Enhancement Center Redesign

Date: 2026-06-17
Project: qieman-manager-dashboard
Target version: next release after v2.8.2

## Goal

Redesign the `增强` section from a set of four rough utility panels into a professional monthly investment workbench. The redesigned module should help a recurring user quickly answer:

- What is the current monthly portfolio condition?
- What needs action before the data or report can be trusted?
- What changed since recent snapshots, and why?
- Which export, import, watch, or insight action should happen next?

The redesign is primarily a SwiftUI product and interaction upgrade. It should reuse existing Core models where possible and add new pure presentation models only when they make the UI easier to test and reason about.

## Current Problems

The current `EnhancementCenterView` works functionally, but it feels unfinished for four reasons:

- The top cards are status fragments, not a decision surface. They show values but do not tell the user what to do next.
- The segmented control makes `复盘`, `巡检`, `导入`, and `洞察` feel like unrelated tools instead of one monthly workflow.
- The `复盘` tab overweights raw Markdown. The report is useful, but the first screen should show conclusions before source text.
- The `导入` and `巡检` flows lack enough prioritization. Risk, blockers, recovery, and next action are present in data but not visually elevated.

## Product Direction

Use a `月度增强工作台` pattern.

The page remains an operational macOS dashboard, not a landing page. It should be dense, quiet, and precise, with one memorable product-specific device: an `行动队列` rail that continuously explains what the user should handle next.

The redesigned page has three layers:

1. `月度状态栏`: month, portfolio health, actionable count, primary action, and runtime status chips.
2. `四张状态卡`: review, watch, import safety, and insight coverage. Cards are clickable navigation and include next-action text.
3. `主工作区 + 行动队列`: the selected workflow appears on the left; cross-cutting risks and recent evidence appear on the right.

This keeps the module professional by making structure encode workflow rather than decoration.

## Visual System

Follow the existing app palette and macOS conventions:

- Use `AppPalette` tokens for surfaces, borders, text, semantic states, and Chinese market red-gain/green-loss colors.
- Keep cards at the existing 10-12pt radius range.
- Use SF Symbols only, with consistent icon boxes and no emoji.
- Keep typography compact: 10-12pt labels, 13-15pt body, 18-24pt key figures.
- Use monospaced digits for money, counts, dates, and percentages.
- Avoid large marketing hero treatment, decorative blobs, and oversized empty whitespace.

Recommended visual tone:

- Background: existing subtle blue-gray canvas.
- Surfaces: white/light card surfaces with restrained borders.
- Accent: brand blue for selected workflow and primary action.
- Risk: warning amber for attention, danger red only for destructive/blocked state.
- Market values: red for gain, green for loss through `AppPalette.marketTint`.

## Information Architecture

### Header

Replace the plain module body start with a compact header inside the page content:

- Title: `月度增强工作台`
- Subtitle: current month and concise state, for example `2026-06 · 组合健康 · 2 项待处理`
- Primary action:
  - `处理导入预览` when active import preview has confirmable or blocked rows.
  - `立即巡检` when watch timeline has no recent result or last event failed.
  - `保存月报` when report has not been archived this month.
  - `生成快照` or `查看洞察` when insight history is insufficient or ready.
- Runtime chips:
  - Cookie state.
  - Native direct state.
  - Snapshot count or insight coverage.
  - Last watch event time.

The header should not duplicate the global toolbar refresh button. It should focus on this module's next task.

### Status Cards

Use four horizontally adaptive cards:

- `复盘`
  - Key value: report month.
  - Secondary: archive status and generated time.
  - Next action: copy, archive, or review summary.
- `巡检`
  - Key value: latest status.
  - Secondary: event count, failure count, last success.
  - Next action: run watch or inspect failure.
- `导入安全`
  - Key value: safe, confirmable, blocked, or undoable.
  - Secondary: added/updated/duplicate/blocked counts when preview exists.
  - Next action: preview, confirm, resolve blocker, or undo.
- `组合洞察`
  - Key value: ready or needs snapshots.
  - Secondary: snapshot coverage and headline.
  - Next action: record snapshot, inspect drift, or open insight.

Cards should be selectable and should update `selectedEnhancementTab`. Selected cards use a stronger border and soft brand fill. They must remain keyboard accessible through native SwiftUI buttons.

### Main Work Area

Use an adaptive split:

- Wide layout: left content `min 620pt`, right rail `280-360pt`.
- Narrow layout: stack the right rail below the selected workflow.

The segmented control can remain, but it should be visually secondary to the cards. The selected status card should be the main navigation affordance.

## Workflow Panels

### Review Panel

The first screen should be a report summary, not a raw Markdown wall.

Content order:

1. Report status strip: month, generated time, last archive file, Markdown line count.
2. Summary grid from existing monthly report inputs:
   - portfolio overview,
   - diagnostics,
   - reminders,
   - profit attribution,
   - plan simulation.
3. Actions:
   - `复制 Markdown`,
   - `保存到归档`,
   - `另存为`.
4. Collapsible Markdown preview:
   - default collapsed or height-limited,
   - monospaced text,
   - `展开全文` and `收起` controls.

This makes the report readable before it becomes exportable.

### Watch Panel

Make the timeline into an operations log.

Content order:

1. Watch health strip: latest status, failure count, last success, total events.
2. Filter chips:
   - `全部`,
   - `命中`,
   - `失败`,
   - `重复抑制`,
   - `恢复/完成`.
3. Timeline rows:
   - event type icon,
   - title and detail,
   - timestamp,
   - optional error shown as inline warning.
4. Empty state:
   - explain that enabling watch or running manual watch creates records.

Failures and recoveries should be visually distinct. Duplicate suppression is informational, not an error.

### Import Panel

Make import preview feel like a data review flow.

Content order:

1. Import control bar:
   - target picker,
   - save mode picker,
   - table import,
   - image recognition,
   - generate preview.
2. Draft input:
   - keep visible but visually subordinate,
   - label it as source draft,
   - use a stable min height.
3. Preview summary:
   - added,
   - updated,
   - unchanged,
   - duplicate,
   - removed,
   - blocked.
4. Diff list grouped by severity:
   - blocked first,
   - duplicate and removed next,
   - updated,
   - added,
   - unchanged last and visually muted.
5. Action footer:
   - primary `确认写入` only when safe,
   - destructive `撤销上次导入` separated into a danger zone.

Confirm remains disabled when `activeImportPreviewSession?.canConfirm != true`. The UI should state why confirmation is unavailable.

### Insight Panel

Use a compact metric matrix rather than plain cards.

Content order:

1. Insight readiness strip: snapshot count, coverage, current headline.
2. Metric grid:
   - asset value change,
   - concentration drift,
   - plan impact,
   - pending trade impact,
   - profit direction,
   - data freshness or coverage.
3. Evidence text:
   - concise explanation for each metric.
4. Insufficient history state:
   - explain the missing condition,
   - provide a direct action through `recordPortfolioInsightSnapshotIfPossible` when current rows are available.

No new chart dependency should be introduced in this pass.

## Action Queue Rail

Add a right-side rail named `行动队列`.

It aggregates cross-cutting items from current AppModel state:

- Import preview exists and has blocked rows.
- Import preview exists and can be confirmed.
- Undo snapshot is available.
- Watch latest event failed.
- Watch has no events.
- Monthly report has not been archived for the current month.
- Insight history is insufficient.
- Portfolio reminders contain urgent items.
- Pending trades exist.
- Active plans have upcoming execution.

Each action item should include:

- severity: info, success, warning, danger,
- title,
- detail,
- destination tab,
- optional action button label.

The rail is the core professional upgrade: it turns the enhancement center from a collection of utilities into a guided control surface.

## Core And Presentation Model

Keep business logic out of the SwiftUI body by adding pure presentation helpers:

- `EnhancementDashboardSummary`
  - month state,
  - primary action,
  - status cards,
  - action queue,
  - runtime chips.
- `EnhancementStatusCard`
  - tab,
  - title,
  - value,
  - detail,
  - nextAction,
  - icon,
  - tone.
- `EnhancementActionItem`
  - severity,
  - title,
  - detail,
  - target tab,
  - action kind.
- `EnhancementWatchFilter`
  - all, hit, failure, duplicate, recovery.

These models should be built from existing summaries:

- `MonthlyReportSummary`
- `ManagerWatchTimelineSummary`
- `ImportPreviewSession`
- `PortfolioSnapshotInsightSummary`
- `PortfolioReminderSummary`
- `PlanSimulationSummary`

Presentation models should be unit tested without launching SwiftUI.

## File Boundaries

Expected implementation files:

- Modify `macos-app/Views/EnhancementCenterView.swift`.
- Add `macos-app/Core/EnhancementDashboardPresentation.swift`.
- Add `macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift`.

If `EnhancementCenterView.swift` grows beyond roughly 650 lines after the redesign, split reusable view pieces into:

- `macos-app/Views/Enhancement/EnhancementDashboardHeader.swift`
- `macos-app/Views/Enhancement/EnhancementActionQueueView.swift`
- `macos-app/Views/Enhancement/EnhancementImportReviewView.swift`

Avoid moving unrelated portfolio, platform, forum, or settings code.

## Error Handling

- Report export errors keep the report preview visible and show the failed path through existing `errorMessage`.
- Import confirmation fails closed and keeps the preview visible.
- Watch timeline persistence failures should not block manual or automatic watch behavior.
- Insight insufficient history states should be explicit and actionable, not blank.
- Destructive actions, especially import undo, should remain disabled when unsafe.

## Accessibility And Interaction

- Use real `Button`, `Picker`, `TextEditor`, and SwiftUI controls.
- Add `.help(...)` to icon-only or compact actions.
- Keep click targets at least 44pt high for custom card buttons.
- Use text plus color for warning/success states.
- Preserve text selection for Markdown preview.
- Avoid hover-only affordances.
- Keep keyboard focus order: header action, status cards, tab controls, main panel, action queue.

## Testing Plan

Add focused XCTest coverage for pure presentation logic:

- Primary action prioritizes blocked import over report archive and insight readiness.
- Status cards map each tab to the expected value, tone, and next action.
- Action queue includes confirmable import, blocked import, undo, watch failure, missing watch history, missing archive, insufficient insight history, pending trades, and upcoming plans.
- Watch filtering groups failure, duplicate suppression, hit, and recovery events correctly.
- Report preview metadata includes month, generated time, archive state, and line count.

Existing broader verification remains:

```bash
swift build --package-path macos-app --build-tests
rm -rf /tmp/qieman-xctest-enhancement-redesign
mkdir -p /tmp/qieman-xctest-enhancement-redesign
cp -R macos-app/.build/arm64-apple-macosx/debug/QiemanDashboardPackageTests.xctest /tmp/qieman-xctest-enhancement-redesign/
mkdir -p /tmp/qieman-xctest-enhancement-redesign/QiemanDashboardPackageTests.xctest/Contents/Resources
codesign --force --sign - --deep /tmp/qieman-xctest-enhancement-redesign/QiemanDashboardPackageTests.xctest
xcrun xctest /tmp/qieman-xctest-enhancement-redesign/QiemanDashboardPackageTests.xctest
APP_VERSION=2.8.2 SIGN_IDENTITY="-" TARGET_ARCH=arm64 bash scripts/build_macos_app.sh
```

## Rollout And Release Risk

Release readiness: Ready with caveats after implementation and verification.

Main risks:

- UI scope can expand if report editing, full charting, or multi-import history are added. These are intentionally out of scope.
- The action queue must not invent data. It should only explain existing local state.
- Large SwiftUI views can become hard to maintain. Split view files when repeated sections grow.

Rollback:

- Revert the presentation model and `EnhancementCenterView` changes.
- Existing Core data stores and persisted enhancement state should remain compatible because this redesign does not change storage formats.

## Out Of Scope

- Full report editor with rich Markdown editing.
- New charting framework.
- Multi-version import rollback history.
- Keychain migration.
- New external NAV or market-history API.
- Redesigning other app sections.
