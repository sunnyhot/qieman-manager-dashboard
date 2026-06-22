# Trend Analysis Workbench

Date: 2026-06-22
Project: qieman-manager-dashboard
Target version: next release

## Goal

Add a new `趋势` tab to the existing `增强工作台`. The feature should use the configured large model to analyze the user's portfolio together with fresh market, macro, news, and policy context, then produce a structured trend report for portfolio-level, sector-level, and key-asset decisions.

The feature is a research assistant inside the app. It may produce trend views and action candidates, but it must not automate trades, change investment plans, or present model output as guaranteed investment advice.

## Confirmed Scope

The first version should support:

- A new `趋势` tab in `EnhancementCenterView`.
- Large-model-first analysis through an OpenAI-compatible provider.
- Model-provided online search/news capability when the selected provider supports it.
- No standalone search API integration in the first version.
- Portfolio overview plus sector/industry attribution plus key asset drill-down.
- Short, medium, and long horizon judgments in the same report.
- Action candidates from watch-only suggestions to conditional add/reduce/pause-plan candidates.
- Manual generation by default.
- Optional daily automatic generation in settings.
- Privacy mode switch:
  - default `脱敏摘要`;
  - optional `完整明细` after explicit user confirmation.
- Local AI configuration discovery:
  - detect common local AI/agent configuration candidates such as Codex, Claude/cc, and OpenAI-compatible environment/config values;
  - show discovered candidates for user review;
  - import only OpenAI-compatible provider settings automatically supported by this feature;
  - never silently reuse another tool's API key or send portfolio data through it without explicit user confirmation.
- Persistent latest report cache so the user can reopen the app and keep the last successful analysis.

Out of scope for the first version:

- Automatic trade execution.
- Automatic modification of investment plans or pending trades.
- Separate Tavily, Brave, SerpAPI, or other search-provider integration.
- Multi-provider comparison, ranking, or cost optimization.
- Long chat history with the model.
- Full historical backtesting. Existing snapshot and valuation data can be used as context, but this is not a backtest engine.

## Product Shape

The tab behaves as a structured workbench, not as a free-form chat page.

Top area:

- Provider/config status.
- Last report time and freshness state.
- Privacy mode.
- Manual `生成趋势分析` button.
- Optional daily automation state.

Main report sections:

1. `组合总览`
   - Overall direction.
   - Portfolio risk level.
   - Short, medium, and long horizon calls.
   - Main opportunity and pressure drivers.
2. `板块归因`
   - Group holdings into broad sectors or themes.
   - Show exposure, trend direction, confidence, drivers, evidence, and counter-signals.
3. `重点标的`
   - Do not force every asset into a long write-up.
   - Highlight assets with high weight, high risk, high opportunity, notable plan exposure, or notable news sensitivity.
4. `行动候选`
   - Show candidates such as `关注`, `等待确认`, `分批观察`, `暂停定投`, `可考虑加仓`, `可考虑减仓`.
   - Every candidate must include trigger conditions, invalidating conditions, confidence, and rationale.
5. `来源与免责声明`
   - Show data timestamps, model/search capability state, cited external sources, and a fixed non-advice notice.

The tab should feel consistent with the current enhancement center: compact, operational, and card-based, using `AppPalette`, native SwiftUI controls, and the current status-card/action-queue pattern.

## User Stories

**User story 1:** As a portfolio owner, I want to see whether my overall portfolio trend is improving or worsening across short, medium, and long horizons, so that I can decide what deserves attention.

**User story 2:** As a portfolio owner, I want sector/theme attribution, so that I can understand which exposures are driving opportunity or risk.

**User story 3:** As a portfolio owner, I want key-asset trend explanations, so that I can focus on the funds or stocks that matter most instead of reading every holding.

**User story 4:** As a privacy-conscious user, I want the app to default to sanitized model input and only send full details after I explicitly choose it, so that my actual asset amounts are protected by default.

**User story 5:** As a recurring user, I want optional daily automatic analysis, so that I can get a fresh research view without manually generating it every day.

## Acceptance Criteria

