from __future__ import annotations

from typing import Any, Dict, Optional

PLATFORM_TRADE_TTL_SECONDS = 120
FUND_HISTORY_TTL_SECONDS = 12 * 60 * 60
FUND_QUOTE_TTL_SECONDS = 5 * 60

LIVE_SNAPSHOT: Optional[Dict[str, Any]] = None
PLATFORM_TRADE_CACHE: Dict[str, Dict[str, Any]] = {}
FUND_HISTORY_CACHE: Dict[str, Dict[str, Any]] = {}
FUND_QUOTE_CACHE: Dict[str, Dict[str, Any]] = {}
