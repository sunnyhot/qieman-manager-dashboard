#!/usr/bin/env python3
from __future__ import annotations

import argparse
from typing import Any, Dict, List

from _qieman_skill_common import ensure_project_dir, load_dashboard_module, print_json, resolve_project_dir


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="查询平台当前持仓（含估值与成本信息）")
    parser.add_argument("--prod-code", default="LONG_WIN", help="产品代码")
    parser.add_argument("--category", default="", help="按分类过滤，如 宽基指数/行业主题/海外权益")
    parser.add_argument("--fund-code", default="", help="按基金代码过滤")
    parser.add_argument("--min-units", type=int, default=1, help="最小份数")
    parser.add_argument("--limit", type=int, default=100, help="返回上限")
    parser.add_argument("--project-dir", default="", help="可选，项目目录")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


def build_rows(dashboard, items: List[Dict[str, Any]], args: argparse.Namespace) -> List[Dict[str, Any]]:
    category_filter = args.category.strip()
    fund_code_filter = args.fund_code.strip()
    rows: List[Dict[str, Any]] = []
    for item in items:
        units = dashboard.safe_int(item.get("current_units"))
        if units < max(0, args.min_units):
            continue
        if fund_code_filter and fund_code_filter != dashboard.normalize_text(item.get("fund_code")):
            continue
        category = dashboard.classify_platform_holding_category(item)
        if category_filter and category_filter != category:
            continue
        rows.append(
            {
                "label": dashboard.normalize_text(item.get("label")),
                "fund_name": dashboard.normalize_text(item.get("fund_name")),
                "fund_code": dashboard.normalize_text(item.get("fund_code")),
                "category": category,
                "current_units": units,
                "avg_cost": dashboard.safe_float(item.get("avg_cost")),
                "current_price": dashboard.safe_float(item.get("current_price")),
                "price_source_label": dashboard.normalize_text(item.get("price_source_label")),
                "price_time": dashboard.normalize_text(item.get("price_time")),
                "position_value": dashboard.safe_float(item.get("position_value")),
                "profit_amount": dashboard.safe_float(item.get("profit_amount")),
                "profit_ratio": dashboard.safe_float(item.get("profit_ratio")),
                "latest_action_title": dashboard.normalize_text(item.get("latest_action_title")),
                "latest_time": dashboard.normalize_text(item.get("latest_time")),
            }
        )
        if len(rows) >= max(1, args.limit):
            break
    return rows


def run(args: argparse.Namespace) -> int:
    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    dashboard = load_dashboard_module(project_dir)

    data = dashboard.fetch_platform_trade_data(args.prod_code)
    if not data.get("supported"):
        raise SystemExit(dashboard.normalize_text(data.get("error")) or "平台调仓接口不可用")

    actions = [item for item in list(data.get("actions") or []) if isinstance(item, dict)]
    raw_holdings = data.get("holdings") if isinstance(data.get("holdings"), dict) else {}
    holdings = dashboard.enrich_platform_holdings_with_pricing(raw_holdings, actions)
    items = [item for item in list(holdings.get("items") or []) if isinstance(item, dict)]
    rows = build_rows(dashboard, items, args)

    payload = {
        "prod_code": args.prod_code,
        "asset_count": dashboard.safe_int(holdings.get("asset_count")),
        "total_units": dashboard.safe_int(holdings.get("total_units")),
        "pricing_summary": holdings.get("pricing_summary") or {},
        "count": len(rows),
        "items": rows,
    }

    if args.json:
        print_json(payload)
    else:
        print(
            f"prod={payload['prod_code']} | assets={payload['asset_count']} | "
            f"total_units={payload['total_units']} | rows={payload['count']}"
        )
        for item in rows:
            current = dashboard.format_decimal(item["current_price"]) if item["current_price"] > 0 else "—"
            print(
                f"{item['label']} ({item['fund_code']}) | {item['category']} | units={item['current_units']} "
                f"| 当前{item['price_source_label'] or '估值'} {current}"
            )
    return 0


def main() -> int:
    return run(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
