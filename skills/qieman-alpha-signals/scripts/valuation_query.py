#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, List

from _qieman_skill_common import (
    ensure_project_dir,
    load_project_module,
    parse_csv_codes,
    resolve_project_dir,
    unique_codes,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="估值查询：支持当前估值和指定日期净值回看")
    parser.add_argument("--fund-code", action="append", default=[], help="基金代码，可重复")
    parser.add_argument("--fund-codes", default="", help="逗号分隔基金代码")
    parser.add_argument("--at-date", default="", help="可选，回看日期 YYYY-MM-DD")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    parser.add_argument("--project-dir", default="", help="可选，项目目录；默认读 QIEMAN_PROJECT_DIR")
    return parser


def parse_codes(args: argparse.Namespace) -> List[str]:
    codes = list(args.fund_code or [])
    if args.fund_codes:
        codes.extend(parse_csv_codes(args.fund_codes))
    return unique_codes(codes)


def run(args: argparse.Namespace) -> int:
    codes = parse_codes(args)
    if not codes:
        raise SystemExit("请至少提供一个基金代码：--fund-code 021550")

    project_dir = ensure_project_dir(resolve_project_dir(args.project_dir))
    dashboard = load_project_module(project_dir, "dashboard_server")

    histories, quotes = dashboard.preload_fund_market_data(codes)
    results: List[Dict[str, Any]] = []

    for code in codes:
        history = histories.get(code) or {}
        quote = quotes.get(code) or {}
        current_value = dashboard.safe_float(quote.get("price"))
        current_time = dashboard.normalize_text(quote.get("price_time") or quote.get("official_nav_date"))
        current_source = dashboard.normalize_text(quote.get("price_source_label")) or "未知"

        at_value = 0.0
        at_actual_date = ""
        if args.at_date:
            entry = dashboard.lookup_fund_nav_by_date(history, args.at_date)
            at_value = dashboard.safe_float(entry.get("nav"))
            at_actual_date = dashboard.normalize_text(entry.get("date"))

        change_pct = 0.0
        if at_value > 0 and current_value > 0:
            change_pct = round((current_value / at_value - 1.0) * 100.0, 2)

        results.append(
            {
                "fund_code": code,
                "fund_name": dashboard.normalize_text(quote.get("fund_name") or history.get("fund_name")),
                "current_valuation": round(current_value, 4) if current_value > 0 else 0.0,
                "current_source": current_source,
                "current_time": current_time,
                "valuation_at_date": round(at_value, 4) if at_value > 0 else 0.0,
                "valuation_at_actual_date": at_actual_date,
                "change_pct": change_pct,
            }
        )

    if args.json:
        print(json.dumps({"count": len(results), "items": results}, ensure_ascii=False, indent=2))
        return 0

    for item in results:
        current_text = (
            f"{dashboard.format_decimal(item['current_valuation'])}"
            if item["current_valuation"] > 0
            else "—"
        )
        line = f"[{item['fund_code']}] {item['fund_name'] or '未知基金'} | 当前{item['current_source']} {current_text}"
        if item["current_time"]:
            line += f" ({item['current_time']})"
        if args.at_date:
            at_text = (
                f"{dashboard.format_decimal(item['valuation_at_date'])}"
                if item["valuation_at_date"] > 0
                else "—"
            )
            line += f" | {args.at_date}净值 {at_text}"
            if item["valuation_at_actual_date"] and item["valuation_at_actual_date"] != args.at_date:
                line += f" (实际 {item['valuation_at_actual_date']})"
            if item["valuation_at_date"] > 0 and item["current_valuation"] > 0:
                line += f" | 变化 {dashboard.format_signed_percent(item['change_pct'])}"
        print(line)
    return 0


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
