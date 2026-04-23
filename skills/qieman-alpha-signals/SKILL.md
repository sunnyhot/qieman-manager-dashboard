---
name: qieman-alpha-signals
description: Atomic Qieman toolkit for OpenClaw and Hermes with fine-grained commands across auth status, followed users, group resolution, following/group/space/public speech feeds, post comments, platform launch actions, holdings, timelines, valuation lookup, snapshot index/read, and signal extraction. Use when agents need single-purpose Chinese investment data operations without branching logic.
---

# Qieman Alpha Signals

Use this skill as a single-purpose command toolkit for the Qieman project at `/Users/xufan65/Documents/Codex/2026-04-17-new-chat`.

## Quick Start

```bash
export QIEMAN_PROJECT_DIR=/Users/xufan65/Documents/Codex/2026-04-17-new-chat
```

All scripts support `--json` for machine-readable output.

## One-Click Full Project Runtime

```bash
# 默认即 start，拉起 dashboard + 前端页面
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/project_runtime.py --json

# 启动并自动打开前端页面
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/project_runtime.py --open-browser --json

# 查看状态 / 停止
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/project_runtime.py --action status --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/project_runtime.py --action stop --json
```

## Incremental Watch (New Trades + New Forum Posts)

```bash
# 首次运行默认建基线，不提醒历史数据
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/updates_watch.py \
  --prod-code LONG_WIN \
  --manager-name "ETF拯救世界" \
  --forum-mode auto \
  --json

# 后续轮询：仅返回新增调仓/新增发言
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/updates_watch.py \
  --prod-code LONG_WIN \
  --manager-name "ETF拯救世界" \
  --forum-mode auto \
  --json
```

## Routing Guide

1. Need one-click full project runtime (frontend page): run `project_runtime.py`.
2. Need auth/user identity: run `auth_status.py`.
3. Need people/group context: run `following_users_query.py`, `my_groups_query.py`, `group_lookup.py`.
4. Need posts/speech source data: run one of `following_posts_query.py`, `group_posts_query.py`, `space_items_query.py`, `public_items_query.py`.
5. Need comments for a post: run `post_comments_query.py`.
6. Need platform adjustments/positions: run `manager_launch.py`, `platform_holdings_query.py`, `platform_timeline_query.py`, `platform_monthly_overview_query.py`.
7. Need near-real-time incremental watch for new trades/posts: run `updates_watch.py`.
8. Need valuation only: run `valuation_query.py`.
9. Need local snapshots: run `snapshot_index.py`, `snapshot_read.py`.
10. Need signal inference from posts/snapshots: run `signal_extract.py`.

## Atomic Commands

### Full Project Runtime

- `scripts/project_runtime.py`
  - `--action start|status|stop|restart`
  - one-click launch dashboard + frontend page URL
  - supports background mode with PID/log management

### Identity and Context

- `scripts/auth_status.py`
- `scripts/following_users_query.py`
- `scripts/my_groups_query.py`
- `scripts/group_lookup.py`

### Speech and Content

- `scripts/following_posts_query.py`
- `scripts/group_posts_query.py`
- `scripts/space_items_query.py`
- `scripts/public_items_query.py`
- `scripts/post_comments_query.py`

### Platform Trading and Valuation

- `scripts/manager_launch.py`
- `scripts/platform_holdings_query.py`
- `scripts/platform_timeline_query.py`
- `scripts/platform_monthly_overview_query.py`
- `scripts/valuation_query.py`

### Snapshot and Signal Processing

- `scripts/snapshot_index.py`
- `scripts/snapshot_read.py`
- `scripts/signal_extract.py`

### Incremental Monitoring

- `scripts/updates_watch.py`
  - watches both platform actions and forum speech
  - stateful deduplication via local `output/watch-state-*.json`
  - first run builds baseline (no historical alert), next runs return only new items
  - `auto` forum mode: tries `following-posts`, falls back to `public` when auth is unavailable

### Compatibility Wrapper

- `scripts/manager_speech.py` remains for multi-mode compatibility, but prefer atomic scripts above for agent workflows.

## Safety and Reliability

1. Prefer `--cookie-file` or local `qieman.cookie`; avoid printing raw cookie values.
2. Always return absolute dates (`YYYY-MM-DD` or full datetime) in summaries.
3. Prefer `--json` in autonomous agent flows.
4. Use atomic scripts instead of one broad script when the task can be expressed as one operation.

## Resources

- Capability matrix and examples: [references/capabilities.md](/Users/xufan65/.codex/skills/qieman-alpha-signals/references/capabilities.md)
- Scripts directory: [/Users/xufan65/.codex/skills/qieman-alpha-signals/scripts](/Users/xufan65/.codex/skills/qieman-alpha-signals/scripts)
