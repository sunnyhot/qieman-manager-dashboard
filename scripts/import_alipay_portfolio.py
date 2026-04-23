#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.parse
import urllib.request
import uuid
from dataclasses import asdict, dataclass
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)

MANUAL_CODE_OVERRIDES = {
    "华夏标普500ETF联接(QDII)A": "018064",
    "易方达中概互联网ETF联接(QDII)A(人民币份额)": "006327",
    "华泰柏瑞纳斯达克100ETF联接(QDII)A": "019524",
    "汇添富文体娱乐主题混合A": "004424",
    "兴全商业模式优选混合(LOF)A": "163415",
}


@dataclass
class AlipayHoldingLine:
    fund_name: str
    market_value: float
    profit_amount: float
    profit_pct: float


@dataclass
class ResolvedHolding:
    fund_name: str
    resolved_name: str
    fund_code: str
    market_value: float
    profit_amount: float
    profit_pct: float
    current_price: float
    current_price_time: str
    current_price_source: str
    estimated_units: float
    estimated_cost_price: float
    estimated_cost_value: float
    match_score: float
    match_source: str

    def holding_payload(self) -> dict[str, Any]:
        return {
            "id": str(uuid.uuid4()),
            "fundCode": self.fund_code,
            "units": self.estimated_units,
            "costPrice": self.estimated_cost_price,
            "displayName": self.fund_name,
        }


def app_support_portfolio_path() -> Path:
    return Path.home() / "Library" / "Application Support" / "QiemanDashboard" / "user-portfolio.json"


def normalize_name(value: str) -> str:
    text = value.upper().strip()
    replacements = {
        "（": "(",
        "）": ")",
        "【": "(",
        "】": ")",
        "人民币份额": "",
        "人民币A": "A",
        "人民币C": "C",
        "人民币": "",
        "美元现汇": "",
        "美汇": "",
        "美钞": "",
        "发起式": "",
        "联接基金": "联接",
        "Ａ": "A",
        "Ｃ": "C",
        "ＱＤＩＩ": "QDII",
        "ＬＯＦ": "LOF",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    text = re.sub(r"[\s·•\-_/]", "", text)
    return text


def fetch_text(url: str, *, referer: str | None = None) -> str:
    headers = {"User-Agent": USER_AGENT}
    if referer:
        headers["Referer"] = referer
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=20) as response:
        return response.read().decode("utf-8", errors="ignore")


def parse_alipay_lines(path: Path) -> list[AlipayHoldingLine]:
    items: list[AlipayHoldingLine] = []
    for index, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split("|")]
        if len(parts) != 4:
            raise ValueError(f"第 {index} 行格式不对，应为：基金名 | 当前金额 | 持有收益 | 持有收益率")
        items.append(
            AlipayHoldingLine(
                fund_name=parts[0],
                market_value=parse_number(parts[1]),
                profit_amount=parse_number(parts[2]),
                profit_pct=parse_number(parts[3].replace("%", "")),
            )
        )
    if not items:
        raise ValueError("没有解析到任何支付宝持仓行。")
    return items


def parse_number(text: str) -> float:
    return float(text.replace(",", "").strip())


def score_candidate(target_name: str, candidate_name: str) -> float:
    target = normalize_name(target_name)
    candidate = normalize_name(candidate_name)
    score = SequenceMatcher(None, target, candidate).ratio() * 100
    if target == candidate:
        score += 200
    if target in candidate or candidate in target:
        score += 70
    if target.endswith("A") and candidate.endswith("A"):
        score += 15
    if target.endswith("C") and candidate.endswith("C"):
        score += 15
    for token in ("QDII", "ETF", "LOF", "指数", "联接", "混合", "债券", "股票"):
        if token in target_name and token in candidate_name:
            score += 4
    return score


def search_fund_candidates(name: str) -> list[dict[str, Any]]:
    url = (
        "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx"
        f"?m=1&key={urllib.parse.quote(name)}"
    )
    payload = json.loads(fetch_text(url))
    return payload.get("Datas", [])


def resolve_fund(name: str) -> tuple[str, str, float, str]:
    override_code = MANUAL_CODE_OVERRIDES.get(name)
    candidates = search_fund_candidates(name)
    if not candidates:
        raise RuntimeError(f"没有搜到基金代码：{name}")

    if override_code:
        for item in candidates:
            if item.get("CODE") == override_code:
                return override_code, item.get("NAME", name), 999.0, "override"
        return override_code, name, 999.0, "override"

    best_item = None
    best_score = -1.0
    for item in candidates[:12]:
        score = score_candidate(name, item.get("NAME", ""))
        if score > best_score:
            best_item = item
            best_score = score

    if not best_item:
        raise RuntimeError(f"无法匹配基金代码：{name}")
    return best_item.get("CODE", ""), best_item.get("NAME", name), round(best_score, 2), "search"


