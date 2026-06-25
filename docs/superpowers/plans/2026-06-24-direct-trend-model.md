# Direct Trend Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore trend analysis to direct OpenAI-compatible model calls instead of local agent execution.

**Architecture:** Trend generation will build the existing investment context and trend skill prompt, then call a direct `chat/completions` client. Agent detection, agent selection, and local command execution will be removed from the user-facing flow.

**Tech Stack:** SwiftUI, Foundation `URLSession`, OpenAI-compatible `POST /chat/completions`, XCTest.

## Global Constraints

- Preserve the existing `TrendAnalysisReport` JSON schema and validator.
- Keep the current investment trend skill as prompt guidance.
- Do not auto-fallback to local agents.
- Store API key configuration with existing local settings permissions.

---

### Task 1: Direct Model Settings And Client

**Files:**
- Modify: `macos-app/Core/TrendAnalysisModels.swift`
- Create: `macos-app/Core/TrendAIClient.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendAIClientTests.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendAnalysisStoreTests.swift`

**Interfaces:**
- Produces: `TrendAIProviderSettings`, `TrendAIClientProtocol`, `TrendAIClient`, `TrendConnectionCheckResult`.
- Consumes: `TrendModelPrompt`, `TrendAnalysisReport`.

- [ ] Write failing tests for provider settings persistence and OpenAI-compatible response decoding.
- [ ] Implement settings and direct client.
- [ ] Verify targeted tests pass.

### Task 2: AppModel Direct Generation Flow

**Files:**
- Modify: `macos-app/Core/AppModel.swift`
- Modify: `macos-app/Core/AppModel/SubModels.swift`
- Modify: `macos-app/Core/AppModel/TrendAnalysis.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/TrendAnalysisAppModelTests.swift`

**Interfaces:**
- Consumes: `TrendAIClientProtocol.generateReport(prompt:settings:)`.
- Produces: direct model progress logs and provider connection state.

- [ ] Write failing AppModel tests for configured direct provider generation and missing provider failure.
- [ ] Replace agent runner calls with direct model client calls.
- [ ] Verify targeted AppModel tests pass.

### Task 3: Settings And Trend Panel Copy

**Files:**
- Modify: `macos-app/Views/SettingsTrendPanel.swift`
- Modify: `macos-app/Views/EnhancementTrendPanel.swift`
- Modify: `macos-app/Core/EnhancementDashboardPresentation.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift`

**Interfaces:**
- Consumes: `trendSettings.provider.isConfigured`.
- Produces: model-oriented settings UI and action queue text.

- [ ] Write failing presentation test for "配置趋势分析模型".
- [ ] Replace Agent UI controls with base URL, model, API key, timeout, search support, and direct connection check.
- [ ] Verify targeted presentation tests pass.

### Task 4: Cleanup And Full Verification

**Files:**
- Modify or delete unused local-agent-only core/test files when no longer referenced.

**Interfaces:**
- Produces: buildable app with no local agent dependency in trend flow.

- [ ] Run `swift test --package-path macos-app`.
- [ ] Run `APP_VERSION=2.8.9 bash scripts/build_macos_app.sh`.
- [ ] Report changed files and any remaining risk.
