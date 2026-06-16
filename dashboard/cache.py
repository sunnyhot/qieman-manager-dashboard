from __future__ import annotations

import time
from threading import Lock
from typing import Any, Dict, Optional

PLATFORM_TRADE_TTL_SECONDS = 120
FUND_HISTORY_TTL_SECONDS = 12 * 60 * 60
FUND_QUOTE_TTL_SECONDS = 5 * 60
COMMENTS_TTL_SECONDS = 30
MAX_DERIVED_CACHE_ENTRIES = 64
MAX_FUND_CACHE_ENTRIES = 256

LIVE_SNAPSHOT: Optional[Dict[str, Any]] = None
PLATFORM_TRADE_CACHE: Dict[str, Dict[str, Any]] = {}
PLATFORM_TRADE_LOCKS: Dict[str, Lock] = {}
PLATFORM_TRADE_LOCKS_GUARD = Lock()
PLATFORM_HOLDINGS_PRICING_CACHE: Dict[str, Dict[str, Any]] = {}
PLATFORM_ACTION_VALUATION_CACHE: Dict[str, Dict[str, Any]] = {}
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
        for key in ("ts", "loaded_at"):
            try:
                value = float(entry.get(key, 0))
            except (TypeError, ValueError):
                value = 0.0
            if value > 0:
                return value
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


def store_loaded_cache_entry(
    target_cache: Dict[str, Dict[str, Any]],
    key: str,
    data: Dict[str, Any],
    *,
    max_entries: int = MAX_FUND_CACHE_ENTRIES,
) -> None:
    target_cache[key] = data
    if max_entries <= 0:
        return
    while len(target_cache) > max_entries:
        oldest_key = min(target_cache, key=lambda item_key: _cache_entry_timestamp(target_cache.get(item_key)))
        target_cache.pop(oldest_key, None)


def _store_lock(
    lock_cache: Dict[str, Lock],
    key: str,
    *,
    max_entries: int,
) -> Lock:
    lock = lock_cache.get(key)
    if lock is None:
        lock = Lock()
        lock_cache[key] = lock
    if max_entries <= 0:
        return lock
    while len(lock_cache) > max_entries:
        removable_key = next(
            (
                item_key
                for item_key, item_lock in lock_cache.items()
                if item_key != key and not item_lock.locked()
            ),
            None,
        )
        if removable_key is None:
            break
        lock_cache.pop(removable_key, None)
    return lock


def platform_trade_lock(prod_code: str) -> Lock:
    with PLATFORM_TRADE_LOCKS_GUARD:
        return _store_lock(PLATFORM_TRADE_LOCKS, prod_code, max_entries=MAX_DERIVED_CACHE_ENTRIES)


def fund_history_lock(fund_code: str) -> Lock:
    with FUND_HISTORY_LOCKS_GUARD:
        return _store_lock(FUND_HISTORY_LOCKS, fund_code, max_entries=MAX_FUND_CACHE_ENTRIES)


def fund_quote_lock(fund_code: str) -> Lock:
    with FUND_QUOTE_LOCKS_GUARD:
        return _store_lock(FUND_QUOTE_LOCKS, fund_code, max_entries=MAX_FUND_CACHE_ENTRIES)