def fetch_latest_nav(code: str) -> tuple[float | None, str, str]:
    url = f"https://fund.eastmoney.com/pingzhongdata/{code}.js?v=1"
    text = fetch_text(url, referer="https://fund.eastmoney.com/")
    name_match = re.search(r'var\s+fS_name\s*=\s*"([^"]*)";', text)
    name = name_match.group(1) if name_match else ""
    trend_match = re.search(r"var\s+Data_netWorthTrend\s*=\s*(\[[\s\S]*?\]);", text)
    if not trend_match:
        return None, "", name
    rows = json.loads(trend_match.group(1))
    latest = None
    for row in rows:
        nav = row.get("y")
        ts = row.get("x")
        if nav is None or ts is None:
            continue
        latest = (float(nav), timestamp_to_date(int(ts)))
    if not latest:
        return None, "", name
    return latest[0], latest[1], name


def fetch_quote(code: str) -> tuple[float, str, str, str]:
    url = f"https://fundgz.1234567.com.cn/js/{code}.js?rt=1"
    try:
        text = fetch_text(url, referer="https://fund.eastmoney.com/")
    except Exception:
        text = ""

    match = re.search(r"jsonpgz\((\{[\s\S]*\})\);", text)
    if match:
        payload = json.loads(match.group(1))
        estimate_price = payload.get("gsz")
        if estimate_price not in (None, "", "0.0000", "0"):
            return (
                float(estimate_price),
                payload.get("gztime", ""),
                "盘中估值",
                payload.get("name", ""),
            )

    nav, nav_date, nav_name = fetch_latest_nav(code)
    if nav and nav > 0:
        return nav, nav_date, "最近净值", nav_name
    raise RuntimeError(f"无法获取基金估值：{code}")


def timestamp_to_date(timestamp_ms: int) -> str:
    from datetime import datetime

    return datetime.fromtimestamp(timestamp_ms / 1000).strftime("%Y-%m-%d")


def round_money(value: float, digits: int = 2) -> float:
    return round(value + 1e-10, digits)


def round_units(value: float) -> float:
    return round(value + 1e-10, 4)


def build_resolved_holdings(lines: list[AlipayHoldingLine]) -> list[ResolvedHolding]:
    resolved: list[ResolvedHolding] = []
    for item in lines:
        code, resolved_name, score, match_source = resolve_fund(item.fund_name)
        current_price, price_time, price_source, _ = fetch_quote(code)
        estimated_units = round_units(item.market_value / current_price)
        estimated_cost_value = round_money(item.market_value - item.profit_amount)
        estimated_cost_price = round(item.market_value - item.profit_amount, 6) / estimated_units
        estimated_cost_price = round(estimated_cost_price + 1e-10, 4)
        resolved.append(
            ResolvedHolding(
                fund_name=item.fund_name,
                resolved_name=resolved_name,
                fund_code=code,
                market_value=round_money(item.market_value),
                profit_amount=round_money(item.profit_amount),
                profit_pct=round(item.profit_pct, 2),
                current_price=round(current_price + 1e-10, 4),
                current_price_time=price_time,
                current_price_source=price_source,
                estimated_units=estimated_units,
                estimated_cost_price=estimated_cost_price,
                estimated_cost_value=estimated_cost_value,
                match_score=score,
                match_source=match_source,
            )
        )
    return resolved


def write_output(resolved: list[ResolvedHolding], output_path: Path, preview_path: Path | None) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    holdings_payload = [item.holding_payload() for item in resolved]
    output_path.write_text(json.dumps(holdings_payload, ensure_ascii=False, indent=2), encoding="utf-8")

    if preview_path:
        preview_path.parent.mkdir(parents=True, exist_ok=True)
        preview_path.write_text(
            json.dumps([asdict(item) for item in resolved], ensure_ascii=False, indent=2),
            encoding="utf-8",
        )


def print_summary(resolved: list[ResolvedHolding], output_path: Path, preview_path: Path | None) -> None:
    total_market = round_money(sum(item.market_value for item in resolved))
    total_profit = round_money(sum(item.profit_amount for item in resolved))
    print(f"已导入 {len(resolved)} 条支付宝持仓")
    print(f"写入文件: {output_path}")
    if preview_path:
        print(f"预览文件: {preview_path}")
    print(f"支付宝截图总市值: {total_market:.2f}")
    print(f"支付宝截图总盈亏: {total_profit:.2f}")
    print()
    for item in resolved:
        print(
            f"{item.fund_code} | {item.fund_name} | "
            f"估算份额 {item.estimated_units:.4f} | 估算成本价 {item.estimated_cost_price:.4f} | "
            f"当前价 {item.current_price:.4f} ({item.current_price_source})"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="把支付宝基金持仓摘要导入 QiemanDashboard 的个人持仓文件。")
    parser.add_argument("--input", required=True, help="输入文本文件，每行格式：基金名 | 当前金额 | 持有收益 | 持有收益率")
    parser.add_argument("--output", default=str(app_support_portfolio_path()), help="输出 user-portfolio.json 路径")
    parser.add_argument("--preview", help="额外输出解析预览 JSON，方便核对基金代码、估算份额和成本价")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()
    preview_path = Path(args.preview).expanduser().resolve() if args.preview else None

    try:
        lines = parse_alipay_lines(input_path)
        resolved = build_resolved_holdings(lines)
        write_output(resolved, output_path, preview_path)
        print_summary(resolved, output_path, preview_path)
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"导入失败: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
