# Expanded Trend Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend AI trend analysis to cover market outlook, sector opportunities, investment opportunities such as gold, and per-held-fund trend analysis.

**Architecture:** Add additive top-level report arrays so old cached reports still decode with empty defaults while new model outputs are schema-required. Keep `keyAssets` focused on important assets and use `assetTrends` for every held fund. Reuse `TrendAssetView` shape for asset trend rows to minimize UI and decoding churn.

**Tech Stack:** SwiftUI/AppKit macOS 14, Swift Package Manager/XCTest, JSON Schema draft 2020-12, local investment trend skill pack.

## Global Constraints

- AppModel remains the single `@MainActor ObservableObject` state container.
- Trend analysis is personal research, not investment advice.
- Output must use conditional Chinese wording and include counter-signals.
- Existing cached trend reports must remain decodable.
- Python server remains zero third-party dependency; this change is Swift/skill-pack only.

---

### Task 1: Contract Tests

**Files:**
- Modify: `macos-app/Tests/QiemanDashboardTests/TrendSkillPackTests.swift`
- Modify: `macos-app/Tests/QiemanDashboardTests/TrendPromptBuilderTests.swift`
- Modify: `macos-app/Tests/QiemanDashboardTests/TrendAnalysisValidatorTests.swift`

**Interfaces:**
- Consumes: current `TrendAnalysisReport`, `TrendPromptBuilder`, `TrendAnalysisValidator`.
- Produces: failing tests that require `marketOutlook`, `opportunities`, and `assetTrends`.

- [ ] Add schema tests requiring top-level fields and item schemas.
- [ ] Add prompt tests requiring market, opportunity, and per-held-fund coverage instructions.
- [ ] Add validator tests rejecting missing asset trends for fund assets and weak opportunity evidence.
- [ ] Run `swift test --filter TrendSkillPackTests --filter TrendPromptBuilderTests --filter TrendAnalysisValidatorTests` and confirm expected failures.

### Task 2: Skill Pack And Prompt

**Files:**
- Modify: `skills/investment-trend-analysis/references/domain-rules.md`
- Modify: `skills/investment-trend-analysis/references/output-contract.md`
- Modify: `skills/investment-trend-analysis/assets/trend-report.schema.json`
- Modify: `skills/investment-trend-analysis/assets/examples.json`
- Modify: `macos-app/Core/TrendPromptBuilder.swift`

**Interfaces:**
- Produces: schema-required `marketOutlook`, `opportunities`, `assetTrends`; prompt instructions that keep `keyAssets` focused.

- [ ] Update skill docs to include market, opportunity, and per-held-fund analysis.
- [ ] Extend JSON schema with strict `marketOutlook`, `opportunities`, and `assetTrends` arrays.
- [ ] Update examples with representative Chinese output including gold.
- [ ] Update prompt JSON shape and coverage instructions.
- [ ] Run `python3 -m json.tool skills/investment-trend-analysis/assets/trend-report.schema.json`.

### Task 3: Swift DTO And Validation

**Files:**
- Modify: `macos-app/Core/TrendAnalysisModels.swift`
- Modify: `macos-app/Core/TrendAnalysisValidator.swift`
- Modify: `macos-app/Core/TrendDashboardSummary.swift`
- Modify: `macos-app/Core/TrendAssetTagging.swift`
- Modify: `macos-app/Tests/QiemanDashboardTests/TrendAnalysisStoreTests.swift`

**Interfaces:**
- Produces: additive Swift DTOs and default decoding for old cached reports.

- [ ] Add `TrendMarketOutlook`, `TrendOpportunity`, and `assetTrends`.
- [ ] Decode missing new fields as empty arrays.
- [ ] Prefer `assetTrends` before fallback in held asset tag lookup.
- [ ] Validate opportunities and per-fund trend counter-signals.
- [ ] Update shared fixtures.

### Task 4: Verification

**Files:**
- No new files beyond tests and plan.

**Interfaces:**
- Produces: evidence that contract and app tests pass.

- [ ] Run trend-focused tests.
- [ ] Run skill validation.
- [ ] Run full `swift test`.
