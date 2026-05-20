from __future__ import annotations

import html
from datetime import datetime
from typing import Any, Dict, List, Optional
from urllib.parse import urlencode

from .config import (
    MODE_OPTIONS,
    PLATFORM_SIGNAL_SECTION_ID,
    PLATFORM_TIMELINE_SECTION_ID,
    PLATFORM_WINDOW_OPTIONS,
)
from .html_helpers import (
    append_url_fragment,
    build_route_url,
    first_mapping_value,
    format_decimal,
    format_signed_percent,
    html_text,
    metric_cards,
    normalize_date_text,
    normalize_text,
    platform_action_date_text,
    render_platform_trade_overview,
    safe_float,
    safe_int,
    snapshot_section_title,
)
from .platform_fetcher import (
    build_platform_timeline_from_actions,
    enrich_platform_holdings_with_pricing,
    filter_platform_actions,
    platform_effective_range,
    summarize_filtered_platform_actions,
)
from .utils import (
    format_amount,
    format_signed_amount,
    format_time,
    strip_html,
)


def render_signal_panel(
    platform_trades: Dict[str, Any],
    form_values: Dict[str, str],
    snapshot_name: str,
    signal_filter: str,
    timeline_asset: str,
    page_path: str = "/",
    card_limit: int = 36,
    home_mode: bool = False,
    section_anchor: str = "",
) -> str:
    if not platform_trades:
        return ""
    if not platform_trades.get("supported"):
        if not normalize_text(platform_trades.get("error")):
            return ""
        return (
            '<section class="panel">'
            '<div class="snapshot-head"><div><h2>平台调仓</h2>'
            '<p class="muted">这里优先展示从且慢平台直拉的真实调仓记录，不再只靠帖子正文推断。</p>'
            '</div></div>'
            f'<div class="empty">{html.escape(normalize_text(platform_trades.get("error")))}</div>'
            '</section>'
        )
    platform_window = normalize_text(form_values.get("platform_window")) or "all"
    section_anchor = normalize_text(section_anchor).lstrip("#")
    range_info = platform_effective_range(form_values)
    range_label = normalize_text(range_info.get("label")) or "全部"
    using_custom_range = normalize_text(range_info.get("mode")) == "custom"
    all_actions = filter_platform_actions(platform_trades, form_values, "all")
    filtered_actions = filter_platform_actions(platform_trades, form_values, signal_filter)
    summary_all = summarize_filtered_platform_actions(all_actions)
    summary_buy = summarize_filtered_platform_actions(filter_platform_actions(platform_trades, form_values, "buy"))
    summary_sell = summarize_filtered_platform_actions(filter_platform_actions(platform_trades, form_values, "sell"))
    trade_overview_html = render_platform_trade_overview(all_actions, range_label, using_custom_range)
    toolbar = []
    for value, label, count in [
        ("all", "全部动作", safe_int(summary_all.get("count"))),
        ("buy", "只看买入", safe_int(summary_buy.get("count"))),
        ("sell", "只看卖出", safe_int(summary_sell.get("count"))),
    ]:
        url = build_route_url(
            page_path,
            form_values,
            snapshot=snapshot_name or None,
            signal_filter=value if value != "all" else None,
            timeline_asset=timeline_asset if timeline_asset != "all" else None,
        )
        url = append_url_fragment(url, section_anchor)
        toolbar.append(f'<a class="mini-btn{" active" if signal_filter == value else ""}" href="{html.escape(url)}">{html.escape(label)} · {count}</a>')
    window_toolbar = []
    if using_custom_range:
        window_toolbar.append(f'<span class="chip">已跟随左侧起止日期：{html.escape(range_label)}</span>')
    else:
        for value, label in PLATFORM_WINDOW_OPTIONS:
            url = build_route_url(
                page_path,
                form_values,
                snapshot=snapshot_name or None,
                signal_filter=signal_filter if signal_filter != "all" else None,
                timeline_asset=timeline_asset if timeline_asset != "all" else None,
                platform_window=value if value != "all" else None,
            )
            url = append_url_fragment(url, section_anchor)
            active = platform_window == value or (platform_window == "" and value == "all")
            window_toolbar.append(f'<a class="mini-btn{" active" if active else ""}" href="{html.escape(url)}">{html.escape(label)}</a>')
    signal_cards = []
    for action in filtered_actions[:card_limit]:
        card_side = normalize_text(action.get("side")) or "watch"
        detail_bits = [
            normalize_text(action.get("title")),
            normalize_text(action.get("fund_code")),
            normalize_text(action.get("strategy_type")),
            normalize_text(action.get("large_class")),
        ]
        detail = " · ".join(bit for bit in detail_bits if bit)
        if normalize_text(action.get("buy_date")):
            detail += f" · 买入日期 {normalize_text(action.get('buy_date'))}"
        if safe_int(action.get("post_plan_unit")):
            detail += f" · 当前计划份数 {safe_int(action.get('post_plan_unit'))}"
        summary_line = normalize_text(action.get("comment"))
        article_url = normalize_text(action.get("article_url"))
        related_count = max(0, safe_int(action.get("order_count_in_adjustment")) - 1)
        trade_valuation = safe_float(action.get("trade_valuation"))
        trade_valuation_date = normalize_date_text(normalize_text(action.get("trade_valuation_date")))
        current_valuation = safe_float(action.get("current_valuation"))
        current_valuation_source = normalize_text(action.get("current_valuation_source")) or "当前估值"
        current_valuation_time = normalize_text(action.get("current_valuation_time"))
        valuation_change_pct = safe_float(action.get("valuation_change_pct"))
        trade_valuation_text = format_decimal(trade_valuation) if trade_valuation > 0 else "—"
        if trade_valuation > 0 and trade_valuation_date:
            trade_valuation_text += f"（{trade_valuation_date}）"
        current_valuation_text = format_decimal(current_valuation) if current_valuation > 0 else "—"
        if current_valuation > 0 and current_valuation_time:
            current_valuation_text += f"（{current_valuation_time}）"
        valuation_line = f"调仓时估值 {trade_valuation_text} · 当前{current_valuation_source} {current_valuation_text}"
        if trade_valuation > 0 and current_valuation > 0:
            valuation_line += f" · 变化 {format_signed_percent(valuation_change_pct)}"
        signal_cards.append(
            f'<article class="signal-card {html.escape(card_side)}">'
            '<div class="signal-top">'
            f'<h3 class="signal-title">{html_text(action.get("action_title"))}</h3>'
            f'<span class="signal-badge {html.escape(card_side)}">{html_text(action.get("txn_date") or action.get("created_at"))}</span>'
            "</div>"
            f'<div class="record-meta"><span>调仓单 {safe_int(action.get("adjustment_id"))}</span><span>{html_text(action.get("action"))} {safe_int(action.get("trade_unit"))} 份</span><span>{html_text(action.get("fund_name"))}</span><span>创建 {html_text(action.get("created_at"))}</span></div>'
            f'<div class="signal-events"><div class="signal-line">{html.escape(detail)}</div>'
            + f'<div class="signal-line">{html.escape(valuation_line)}</div>'
            + (f'<div class="signal-line">同单说明 · {html.escape(summary_line)}</div>' if summary_line else "")
            + (f'<div class="signal-line">同一调仓单还包含 {related_count} 个其他动作</div>' if related_count else "")
            + '</div>'
            + (f'<a class="mini-btn" href="{html.escape(article_url)}">打开平台原文</a>' if article_url else "")
            + "</article>"
        )
    signal_list_html = "".join(signal_cards) if signal_cards else '<div class="empty">当前筛选下没有平台调仓记录。</div>'
    latest = summary_all.get("latest") or {}
    latest_text = normalize_text(latest.get("action_title")) or "暂无"
    detail_url = build_route_url(
        "/platform",
        form_values,
        snapshot=snapshot_name or None,
        signal_filter=signal_filter if signal_filter != "all" else None,
        timeline_asset=timeline_asset if timeline_asset != "all" else None,
        platform_window=platform_window if platform_window != "all" else None,
    )
    detail_url = append_url_fragment(detail_url, PLATFORM_SIGNAL_SECTION_ID)
    timeline_url = build_route_url(
        "/timeline",
        form_values,
        snapshot=snapshot_name or None,
        signal_filter=signal_filter if signal_filter != "all" else None,
        timeline_asset=timeline_asset if timeline_asset != "all" else None,
        platform_window=platform_window if platform_window != "all" else None,
    )
    timeline_url = append_url_fragment(timeline_url, PLATFORM_TIMELINE_SECTION_ID)
    home_url = build_route_url(
        "/",
        form_values,
        snapshot=snapshot_name or None,
        signal_filter=signal_filter if signal_filter != "all" else None,
        timeline_asset=timeline_asset if timeline_asset != "all" else None,
        platform_window=platform_window if platform_window != "all" else None,
    )
    if home_mode:
        head_actions = (
            f'<div class="record-actions"><a class="mini-btn" href="{html.escape(detail_url)}">查看全部调仓</a>'
            f'<a class="mini-btn" href="{html.escape(timeline_url)}">查看按标的时间线</a></div>'
        )
    else:
        head_actions = (
            f'<div class="record-actions"><a class="mini-btn" href="{html.escape(home_url)}">返回主理人看板</a>'
            f'<a class="mini-btn" href="{html.escape(timeline_url)}">查看按标的时间线</a></div>'
        )
    if home_mode:
        subline = (
            f'当前时间范围：{html.escape(range_label)}{"（跟随左侧日期）" if using_custom_range else ""}。最近动作：'
            f'{html.escape(latest_text[:60] + ("…" if len(latest_text) > 60 else ""))}。'
            f'首页只展示最近 {min(card_limit, len(filtered_actions))} 条，更多请进调仓详情页。'
        )
    else:
        subline = (
            f'当前时间范围：{html.escape(range_label)}{"（跟随左侧日期）" if using_custom_range else ""}。最近动作：'
            f'{html.escape(latest_text[:60] + ("…" if len(latest_text) > 60 else ""))}。'
            f'当前列表展示 {min(card_limit, len(filtered_actions))} / {len(filtered_actions)} 条。'
        )
    section_open = (
        f'<section id="{html.escape(section_anchor)}" class="panel">'
        if section_anchor
        else '<section class="panel">'
    )
    return (
        section_open
        + '<div class="snapshot-head">'
        '<div>'
        '<h2>平台调仓</h2>'
        '<p class="muted">这里直接来自且慢平台调仓接口 `/long-win/plan/adjustments`，不再只靠帖子内容匹配买卖动作。</p>'
        '</div>'
        f'{head_actions}'
        '</div>'
        '<div class="metrics signal-metrics">'
        f'<div class="metric"><small>调仓记录</small><strong>{safe_int(summary_all.get("count"))}</strong></div>'
        f'<div class="metric"><small>买入动作</small><strong>{safe_int(summary_all.get("buy_count"))}</strong></div>'
        f'<div class="metric"><small>卖出动作</small><strong>{safe_int(summary_all.get("sell_count"))}</strong></div>'
        f'<div class="metric"><small>覆盖调仓单</small><strong>{safe_int(summary_all.get("adjustment_count"))}</strong></div>'
        '</div>'
        f'{trade_overview_html}'
        f'<div class="toolbar">{"".join(toolbar)}</div>'
        f'<div class="toolbar">{"".join(window_toolbar)}</div>'
        f'<div class="record-subline">{subline}</div>'
        f'<div class="signal-list">{signal_list_html}</div>'
        '</section>'
    )