1. WHEN the user opens the enhancement center THEN the system SHALL show a new `趋势` tab alongside the existing enhancement tabs.
2. WHEN AI provider settings are incomplete THEN the system SHALL show the missing configuration and SHALL disable report generation.
3. WHEN the user generates a report in sanitized mode THEN the system SHALL send no real holding amount, cost amount, profit amount, plan amount, or pending trade amount to the model.
4. WHEN the user switches to full-detail mode THEN the system SHALL show a confirmation explaining which financial details will be sent.
5. WHEN the user confirms full-detail mode THEN the system SHALL include full portfolio details in the model context until the user switches back or the app setting changes.
6. WHEN the selected model/provider supports online search THEN the system SHALL instruct the model to use current news, macro, and policy information and require source metadata.
7. WHEN the selected model/provider does not support online search THEN the system SHALL still allow local-context analysis and SHALL mark external news/macro signals as unavailable.
8. WHEN the model response cannot be decoded as the required report schema THEN the system SHALL not render it as an official trend report and SHALL show a format error.
9. WHEN report generation fails THEN the system SHALL keep the last successful report visible and SHALL show the new failure state separately.
10. WHEN daily automatic analysis is enabled THEN the system SHALL generate at most one automatic report per local day unless the user manually triggers another run.
11. WHEN automatic analysis fails THEN the system SHALL add an enhancement-center action item instead of interrupting the user with a blocking alert.
12. WHEN the report includes an action candidate THEN the system SHALL show trigger conditions, invalidating conditions, confidence, and the non-advice notice.
13. IF the report contains unsupported absolute claims such as guaranteed returns or mandatory buy/sell wording THEN the system SHALL reject or downgrade the report and show a validation warning.
14. WHEN the user asks the app to detect local AI configuration THEN the system SHALL scan only known safe local config locations and process environment variables, and SHALL present candidates without logging or exposing secret values.
15. WHEN a discovered candidate is OpenAI-compatible THEN the system SHALL allow the user to import its base URL, model, provider label, and key reference or key value only after explicit confirmation.
16. WHEN a discovered candidate is not OpenAI-compatible, such as a direct Anthropic/Claude-only configuration, THEN the system SHALL show it as detected but not directly usable for trend generation until a compatible endpoint/client is configured.

## Architecture

Use the existing Swift-native path as the primary implementation surface. Python dashboard support is not required for the first version.

New Core components:

- `TrendAnalysisContextBuilder`
  - Builds sanitized and full-detail model input from existing app state.
  - Uses `PersonalAssetAggregateRow`, portfolio valuation rows, investment plans, pending trades, market index quotes, platform actions, manager watch summaries, and portfolio insight snapshots where available.
- `TrendPromptBuilder`
  - Produces the system and user prompts.
  - Enforces JSON-only output, evidence rules, non-advice language, confidence scoring, counter-signals, and action-candidate constraints.
- `TrendAIClient`
  - Calls an OpenAI-compatible API endpoint with `baseURL`, `apiKey`, and `model`.
  - Treats online search as a provider capability flag/instruction rather than a separate app-managed API.
- `TrendAnalysisReport`
  - Codable schema for the model result.
  - Contains portfolio, sector, key-asset, action, evidence, and metadata sections.
- `TrendAnalysisValidator`
  - Validates required fields and rejects unsafe language or missing constraints.
- `TrendAnalysisStore`
  - Saves and loads latest reports and generation metadata from the app data directory.
- `LocalAIConfigurationDetector`
  - Best-effort detector for existing local model/tool configuration.
  - Reads candidate metadata from known locations such as `~/.codex/config.toml`, Claude/cc config files, and relevant process environment variables when available to the app process.
  - Masks secret values and returns compatibility status instead of silently copying credentials.
- `LocalAIConfigurationCandidate`
  - Describes provider label, base URL, model, key source, compatibility, confidence, and import warning text.

AppModel integration:

- Extend `EnhancementState` with:
  - `trendReport`
  - `trendGenerationState`
  - `trendPrivacyMode`
  - `trendSettings`
  - `lastTrendGeneratedAt`
  - `lastTrendError`
