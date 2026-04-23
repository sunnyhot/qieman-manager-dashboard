#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
import uuid
from pathlib import Path
from typing import Any


MANUAL_CODES = {
    "易方达恒生科技ETF联接(QDII)A": "013308",
    "华夏中证A500ETF联接A": "022430",
    "华夏国证自由现金流ETF联接A": "023917",
    "摩根标普500指数(QDII)A": "017641",
    "易方达中证红利ETF联接A": "009051",
    "华泰柏瑞纳斯达克100ETF联接(QDII)A": "019524",
    "广发全球医疗保健指数(QDII)A": "000369",
}


def app_support_plan_path() -> Path:
    return Path.home() / "Library" / "Application Support" / "QiemanDashboard" / "user-investment-plans.json"


def normalize_name(value: str) -> str:
    text = value.upper().strip()
    replacements = {
        "（": "(",
        "）": ")",
        "人民币份额": "",
        "发起式": "",
        "人民币A": "A",
        "人民币C": "C",
        "人民币": "",
        "Ａ": "A",
        "Ｃ": "C",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    return re.sub(r"[\s·•\-_/]", "", text)


def load_known_codes() -> dict[str, str]:
    known: dict[str, str] = {}
    for file_name in ("user-portfolio.json", "user-pending-trades.json"):
        path = Path.home() / "Library" / "Application Support" / "QiemanDashboard" / file_name
        if not path.exists():
            continue
        try:
            rows = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        for item in rows:
            fund_name = (item.get("displayName") or item.get("fundName") or "").strip()
            fund_code = (item.get("fundCode") or "").strip()
            if fund_name and fund_code:
                known[normalize_name(fund_name)] = fund_code
    for name, code in MANUAL_CODES.items():
        known[normalize_name(name)] = code
    return known


def parse_money(text: str) -> tuple[float | None, float | None]:
    normalized = text.replace(",", "").replace("元", "").strip()
    if "~" in normalized:
        start, end = [part.strip() for part in normalized.split("~", 1)]
        return float(start), float(end)
    if normalized:
        value = float(normalized)
        return value, value
    return None, None


def parse_int(text: str) -> int | None:
    text = text.strip()
    if not text:
        return None
    return int(text)


def parse_cumulative_amount(text: str) -> float | None:
    text = text.replace(",", "").replace("元", "").strip()
    return float(text) if text else None


def resolve_code(name: str, known_codes: dict[str, str]) -> str | None:
    return known_codes.get(normalize_name(name))


def parse_input(path: Path) -> list[dict[str, Any]]:
    known_codes = load_known_codes()
    items: list[dict[str, Any]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split("|")]
        if len(parts) < 8:
            raise ValueError(
                f"行格式不正确：{line}\n应为：计划类型 | 基金名 | 计划说明 | 买入金额 | 已投期数 | 累计定投 | 支付方式 | 下次时间 [| 状态] [| 备注]"
            )
        plan_type, fund_name, schedule_text, amount_text, periods_text, cumulative_text, payment_method, next_execution_date = parts[:8]
        status = parts[8] if len(parts) >= 9 else "进行中"
        note = parts[9] if len(parts) >= 10 else None
        min_amount, max_amount = parse_money(amount_text)
        items.append(
            {
                "id": str(uuid.uuid4()),
                "planTypeLabel": plan_type,
                "fundName": fund_name,
                "fundCode": resolve_code(fund_name, known_codes),
                "scheduleText": schedule_text,
                "amountText": amount_text,
                "minAmount": min_amount,
                "maxAmount": max_amount,
                "investedPeriods": parse_int(periods_text),
                "cumulativeInvestedAmount": parse_cumulative_amount(cumulative_text),
                "paymentMethod": payment_method,
                "nextExecutionDate": next_execution_date,
                "status": status,
                "note": note,
            }
        )
    if not items:
        raise ValueError("没有解析到任何定投计划。")
    return items


def write_output(items: list[dict[str, Any]], output_path: Path, preview_path: Path | None) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")
    if preview_path:
        preview_path.parent.mkdir(parents=True, exist_ok=True)
        preview_path.write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")


def print_summary(items: list[dict[str, Any]], output_path: Path) -> None:
    smart_count = sum(1 for item in items if "智能" in item["planTypeLabel"])
    daily_count = sum(1 for item in items if "每日" in item["scheduleText"])
    weekly_count = sum(1 for item in items if "每周" in item["scheduleText"])
    total_cumulative = sum((item.get("cumulativeInvestedAmount") or 0) for item in items)
    upcoming_dates = [item["nextExecutionDate"] for item in items if item.get("nextExecutionDate")]
    next_execution = min(upcoming_dates) if upcoming_dates else "无后续执行时间"

    print(f"已导入 {len(items)} 条定投计划")
    print(f"写入文件: {output_path}")
    print(f"智能定投: {smart_count} | 日定投: {daily_count} | 周定投: {weekly_count}")
    print(f"累计定投: {total_cumulative:.2f}")
    print(f"最近执行: {next_execution}")
    print()
    for item in items:
        print(
            f"{item['planTypeLabel']} | {item['fundName']} | {item['scheduleText']} | "
            f"{item['amountText']} | {item['nextExecutionDate']}"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="把支付宝定投计划导入 QiemanDashboard。")
    parser.add_argument("--input", required=True, help="输入文本文件")
    parser.add_argument("--output", default=str(app_support_plan_path()), help="输出 user-investment-plans.json 路径")
    parser.add_argument("--preview", help="额外输出解析预览 JSON")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()
    preview_path = Path(args.preview).expanduser().resolve() if args.preview else None
    try:
        items = parse_input(input_path)
        write_output(items, output_path, preview_path)
        print_summary(items, output_path)
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"导入失败: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
