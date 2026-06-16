from __future__ import annotations

import hashlib
import time
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from .cache import (
    FUND_QUOTE_TTL_SECONDS,
    PLATFORM_HOLDINGS_PRICING_CACHE,
    PLATFORM_TRADE_CACHE,
    PLATFORM_TRADE_TTL_SECONDS,
    platform_trade_lock,
)
from .config import (
    HOLDING_BROAD_INDEX_KEYWORDS,
    HOLDING_CATEGORY_ORDER,
    HOLDING_INDEX_MARKERS,
    HOLDING_OVERSEAS_BOND_KEYWORDS,
    HOLDING_THEME_KEYWORDS,
    PLATFORM_ORDER_SIDE_MAP,
)
from .fund_fetcher import lookup_fund_nav_by_date, preload_fund_market_data
from .performance import performance_start, record_performance
from .snapshot import build_dashboard_client
from .utils import (
    format_decimal,
    format_signed_amount,
    format_signed_percent,
    format_time,
    format_timestamp_ms,
    normalize_date_text,
    normalize_text,
    safe_float,
    safe_int,
)


def get_snapshot_by_name(name: str) -> Dict[str, Any]:
    from .cache import LIVE_SNAPSHOT
    target = normalize_text(name)
    if target == "__live__":
        if LIVE_SNAPSHOT:
            return LIVE_SNAPSHOT
        raise FileNotFoundError(target)
    raise FileNotFoundError(target)


def normalize_platform_order(order: Dict[str, Any], adjustment_id: int) -> Dict[str, Any]:
    order_code = normalize_text(order.get("orderCode"))
    side, label = PLATFORM_ORDER_SIDE_MAP.get(order_code, ("unknown", order_code or "未知"))
    fund = order.get("fund") if isinstance(order.get("fund"), dict) else {}
    title = (
        normalize_text(order.get("variety"))
        or normalize_text(fund.get("fundName"))
        or normalize_text(fund.get("fundCode"))
        or "未命名标的"
    )
    return {
        "adjustment_id": adjustment_id,
        "order_code": order_code,
        "side": side,
        "label": label,
        "fund_code": normalize_text(fund.get("fundCode")),
        "fund_name": normalize_text(fund.get("fundName")),
        "title": title,
        "trade_unit": safe_int(order.get("tradeUnit")),
        "post_plan_unit": safe_int(order.get("postPlanUnit")),
        "trade_ratio": normalize_text(order.get("tradeRatio")),
        "strategy_type": normalize_text(order.get("strategyType")),
        "large_class": normalize_text(order.get("largeClass")),
        "class_code": normalize_text(order.get("classCode")),
        "nav": normalize_text(order.get("nav")),
        "nav_date": format_time(format_timestamp_ms(order.get("navDate")) or order.get("navDate")),
        "adjust_txn_date": format_time(format_timestamp_ms(order.get("adjustTxnDate"))),
        "buy_adjustment_id": safe_int(order.get("buyAdjustmentId")),
        "buy_date": format_time(format_timestamp_ms((order.get("gridDetail") or {}).get("buyDate"))),
    }


def platform_action_timestamp(action: Dict[str, Any]) -> int:
    return safe_int(action.get("txn_ts")) or safe_int(action.get("created_ts"))


