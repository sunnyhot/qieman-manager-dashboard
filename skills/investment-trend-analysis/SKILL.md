---
name: investment-trend-analysis
description: Analyze a local investment portfolio trend packet and return a strict JSON trend report. Use when an agent receives qieman-manager-dashboard portfolio context, platform signals, watch events, and a trend-report schema and must produce structured portfolio, horizon, sector, key-asset, evidence, warning, and action-candidate analysis.
---

# Investment Trend Analysis

Read the provided run packet files. Produce only JSON matching `schema/trend-report.schema.json`.

Use `skill/domain-rules.md` for portfolio interpretation rules and `skill/output-contract.md` for required report behavior. Do not execute trades, mutate files outside `output/trend-report.json`, or guarantee returns.
