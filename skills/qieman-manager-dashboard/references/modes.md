# Qieman Skill Modes

## Project Path

Default project path:

`/Users/xufan65/Documents/Codex/2026-04-17-new-chat`

Override with:

`QIEMAN_PROJECT_DIR=/custom/path`

## Launcher Commands

### Dashboard

```bash
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py dashboard --open
```

Use when the user wants:

- the local web UI
- platform trades and holdings
- forum details and comments

### Public Content Search

```bash
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py public -- --query "长赢计划" --author "ETF拯救世界" --markdown
```

Use when the user wants:

- public content pages
- keyword search across Qieman content pages
- author-filtered public posts

### Community Flow

```bash
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py community -- --prod-code LONG_WIN --pages 3 --markdown
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py community -- --mode following-posts --user-name "ETF拯救世界" --pages 5 --markdown
```

Use when the user wants:

- group-manager
- following-posts
- following-users
- my-groups
- space-items
- keyword/date filtered community posts

### Auth Check

```bash
python /Users/xufan65/.codex/skills/qieman-manager-dashboard/scripts/qieman_tool.py auth-check
```

Default cookie path:

`/Users/xufan65/Documents/Codex/2026-04-17-new-chat/qieman.cookie`

## Dashboard Notes

The dashboard currently exposes:

- `/`
  Home summary
- `/platform`
  Platform trades, holdings, cost and valuation
- `/forum`
  Forum posts and comments
- `/timeline`
  Asset-level trade timeline

Dashboard behavior updates:

- Home keeps three focus sections: compact real-time query, platform trades, forum speech.
- Platform trades now include a monthly buy/sell frequency overview for quick cadence checks.
- `验证登录态` uses async auth check and transient feedback (auto-hide + manual close), so auth messages do not stay pinned.

## Output Notes

- Local runtime data is written under `output/`.
- Do not expose raw `qieman.cookie`.
- When discussing valuation, mention that current estimate may be intraday estimate or latest NAV fallback.
