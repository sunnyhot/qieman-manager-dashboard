#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


HEADER_ALIASES = {
    "fund_name": {"fundname", "displayname", "name", "基金", "基金名称", "名称", "标的", "fund"},
    "fund_code": {"fundcode", "code", "代码", "基金代码", "标的代码"},
    "asset_type": {"assettype", "资产类型", "类型"},
    "units": {"units", "份额", "持有份额", "数量"},
    "cost_price": {"costprice", "cost", "成本", "成本价"},
    "market_value": {"marketvalue", "amount", "金额", "持仓金额", "持有金额", "当前金额"},
    "profit_amount": {"profitamount", "profit", "持有收益", "收益"},
    "profit_pct": {"profitpct", "收益率", "持有收益率", "收益比例"},
    "occurred_at": {"occurredat", "time", "datetime", "时间", "发生时间"},
    "action": {"action", "actionlabel", "动作", "类型"},
    "target_fund_name": {"targetfundname", "目标基金", "转入基金", "目标标的"},
    "target_fund_code": {"targetfundcode", "目标基金代码", "转入基金代码", "目标代码"},
    "amount_text": {"amounttext", "金额文本", "金额/份额", "金额", "份额"},
    "status": {"status", "状态"},
    "plan_type": {"plantype", "plantypelabel", "计划类型", "类型", "定投类型"},
    "schedule_text": {"scheduletext", "计划说明", "频率", "周期", "扣款方式"},
    "invested_periods": {"investedperiods", "已投期数", "期数"},
    "cumulative": {"cumulativeinvestedamount", "累计定投", "累计投入", "累计金额"},
    "payment_method": {"paymentmethod", "支付方式", "付款方式"},
    "next_execution_date": {"nextexecutiondate", "下次定投时间", "下次时间", "下次执行", "下次扣款"},
    "note": {"note", "备注"},
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="把图片 OCR 或表格文件预处理成个人资产导入草稿。")
    parser.add_argument("--target", required=True, choices=["holdings", "pending_trades", "investment_plans"])
    parser.add_argument("--source", required=True, choices=["ocr", "table"])
    parser.add_argument("--input", required=True)
    return parser.parse_args()


