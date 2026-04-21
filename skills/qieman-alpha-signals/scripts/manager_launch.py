#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from typing import Any, Dict, List

from _qieman_skill_common import ensure_project_dir, in_date_range, parse_date, resolve_project_dir
from _qieman_skill_common import load_project_module


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="主理人发车（平台调仓）查询")
    parser.add_argument("--prod-code", default="LONG_WIN", help="产品代码，默认 LONG_WIN")
    parser.add_argument("--side", choices=("all", "buy", "sell"), default="all", help="动作方向")
    parser.add_argument("--since", default="", help="起始日期 YYYY-MM-DD")
    parser.add_argument("--until", default="", help="结束日期 YYYY-MM-DD")
    parser.add_argument("--limit", type=int, default=20, help="最多输出多少条，默认 20")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    parser.add_argument("--project-dir", default="", help="可选，项目目录；默认读 QIEMAN_PROJECT_DIR")
    return parser


def filter_actions(
    dashboard,
    actions: List[Dict[str, Any]],
    side: str,
    since: str,
    until: str,
    limit: int,
) -> List[Dict[str, Any]]:
    target_side = side.strip() or "all"
    since_date = parse_date(since) if since else None
    until_date = parse_date(until) if until else None

    filtered: List[Dict[str, Any]] = []
    for action in actions:
        action_side = dashboard.normalize_text(action.get("side"))
        if target_side != "all" and action_side != target_side:
            continue
        action_date = dashboard.normalize_date_text(
            dashboard.normalize_text(action.get("txn_date") or action.get("created_at"))
        )
        if (since_date or until_date) and not in_date_range(action_date, since_date, until_date):
            continue
        filtered.append(action)
        if len(filtered) >= max(1, limit):
            break
    return filtered


def build_output_row(dashboard, action: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "date": dashboard.normalize_text(action.get("txn_date") or action.get("created_at")),
        "adjustment_id": dashboard.safe_int(action.get("adjustment_id")),
        "action": dashboard.normalize_text(action.get("action")),
        "action_title": dashboard.normalize_text(action.get("action_title")),
        "side": dashboard.normalize_text(action.get("side")),
        "fund_code": dashboard.normalize_text(action.get("fund_code")),
        "fund_name": dashboard.normalize_text(action.get("fund_name")),
        "trade_unit": dashboard.safe_int(action.get("trade_unit")),
        "trade_valuation": dashboard.safe_float(action.get("trade_valuation")),
        "trade_valuation_date": dashboard.normalize_text(action.get("trade_valuation_date")),
        "current_valuation": dashboard.safe_float(action.get("current_valuation")),
        "current_valuation_source": dashboard.normalize_text(action.get("current_valuation_source")),
        "current_valuation_time": dashboard.normalize_text(action.get("current_valuation_time")),
        "valuation_change_pct": dashboard.safe_float(action.get("valuation_change_pct")),
        "article_url": dashboard.normalize_text(action.get("article_url")),
    }


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    dashboard = load_project_module(project_dir, "dashboard_server")

    data = dashboard.fetch_platform_trade_data(args.prod_code)
    if not data.get("supported"):
        raise SystemExit(dashboard.normalize_text(data.get("error")) or "平台调仓接口不可用")

    actions = [item for item in list(data.get("actions") or []) if isinstance(item, dict)]
    picked = filter_actions(
        dashboard=dashboard,
        actions=actions,
        side=args.side,
        since=args.since,
        until=args.until,
        limit=args.limit,
    )
    rows = [build_output_row(dashboard, action) for action in picked]

    if args.json:
        payload = {
            "prod_code": args.prod_code,
            "side": args.side,
            "since": args.since,
            "until": args.until,
            "count": len(rows),
            "items": rows,
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    print(f"产品 {args.prod_code} | side={args.side} | 返回 {len(rows)} 条")
    for row in rows:
        trade_text = dashboard.format_decimal(row["trade_valuation"]) if row["trade_valuation"] > 0 else "—"
        current_text = dashboard.format_decimal(row["current_valuation"]) if row["current_valuation"] > 0 else "—"
        line = (
            f"[{row['date']}] #{row['adjustment_id']} {row['action_title']} "
            f"| 调仓估值 {trade_text} | 当前{row['current_valuation_source']} {current_text}"
        )
        if row["trade_valuation"] > 0 and row["current_valuation"] > 0:
            line += f" | 变化 {dashboard.format_signed_percent(row['valuation_change_pct'])}"
        print(line)
    return 0


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
