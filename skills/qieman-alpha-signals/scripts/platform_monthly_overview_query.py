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
    parser = argparse.ArgumentParser(description="按月汇总平台调仓频率（买入/卖出分开）")
    parser.add_argument("--prod-code", default="LONG_WIN", help="产品代码")
    parser.add_argument("--side", choices=("all", "buy", "sell"), default="all", help="方向过滤")
    parser.add_argument("--since", default="", help="起始日期 YYYY-MM-DD")
    parser.add_argument("--until", default="", help="结束日期 YYYY-MM-DD")
    parser.add_argument("--months", type=int, default=12, help="最多返回最近几个月，默认 12")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


def filter_actions(dashboard, actions: List[Dict[str, Any]], args: argparse.Namespace) -> List[Dict[str, Any]]:
    target_side = args.side.strip() or "all"
    since = parse_date(args.since) if args.since else None
    until = parse_date(args.until) if args.until else None

    filtered: List[Dict[str, Any]] = []
    for action in actions:
        side = dashboard.normalize_text(action.get("side"))
        if target_side != "all" and side != target_side:
            continue
        date_text = dashboard.platform_action_date_text(action)
        if (since or until) and not in_date_range(date_text, since, until):
            continue
        filtered.append(action)
    return filtered


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    dashboard = load_dashboard_module(project_dir)

    data = dashboard.fetch_platform_trade_data(args.prod_code)
    if not data.get("supported"):
        raise SystemExit(dashboard.normalize_text(data.get("error")) or "平台调仓接口不可用")

    actions = [item for item in list(data.get("actions") or []) if isinstance(item, dict)]
    filtered_actions = filter_actions(dashboard, actions, args)
    overview = dashboard.build_platform_monthly_overview(
        filtered_actions,
        limit_months=max(1, int(args.months)),
    )

    payload = {
        "prod_code": args.prod_code,
        "side": args.side,
        "since": args.since,
        "until": args.until,
        "months": max(1, int(args.months)),
        "summary": {
            "month_count": dashboard.safe_int(overview.get("month_count")),
            "total_count": dashboard.safe_int(overview.get("total_count")),
            "buy_count": dashboard.safe_int(overview.get("buy_count")),
            "sell_count": dashboard.safe_int(overview.get("sell_count")),
            "avg_total_per_month": dashboard.safe_float(overview.get("avg_total_per_month")),
            "avg_buy_per_month": dashboard.safe_float(overview.get("avg_buy_per_month")),
            "avg_sell_per_month": dashboard.safe_float(overview.get("avg_sell_per_month")),
        },
        "items": [item for item in list(overview.get("items") or []) if isinstance(item, dict)],
    }

    if args.json:
        print_json(payload)
        return 0

    summary = payload["summary"]
    print(
        f"prod={args.prod_code} side={args.side} "
        f"| months={summary['month_count']} total={summary['total_count']} "
        f"(buy={summary['buy_count']}, sell={summary['sell_count']})"
    )
    for item in payload["items"]:
        month = dashboard.normalize_text(item.get("month"))
        total_count = dashboard.safe_int(item.get("total_count"))
        buy_count = dashboard.safe_int(item.get("buy_count"))
        sell_count = dashboard.safe_int(item.get("sell_count"))
        active_day_count = dashboard.safe_int(item.get("active_day_count"))
        freq = dashboard.safe_float(item.get("trades_per_active_day"))
        print(
            f"{month} | total={total_count} buy={buy_count} sell={sell_count} "
            f"| active_days={active_day_count} | per_active_day={freq:.2f}"
        )
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