- Add computed presentation helpers in an `AppModel/TrendAnalysis.swift` extension.
- Add generation methods:
  - `generateTrendAnalysis(userInitiated: Bool)`
  - `loadTrendAnalysisState()`
  - `saveTrendAnalysisSettings()`
  - `runDailyTrendAnalysisIfNeeded()`

Settings integration:

- Add a trend/AI settings panel or section with:
  - provider base URL;
  - model;
  - API key;
  - online search capability toggle;
  - daily auto analysis toggle;
  - default privacy mode;
  - timeout;
  - `检测本机配置` action showing importable and non-importable local candidates.

The API key must not be printed in logs or shown in plain text after entry. A future Keychain migration is allowed, but the first version must at minimum keep the key local and out of committed files.

Local configuration import rules:

- Import is user-initiated only.
- Importable candidates must be OpenAI-compatible or explicitly marked compatible by the user.
- Claude/cc direct Anthropic-style settings can be detected for awareness, but they are not used by the first-version OpenAI-compatible client unless they point to an OpenAI-compatible gateway.
- Shell profile scraping is out of scope for the first version because a GUI macOS app cannot reliably inherit interactive-shell environment and because shell files can contain unrelated secrets.
- The detector may read local config files, but it must not write to those files.

## Data Flow

Manual generation:

1. User opens `增强 -> 趋势`.
2. UI checks provider settings and current portfolio availability.
3. User chooses `脱敏摘要` or `完整明细`.
4. `TrendAnalysisContextBuilder` builds the payload.
5. `TrendPromptBuilder` wraps the payload in strict model instructions.
6. `TrendAIClient` sends the request.
7. App decodes `TrendAnalysisReport`.
8. `TrendAnalysisValidator` validates structure and safety constraints.
9. App saves the report and updates `EnhancementState`.
10. UI renders the report cards and source/metadata area.

Daily automatic generation:

1. App startup or suitable refresh point calls `runDailyTrendAnalysisIfNeeded()`.
2. The method checks setting enabled, provider configured, portfolio available, not already generated today, and no generation in progress.
3. It runs generation with `userInitiated: false`.
4. On success, latest report is saved silently.
5. On failure, last report remains visible and the enhancement action queue gets a trend action item.

## Model Output Schema

The report should decode into a shape equivalent to:

