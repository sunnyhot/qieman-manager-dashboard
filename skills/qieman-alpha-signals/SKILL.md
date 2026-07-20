---
name: qieman-alpha-signals
description: Native macOS Qieman toolkit with atomic Swift CLI commands for auth, followed users, group/space feeds, comments, platform actions, holdings, valuations, incremental updates, and signal extraction.
---

# Qieman Alpha Signals

Use the native Swift command-line tool in this repository. The toolkit is macOS-only and has no Python or local HTTP-server dependency.

## Setup

Resolve the repository, then use its launcher:

```bash
export QIEMAN_PROJECT_DIR=/path/to/qieman-manager-dashboard
QIEMAN="$QIEMAN_PROJECT_DIR/scripts/qieman"
```

The launcher builds `dist/bin/qieman-cli` on first use. Every data command emits machine-readable JSON with stable snake_case keys.

## Commands

```bash
$QIEMAN auth-status
$QIEMAN following-users --pages 5 --page-size 50
$QIEMAN my-groups
$QIEMAN group-lookup --prod-code LONG_WIN --with-group-info
$QIEMAN following-posts --user-name "ETF拯救世界" --pages 5
$QIEMAN group-posts --prod-code LONG_WIN --pages 5
$QIEMAN space-items --space-user-id 123456 --pages 5
$QIEMAN public-items --prod-code LONG_WIN --query "长赢计划"
$QIEMAN post-comments --post-id 73567 --sort-type hot
$QIEMAN platform-actions --prod-code LONG_WIN --side all --limit 20
$QIEMAN platform-holdings --prod-code LONG_WIN
$QIEMAN platform-timeline --prod-code LONG_WIN
$QIEMAN platform-monthly --prod-code LONG_WIN --months 12
$QIEMAN valuation --fund-codes 021550,001052
$QIEMAN updates-watch --prod-code LONG_WIN --manager-name "ETF拯救世界"
$QIEMAN signal-extract --json-path /path/to/posts.json
```

To open the native application:

```bash
$QIEMAN app-open
```

## Routing

1. Identity and login: `auth-status`.
2. People and group context: `following-users`, `my-groups`, `group-lookup`.
3. Speech sources: `following-posts`, `group-posts`, `space-items`, `public-items`.
4. Comments: `post-comments`.
5. Platform data: `platform-actions`, `platform-holdings`, `platform-timeline`, `platform-monthly`.
6. Current estimates: `valuation`.
7. Incremental polling: `updates-watch`; first run builds a baseline unless `--emit-initial` is supplied.
8. Local JSON inference: `signal-extract`.

## Safety

- Prefer `--cookie-file` or `~/Library/Application Support/QiemanDashboard/qieman.cookie`.
- Never print or summarize raw Cookie values.
- Use absolute dates in user-facing summaries.
- Treat valuation as an estimate unless the returned source indicates a confirmed official NAV.

See [references/capabilities.md](references/capabilities.md) for the command contract.
