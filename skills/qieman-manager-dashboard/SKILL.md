---
name: qieman-manager-dashboard
description: Qieman manager/community crawler and local dashboard for inspecting manager posts, comments, platform rebalancing, holdings, average cost, and valuation. Use when Codex, OpenClaw, or Hermes needs to launch or reuse the local Qieman dashboard, refresh current Qieman data, validate Qieman login cookies, pull public or logged-in manager feeds, or analyze platform holdings and trades for managers such as ETF拯救世界.
---

# Qieman Manager Dashboard

Use this skill as the control layer for the Qieman project at `/Users/xufan65/Documents/Codex/2026-04-17-new-chat`.

## Quick Start

Use the launcher script for the common entry points:

```bash
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py dashboard --open
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py community -- --mode following-posts --user-name "ETF拯救世界" --pages 5 --markdown
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py public -- --query "长赢计划" --author "ETF拯救世界" --markdown
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py auth-check
```

If the project is moved, set `QIEMAN_PROJECT_DIR` before using this skill.

## Workflow

1. Resolve the project path.
   Use the launcher script. It defaults to `/Users/xufan65/Documents/Codex/2026-04-17-new-chat`.
2. Choose the data source.
   Use `public` for public content pages.
   Use `community` for group-manager, following-posts, following-users, my-groups, and space-items.
   Use `dashboard` when the user wants the browser UI.
3. Reuse local state instead of rebuilding it.
   The dashboard already knows how to show platform trades, holdings, comments, average cost, and valuation.
4. Prefer safe local files for auth.
   Use `qieman.cookie` or `QIEMAN_COOKIE`; do not print raw cookie contents in responses.

## Common Tasks

### Launch the local dashboard

```bash
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py dashboard --open
```

The dashboard listens on `http://127.0.0.1:8765`.

### Validate the Qieman login state

```bash
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py auth-check
```

This checks the local cookie file by default. Override with `--cookie-file`.

### Pull logged-in following posts

```bash
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py community -- --mode following-posts --user-name "ETF拯救世界" --pages 5 --markdown
```

### Pull public manager posts

```bash
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py community -- --prod-code LONG_WIN --pages 3 --markdown
```

### Search public content pages

```bash
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py public -- --query "长期指数投资" --markdown
```

## Important Notes

- Platform trades come from the Qieman platform adjustments endpoint, not from forum text matching.
- Platform panel includes a month-level trading overview:
  - monthly buy/sell frequency split
  - active trade days and per-active-day frequency
  - rolling 12-month summary metrics
- Holdings analysis in the dashboard shows:
  - asset classification
  - current units
  - average cost
  - current estimate or latest NAV fallback
  - relative gain/loss versus average cost
- Average cost is reconstructed from platform trade history plus historical NAV backfill using a moving-average method.
- Current valuation prefers Eastmoney intraday estimate and falls back to the latest official NAV when intraday data is unavailable.
- Login validation in dashboard is non-sticky:
  - validate button runs async `/api/check-auth`
  - feedback is dismissible and auto-hides after a short delay
- `output/` contains local runtime data; treat it as working data, not source code.

## Resources

- Read [references/modes.md](/Users/xufan65/.codex/skills/qieman-manager-dashboard/references/modes.md) for task mapping, commands, and output expectations.
- Use [scripts/qieman_tool.py](/Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py) instead of reconstructing long commands by hand when possible.
