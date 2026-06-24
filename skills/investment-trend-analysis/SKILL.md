---
name: investment-trend-analysis
description: Use when a local agent receives qieman-manager-dashboard portfolio context, platform or manager signals, watch events, examples, and a trend-report schema and must produce a strict JSON personal research trend report with portfolio, horizon, sector, key-asset, evidence, warning, and conditional action analysis.
---

# Investment Trend Analysis

Analyze one local Qieman run packet. Produce a personal research trend report, not investment advice.

## Required Workflow

1. Read `input/portfolio-context.json`, `skill/domain-rules.md`, `skill/output-contract.md`, `skill/examples.json`, and `schema/trend-report.schema.json`.
2. Build the report from local portfolio facts first, then platform or manager signals, then reliable external signals if the selected agent has access.
3. Return only one JSON object matching `schema/trend-report.schema.json`.
4. Write the final JSON to `output/trend-report.json`.

## Boundaries

- Do not execute trades, mutate files outside `output/trend-report.json`, or guarantee returns.
- Do not invent sources. If external information is unavailable, set `externalSignalStatus` to `unavailable` or `partial`.
- Use conditional Chinese wording such as `可关注`, `等待确认`, `若...则...`; avoid mandatory buy or sell language.
- Use `skill/domain-rules.md` for the analysis workflow and `skill/output-contract.md` for required report behavior.