def render_platform_holdings_panel(platform_trades: Dict[str, Any]) -> str:
    if not platform_trades or not platform_trades.get("supported"):
        return ""
    raw_holdings = platform_trades.get("holdings") if isinstance(platform_trades.get("holdings"), dict) else {}
    holdings = enrich_platform_holdings_with_pricing(
        raw_holdings,
        [item for item in list(platform_trades.get("actions") or []) if isinstance(item, dict)],
    )
    items = [item for item in list(holdings.get("items") or []) if isinstance(item, dict)]
    breakdown = holdings.get("breakdown") if isinstance(holdings.get("breakdown"), dict) else {}
    pricing_summary = holdings.get("pricing_summary") if isinstance(holdings.get("pricing_summary"), dict) else {}
    requested_categories = [
        item
        for item in list(breakdown.get("requested_categories") or [])
        if isinstance(item, dict) and safe_int(item.get("units")) > 0
    ]
    remainder_categories = [item for item in list(breakdown.get("remainder_categories") or []) if isinstance(item, dict)]
    latest_time = format_time(holdings.get("latest_time"))
    allocation_cards: List[str] = []
    for category in requested_categories:
        ratio = float(category.get("ratio") or 0.0)
        units = safe_int(category.get("units"))
        top_items = [entry for entry in list(category.get("items") or []) if isinstance(entry, dict)][:3]
        examples = " / ".join(
            f"{normalize_text(entry.get('label'))} {safe_int(entry.get('units'))}份"
            for entry in top_items
            if normalize_text(entry.get("label"))
        )
        allocation_cards.append(
            '<article class="allocation-card">'
            f'<div class="allocation-row"><strong>{html.escape(normalize_text(category.get("label")) or "未分类")}</strong><span>{ratio:.1f}%</span></div>'
            f'<div class="allocation-track"><div class="allocation-fill" style="width:{max(0.0, min(ratio, 100.0)):.1f}%"></div></div>'
            f'<div class="allocation-meta">{units} 份</div>'
            + (f'<div class="allocation-note">{html.escape(examples)}</div>' if examples else "")
            + '</article>'
        )
    remainder_html = ""
    if remainder_categories:
        extras = []
        for category in remainder_categories:
            extras.append(
                f'{normalize_text(category.get("label")) or "未分类"} {float(category.get("ratio") or 0.0):.1f}%（{safe_int(category.get("units"))}份）'
            )
        remainder_html = (
            '<div class="record-subline">'
            '补充说明：按常见资产分类口径仍无法稳定归类的部分有 '
            + html.escape("；".join(extras))
            + '。我把它们单列出来，避免硬塞进不合适的分类后导致占比失真。'
            '</div>'
        )
    cards: List[str] = []
    for item in items:
        label = normalize_text(item.get("label")) or normalize_text(item.get("fund_name")) or normalize_text(item.get("fund_code")) or "未命名标的"
        fund_name = normalize_text(item.get("fund_name"))
        fund_code = normalize_text(item.get("fund_code"))
        units = safe_int(item.get("current_units"))
        latest_action_title = normalize_text(item.get("latest_action_title")) or normalize_text(item.get("latest_action"))
        latest_action = normalize_text(item.get("latest_action"))
        meta_parts = []
        if fund_code:
            meta_parts.append(f"<span>代码 {html.escape(fund_code)}</span>")
        meta_parts.append(f"<span>当前 {units} 份</span>")
        if latest_action:
            meta_parts.append(f"<span>最近动作 {html.escape(latest_action)}</span>")
        if normalize_text(item.get("large_class")):
            meta_parts.append(f"<span>{html.escape(normalize_text(item.get('large_class')))}</span>")
        if normalize_text(item.get("strategy_type")):
            meta_parts.append(f"<span>{html.escape(normalize_text(item.get('strategy_type')))}</span>")
        note_parts = []
        if latest_action_title:
            note_parts.append(f"最近一次涉及这只标的的调仓：{latest_action_title}")
        if normalize_text(item.get("latest_time")):
            note_parts.append(f"时间 {normalize_text(item.get('latest_time'))}")
        if normalize_text(item.get("buy_date")) and normalize_text(item.get("buy_date")) != "未记录":
            note_parts.append(f"首次买入 {normalize_text(item.get('buy_date'))}")
        pricing_html = ""
        if item.get("cost_ready") or item.get("quote_ready"):
            avg_cost = safe_float(item.get("avg_cost"))
            current_price = safe_float(item.get("current_price"))
            position_value = safe_float(item.get("position_value"))
            profit_amount = safe_float(item.get("profit_amount"))
            profit_ratio = safe_float(item.get("profit_ratio"))
            profit_class = "flat"
            if profit_amount > 0:
                profit_class = "up"
            elif profit_amount < 0:
                profit_class = "down"
            quote_label = normalize_text(item.get("price_source_label")) or "当前估值"
            quote_time = normalize_text(item.get("price_time"))
            official_nav = safe_float(item.get("official_nav"))
            official_nav_date = normalize_text(item.get("official_nav_date"))
            coverage_note_parts = []
            if item.get("cost_ready"):
                coverage_note_parts.append(
                    f"平均成本按{safe_int(item.get('cost_covered_actions'))}笔历史调仓净值回填，并用移动平均法估算"
                )
            else:
                coverage_note_parts.append("平均成本暂未算全")
            if normalize_text(item.get("price_source")) == "estimate":
                coverage_note_parts.append(f"{quote_label}时间 {quote_time}")
                if official_nav > 0 and official_nav_date:
                    coverage_note_parts.append(f"上一日净值 {format_decimal(official_nav)}（{official_nav_date}）")
            elif current_price > 0:
                coverage_note_parts.append(f"{quote_label}日期 {quote_time}")
            pricing_html = (
                '<div class="holding-valuation">'
                f'<div class="holding-valuation-item"><small>平均成本</small><strong>{format_decimal(avg_cost) if avg_cost > 0 else "—"}</strong></div>'
                f'<div class="holding-valuation-item"><small>{html.escape(quote_label)}</small><strong>{format_decimal(current_price) if current_price > 0 else "—"}</strong></div>'
                f'<div class="holding-valuation-item"><small>按当前份数估值</small><strong>{format_amount(position_value) if position_value > 0 else "—"}</strong></div>'
                f'<div class="holding-valuation-item {profit_class}"><small>相对成本</small><strong>{f"{format_signed_amount(profit_amount)} / {format_signed_percent(profit_ratio)}" if avg_cost > 0 and current_price > 0 else "—"}</strong></div>'
                '</div>'
                + f'<div class="holding-valuation-note">{html.escape("；".join(part for part in coverage_note_parts if part))}</div>'
            )
        cards.append(
            '<article class="holding-card">'
            '<div class="holding-top">'
            '<div>'
            f'<h3 class="holding-name">{html.escape(label)}</h3>'
            + (f'<div class="holding-fund-name">{html.escape(fund_name)}</div>' if fund_name and fund_name != label else "")
            + f'<div class="record-meta">{"".join(meta_parts)}</div>'
            + '</div>'
            f'<div class="holding-units"><strong>{units}</strong><small>当前份数</small></div>'
            '</div>'
            + pricing_html
            + (f'<div class="holding-note">{html.escape(" · ".join(note_parts))}</div>' if note_parts else "")
            + '</article>'
        )
    list_html = "".join(cards) if cards else '<div class="empty">当前没有可展示的持仓数据。</div>'
    return (
        '<section class="panel">'
        '<div class="snapshot-head">'
        '<div>'
        '<h2>当前持仓情况</h2>'
        '<p class="muted">这里看的是当前还持有的标的和份数。口径按平台全部调仓记录里每个标的最近一次返回的 `postPlanUnit` 汇总，不跟下面的 30 天、60 天、今年筛选联动。</p>'
        '</div>'
        '</div>'
        '<div class="metrics">'
        f'<div class="metric"><small>当前持仓标的</small><strong>{safe_int(holdings.get("asset_count"))}</strong></div>'
        f'<div class="metric"><small>当前总份数</small><strong>{safe_int(holdings.get("total_units"))}</strong></div>'

        f'<div class="metric"><small>最近更新</small><strong>{html.escape(latest_time)}</strong></div>'
        f'<div class="metric"><small>估值覆盖</small><strong>{safe_int(pricing_summary.get("estimate_count"))}/{safe_int(pricing_summary.get("asset_count"))}</strong></div>'
        '</div>'
        '<div class="record-subline">下面这组占比按行业里更常见的资产分类口径和"当前份数"计算，不是按实时市值。因为平台这条接口稳定给到的是 `postPlanUnit`，没有稳定的实时持仓金额字段。</div>'
        f'<div class="record-subline">每张卡片里新增了"平均成本 / 当前估值 / 按当前份数估值 / 相对成本"。盘中拿不到估值的基金，会回退到最近官方净值。目前有 {safe_int(pricing_summary.get("estimate_count"))} 只使用盘中估值，{safe_int(pricing_summary.get("fallback_count"))} 只使用最近净值回退。这里的"按当前份数估值"是归一化比较值，不等于你真实账户金额。</div>'
        f'<div class="allocation-grid">{"".join(allocation_cards)}</div>'
        f'{remainder_html}'
        '<div class="record-subline">如果某只标的已经被卖到 0 份，它不会出现在这里；下面的调仓列表和时间线仍然可以继续按时间范围筛选。</div>'
        f'<div class="holdings-list">{list_html}</div>'
        '</section>'
    )

