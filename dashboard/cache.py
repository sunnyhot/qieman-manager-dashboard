from __future__ import annotations

import time
from threading import Lock
from typing import Any, Dict, Optional

PLATFORM_TRADE_TTL_SECONDS = 120
FUND_HISTORY_TTL_SECONDS = 12 * 60 * 60
FUND_QUOTE_TTL_SECONDS = 5 * 60
COMMENTS_TTL_SECONDS = 30
MAX_DERIVED_CACHE_ENTRIES = 64

LIVE_SNAPSHOT: Optional[Dict[str, Any]] = None
PLATFORM_TRADE_CACHE: Dict[str, Dict[str, Any]] = {}
PLATFORM_TRADE_LOCKS: Dict[str, Lock] = {}
PLATFORM_TRADE_LOCKS_GUARD = Lock()
PLATFORM_HOLDINGS_PRICING_CACHE: Dict[str, Dict[str, Any]] = {}
PLATFORM_ACTION_PRESENTATION_CACHE: Dict[str, Dict[str, Any]] = {}
PLATFORM_TIMELINE_CACHE: Dict[str, Dict[str, Any]] = {}
PLATFORM_MONTHLY_OVERVIEW_CACHE: Dict[str, Dict[str, Any]] = {}
COMMENTS_CACHE: Dict[str, Dict[str, Any]] = {}
CLIENT_AUTH_CACHE: Dict[str, Any] = {}
FUND_HISTORY_CACHE: Dict[str, Dict[str, Any]] = {}
FUND_HISTORY_LOCKS: Dict[str, Lock] = {}
FUND_HISTORY_LOCKS_GUARD = Lock()
FUND_QUOTE_CACHE: Dict[str, Dict[str, Any]] = {}
FUND_QUOTE_LOCKS: Dict[str, Lock] = {}
FUND_QUOTE_LOCKS_GUARD = Lock()


def _cache_entry_timestamp(entry: Any) -> float:
    if isinstance(entry, dict):
        try:
            return float(entry.get("ts", 0))
        except (TypeError, ValueError):
            return 0.0
    return 0.0


def store_ttl_cache_entry(
    target_cache: Dict[str, Dict[str, Any]],
    key: str,
    data: Any,
    *,
    ts: Optional[float] = None,
    max_entries: int = MAX_DERIVED_CACHE_ENTRIES,
) -> None:
    target_cache[key] = {
        "ts": time.time() if ts is None else ts,
        "data": data,
    }
    if max_entries <= 0:
        return
    while len(target_cache) > max_entries:
        oldest_key = min(target_cache, key=lambda item_key: _cache_entry_timestamp(target_cache.get(item_key)))
        target_cache.pop(oldest_key, None)


def platform_trade_lock(prod_code: str) -> Lock:
    with PLATFORM_TRADE_LOCKS_GUARD:
        lock = PLATFORM_TRADE_LOCKS.get(prod_code)
        if lock is None:
            lock = Lock()
            PLATFORM_TRADE_LOCKS[prod_code] = lock
        return lock


def fund_history_lock(fund_code: str) -> Lock:
    with FUND_HISTORY_LOCKS_GUARD:
        lock = FUND_HISTORY_LOCKS.get(fund_code)
        if lock is None:
            lock = Lock()
            FUND_HISTORY_LOCKS[fund_code] = lock
        return lock


def fund_quote_lock(fund_code: str) -> Lock:
    with FUND_QUOTE_LOCKS_GUARD:
        lock = FUND_QUOTE_LOCKS.get(fund_code)
        if lock is None:
            lock = Lock()
            FUND_QUOTE_LOCKS[fund_code] = lock
        return lock