def enrich_platform_actions_with_valuation(actions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    source_actions = [dict(item) for item in actions if isinstance(item, dict)]
    if not source_actions:
        return actions
    fund_codes = [normalize_text(item.get("fund_code")) for item in source_actions if normalize_text(item.get("fund_code"))]
    histories, quotes = preload_fund_market_data(fund_codes)
    enriched_actions: List[Dict[str, Any]] = []
    for action in source_actions:
        enriched = dict(action)
        fund_code = normalize_text(enriched.get("fund_code"))
        history = histories.get(fund_code) if fund_code else {}

        trade_valuation = safe_float(enriched.get("nav"))
        trade_valuation_date = normalize_date_text(normalize_text(enriched.get("nav_date")))
        trade_valuation_source = "调仓净值"
        if trade_valuation <= 0:
            nav_entry = lookup_fund_nav_by_date(history or {}, enriched.get("txn_date") or enriched.get("created_at"))
            trade_valuation = safe_float(nav_entry.get("nav"))
            trade_valuation_date = trade_valuation_date or normalize_date_text(normalize_text(nav_entry.get("date")))
            if trade_valuation > 0:
                trade_valuation_source = "历史净值回填"
            else:
                trade_valuation_source = ""
        elif not trade_valuation_date:
            trade_valuation_date = normalize_date_text(normalize_text(enriched.get("txn_date") or enriched.get("created_at")))

        quote = quotes.get(fund_code) if fund_code else {}
        current_valuation = safe_float(quote.get("price"))
        current_valuation_time = normalize_text(quote.get("price_time"))
        current_valuation_source = normalize_text(quote.get("price_source_label")) or "当前估值"

        valuation_change_amount = 0.0
        valuation_change_pct = 0.0
        if trade_valuation > 0 and current_valuation > 0:
            valuation_change_amount = round(current_valuation - trade_valuation, 4)
            valuation_change_pct = round((current_valuation / trade_valuation - 1.0) * 100.0, 2)

        enriched.update(
            {
                "trade_valuation": round(trade_valuation, 4) if trade_valuation > 0 else 0.0,
                "trade_valuation_date": trade_valuation_date,
                "trade_valuation_source": trade_valuation_source,
                "current_valuation": round(current_valuation, 4) if current_valuation > 0 else 0.0,
                "current_valuation_time": current_valuation_time,
                "current_valuation_source": current_valuation_source,
                "valuation_change_amount": valuation_change_amount,
                "valuation_change_pct": valuation_change_pct,
            }
        )
        enriched_actions.append(enriched)
    return enriched_actions


def enrich_platform_holdings_with_pricing(holdings: Dict[str, Any], actions: List[Dict[str, Any]]) -> Dict[str, Any]:
    items = [dict(item) for item in list(holdings.get("items") or []) if isinstance(item, dict)]
    if not items:
        return holdings
    fund_codes = [normalize_text(item.get("fund_code")) for item in items if normalize_text(item.get("fund_code"))]
    histories, quotes = preload_fund_market_data(fund_codes)
    current_keys = {
        normalize_text(item.get("fund_code")) or normalize_text(item.get("label")) or normalize_text(item.get("fund_name"))
        for item in items
    }
    action_map: Dict[str, List[Dict[str, Any]]] = {}
    for action in sorted(actions, key=platform_action_timestamp):
        action_key = normalize_text(action.get("fund_code")) or normalize_text(action.get("title")) or normalize_text(action.get("fund_name"))
        if not action_key or action_key not in current_keys:
            continue
        action_map.setdefault(action_key, []).append(action)
    enriched_items: List[Dict[str, Any]] = []
    estimate_count = 0
    fallback_count = 0
    priced_count = 0
    for item in items:
        fund_code = normalize_text(item.get("fund_code"))
        asset_key = normalize_text(item.get("fund_code")) or normalize_text(item.get("label")) or normalize_text(item.get("fund_name"))
        relevant_actions = [entry for entry in list(action_map.get(asset_key) or []) if isinstance(entry, dict)]
        simulated_units = 0
        total_cost = 0.0
        pricing_coverage_count = 0
        missing_nav_count = 0
        history = histories.get(fund_code) if fund_code else {}
        for action in relevant_actions:
            trade_units = safe_int(action.get("trade_unit"))
            if trade_units <= 0:
                continue
            nav_value = safe_float(action.get("nav"))
            if nav_value <= 0:
                nav_entry = lookup_fund_nav_by_date(history or {}, action.get("txn_date") or action.get("created_at"))
                nav_value = safe_float(nav_entry.get("nav"))
            if nav_value <= 0:
                missing_nav_count += 1
                continue
            pricing_coverage_count += 1
            if normalize_text(action.get("side")) == "buy":
                simulated_units += trade_units
                total_cost += nav_value * trade_units
                continue
            if normalize_text(action.get("side")) == "sell" and simulated_units > 0:
                sell_units = min(trade_units, simulated_units)
                average_before_sell = total_cost / simulated_units if simulated_units else 0.0
                total_cost -= average_before_sell * sell_units
                simulated_units -= sell_units
                if simulated_units <= 0:
                    simulated_units = 0
                    total_cost = 0.0
                if trade_units > sell_units:
                    missing_nav_count += trade_units - sell_units
                continue
            missing_nav_count += trade_units
        current_units = safe_int(item.get("current_units"))
        avg_cost = round(total_cost / current_units, 4) if current_units > 0 and simulated_units == current_units and total_cost > 0 else 0.0
        quote = quotes.get(fund_code) if fund_code else {}
        current_price = safe_float(quote.get("price"))
        position_cost = round(avg_cost * current_units, 2) if avg_cost > 0 and current_units > 0 else 0.0
        position_value = round(current_price * current_units, 2) if current_price > 0 and current_units > 0 else 0.0
        profit_amount = round(position_value - position_cost, 2) if position_cost > 0 and position_value > 0 else 0.0
        profit_ratio = round(((current_price / avg_cost) - 1.0) * 100.0, 2) if avg_cost > 0 and current_price > 0 else 0.0
        price_source = normalize_text(quote.get("price_source"))
        if current_price > 0:
            priced_count += 1
            if price_source == "estimate":
                estimate_count += 1
            elif price_source == "official_nav":
                fallback_count += 1
        enriched = dict(item)
        enriched.update(
            {
                "avg_cost": avg_cost,
                "position_cost": position_cost,
                "current_price": round(current_price, 4) if current_price > 0 else 0.0,
                "price_time": normalize_text(quote.get("price_time")),
                "price_source": price_source,
                "price_source_label": normalize_text(quote.get("price_source_label")),
                "official_nav": round(safe_float(quote.get("official_nav")), 4) if safe_float(quote.get("official_nav")) > 0 else 0.0,
                "official_nav_date": normalize_text(quote.get("official_nav_date")),
                "estimate_change_pct": safe_float(quote.get("estimate_change_pct")),
                "position_value": position_value,
                "profit_amount": profit_amount,
                "profit_ratio": profit_ratio,
                "cost_method": "移动平均",
                "cost_covered_actions": pricing_coverage_count,
                "cost_missing_actions": missing_nav_count,
                "cost_ready": bool(avg_cost > 0 and current_units > 0 and simulated_units == current_units),
                "quote_ready": bool(current_price > 0),
            }
        )
        enriched_items.append(enriched)
    enriched_holdings = dict(holdings)
    enriched_holdings["items"] = enriched_items
    enriched_holdings["pricing_summary"] = {
        "priced_count": priced_count,
        "estimate_count": estimate_count,
        "fallback_count": fallback_count,
        "asset_count": len(enriched_items),
    }
    return enriched_holdings


def platform_holdings_pricing_cache_key(platform_trades: Dict[str, Any], actions: List[Dict[str, Any]]) -> str:
    prod_code = normalize_text(platform_trades.get("prod_code")) if isinstance(platform_trades, dict) else ""
    action_tokens: List[str] = []
    for action in actions:
        token = normalize_text(action.get("action_key"))
        if not token:
            token = ":".join(
                [
                    str(safe_int(action.get("adjustment_id"))),
                    normalize_text(action.get("fund_code")),
                    normalize_text(action.get("side")),
                    str(platform_action_timestamp(action)),
                ]
            )
        action_tokens.append(token)
    digest_source = "|".join(action_tokens)
    digest = hashlib.sha1(digest_source.encode("utf-8")).hexdigest()[:16] if digest_source else "empty"
    return f"{prod_code}:{len(action_tokens)}:{digest}"


def get_priced_platform_holdings(platform_trades: Dict[str, Any]) -> Dict[str, Any]:
    raw_holdings = platform_trades.get("holdings") if isinstance(platform_trades.get("holdings"), dict) else {}
    actions = [item for item in list(platform_trades.get("actions") or []) if isinstance(item, dict)]
    cache_key = platform_holdings_pricing_cache_key(platform_trades, actions)
    now = time.time()
    cached = PLATFORM_HOLDINGS_PRICING_CACHE.get(cache_key)
    if cached and now - safe_float(cached.get("ts")) < FUND_QUOTE_TTL_SECONDS:
        return cached.get("data") if isinstance(cached.get("data"), dict) else raw_holdings
    priced_holdings = enrich_platform_holdings_with_pricing(raw_holdings, actions)
    PLATFORM_HOLDINGS_PRICING_CACHE[cache_key] = {
        "ts": now,
        "data": priced_holdings,
    }
    return priced_holdings


def platform_window_label(value: str) -> str:
    from .config import PLATFORM_WINDOW_OPTIONS
    target = normalize_text(value) or "all"
    for option_value, label in PLATFORM_WINDOW_OPTIONS:
        if option_value == target:
            return label
    return "全部"


def parse_date_start_ms(value: str) -> int:
    text = normalize_date_text(value)
    if not text:
        return 0
    try:
        return int(datetime.strptime(text, "%Y-%m-%d").timestamp() * 1000)
    except ValueError:
        return 0


def parse_date_end_exclusive_ms(value: str) -> int:
    text = normalize_date_text(value)
    if not text:
        return 0
    try:
        return int((datetime.strptime(text, "%Y-%m-%d") + timedelta(days=1)).timestamp() * 1000)
    except ValueError:
        return 0


def platform_window_cutoff_ms(window_value: str) -> int:
    target = normalize_text(window_value) or "all"
    now = datetime.now()
    if target == "30d":
        return int((now - timedelta(days=30)).timestamp() * 1000)
    if target == "60d":
        return int((now - timedelta(days=60)).timestamp() * 1000)
    if target == "365d":
        return int((now - timedelta(days=365)).timestamp() * 1000)
    if target == "ytd":
        return int(datetime(now.year, 1, 1).timestamp() * 1000)
    return 0


def platform_effective_range(form_values: Dict[str, str]) -> Dict[str, Any]:
    since_text = normalize_date_text(normalize_text(form_values.get("since")))
    until_text = normalize_date_text(normalize_text(form_values.get("until")))
    start_ms = parse_date_start_ms(since_text)
    end_ms = parse_date_end_exclusive_ms(until_text)
    if start_ms or end_ms:
        start_label = since_text or "最早"
        end_label = until_text or "最新"
        return {
            "mode": "custom",
            "label": f"{start_label} 至 {end_label}",
            "start_ms": start_ms,
            "end_ms": end_ms,
        }
    window_value = normalize_text(form_values.get("platform_window")) or "all"
    return {
        "mode": "window",
        "label": platform_window_label(window_value),
        "start_ms": platform_window_cutoff_ms(window_value),
        "end_ms": 0,
    }


def filter_platform_actions(platform_trades: Dict[str, Any], form_values: Dict[str, str], side: str = "all") -> List[Dict[str, Any]]:
    actions = [item for item in list(platform_trades.get("actions") or []) if isinstance(item, dict)]
    range_info = platform_effective_range(form_values)
    start_ms = safe_int(range_info.get("start_ms"))
    end_ms = safe_int(range_info.get("end_ms"))
    target_side = normalize_text(side) or "all"
    filtered: List[Dict[str, Any]] = []
    for action in actions:
        action_ts = platform_action_timestamp(action)
        if start_ms and (not action_ts or action_ts < start_ms):
            continue
        if end_ms and action_ts and action_ts >= end_ms:
            continue
        if target_side in {"buy", "sell"} and normalize_text(action.get("side")) != target_side:
            continue
        filtered.append(action)
    return filtered


def summarize_filtered_platform_actions(actions: List[Dict[str, Any]]) -> Dict[str, Any]:
    buy_count = 0
    sell_count = 0
    adjustment_ids = set()
    latest = actions[0] if actions else None
    for action in actions:
        side = normalize_text(action.get("side"))
        if side == "buy":
            buy_count += 1
        if side == "sell":
            sell_count += 1
        adjustment_id = safe_int(action.get("adjustment_id"))
        if adjustment_id:
            adjustment_ids.add(adjustment_id)
    return {
        "count": len(actions),
        "buy_count": buy_count,
        "sell_count": sell_count,
        "adjustment_count": len(adjustment_ids),
        "latest": latest,
    }


def _empty_platform_action_summary() -> Dict[str, Any]:
    return {
        "count": 0,
        "buy_count": 0,
        "sell_count": 0,
        "adjustment_ids": set(),
        "latest": None,
    }


def _accumulate_platform_action_summary(summary: Dict[str, Any], action: Dict[str, Any]) -> None:
    summary["count"] += 1
    if summary.get("latest") is None:
        summary["latest"] = action
    side = normalize_text(action.get("side"))
    if side == "buy":
        summary["buy_count"] += 1
    if side == "sell":
        summary["sell_count"] += 1
    adjustment_id = safe_int(action.get("adjustment_id"))
    if adjustment_id:
        summary["adjustment_ids"].add(adjustment_id)


def _finish_platform_action_summary(summary: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "count": safe_int(summary.get("count")),
        "buy_count": safe_int(summary.get("buy_count")),
        "sell_count": safe_int(summary.get("sell_count")),
        "adjustment_count": len(summary.get("adjustment_ids") or set()),
        "latest": summary.get("latest"),
    }


def build_platform_action_presentation(
    platform_trades: Dict[str, Any],
    form_values: Dict[str, str],
    selected_side: str = "all",
) -> Dict[str, Any]:
    range_info = platform_effective_range(form_values)
    start_ms = safe_int(range_info.get("start_ms"))
    end_ms = safe_int(range_info.get("end_ms"))
    target_side = normalize_text(selected_side) or "all"
    actions_by_side: Dict[str, List[Dict[str, Any]]] = {
        "all": [],
        "buy": [],
        "sell": [],
    }
    summary_builders: Dict[str, Dict[str, Any]] = {
        "all": _empty_platform_action_summary(),
        "buy": _empty_platform_action_summary(),
        "sell": _empty_platform_action_summary(),
    }
    source_actions = platform_trades.get("actions") if isinstance(platform_trades, dict) else []
    for action in source_actions or []:
        if not isinstance(action, dict):
            continue
        action_ts = platform_action_timestamp(action)
        if start_ms and (not action_ts or action_ts < start_ms):
            continue
        if end_ms and action_ts and action_ts >= end_ms:
            continue
        actions_by_side["all"].append(action)
        _accumulate_platform_action_summary(summary_builders["all"], action)
        side = normalize_text(action.get("side"))
        if side in {"buy", "sell"}:
            actions_by_side[side].append(action)
            _accumulate_platform_action_summary(summary_builders[side], action)

    summaries = {
        side: _finish_platform_action_summary(summary)
        for side, summary in summary_builders.items()
    }
    filtered_actions = actions_by_side[target_side] if target_side in {"buy", "sell"} else actions_by_side["all"]
    return {
        "range_info": range_info,
        "all_actions": actions_by_side["all"],
        "filtered_actions": filtered_actions,
        "actions_by_side": actions_by_side,
        "summary_all": summaries["all"],
        "summary_buy": summaries["buy"],
        "summary_sell": summaries["sell"],
        "summaries": summaries,
    }


def build_platform_timeline_from_actions(actions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    grouped: Dict[str, Dict[str, Any]] = {}
    for action in actions:
        label = normalize_text(action.get("title")) or normalize_text(action.get("fund_name")) or normalize_text(action.get("fund_code")) or "未命名标的"
        bucket = grouped.setdefault(
            label,
            {
                "label": label,
                "entries": [],
                "buy_count": 0,
                "sell_count": 0,
                "event_count": 0,
                "latest_time": "",
                "latest_ts": 0,
            },
        )
        bucket["entries"].append(action)
        bucket["event_count"] += 1
        if normalize_text(action.get("side")) == "buy":
            bucket["buy_count"] += 1
        if normalize_text(action.get("side")) == "sell":
            bucket["sell_count"] += 1
        action_ts = platform_action_timestamp(action)
        if action_ts >= safe_int(bucket.get("latest_ts")):
            bucket["latest_ts"] = action_ts
            bucket["latest_time"] = normalize_text(action.get("txn_date") or action.get("created_at"))
    items: List[Dict[str, Any]] = []
    for bucket in grouped.values():
        entries = sorted(bucket["entries"], key=platform_action_timestamp, reverse=True)
        items.append(
            {
                "label": bucket["label"],
                "entries": entries[:12],
                "buy_count": bucket["buy_count"],
                "sell_count": bucket["sell_count"],
                "event_count": bucket["event_count"],
                "latest_time": bucket["latest_time"],
                "latest_ts": bucket["latest_ts"],
            }
        )
    items.sort(key=lambda item: (-safe_int(item.get("event_count")), -safe_int(item.get("latest_ts"))))
    return items


def build_platform_holdings_from_actions(actions: List[Dict[str, Any]]) -> Dict[str, Any]:
    latest_by_asset: Dict[str, Dict[str, Any]] = {}
    for action in sorted(actions, key=platform_action_timestamp, reverse=True):
        asset_key = normalize_text(action.get("fund_code")) or normalize_text(action.get("title")) or normalize_text(action.get("fund_name"))
        if not asset_key or asset_key in latest_by_asset:
            continue
        latest_by_asset[asset_key] = {
            "asset_key": asset_key,
            "label": normalize_text(action.get("title")) or normalize_text(action.get("fund_name")) or asset_key,
            "fund_name": normalize_text(action.get("fund_name")),
            "fund_code": normalize_text(action.get("fund_code")),
            "current_units": safe_int(action.get("post_plan_unit")),
            "latest_action": normalize_text(action.get("action")),
            "latest_action_title": normalize_text(action.get("action_title")),
            "latest_time": normalize_text(action.get("txn_date") or action.get("created_at")),
            "latest_ts": platform_action_timestamp(action),
            "strategy_type": normalize_text(action.get("strategy_type")),
            "large_class": normalize_text(action.get("large_class")),
            "buy_date": normalize_text(action.get("buy_date")),
        }

    items = [
        item
        for item in latest_by_asset.values()
        if safe_int(item.get("current_units")) > 0
    ]
    items.sort(
        key=lambda item: (
            -safe_int(item.get("current_units")),
            -safe_int(item.get("latest_ts")),
            normalize_text(item.get("label")),
        )
    )
    latest_item = max(items, key=lambda item: safe_int(item.get("latest_ts")), default={})
    return {
        "asset_count": len(items),
        "total_units": sum(safe_int(item.get("current_units")) for item in items),
        "latest_time": normalize_text(latest_item.get("latest_time")),
        "latest_ts": safe_int(latest_item.get("latest_ts")),
        "items": items,
        "breakdown": build_platform_holdings_breakdown(
            {
                "items": items,
            }
        ),
    }


def classify_platform_holding_category(item: Dict[str, Any]) -> str:
    label = normalize_text(item.get("label"))
    fund_name = normalize_text(item.get("fund_name"))
    large_class = normalize_text(item.get("large_class"))
    text = " ".join(part for part in [label, fund_name, large_class] if part)
    lower_text = text.lower()

    if "黄金" in text:
        return "黄金"
    if "红利" in text:
        return "红利策略"
    if "海外债券" in large_class or any(keyword in text for keyword in HOLDING_OVERSEAS_BOND_KEYWORDS):
        return "海外债券"
    if "海外" in large_class or "qdii" in lower_text:
        return "海外权益"
    if "债" in text or "债券" in large_class:
        return "债券固收"
    if any(keyword in text for keyword in HOLDING_BROAD_INDEX_KEYWORDS):
        return "宽基指数"
    if large_class == "A股" and any(keyword in text for keyword in HOLDING_THEME_KEYWORDS) and any(
        marker in text for marker in HOLDING_INDEX_MARKERS
    ):
        return "行业主题"
    if large_class == "A股" and not any(marker in text for marker in HOLDING_INDEX_MARKERS):
        return "主动权益"
    return "其他"


def build_platform_holdings_breakdown(holdings: Dict[str, Any]) -> Dict[str, Any]:
    items = [item for item in list(holdings.get("items") or []) if isinstance(item, dict)]
    total_units = sum(safe_int(item.get("current_units")) for item in items)
    grouped: Dict[str, Dict[str, Any]] = {}
    for category in HOLDING_CATEGORY_ORDER:
        grouped[category] = {
            "label": category,
            "units": 0,
            "ratio": 0.0,
            "items": [],
        }
    for item in items:
        category = classify_platform_holding_category(item)
        bucket = grouped.setdefault(
            category,
            {
                "label": category,
                "units": 0,
                "ratio": 0.0,
                "items": [],
            },
        )
        units = safe_int(item.get("current_units"))
        bucket["units"] += units
        bucket["items"].append(
            {
                "label": normalize_text(item.get("label")) or normalize_text(item.get("fund_name")) or normalize_text(item.get("fund_code")),
                "units": units,
            }
        )
    categories: List[Dict[str, Any]] = []
    for category in HOLDING_CATEGORY_ORDER:
        bucket = grouped.get(category) or {}
        units = safe_int(bucket.get("units"))
        categories.append(
            {
                "label": category,
                "units": units,
                "ratio": round((units / total_units * 100.0), 1) if total_units else 0.0,
                "items": sorted(
                    [entry for entry in list(bucket.get("items") or []) if isinstance(entry, dict)],
                    key=lambda entry: (-safe_int(entry.get("units")), normalize_text(entry.get("label"))),
                ),
            }
        )
    requested_labels = [label for label in HOLDING_CATEGORY_ORDER if label != "其他"]
    requested_categories = [item for item in categories if item.get("label") in requested_labels]
    remainder_categories = [item for item in categories if item.get("label") not in requested_labels and safe_int(item.get("units")) > 0]
    return {
        "total_units": total_units,
        "categories": categories,
        "requested_categories": requested_categories,
        "remainder_categories": remainder_categories,
    }


def build_platform_trade_data(prod_code: str, raw_items: List[Dict[str, Any]]) -> Dict[str, Any]:
    adjustments: List[Dict[str, Any]] = []
    actions: List[Dict[str, Any]] = []
    for raw_item in raw_items:
        adjustment_id = safe_int(raw_item.get("adjustmentId"))
        created_ts = safe_int(raw_item.get("adjustCreateTime"))
        txn_ts = safe_int(raw_item.get("adjustTxnDate"))
        normalized_orders = [
            normalize_platform_order(order, adjustment_id)
            for order in list(raw_item.get("orders") or [])
            if isinstance(order, dict)
        ]
        adjustment_title = normalize_text(raw_item.get("comment")) or f"调仓 {adjustment_id}"
        article_url = normalize_text(raw_item.get("url"))
        created_at = format_time(format_timestamp_ms(created_ts))
        txn_date = format_time(format_timestamp_ms(txn_ts))
        order_count = 0
        for index, order in enumerate(normalized_orders, start=1):
            side = normalize_text(order.get("side"))
            if side not in {"buy", "sell"}:
                continue
            order_count += 1
            action_title = f"{normalize_text(order.get('label'))}{safe_int(order.get('trade_unit'))}份{normalize_text(order.get('title'))}"
            actions.append(
                {
                    "action_key": f"{adjustment_id}:{normalize_text(order.get('fund_code'))}:{side}:{index}",
                    "adjustment_id": adjustment_id,
                    "adjustment_title": adjustment_title,
                    "title": normalize_text(order.get("title")),
                    "action_title": action_title,
                    "fund_name": order["fund_name"],
                    "fund_code": order["fund_code"],
                    "side": side,
                    "action": order["label"],
                    "trade_unit": order["trade_unit"],
                    "post_plan_unit": order["post_plan_unit"],
                    "created_at": created_at,
                    "txn_date": txn_date,
                    "created_ts": created_ts,
                    "txn_ts": txn_ts,
                    "article_url": article_url,
                    "comment": adjustment_title,
                    "strategy_type": normalize_text(order.get("strategy_type")),
                    "large_class": normalize_text(order.get("large_class")),
                    "buy_date": normalize_text(order.get("buy_date")),
                    "nav": safe_float(order.get("nav")),
                    "nav_date": normalize_text(order.get("nav_date")),
                    "order_count_in_adjustment": len(normalized_orders),
                }
            )
        adjustments.append(
            {
                "adjustment_id": adjustment_id,
                "title": adjustment_title,
                "description": normalize_text(raw_item.get("description")),
                "article_url": article_url,
                "created_at": created_at,
                "txn_date": txn_date,
                "created_ts": created_ts,
                "txn_ts": txn_ts,
                "invest_type": normalize_text(raw_item.get("investType")),
                "orders": normalized_orders,
                "order_count": order_count,
            }
        )
    actions = sorted(actions, key=platform_action_timestamp, reverse=True)
    actions = enrich_platform_actions_with_valuation(actions)
    adjustments = sorted(
        adjustments,
        key=lambda item: safe_int(item.get("txn_ts")) or safe_int(item.get("created_ts")),
        reverse=True,
    )
    summary = summarize_filtered_platform_actions(actions)
    return {
        "supported": True,
        "prod_code": prod_code,
        "count": summary["count"],
        "buy_count": summary["buy_count"],
        "sell_count": summary["sell_count"],
        "adjustment_count": len(adjustments),
        "latest": summary["latest"],
        "latest_adjustment": adjustments[0] if adjustments else None,
        "actions": actions,
        "items": adjustments,
        "holdings": build_platform_holdings_from_actions(actions),
        "timeline": build_platform_timeline_from_actions(actions),
    }


def fetch_platform_trade_data(prod_code: str, timeout_seconds: int = 10) -> Dict[str, Any]:
    from .config import PLATFORM_FETCH_TIMEOUT_SECONDS
    started_at = performance_start()
    cache_status = "miss"

    if timeout_seconds <= 0:
        timeout_seconds = PLATFORM_FETCH_TIMEOUT_SECONDS
    target = normalize_text(prod_code)
    if not target:
        cache_status = "empty"
        try:
            return {
                "supported": False,
                "error": "没有产品代码，无法直拉平台调仓记录。",
                "prod_code": "",
            }
        finally:
            record_performance("platform.fetch", started_at, prod_code="<empty>", cache=cache_status)
    cached = PLATFORM_TRADE_CACHE.get(target)
    now = time.time()
    if cached and now - float(cached.get("ts", 0)) < PLATFORM_TRADE_TTL_SECONDS:
        cache_status = "hit"
        record_performance("platform.fetch", started_at, prod_code=target, cache=cache_status)
        return cached["data"]

    with platform_trade_lock(target):
        cached = PLATFORM_TRADE_CACHE.get(target)
        now = time.time()
        if cached and now - float(cached.get("ts", 0)) < PLATFORM_TRADE_TTL_SECONDS:
            cache_status = "hit_after_wait"
            record_performance("platform.fetch", started_at, prod_code=target, cache=cache_status)
            return cached["data"]

        client = build_dashboard_client()
        try:
            raw = client.get(
                "/long-win/plan/adjustments",
                {"desc": "true", "prodCode": target},
                timeout=max(1, safe_int(timeout_seconds)),
            )
            if not isinstance(raw, list):
                raise RuntimeError("平台调仓接口返回结构异常")
            data = build_platform_trade_data(target, [item for item in raw if isinstance(item, dict)])
        except Exception as exc:
            data = {
                "supported": False,
                "error": str(exc),
                "prod_code": target,
            }
        PLATFORM_TRADE_CACHE[target] = {"ts": now, "data": data}
        record_performance(
            "platform.fetch",
            started_at,
            prod_code=target,
            cache=cache_status,
            supported=bool(data.get("supported")),
            action_count=len(data.get("actions") or []),
        )
        return data