def render_platform_timeline_section(
    platform_trades: Dict[str, Any],
    form_values: Dict[str, str],
    snapshot_name: str,
    signal_filter: str,
    timeline_asset: str,
) -> str:
    if not platform_trades:
        return ""
    if not platform_trades.get("supported"):
        return (
            '<section class="panel">'
            '<div class="snapshot-head"><div><h2>按标的聚合时间线</h2>'
            '<p class="muted">这里只展示平台真实调仓里的买入和卖出，并按标的串起来。</p>'
            '</div></div>'
            f'<div class="empty">{html.escape(normalize_text(platform_trades.get("error") or "暂时拿不到时间线数据。"))}</div>'
            '</section>'
        )
    platform_window = normalize_text(form_values.get("platform_window")) or "all"
    section_anchor = PLATFORM_TIMELINE_SECTION_ID
    range_info = platform_effective_range(form_values)
    range_label = normalize_text(range_info.get("label")) or "全部"
    using_custom_range = normalize_text(range_info.get("mode")) == "custom"
    all_actions = filter_platform_actions(platform_trades, form_values, "all")
    summary_all = summarize_filtered_platform_actions(all_actions)
    side_toolbar: List[str] = []
    for value, label, count in [
        ("all", "全部动作", safe_int(summary_all.get("count"))),
        ("buy", "只看买入", safe_int(summarize_filtered_platform_actions(filter_platform_actions(platform_trades, form_values, "buy")).get("count"))),
        ("sell", "只看卖出", safe_int(summarize_filtered_platform_actions(filter_platform_actions(platform_trades, form_values, "sell")).get("count"))),
    ]:
        url = build_route_url(
            "/timeline",
            form_values,
            snapshot=snapshot_name or None,
            signal_filter=value if value != "all" else None,
            timeline_asset=timeline_asset if timeline_asset != "all" else None,
            platform_window=platform_window if platform_window != "all" else None,
        )
        url = append_url_fragment(url, section_anchor)
        side_toolbar.append(
            f'<a class="mini-btn{" active" if signal_filter == value else ""}" href="{html.escape(url)}">{html.escape(label)} · {count}</a>'
        )
    window_toolbar: List[str] = []
    if using_custom_range:
        window_toolbar.append(f'<span class="chip">已跟随左侧起止日期：{html.escape(range_label)}</span>')
    else:
        for value, label in PLATFORM_WINDOW_OPTIONS:
            url = build_route_url(
                "/timeline",
                form_values,
                snapshot=snapshot_name or None,
                signal_filter=signal_filter if signal_filter != "all" else None,
                timeline_asset=timeline_asset if timeline_asset != "all" else None,
                platform_window=value if value != "all" else None,
            )
            url = append_url_fragment(url, section_anchor)
            active = platform_window == value or (platform_window == "" and value == "all")
            window_toolbar.append(f'<a class="mini-btn{" active" if active else ""}" href="{html.escape(url)}">{html.escape(label)}</a>')

    filtered_actions = filter_platform_actions(platform_trades, form_values, signal_filter)
    asset_source_items = build_platform_timeline_from_actions(filtered_actions)
    filtered_items = asset_source_items
    if timeline_asset and timeline_asset != "all":
        filtered_items = [item for item in asset_source_items if normalize_text(item.get("label")) == timeline_asset]

    all_assets_url = build_route_url(
        "/timeline",
        form_values,
        snapshot=snapshot_name or None,
        signal_filter=signal_filter if signal_filter != "all" else None,
        timeline_asset=None,
        platform_window=platform_window if platform_window != "all" else None,
    )
    all_assets_url = append_url_fragment(all_assets_url, section_anchor)
    asset_toolbar = [
        f'<a class="mini-btn{" active" if timeline_asset in {"", "all"} else ""}" href="{html.escape(all_assets_url)}">全部标的</a>'
    ]
    for item in asset_source_items[:12]:
        label = normalize_text(item.get("label"))
        url = build_route_url(
            "/timeline",
            form_values,
            snapshot=snapshot_name or None,
            signal_filter=signal_filter if signal_filter != "all" else None,
            timeline_asset=label,
            platform_window=platform_window if platform_window != "all" else None,
        )
        url = append_url_fragment(url, section_anchor)
        asset_toolbar.append(
            f'<a class="mini-btn{" active" if timeline_asset == label else ""}" href="{html.escape(url)}">{html.escape(label)} · {safe_int(item.get("event_count"))}</a>'
        )

    timeline_cards = []
    for item in filtered_items:
        entries_html = []
        for entry in list(item.get("entries") or [])[:12]:
            article_url = normalize_text(entry.get("article_url"))
            entries_html.append(
                '<div class="timeline-entry">'
                f'<div class="timeline-time">{html_text(entry.get("txn_date") or entry.get("created_at"))}</div>'
                '<div class="timeline-entry-main">'
                f'<div class="record-meta"><span>{html_text(entry.get("action"))}</span><span>{html_text(entry.get("fund_code"))}</span><span>{html_text(entry.get("fund_name"))}</span></div>'
                f'<div class="timeline-entry-title">{html_text(entry.get("comment") or entry.get("title"))}</div>'
                + (f'<a class="mini-btn" href="{html.escape(article_url)}">打开平台原文</a>' if article_url else "")
                + "</div>"
                "</div>"
            )
        timeline_entries_html = "".join(entries_html) if entries_html else '<div class="empty">当前标的没有调仓记录。</div>'
        timeline_cards.append(
            '<article class="timeline-card">'
            '<div class="timeline-card-head">'
            f'<div><h4>{html_text(item.get("label"))}</h4>'
            f'<div class="record-meta"><span>买入 {safe_int(item.get("buy_count"))}</span><span>卖出 {safe_int(item.get("sell_count"))}</span><span>动作 {safe_int(item.get("event_count"))}</span></div>'
            "</div>"
            "</div>"
            f'<div class="timeline-entries">{timeline_entries_html}</div>'
            "</article>"
        )

    display_buy_count = safe_int(summary_all.get("buy_count")) if signal_filter == "all" else sum(safe_int(item.get("buy_count")) for item in asset_source_items)
    display_sell_count = safe_int(summary_all.get("sell_count")) if signal_filter == "all" else sum(safe_int(item.get("sell_count")) for item in asset_source_items)
    latest_text = "暂无"
    if asset_source_items and list(asset_source_items[0].get("entries") or []):
        latest_entry = list(asset_source_items[0].get("entries") or [])[0]
        latest_text = normalize_text(latest_entry.get("action_title") or latest_entry.get("comment") or latest_entry.get("title")) or "暂无"
    timeline_list_html = "".join(timeline_cards) if timeline_cards else '<div class="empty">当前筛选下没有标的时间线。</div>'
    home_url = "/"
    section_open = f'<section id="{html.escape(section_anchor)}" class="panel">'
    return (
        section_open
        + '<div class="snapshot-head">'
        '<div><h2>按标的聚合时间线</h2><p class="muted">这里只展示平台真实调仓单中的买入和卖出，并按标的串起来。</p></div>'
        f'<a class="mini-btn" href="{html.escape(home_url)}">返回主页</a>'
        '</div>'
        '<div class="metrics signal-metrics">'
        f'<div class="metric"><small>标的数</small><strong>{len(asset_source_items)}</strong></div>'
        f'<div class="metric"><small>买入动作</small><strong>{display_buy_count}</strong></div>'
        f'<div class="metric"><small>卖出动作</small><strong>{display_sell_count}</strong></div>'
        f'<div class="metric"><small>当前范围</small><strong>{html.escape(range_label)}</strong></div>'
        '</div>'
        f'<div class="toolbar">{"".join(side_toolbar)}</div>'
        f'<div class="toolbar">{"".join(window_toolbar)}</div>'
        f'<div class="toolbar">{"".join(asset_toolbar)}</div>'
        f'<div class="record-subline">最近动作：{html.escape(latest_text[:60] + ("…" if len(latest_text) > 60 else ""))}{"。当前范围跟随左侧起止日期" if using_custom_range else ""}</div>'
        f'<div class="timeline-list">{timeline_list_html}</div>'
        '</section>'
    )

def build_meta_refresh(form_values: Dict[str, str], snapshot_name: str, path: str = "/") -> str:
    interval = normalize_text(form_values.get("auto_refresh"))
    if interval not in {"30", "60", "300"}:
        return ""
    target = build_route_url(
        path,
        form_values,
        snapshot=snapshot_name or "__live__",
        auto_run="1",
    )

    return f'<meta http-equiv="refresh" content="{html.escape(interval)};url={html.escape(target)}">'

def mode_options_html(selected_mode: str) -> str:
    return "".join(
        f'<option value="{html.escape(value)}"{" selected" if value == selected_mode else ""}>{html.escape(label)}</option>'
        for value, label in MODE_OPTIONS
    )
