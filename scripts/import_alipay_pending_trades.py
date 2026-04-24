#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
import uuid
from pathlib import Path
from typing import Any


MANUAL_CODES = {
    "华泰柏瑞纳斯达克100ETF联接(QDII)A": "019524",
    "摩根标普500指数(QDII)A": "017641",
    "广发全球医疗保健指数(QDII)A": "000369",
    "易方达中证红利ETF联接A": "009051",
    "国泰中证畜牧养殖ETF联接A": "012724",
    "易方达中概互联网ETF联接(QDII)A(人民币份额)": "006327",
    "华夏标普500ETF联接(QDII)A": "018064",
}

FUND_NAME_CACHE: dict[str, str | None] = {}
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)


def app_support_pending_path() -> Path:
    return Path.home() / "Library" / "Application Support" / "QiemanDashboard" / "user-pending-trades.json"


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


def load_known_assets() -> tuple[dict[str, str], dict[str, str]]:
    known_by_name: dict[str, str] = {}
    known_by_code: dict[str, str] = {}
    portfolio_path = Path.home() / "Library" / "Application Support" / "QiemanDashboard" / "user-portfolio.json"
    if portfolio_path.exists():
        try:
            holdings = json.loads(portfolio_path.read_text(encoding="utf-8"))
            for item in holdings:
                display_name = (item.get("displayName") or "").strip()
                fund_code = (item.get("fundCode") or "").strip()
                if display_name and fund_code:
                    known_by_name[normalize_name(display_name)] = fund_code
                    known_by_code[fund_code] = display_name
        except Exception:
            pass
    for name, code in MANUAL_CODES.items():
        known_by_name[normalize_name(name)] = code
        known_by_code[code] = name
    return known_by_name, known_by_code


def resolve_code(name: str, known_codes: dict[str, str]) -> str | None:
    return known_codes.get(normalize_name(name))


def is_fund_code(value: str) -> bool:
    return bool(re.fullmatch(r"\d{5,6}", value.strip()))


def fetch_text(url: str, *, referer: str | None = None) -> str:
    headers = {"User-Agent": USER_AGENT}
    if referer:
        headers["Referer"] = referer
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=12) as response:
        return response.read().decode("utf-8", errors="ignore")


def resolve_name_by_code(code: str) -> str | None:
    if code in FUND_NAME_CACHE:
        return FUND_NAME_CACHE[code]
    name: str | None = None
    try:
        text = fetch_text(f"https://fund.eastmoney.com/pingzhongdata/{code}.js?v=1", referer="https://fund.eastmoney.com/")
        match = re.search(r'var\s+fS_name\s*=\s*"([^"]*)";', text)
        if match:
            name = match.group(1).strip() or None
    except Exception:
        name = None
    FUND_NAME_CACHE[code] = name
    return name


def resolve_asset(value: str, known_codes: dict[str, str], known_names: dict[str, str]) -> tuple[str, str | None]:
    text = value.strip()
    if is_fund_code(text):
        return known_names.get(text) or resolve_name_by_code(text) or text, text
    return text, resolve_code(text, known_codes)


def parse_amount(amount_text: str) -> tuple[float | None, float | None]:
    normalized = amount_text.replace(",", "").strip()
    if normalized.endswith("元"):
        return float(normalized[:-1]), None
    if normalized.endswith("份"):
        return None, float(normalized[:-1])
    return None, None


def parse_line(raw: str, known_codes: dict[str, str], known_names: dict[str, str]) -> dict[str, Any]:
    parts = [part.strip() for part in raw.split("|")]
    if len(parts) < 5:
        raise ValueError(f"行格式不正确：{raw}")

    occurred_at, action_label, fund_part, amount_text, status = parts[:5]
    note = parts[5] if len(parts) >= 6 else None
    fund_name = fund_part
    target_fund_name = None
    fund_code: str | None
    target_fund_code: str | None = None
    if "->" in fund_part:
        left, right = [part.strip() for part in fund_part.split("->", 1)]
        fund_name, fund_code = resolve_asset(left, known_codes, known_names)
        target_fund_name, target_fund_code = resolve_asset(right, known_codes, known_names)
    else:
        fund_name, fund_code = resolve_asset(fund_part, known_codes, known_names)

    amount_value, unit_value = parse_amount(amount_text)
    return {
        "id": str(uuid.uuid4()),
        "occurredAt": occurred_at,
        "actionLabel": action_label,
        "fundName": fund_name,
        "targetFundName": target_fund_name,
        "fundCode": fund_code,
        "targetFundCode": target_fund_code,
        "amountText": amount_text,
        "amountValue": amount_value,
        "unitValue": unit_value,
        "status": status,
        "note": note,
    }


def parse_input(path: Path) -> list[dict[str, Any]]:
    known_codes, known_names = load_known_assets()
    items: list[dict[str, Any]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        items.append(parse_line(line, known_codes, known_names))
    if not items:
        raise ValueError("没有解析到任何买入中记录。")
    return items


def write_output(items: list[dict[str, Any]], output_path: Path, preview_path: Path | None) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")
    if preview_path:
        preview_path.parent.mkdir(parents=True, exist_ok=True)
        preview_path.write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")


def print_summary(items: list[dict[str, Any]], output_path: Path) -> None:
    total_cash = sum(item.get("amountValue") or 0 for item in items)
    cash_count = sum(1 for item in items if item.get("amountValue") is not None)
    unit_count = sum(1 for item in items if item.get("unitValue") is not None)
    print(f"已导入 {len(items)} 条买入中记录")
    print(f"写入文件: {output_path}")
    print(f"待确认金额: {total_cash:.2f}")
    print(f"现金单: {cash_count} | 份额单: {unit_count}")
    print()
    for item in items:
        route = item["fundName"]
        if item.get("targetFundName"):
            route += f" -> {item['targetFundName']}"
        print(f"{item['occurredAt']} | {item['actionLabel']} | {route} | {item['amountText']} | {item['status']}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="把支付宝买入中/交易进行中的记录导入 QiemanDashboard。")
    parser.add_argument("--input", required=True, help="输入文本文件，每行格式：时间 | 动作 | 基金名 | 金额/份额 | 状态")
    parser.add_argument("--output", default=str(app_support_pending_path()), help="输出 user-pending-trades.json 路径")
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
