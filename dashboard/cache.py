from __future__ import annotations

from threading import Lock
from typing import Any, Dict, Optional

PLATFORM_TRADE_TTL_SECONDS = 120
FUND_HISTORY_TTL_SECONDS = 12 * 60 * 60
FUND_QUOTE_TTL_SECONDS = 5 * 60
COMMENTS_TTL_SECONDS = 30

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
