# Capability Matrix

## Full Project Runtime (Frontend Included)

| Script | Purpose | Typical Args |
|---|---|---|
| `project_runtime.py` | One-click run/stop/status of dashboard + frontend page | `--action start --open-browser --json` |

## Identity and Context

| Script | Purpose | Typical Args |
|---|---|---|
| `auth_status.py` | Validate login and return auth user profile | `--json` |
| `following_users_query.py` | List followed managers/users | `--pages 5 --page-size 50 --json` |
| `my_groups_query.py` | List joined community groups | `--json` |
| `group_lookup.py` | Resolve `groupId` from `prod_code`/`manager_name`/URL | `--prod-code LONG_WIN --with-group-info --json` |

## Speech and Content

| Script | Purpose | Typical Args |
|---|---|---|
| `following_posts_query.py` | Fetch login-only following feed posts | `--user-name "ETF拯救世界" --pages 5 --json` |
| `group_posts_query.py` | Fetch public group manager posts | `--prod-code LONG_WIN --pages 5 --json` |
| `space_items_query.py` | Fetch personal space posts | `--space-user-id 123456 --pages 5 --json` |
| `public_items_query.py` | Crawl public qieman content pages | `--query "长赢计划" --author "ETF拯救世界" --json` |
| `post_comments_query.py` | Fetch comments for a specific post | `--post-id 73567 --sort-type hot --json` |

## Platform Trading and Valuation

| Script | Purpose | Typical Args |
|---|---|---|
| `manager_launch.py` | Fetch platform buy/sell actions with trade-vs-current valuation | `--prod-code LONG_WIN --side all --limit 20 --json` |
| `platform_holdings_query.py` | Fetch current holdings with cost, valuation, P/L | `--prod-code LONG_WIN --json` |
| `platform_timeline_query.py` | Fetch per-asset action timeline | `--prod-code LONG_WIN --side all --json` |
| `platform_monthly_overview_query.py` | Fetch month-level trade frequency split (buy vs sell) | `--prod-code LONG_WIN --months 12 --json` |
| `valuation_query.py` | Fetch fund valuation now and optional date-point valuation | `--fund-codes 021550,001052 --at-date 2026-04-16 --json` |

## Incremental Monitoring

| Script | Purpose | Typical Args |
|---|---|---|
| `updates_watch.py` | Watch new platform actions and new forum posts with local dedup state | `--prod-code LONG_WIN --manager-name "ETF拯救世界" --forum-mode auto --json` |

## Snapshot and Signal Processing

| Script | Purpose | Typical Args |
|---|---|---|
| `snapshot_index.py` | List local snapshots in `output/` | `--limit 30 --json` |
| `snapshot_read.py` | Read one snapshot metadata + preview records | `--latest --preview 10 --json` |
| `signal_extract.py` | Extract high-confidence buy/sell signals from snapshot/JSON | `--latest --json` |

## Compatibility Wrapper

| Script | Purpose | Typical Args |
|---|---|---|
| `manager_speech.py` | Multi-mode speech wrapper (legacy convenience) | `--mode following-posts --user-name "ETF拯救世界" --extract-signals --json` |

## Command Examples

```bash
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/project_runtime.py --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/project_runtime.py --action start --open-browser --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/project_runtime.py --action status --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/project_runtime.py --action stop --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/auth_status.py --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/group_lookup.py --prod-code LONG_WIN --with-group-info --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/following_posts_query.py --user-name "ETF拯救世界" --pages 3 --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/post_comments_query.py --post-id 73567 --sort-type latest --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/manager_launch.py --prod-code LONG_WIN --since 2026-04-01 --until 2026-04-21 --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/platform_monthly_overview_query.py --prod-code LONG_WIN --months 12 --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/updates_watch.py --prod-code LONG_WIN --manager-name "ETF拯救世界" --forum-mode auto --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/platform_holdings_query.py --prod-code LONG_WIN --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/snapshot_index.py --search ETF拯救世界 --json
python /Users/xufan65/.codex/skills/qieman-alpha-signals/scripts/signal_extract.py --latest --json
```