```swift
struct TrendAnalysisReport: Codable, Hashable {
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

Important enums:

- `TrendDirection`: `bullish`, `neutralPositive`, `neutral`, `neutralNegative`, `bearish`, `uncertain`.
- `TrendHorizon`: `short`, `medium`, `long`.
- `TrendConfidence`: numeric score from 0 to 100 plus label.
- `TrendActionKind`: `watch`, `waitForConfirmation`, `observeInBatches`, `pausePlan`, `considerIncrease`, `considerReduce`, `rebalanceReview`.
- `TrendExternalSignalStatus`: `available`, `unavailable`, `partial`, `stale`.

Every report section that makes a claim must include rationale and counter-signals. Any external evidence should include source name, title or summary, URL when available, published date when available, and retrieved time.

## Prompt Constraints

The system prompt should require:

- Return valid JSON only.
- Use the provided schema exactly.
- Separate facts, model judgment, and action candidates.
- Use current online information only if the provider supports online search.
- Do not invent sources.
- Do not guarantee returns.
- Do not use mandatory buy/sell language.
- Always include counter-signals and confidence.
- Always include data timestamps.
- Treat Chinese market convention correctly: red means gain, green means loss in the UI, though the model should output semantic direction rather than colors.
- Prefer conditional wording:
  - allowed: `可考虑`, `等待确认`, `关注`, `若...则...`;
  - disallowed: `必须买入`, `保证上涨`, `一定卖出`.

## UI Design

Add `case trend = "趋势"` to `EnhancementCenterTab`.

Enhancement status card:

- Title: `趋势研判`
- Value examples:
  - `未配置`
  - `待生成`
  - `今日已生成`
  - `外部信号缺失`
  - `生成失败`
- Detail: last generated time, privacy mode, and external signal status.
- Next action: configure, generate, inspect failure, or view report.

Action queue additions:

- Missing provider settings.
- Report stale or never generated.
- Daily auto-analysis failure.
- Model output rejected by validation.
- External news/macro unavailable when online search is expected.

Trend tab layout:

1. `运行状态`
   - provider, model, online search state, last generation, privacy mode.
2. `生成控制`
   - manual generate button;
   - privacy segmented control;
   - daily auto-analysis state;
   - stale/error badges.
3. `组合总览`
   - overall summary and horizon chips.
4. `板块归因`
   - adaptive card grid or compact list.
5. `重点标的`
   - sortable list by impact, confidence, risk, or action severity.
6. `行动候选`
   - grouped by urgency and confidence.
7. `来源与约束`
   - sources, data timestamps, warnings, and non-advice text.

Use compact macOS dashboard styling. Do not add a marketing hero. Do not introduce a new charting dependency in the first version.

## Error Handling

- Missing provider settings:
  - Show setup state.
  - Disable generation.
- Missing portfolio data:
  - Explain that a portfolio refresh or import is required.
- Network/API failure:
  - Keep last successful report.
  - Show error timestamp and message.
- Model timeout:
  - Same as API failure; allow retry.
- Invalid JSON:
  - Reject official report rendering.
  - Show format error.
- Schema validation failure:
  - Reject unsafe or incomplete sections.
  - Keep last successful report.
- Search unavailable:
  - Render local-context analysis with external signal warning.
- Daily automation failure:
  - Add action queue item.
  - Do not show a blocking alert unless the user initiated the run.

## Privacy And Safety

Default behavior:

- Send sanitized portfolio context only.
- Do not send real amounts, costs, profits, plan amounts, or pending trade amounts.
- Send percentages, relative weights, codes, names, market, estimated changes, and high-level exposure.

Full-detail behavior:

- Requires explicit confirmation.
- May include real amount, cost, profit, plan amount, and pending trade amount.
- The UI must clearly state what will be sent.

Logging:

- Never log API keys.
- Never display full API keys from detected local configuration; use masked labels such as `sk-...abcd`.
- Never log full-detail payload by default.
- Error messages should avoid embedding request bodies.

Safety:

- The app does not execute trades.
- The app does not modify holdings, plans, or pending trades from a trend action.
- The report always carries a non-advice disclaimer.

## Testing Plan

Core tests:

- `TrendAnalysisContextBuilderTests`
  - sanitized payload excludes real amounts;
  - full-detail payload includes expected fields after selection;
  - sector/theme aggregation remains stable.
- `TrendPromptBuilderTests`
  - prompt requires JSON-only output;
  - prompt requires evidence and counter-signals;
  - prompt forbids guaranteed return and mandatory buy/sell language.
- `TrendAnalysisReportTests`
  - decode valid report fixture;
  - reject missing required fields;
  - preserve unknown-safe optional fields if added later.
- `TrendAnalysisValidatorTests`
  - reject absolute claims;
  - reject action candidates without trigger or invalidating conditions;
  - warn when external evidence is missing.
- `TrendAnalysisStoreTests`
  - save/load report;
  - determine same-day generation;
  - preserve last successful report after failed generation metadata.
- `EnhancementTrendPresentationTests`
  - status card for missing config;
  - status card for stale report;
  - action queue item for daily automation failure;
  - action queue item for invalid model output.

Integration-style tests with a fake AI client:

- Successful manual generation updates state and saves report.
- User-initiated failure sets visible error.
- Automatic failure records queue state without blocking alert.
- Model search disabled produces external-signal unavailable state.

Verification command:

```bash
swift test
```

Run from `macos-app/`.

## Release Notes

Suggested user-facing commit/release title:

`feat: add AI trend analysis workbench`

Suggested release note:

`新增趋势研判工作台：可结合持仓、板块暴露、最新资讯和大模型分析生成组合、行业与重点标的的短中长期趋势参考，并提供隐私模式和条件化行动候选。`
