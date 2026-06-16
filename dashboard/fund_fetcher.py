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
    fund_history_lock,
    fund_quote_lock,
)
from .performance import performance_start, record_performance
from .utils import (
    date_key_from_text,
    fetch_remote_text,
    normalize_text,
    safe_float,
    safe_int,
)


def fetch_fund_history_series(fund_code: str) -> Dict[str, Any]:
    started_at = performance_start()
    cache_status = "miss"
    target = normalize_text(fund_code)
    if not target:
        cache_status = "empty"
        try:
            return {}
        finally:
            record_performance("fund.history", started_at, has_code=False, cache=cache_status)
    cached = FUND_HISTORY_CACHE.get(target)
    now = time.time()
    if cached and now - safe_float(cached.get("loaded_at")) < FUND_HISTORY_TTL_SECONDS:
        cache_status = "hit"
        record_performance("fund.history", started_at, has_code=True, cache=cache_status)
        return cached
    with fund_history_lock(target):
        cached = FUND_HISTORY_CACHE.get(target)
        now = time.time()
        if cached and now - safe_float(cached.get("loaded_at")) < FUND_HISTORY_TTL_SECONDS:
            cache_status = "hit_after_wait"
            record_performance("fund.history", started_at, has_code=True, cache=cache_status)
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
            if trend_match:
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
        record_performance(
            "fund.history",
            started_at,
            has_code=True,
            cache=cache_status,
            series_count=len(result.get("series") or []),
        )
        return result


def lookup_fund_nav_by_date(history: Dict[str, Any], date_text: Any) -> Dict[str, Any]:
    keys, series = _fund_history_lookup_tables(history)
    target_key = date_key_from_text(date_text)
    if not keys or not series or not target_key:
        return {}
    index = bisect.bisect_right(keys, target_key) - 1
    if index < 0 or index >= len(series):
        return {}
    return series[index]


def fetch_fund_quote(fund_code: str) -> Dict[str, Any]:
    started_at = performance_start()
    cache_status = "miss"
    price_source = ""
    target = normalize_text(fund_code)
    if not target:
        cache_status = "empty"
        try:
            return {}
        finally:
            record_performance("fund.quote", started_at, has_code=False, cache=cache_status)
    cached = FUND_QUOTE_CACHE.get(target)
    now = time.time()
    if cached and now - safe_float(cached.get("loaded_at")) < FUND_QUOTE_TTL_SECONDS:
        cache_status = "hit"
        record_performance(
            "fund.quote",
            started_at,
            has_code=True,
            cache=cache_status,
            source=normalize_text(cached.get("price_source")),
        )
        return cached
    with fund_quote_lock(target):
        cached = FUND_QUOTE_CACHE.get(target)
        now = time.time()
        if cached and now - safe_float(cached.get("loaded_at")) < FUND_QUOTE_TTL_SECONDS:
            cache_status = "hit_after_wait"
            record_performance(
                "fund.quote",
                started_at,
                has_code=True,
                cache=cache_status,
                source=normalize_text(cached.get("price_source")),
            )
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
        price_source = normalize_text(result.get("price_source"))
        record_performance(
            "fund.quote",
            started_at,
            has_code=True,
            cache=cache_status,
            source=price_source,
        )
        return result


def _fund_history_lookup_signature(history: Dict[str, Any]) -> tuple[Any, ...]:
    raw_keys = list(history.get("keys") or [])
    raw_series = list(history.get("series") or [])
    first_row = raw_series[0] if raw_series and isinstance(raw_series[0], dict) else {}
    last_row = raw_series[-1] if raw_series and isinstance(raw_series[-1], dict) else {}
    return (
        len(raw_keys),
        raw_keys[0] if raw_keys else None,
        raw_keys[-1] if raw_keys else None,
        len(raw_series),
        first_row.get("date"),
        first_row.get("nav"),
        last_row.get("date"),
        last_row.get("nav"),
    )


def _fund_history_lookup_tables(history: Dict[str, Any]) -> tuple[List[int], List[Dict[str, Any]]]:
    signature = _fund_history_lookup_signature(history)
    cached_signature = history.get("_lookup_signature")
    cached_keys = history.get("_lookup_keys")
    cached_series = history.get("_lookup_series")
    if cached_signature == signature and isinstance(cached_keys, list) and isinstance(cached_series, list):
        return cached_keys, cached_series

    keys = [safe_int(value) for value in list(history.get("keys") or [])]
    series = [item for item in list(history.get("series") or []) if isinstance(item, dict)]
    history["_lookup_signature"] = signature
    history["_lookup_keys"] = keys
    history["_lookup_series"] = series
    return keys, series


def _unique_fund_codes(fund_codes: List[str]) -> List[str]:
    return [code for code in dict.fromkeys(normalize_text(code) for code in fund_codes) if code]


def preload_selected_fund_market_data(
    history_fund_codes: List[str],
    quote_fund_codes: List[str],
) -> tuple[Dict[str, Dict[str, Any]], Dict[str, Dict[str, Any]]]:
    started_at = performance_start()
    unique_history_codes = _unique_fund_codes(history_fund_codes)
    unique_quote_codes = _unique_fund_codes(quote_fund_codes)
    unique_codes = _unique_fund_codes(unique_history_codes + unique_quote_codes)
    histories: Dict[str, Dict[str, Any]] = {}
    quotes: Dict[str, Dict[str, Any]] = {}
    if not unique_codes:
        record_performance("fund.preload", started_at, code_count=0, history_fetch_count=0, quote_fetch_count=0)
        return histories, quotes

    now = time.time()
    history_codes: List[str] = []
    quote_codes: List[str] = []
    for code in unique_history_codes:
        cached_history = FUND_HISTORY_CACHE.get(code)
        if cached_history and now - safe_float(cached_history.get("loaded_at")) < FUND_HISTORY_TTL_SECONDS:
            histories[code] = cached_history
        else:
            history_codes.append(code)

    for code in unique_quote_codes:
        cached_quote = FUND_QUOTE_CACHE.get(code)
        if cached_quote and now - safe_float(cached_quote.get("loaded_at")) < FUND_QUOTE_TTL_SECONDS:
            quotes[code] = cached_quote
        else:
            quote_codes.append(code)

    if not history_codes and not quote_codes:
        record_performance(
            "fund.preload",
            started_at,
            code_count=len(unique_codes),
            history_cache_count=len(histories),
            quote_cache_count=len(quotes),
            history_fetch_count=0,
            quote_fetch_count=0,
        )
        return histories, quotes

    fetch_count = len(history_codes) + len(quote_codes)
    max_workers = max(1, min(12, fetch_count))
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        history_futures = {executor.submit(fetch_fund_history_series, code): ("history", code) for code in history_codes}
        quote_futures = {executor.submit(fetch_fund_quote, code): ("quote", code) for code in quote_codes}
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
    record_performance(
        "fund.preload",
        started_at,
        code_count=len(unique_codes),
        history_cache_count=len(histories) - len(history_codes),
        quote_cache_count=len(quotes) - len(quote_codes),
        history_fetch_count=len(history_codes),
        quote_fetch_count=len(quote_codes),
    )
    return histories, quotes


def preload_fund_market_data(fund_codes: List[str]) -> tuple[Dict[str, Dict[str, Any]], Dict[str, Dict[str, Any]]]:
    return preload_selected_fund_market_data(fund_codes, fund_codes)
