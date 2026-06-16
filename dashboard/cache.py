from __future__ import annotations

from threading import Lock
from typing import Any, Dict, Optional

PLATFORM_TRADE_TTL_SECONDS = 120
FUND_HISTORY_TTL_SECONDS = 12 * 60 * 60
FUND_QUOTE_TTL_SECONDS = 5 * 60

LIVE_SNAPSHOT: Optional[Dict[str, Any]] = None
PLATFORM_TRADE_CACHE: Dict[str, Dict[str, Any]] = {}
PLATFORM_TRADE_LOCKS: Dict[str, Lock] = {}
PLATFORM_TRADE_LOCKS_GUARD = Lock()
PLATFORM_HOLDINGS_PRICING_CACHE: Dict[str, Dict[str, Any]] = {}
FUND_HISTORY_CACHE: Dict[str, Dict[str, Any]] = {}
FUND_QUOTE_CACHE: Dict[str, Dict[str, Any]] = {}


def platform_trade_lock(prod_code: str) -> Lock:
    with PLATFORM_TRADE_LOCKS_GUARD:
        lock = PLATFORM_TRADE_LOCKS.get(prod_code)
        if lock is None:
            lock = Lock()
            PLATFORM_TRADE_LOCKS[prod_code] = lock
        return lock
