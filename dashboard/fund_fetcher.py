from __future__ import annotations

import bisect
import json
import re
import time
from datetime import datetime
from typing import Any, Dict, List
from concurrent.futures import ThreadPoolExecutor, as_completed
from zoneinfo import ZoneInfo

from .cache import (
    FUND_HISTORY_CACHE,
    FUND_HISTORY_TTL_SECONDS,
    FUND_QUOTE_CACHE,
    FUND_QUOTE_TTL_SECONDS,
    fund_history_lock,
    fund_quote_lock,
    store_loaded_cache_entry,
)

from .performance import performance_start, record_performance
from .utils import (
    date_key_from_text,
    fetch_remote_text,
    normalize_date_text,
    normalize_text,
    safe_float,
    safe_int,
)

CHINA_MARKET_TIME_ZONE = ZoneInfo("Asia/Shanghai")


def _current_market_date_text() -> str:
    return datetime.now(CHINA_MARKET_TIME_ZONE).strftime("%Y-%m-%d")


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
        empty_result: Dict[str, Any] = {
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
                    date_text = datetime.fromtimestamp(ts / 1000, CHINA_MARKET_TIME_ZONE).strftime("%Y-%m-%d")
                    date_key = date_key_from_text(date_text)
                    if not date_key:
                        continue
                    keys.append(date_key)
                    raw_change_pct = row.get("equityReturn")
                    series.append(
                        {
                            "date": date_text,
                            "date_key": date_key,
                            "nav": nav,
                            "ts": ts,
                            "change_pct": safe_float(raw_change_pct) if raw_change_pct not in (None, "") else None,
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
        store_loaded_cache_entry(FUND_HISTORY_CACHE, target, result)
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


def _latest_official_quote(target: str, loaded_at: float) -> Dict[str, Any]:
    try:
        text = fetch_remote_text(
            "https://api.fund.eastmoney.com/f10/lsjz"
            f"?fundCode={target}&pageIndex=1&pageSize=1"
        )
        payload = json.loads(text)
        rows = (
            ((payload.get("Data") or {}).get("LSJZList") or [])
            if safe_int(payload.get("ErrCode")) == 0
            else []
        )
        latest = rows[0] if rows and isinstance(rows[0], dict) else {}
        official_nav = safe_float(latest.get("DWJZ"))
        official_nav_date = normalize_text(latest.get("FSRQ"))
        if official_nav <= 0:
            return {}
        is_today = normalize_date_text(official_nav_date) == _current_market_date_text()
        has_change = bool(is_today and normalize_text(latest.get("JZZZL")))
        return {
            "fund_code": target,
            "price": official_nav,
            "price_time": official_nav_date,
            "price_source": "official_nav",
            "price_source_label": "当日确认净值" if has_change else "最近净值",
            "official_nav": official_nav,
            "official_nav_date": official_nav_date,
            "estimate_change_pct": safe_float(latest.get("JZZZL")) if has_change else 0.0,
            "daily_change_available": has_change,
            "loaded_at": loaded_at,
        }
    except Exception:
        return {}


def _legacy_fund_quote(target: str, loaded_at: float) -> Dict[str, Any]:
    try:
        text = fetch_remote_text(f"https://fundgz.1234567.com.cn/js/{target}.js?rt={int(loaded_at)}")
        match = re.search(r"jsonpgz\((\{[\s\S]*\})\);", text)
        if not match:
            return {}
        payload = json.loads(match.group(1))
        estimate_price = safe_float(payload.get("gsz"))
        estimate_time = normalize_text(payload.get("gztime"))
        is_current_estimate = normalize_date_text(estimate_time) == _current_market_date_text()
        official_nav = safe_float(payload.get("dwjz"))
        official_nav_date = normalize_text(payload.get("jzrq"))
        if estimate_price > 0 and is_current_estimate:
            return {
                "fund_code": target,
                "fund_name": normalize_text(payload.get("name")),
                "price": estimate_price,
                "price_time": estimate_time,
                "price_source": "estimate",
                "price_source_label": "东方财富盘中估值",
                "official_nav": official_nav,
                "official_nav_date": official_nav_date,
                "estimate_change_pct": safe_float(payload.get("gszzl")),
                "daily_change_available": bool(normalize_text(payload.get("gszzl"))),
                "loaded_at": loaded_at,
            }
        if official_nav > 0:
            return {
                "fund_code": target,
                "fund_name": normalize_text(payload.get("name")),
                "price": official_nav,
                "price_time": official_nav_date,
                "price_source": "official_nav",
                "price_source_label": "最近净值",
                "official_nav": official_nav,
                "official_nav_date": official_nav_date,
                "estimate_change_pct": 0.0,
                "daily_change_available": False,
                "loaded_at": loaded_at,
            }
    except Exception:
        pass
    return {}


def _sina_fund_estimate(target: str) -> Dict[str, Any]:
    try:
        text = fetch_remote_text(
            f"https://hq.sinajs.cn/list=fu_{target}",
            headers={"Referer": "https://finance.sina.com.cn/"},
        )
        match = re.search(r'=\"([^\"]*)\";', text)
        parts = match.group(1).split(",") if match else []
        if len(parts) <= 7 or normalize_date_text(parts[7]) != _current_market_date_text():
            return {}
        estimate_price = safe_float(parts[2])
        if estimate_price <= 0:
            return {}
        estimate_change_pct = safe_float(parts[6])
        if not normalize_text(parts[6]) and safe_float(parts[3]) > 0:
            estimate_change_pct = (estimate_price / safe_float(parts[3]) - 1) * 100
        return {
            "fund_name": normalize_text(parts[0]),
            "estimate_price": estimate_price,
            "estimate_time": " ".join(item for item in [normalize_text(parts[7]), normalize_text(parts[1])] if item),
            "estimate_change_pct": estimate_change_pct,
            "source": "sina_estimate",
            "source_label": "新浪盘中估值",
        }
    except Exception:
        return {}


def _fund_estimate_proxy(fund_name: str) -> tuple[str, str, str, str, str]:
    name = normalize_text(fund_name).upper()
    if ("中概" in name and ("互联网" in name or "互联" in name)) or "海外互联网" in name:
        return "sh513050", "中概互联网ETF", "", "", ""
    if "纳斯达克100" in name or "纳指100" in name:
        return "usNDX", "纳斯达克100", "hf_NQ", "纳指100期货", "future"
    if "标普500" in name:
        return "usINX", "标普500", "hf_ES", "标普500期货", "future"
    if "全球医疗保健" in name or "全球医疗" in name:
        return "usIXJ", "全球医疗ETF", "hf_ES", "标普500期货", "future"
    if "QDII" in name and "债" in name:
        return "usAGG", "美国综合债券ETF", "fx_susdcny", "美元兑人民币", "forex"
    if "国开债" in name or "纯债" in name or "债券" in name:
        return "sh000012", "国债指数", "", "", ""
    if "QDII" in name:
        return "usINX", "标普500", "hf_ES", "标普500期货", "future"
    if "科创" in name:
        return "sh000688", "科创50", "", "", ""
    if "创业板" in name:
        return "sz399006", "创业板指", "", "", ""
    return "sh000300", "沪深300", "", "", ""


def _format_tencent_quote_time(value: Any) -> str:
    raw = normalize_text(value)
    if len(raw) >= 10 and raw[4:5] == "-":
        return raw[:19]
    if len(raw) < 14:
        return raw
    return f"{raw[:4]}-{raw[4:6]}-{raw[6:8]} {raw[8:10]}:{raw[10:12]}:{raw[12:14]}"


def _sina_quote_parts(symbol: str) -> List[str]:
    text = fetch_remote_text(
        f"https://hq.sinajs.cn/list={symbol}",
        headers={"Referer": "https://finance.sina.com.cn/"},
    )
    match = re.search(r'=\"([^\"]*)\";', text)
    return match.group(1).split(",") if match else []


def _sina_global_futures_estimate(
    symbol: str,
    label: str,
    fund_name: str,
    official_nav: float,
) -> Dict[str, Any]:
    try:
        parts = _sina_quote_parts(symbol)
        if len(parts) <= 12 or normalize_date_text(parts[12]) != _current_market_date_text():
            return {}
        price = safe_float(parts[0])
        previous_close = safe_float(parts[7])
        if price <= 0 or previous_close <= 0:
            return {}
        change_pct = (price / previous_close - 1) * 100
        if abs(change_pct) > 20:
            return {}
        return {
            "fund_name": fund_name,
            "estimate_price": official_nav * (1 + change_pct / 100),
            "estimate_time": " ".join(
                item for item in [normalize_text(parts[12]), normalize_text(parts[6])] if item
            ),
            "estimate_change_pct": change_pct,
            "source": "market_proxy_estimate",
            "source_label": f"{label}代理估算",
        }
    except Exception:
        return {}


def _sina_forex_estimate(
    symbol: str,
    label: str,
    fund_name: str,
    official_nav: float,
) -> Dict[str, Any]:
    try:
        parts = _sina_quote_parts(symbol)
        if len(parts) <= 17 or normalize_date_text(parts[17]) != _current_market_date_text():
            return {}
        price = safe_float(parts[8])
        previous_close = safe_float(parts[3])
        if price <= 0 or previous_close <= 0:
            return {}
        change_pct = (price / previous_close - 1) * 100
        if abs(change_pct) > 10:
            return {}
        return {
            "fund_name": fund_name,
            "estimate_price": official_nav * (1 + change_pct / 100),
            "estimate_time": " ".join(
                item for item in [normalize_text(parts[17]), normalize_text(parts[0])] if item
            ),
            "estimate_change_pct": change_pct,
            "source": "market_proxy_estimate",
            "source_label": f"{label}代理估算",
        }
    except Exception:
        return {}


def _market_proxy_estimate(target: str, fund_name: str, base_quote: Dict[str, Any]) -> Dict[str, Any]:
    official_nav = safe_float(base_quote.get("official_nav") or base_quote.get("price"))
    if official_nav <= 0:
        return {}
    symbol, label, intraday_symbol, intraday_label, intraday_kind = _fund_estimate_proxy(fund_name)
    try:
        text = fetch_remote_text(
            f"https://qt.gtimg.cn/q={symbol}",
            headers={"Referer": "https://gu.qq.com/"},
        )
        match = re.search(r'=\"([^\"]*)\";', text)
        parts = match.group(1).split("~") if match else []
        if len(parts) > 32 and normalize_text(parts[32]):
            change_pct = safe_float(parts[32])
            quote_time = _format_tencent_quote_time(parts[30])
            quote_date = normalize_date_text(quote_time)
            official_date = normalize_date_text(base_quote.get("official_nav_date"))
            if abs(change_pct) <= 30 and quote_date and (
                not official_date or quote_date > official_date or quote_date == _current_market_date_text()
            ):
                return {
                    "fund_name": fund_name,
                    "estimate_price": official_nav * (1 + change_pct / 100),
                    "estimate_time": quote_time,
                    "estimate_change_pct": change_pct,
                    "source": "market_proxy_estimate",
                    "source_label": f"{label}代理估算",
                }
    except Exception:
        pass

    if intraday_kind == "future" and intraday_symbol:
        return _sina_global_futures_estimate(
            intraday_symbol,
            intraday_label,
            fund_name,
            official_nav,
        )
    if intraday_kind == "forex":
        return _sina_forex_estimate(
            intraday_symbol or "fx_susdcny",
            intraday_label,
            fund_name,
            official_nav,
        )
    return {}


def _quote_from_estimate(target: str, estimate: Dict[str, Any], base: Dict[str, Any], loaded_at: float) -> Dict[str, Any]:
    return {
        "fund_code": target,
        "fund_name": normalize_text(estimate.get("fund_name") or base.get("fund_name")),
        "price": safe_float(estimate.get("estimate_price")),
        "price_time": normalize_text(estimate.get("estimate_time")),
        "price_source": normalize_text(estimate.get("source")) or "estimate",
        "price_source_label": normalize_text(estimate.get("source_label")) or "盘中估值",
        "official_nav": safe_float(base.get("official_nav") or base.get("price")),
        "official_nav_date": normalize_text(base.get("official_nav_date") or base.get("price_time")),
        "estimate_change_pct": safe_float(estimate.get("estimate_change_pct")),
        "daily_change_available": True,
        "loaded_at": loaded_at,
    }


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
            "daily_change_available": False,
            "loaded_at": now,
        }
        empty_result = dict(result)
        official_quote = _latest_official_quote(target, now)
        if official_quote.get("daily_change_available"):
            result = official_quote
        else:
            legacy_quote = _legacy_fund_quote(target, now)
            if legacy_quote.get("daily_change_available"):
                result = legacy_quote
                if safe_float(official_quote.get("official_nav")) > 0:
                    result["official_nav"] = official_quote["official_nav"]
                    result["official_nav_date"] = official_quote["official_nav_date"]
            else:
                sina_estimate = _sina_fund_estimate(target)
                if sina_estimate:
                    result = _quote_from_estimate(target, sina_estimate, official_quote or legacy_quote, now)
                else:
                    result = {}

        if not result:
            base_quote = official_quote or legacy_quote
            fund_name = normalize_text(base_quote.get("fund_name"))
            history: Dict[str, Any] = {}
            if not fund_name or safe_float(base_quote.get("price")) <= 0:
                history = fetch_fund_history_series(target)
                fund_name = fund_name or normalize_text(history.get("fund_name"))
                series = [item for item in list(history.get("series") or []) if isinstance(item, dict)]
                latest = series[-1] if series else {}
                if safe_float(base_quote.get("price")) <= 0 and latest:
                    latest_date = normalize_text(latest.get("date"))
                    is_today = normalize_date_text(latest_date) == _current_market_date_text()
                    base_quote = {
                        "fund_code": target,
                        "fund_name": fund_name,
                        "price": safe_float(latest.get("nav")),
                        "price_time": latest_date,
                        "price_source": "official_nav",
                        "price_source_label": "当日确认净值" if is_today else "最近净值",
                        "official_nav": safe_float(latest.get("nav")),
                        "official_nav_date": latest_date,
                        "estimate_change_pct": safe_float(latest.get("change_pct")) if is_today else 0.0,
                        "daily_change_available": bool(is_today and latest.get("change_pct") is not None),
                        "loaded_at": now,
                    }
            if base_quote.get("daily_change_available"):
                result = base_quote
            elif safe_float(base_quote.get("price")) > 0:
                proxy_estimate = _market_proxy_estimate(target, fund_name, base_quote)
                result = _quote_from_estimate(target, proxy_estimate, base_quote, now) if proxy_estimate else base_quote
            else:
                result = empty_result

        if safe_float(result.get("price")) <= 0:
            history = fetch_fund_history_series(target)
            series = [item for item in list(history.get("series") or []) if isinstance(item, dict)]
            latest = series[-1] if series else {}
            if latest:
                latest_date = normalize_text(latest.get("date"))
                is_today = latest_date[:10] == _current_market_date_text()
                result = {
                    "fund_code": target,
                    "fund_name": normalize_text(history.get("fund_name")),
                    "price": safe_float(latest.get("nav")),
                    "price_time": latest_date,
                    "price_source": "official_nav",
                    "price_source_label": "当日确认净值" if is_today else "最近净值",
                    "official_nav": safe_float(latest.get("nav")),
                    "official_nav_date": latest_date,
                    "estimate_change_pct": safe_float(latest.get("change_pct")) if is_today else 0.0,
                    "daily_change_available": bool(is_today and latest.get("change_pct") is not None),
                    "loaded_at": now,
                }
        store_loaded_cache_entry(FUND_QUOTE_CACHE, target, result)
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
