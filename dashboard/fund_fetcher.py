from __future__ import annotations

import bisect
import json
import re
import time
from datetime import datetime
from typing import Any, Dict, List
from concurrent.futures import ThreadPoolExecutor, as_completed

from .cache import (
    FUND_HISTORY_CACHE,
    FUND_HISTORY_TTL_SECONDS,
    FUND_QUOTE_CACHE,
    FUND_QUOTE_TTL_SECONDS,
)
from .utils import (
    date_key_from_text,
    fetch_remote_text,
    normalize_text,
    safe_float,
    safe_int,
)


def fetch_fund_history_series(fund_code: str) -> Dict[str, Any]:
    target = normalize_text(fund_code)
    if not target:
        return {}
    cached = FUND_HISTORY_CACHE.get(target)
    now = time.time()
    if cached and now - safe_float(cached.get("loaded_at")) < FUND_HISTORY_TTL_SECONDS:
        return cached
    result: Dict[str, Any] = {
        "fund_code": target,
        "fund_name": "",
        "series": [],
        "keys": [],
        "loaded_at": now,
    }
    try:
        text = fetch_remote_text(f"https://fund.eastmoney.com/pingzhongdata/{target}.js?v={int(now)}")
        name_match = re.search(r'var\s+fS_name\s*=\s*"([^"]*)";', text)
        trend_match = re.search(r'var\s+Data_netWorthTrend\s*=\s*(\[[\s\S]*?\]);', text)
        if not trend_match:
            FUND_HISTORY_CACHE[target] = result
            return result
        rows = json.loads(trend_match.group(1))
        series: List[Dict[str, Any]] = []
        keys: List[int] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            nav = safe_float(row.get("y"))
            ts = safe_int(row.get("x"))
            if nav <= 0 or ts <= 0:
                continue
            date_text = datetime.fromtimestamp(ts / 1000).strftime("%Y-%m-%d")
            date_key = date_key_from_text(date_text)
            if not date_key:
                continue
            keys.append(date_key)
            series.append(
                {
                    "date": date_text,
                    "date_key": date_key,
                    "nav": nav,
                    "ts": ts,
                }
            )
        result = {
            "fund_code": target,
            "fund_name": normalize_text(name_match.group(1)) if name_match else "",
            "series": series,
            "keys": keys,
            "loaded_at": now,
        }
    except Exception:
        pass
    FUND_HISTORY_CACHE[target] = result
    return result


def lookup_fund_nav_by_date(history: Dict[str, Any], date_text: Any) -> Dict[str, Any]:
    keys = [safe_int(value) for value in list(history.get("keys") or [])]
    series = [item for item in list(history.get("series") or []) if isinstance(item, dict)]
    target_key = date_key_from_text(date_text)
    if not keys or not series or not target_key:
        return {}
    index = bisect.bisect_right(keys, target_key) - 1
    if index < 0 or index >= len(series):
        return {}
    return series[index]


def fetch_fund_quote(fund_code: str) -> Dict[str, Any]:
    target = normalize_text(fund_code)
    if not target:
        return {}
    cached = FUND_QUOTE_CACHE.get(target)
    now = time.time()
    if cached and now - safe_float(cached.get("loaded_at")) < FUND_QUOTE_TTL_SECONDS:
        return cached
    result: Dict[str, Any] = {
        "fund_code": target,
        "price": 0.0,
        "price_time": "",
        "price_source": "",
        "price_source_label": "",
        "official_nav": 0.0,
        "official_nav_date": "",
        "estimate_change_pct": 0.0,
        "loaded_at": now,
    }
    try:
        text = fetch_remote_text(f"https://fundgz.1234567.com.cn/js/{target}.js?rt={int(now)}")
        match = re.search(r"jsonpgz\((\{[\s\S]*\})\);", text)
        if match:
            payload = json.loads(match.group(1))
            estimate_price = safe_float(payload.get("gsz"))
            if estimate_price > 0:
                result = {
                    "fund_code": target,
                    "fund_name": normalize_text(payload.get("name")),
                    "price": estimate_price,
                    "price_time": normalize_text(payload.get("gztime")),
                    "price_source": "estimate",
                    "price_source_label": "盘中估值",
                    "official_nav": safe_float(payload.get("dwjz")),
                    "official_nav_date": normalize_text(payload.get("jzrq")),
                    "estimate_change_pct": safe_float(payload.get("gszzl")),
                    "loaded_at": now,
                }
    except Exception:
        pass
    if safe_float(result.get("price")) <= 0:
        history = fetch_fund_history_series(target)
        series = [item for item in list(history.get("series") or []) if isinstance(item, dict)]
        latest = series[-1] if series else {}
        if latest:
            result = {
                "fund_code": target,
                "fund_name": normalize_text(history.get("fund_name")),
                "price": safe_float(latest.get("nav")),
                "price_time": normalize_text(latest.get("date")),
                "price_source": "official_nav",
                "price_source_label": "最近净值",
                "official_nav": safe_float(latest.get("nav")),
                "official_nav_date": normalize_text(latest.get("date")),
                "estimate_change_pct": 0.0,
                "loaded_at": now,
            }
    FUND_QUOTE_CACHE[target] = result
    return result


def preload_fund_market_data(fund_codes: List[str]) -> tuple[Dict[str, Dict[str, Any]], Dict[str, Dict[str, Any]]]:
    unique_codes = [code for code in dict.fromkeys(normalize_text(code) for code in fund_codes) if code]
    histories: Dict[str, Dict[str, Any]] = {}
    quotes: Dict[str, Dict[str, Any]] = {}
    if not unique_codes:
        return histories, quotes
    max_workers = max(1, min(12, len(unique_codes) * 2))
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        history_futures = {executor.submit(fetch_fund_history_series, code): ("history", code) for code in unique_codes}
        quote_futures = {executor.submit(fetch_fund_quote, code): ("quote", code) for code in unique_codes}
        all_futures = {**history_futures, **quote_futures}
        for future in as_completed(all_futures):
            kind, code = all_futures[future]
            try:
                if kind == "history":
                    histories[code] = future.result()
                else:
                    quotes[code] = future.result()
            except Exception:
                if kind == "history":
                    histories[code] = {}
                else:
                    quotes[code] = {}
    return histories, quotes