def normalize_header(value: str) -> str:
    text = value.strip().lower()
    replacements = {
        "（": "(",
        "）": ")",
        "_": "",
        "-": "",
        " ": "",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    return text


def looks_like_header_row(row: list[str]) -> bool:
    normalized = {normalize_header(cell) for cell in row if cell.strip()}
    all_aliases = set().union(*HEADER_ALIASES.values())
    return bool(normalized & all_aliases)


def infer_header_key(header: str) -> str | None:
    normalized = normalize_header(header)
    for key, aliases in HEADER_ALIASES.items():
        if normalized in aliases:
            return key
    return None


def clean_ocr_text(text: str) -> str:
    lines = []
    for raw in text.splitlines():
        line = re.sub(r"\s+", " ", raw).strip()
        if not line:
            continue
        lines.append(line)
    if not lines:
        return ""
    return "# 已从图片 OCR 识别，请核对后再保存\n" + "\n".join(lines)


def load_table_rows(path: Path) -> list[list[str]]:
    suffix = path.suffix.lower()
    if suffix in {".txt", ".md"}:
        return [[line] for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if suffix == ".json":
        return load_json_rows(path)
    if suffix in {".csv", ".tsv"}:
        delimiter = "\t" if suffix == ".tsv" else ","
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            return [[cell.strip() for cell in row] for row in csv.reader(handle, delimiter=delimiter)]
    if suffix == ".xlsx":
        return load_xlsx_rows(path)
    raise ValueError(f"暂不支持这种表格格式：{path.name}")


def load_json_rows(path: Path) -> list[list[str]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(payload, dict):
        for key in ("items", "rows", "data", "records"):
            nested = payload.get(key)
            if isinstance(nested, list) and nested:
                payload = nested
                break
    if isinstance(payload, list) and payload and isinstance(payload[0], dict):
        headers = list(payload[0].keys())
        rows = [headers]
        for item in payload:
            rows.append([stringify(item.get(header)) for header in headers])
        return rows
    if isinstance(payload, list) and payload and isinstance(payload[0], list):
        return [[stringify(cell) for cell in row] for row in payload]
    raise ValueError("JSON 需要是对象数组或二维数组。")


def load_xlsx_rows(path: Path) -> list[list[str]]:
    with zipfile.ZipFile(path) as archive:
        shared_strings = read_shared_strings(archive)
        sheet_name = first_sheet_path(archive)
        root = ET.fromstring(archive.read(sheet_name))
        ns = {"a": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
        rows: list[list[str]] = []
        for row_node in root.findall(".//a:sheetData/a:row", ns):
            current: list[str] = []
            current_index = 0
            for cell in row_node.findall("a:c", ns):
                ref = cell.attrib.get("r", "")
                col_index = column_index(ref)
                while current_index < col_index:
                    current.append("")
                    current_index += 1
                cell_type = cell.attrib.get("t")
                value_node = cell.find("a:v", ns)
                value = value_node.text.strip() if value_node is not None and value_node.text else ""
                if cell_type == "s" and value:
                    cell_text = shared_strings[int(value)]
                else:
                    cell_text = value
                current.append(cell_text)
                current_index += 1
            rows.append([cell.strip() for cell in current])
        return rows


def read_shared_strings(archive: zipfile.ZipFile) -> list[str]:
    try:
        data = archive.read("xl/sharedStrings.xml")
    except KeyError:
        return []
    root = ET.fromstring(data)
    ns = {"a": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    values: list[str] = []
    for item in root.findall(".//a:si", ns):
        texts = [node.text or "" for node in item.findall(".//a:t", ns)]
        values.append("".join(texts))
    return values


def first_sheet_path(archive: zipfile.ZipFile) -> str:
    candidates = sorted(name for name in archive.namelist() if name.startswith("xl/worksheets/sheet") and name.endswith(".xml"))
    if not candidates:
        raise ValueError("xlsx 里没有找到工作表。")
    return candidates[0]


def column_index(cell_ref: str) -> int:
    letters = "".join(char for char in cell_ref if char.isalpha()).upper()
    value = 0
    for char in letters:
        value = value * 26 + (ord(char) - ord("A") + 1)
    return max(value - 1, 0)


def stringify(value: object) -> str:
    if value is None:
        return ""
    return str(value).strip()


def value_from_mapping(row_dict: dict[str, str], key: str) -> str:
    for alias in HEADER_ALIASES[key]:
        if alias in row_dict:
            return row_dict[alias]
    return ""


def rows_to_lines(rows: list[list[str]], target: str) -> list[str]:
    filtered = [row for row in rows if any(cell.strip() for cell in row)]
    if not filtered:
        return []

    if all(len(row) == 1 for row in filtered):
        return [row[0] for row in filtered if row[0].strip()]

    if looks_like_header_row(filtered[0]):
        headers = [normalize_header(cell) for cell in filtered[0]]
        mapped_rows = []
        for row in filtered[1:]:
            row_dict = {}
            for index, header in enumerate(headers):
                if header:
                    row_dict[header] = row[index].strip() if index < len(row) else ""
            mapped_rows.append(row_dict)
        if target == "holdings":
            return holdings_lines_from_dict_rows(mapped_rows)
        if target == "pending_trades":
            return pending_lines_from_dict_rows(mapped_rows)
        return plan_lines_from_dict_rows(mapped_rows)

    if target == "holdings":
        return holdings_lines_from_raw_rows(filtered)
    if target == "pending_trades":
        return pending_lines_from_raw_rows(filtered)
    return plan_lines_from_raw_rows(filtered)


def holdings_lines_from_dict_rows(rows: list[dict[str, str]]) -> list[str]:
    lines: list[str] = []
    for row in rows:
        fund_name = value_from_mapping(row, "fund_name")
        fund_code = value_from_mapping(row, "fund_code")
        asset_type = value_from_mapping(row, "asset_type")
        units = value_from_mapping(row, "units")
        cost_price = value_from_mapping(row, "cost_price")
        market_value = value_from_mapping(row, "market_value")
        profit_amount = value_from_mapping(row, "profit_amount")
        profit_pct = value_from_mapping(row, "profit_pct")

        if fund_code and units:
            parts = [asset_type, fund_code, units] if asset_type else [fund_code, units]
            if cost_price:
                parts.append(cost_price)
            if fund_name:
                parts.append(fund_name)
            lines.append(" ".join(parts))
        elif fund_name and market_value and profit_amount and profit_pct:
            pct = profit_pct if "%" in profit_pct else f"{profit_pct}%"
            lines.append(f"{fund_name} | {market_value} | {profit_amount} | {pct}")
    return lines


def holdings_lines_from_raw_rows(rows: list[list[str]]) -> list[str]:
    lines: list[str] = []
    for row in rows:
        if len(row) == 1 and "|" in row[0]:
            lines.append(row[0])
            continue
        cleaned = [cell.strip() for cell in row if cell.strip()]
        if len(cleaned) >= 4 and not cleaned[0].isdigit():
            pct = cleaned[3] if "%" in cleaned[3] else f"{cleaned[3]}%"
            lines.append(f"{cleaned[0]} | {cleaned[1]} | {cleaned[2]} | {pct}")
        elif len(cleaned) >= 2 and (cleaned[0].isdigit() or cleaned[0].lower() in {"股票", "stock", "基金", "fund"}):
            parts = cleaned[:5] if cleaned[0].lower() in {"股票", "stock", "基金", "fund"} else cleaned[:4]
            lines.append(" ".join(parts))
    return lines


def pending_lines_from_dict_rows(rows: list[dict[str, str]]) -> list[str]:
    lines: list[str] = []
    for row in rows:
        occurred_at = value_from_mapping(row, "occurred_at")
        action = value_from_mapping(row, "action")
        fund_name = value_from_mapping(row, "fund_name") or value_from_mapping(row, "fund_code")
        target_fund_name = value_from_mapping(row, "target_fund_name") or value_from_mapping(row, "target_fund_code")
        amount_text = value_from_mapping(row, "amount_text") or value_from_mapping(row, "market_value")
        status = value_from_mapping(row, "status") or "交易进行中"
        note = value_from_mapping(row, "note")
        if occurred_at and action and fund_name and amount_text:
            route = f"{fund_name} -> {target_fund_name}" if target_fund_name else fund_name
            parts = [occurred_at, action, route, amount_text, status]
            if note:
                parts.append(note)
            lines.append(" | ".join(parts))
    return lines


def pending_lines_from_raw_rows(rows: list[list[str]]) -> list[str]:
    lines: list[str] = []
    for row in rows:
        cleaned = [cell.strip() for cell in row if cell.strip()]
        if len(cleaned) == 1 and "|" in cleaned[0]:
            lines.append(cleaned[0])
        elif len(cleaned) >= 5:
            lines.append(" | ".join(cleaned[:6]))
    return lines


def plan_lines_from_dict_rows(rows: list[dict[str, str]]) -> list[str]:
    lines: list[str] = []
    for row in rows:
        plan_type = value_from_mapping(row, "plan_type")
        fund_name = value_from_mapping(row, "fund_name") or value_from_mapping(row, "fund_code")
        schedule_text = value_from_mapping(row, "schedule_text")
        amount_text = value_from_mapping(row, "amount_text") or value_from_mapping(row, "market_value")
        invested_periods = value_from_mapping(row, "invested_periods")
        cumulative = value_from_mapping(row, "cumulative")
        payment_method = value_from_mapping(row, "payment_method")
        next_execution_date = value_from_mapping(row, "next_execution_date")
        status = value_from_mapping(row, "status")
        note = value_from_mapping(row, "note")
        if plan_type and fund_name and schedule_text and amount_text and (next_execution_date or status):
            parts = [
                plan_type,
                fund_name,
                schedule_text,
                amount_text,
                invested_periods,
                cumulative,
                payment_method,
                next_execution_date,
            ]
            if status:
                parts.append(status)
            if note:
                parts.append(note)
            lines.append(" | ".join(parts))
    return lines


def plan_lines_from_raw_rows(rows: list[list[str]]) -> list[str]:
    lines: list[str] = []
    for row in rows:
        cleaned = [cell.strip() for cell in row if cell.strip()]
        if len(cleaned) == 1 and "|" in cleaned[0]:
            lines.append(cleaned[0])
        elif len(cleaned) >= 8:
            lines.append(" | ".join(cleaned[:10]))
    return lines


def main() -> int:
    args = parse_args()
    input_path = Path(args.input).expanduser().resolve()
    try:
        if args.source == "ocr":
            text = input_path.read_text(encoding="utf-8")
            draft = clean_ocr_text(text)
        else:
            rows = load_table_rows(input_path)
            lines = rows_to_lines(rows, args.target)
            if not lines:
                raise ValueError("没有从表格里识别到可导入的数据。")
            draft = "\n".join(lines)
        print(draft)
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"预处理失败: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
