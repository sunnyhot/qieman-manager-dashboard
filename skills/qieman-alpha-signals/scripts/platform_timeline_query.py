#!/usr/bin/env python3
from __future__ import annotations

import argparse
from typing import Any, Dict, List

from _qieman_skill_common import (
    ensure_project_dir,
    in_date_range,
    load_dashboard_module,
    parse_date,
    print_json,
    resolve_project_dir,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="按标的查询平台调仓时间线")
    parser.add_argument("--prod-code", default="LONG_WIN", help="产品代码")
    parser.add_argument("--side", choices=("all", "buy", "sell"), default="all", help="方向过滤")
    parser.add_argument("--asset", default="", help="标的关键字过滤")
    parser.add_argument("--since", default="", help="起始日期 YYYY-MM-DD")
    parser.add_argument("--until", default="", help="结束日期 YYYY-MM-DD")
    parser.add_argument("--limit-assets", type=int, default=20, help="返回标的上限")
    parser.add_argument("--limit-entries", type=int, default=10, help="每个标的返回动作上限")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


def filter_actions(dashboard, actions: List[Dict[str, Any]], args: argparse.Namespace) -> List[Dict[str, Any]]:
    side = args.side.strip() or "all"
    since = parse_date(args.since) if args.since else None
    until = parse_date(args.until) if args.until else None

    rows: List[Dict[str, Any]] = []
    for action in actions:
        action_side = dashboard.normalize_text(action.get("side"))
        if side != "all" and action_side != side:
            continue
        action_date = dashboard.normalize_date_text(
            dashboard.normalize_text(action.get("txn_date") or action.get("created_at"))
        )
        if (since or until) and not in_date_range(action_date, since, until):
            continue
        rows.append(action)
    return rows


def build_rows(dashboard, timeline: List[Dict[str, Any]], args: argparse.Namespace) -> List[Dict[str, Any]]:
    asset_filter = args.asset.strip().lower()
    rows: List[Dict[str, Any]] = []
    for item in timeline:
        label = dashboard.normalize_text(item.get("label"))
        if asset_filter and asset_filter not in label.lower():
            continue
        entries = [entry for entry in list(item.get("entries") or []) if isinstance(entry, dict)]
        rows.append(
            {
                "label": label,
                "event_count": dashboard.safe_int(item.get("event_count")),
                "buy_count": dashboard.safe_int(item.get("buy_count")),
                "sell_count": dashboard.safe_int(item.get("sell_count")),
                "latest_time": dashboard.normalize_text(item.get("latest_time")),
                "entries": [
                    {
                        "date": dashboard.normalize_text(entry.get("txn_date") or entry.get("created_at")),
                        "action": dashboard.normalize_text(entry.get("action")),
                        "side": dashboard.normalize_text(entry.get("side")),
                        "action_title": dashboard.normalize_text(entry.get("action_title")),
                        "fund_code": dashboard.normalize_text(entry.get("fund_code")),
                        "trade_unit": dashboard.safe_int(entry.get("trade_unit")),
                        "trade_valuation": dashboard.safe_float(entry.get("trade_valuation")),
                        "current_valuation": dashboard.safe_float(entry.get("current_valuation")),
                        "valuation_change_pct": dashboard.safe_float(entry.get("valuation_change_pct")),
                        "article_url": dashboard.normalize_text(entry.get("article_url")),
                    }
                    for entry in entries[: max(1, args.limit_entries)]
                ],
            }
        )
        if len(rows) >= max(1, args.limit_assets):
            break
    return rows


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    dashboard = load_dashboard_module(project_dir)

    data = dashboard.fetch_platform_trade_data(args.prod_code)
    if not data.get("supported"):
        raise SystemExit(dashboard.normalize_text(data.get("error")) or "平台调仓接口不可用")

    actions = [item for item in list(data.get("actions") or []) if isinstance(item, dict)]
    filtered = filter_actions(dashboard, actions, args)
    timeline = dashboard.build_platform_timeline_from_actions(filtered)
    rows = build_rows(dashboard, timeline, args)

    payload = {
        "prod_code": args.prod_code,
        "side": args.side,
        "since": args.since,
        "until": args.until,
        "count": len(rows),
        "items": rows,
    }
    if args.json:
        print_json(payload)
    else:
        print(f"prod={args.prod_code} | assets={payload['count']}")
        for item in rows:
            print(
                f"{item['label']} | events={item['event_count']} "
                f"(buy={item['buy_count']}, sell={item['sell_count']}) | latest={item['latest_time']}"
            )
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
