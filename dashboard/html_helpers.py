from __future__ import annotations

import html
import time
from datetime import datetime
from typing import Any, Dict, List, Optional
from urllib.parse import urlencode

from .cache import PLATFORM_MONTHLY_OVERVIEW_CACHE, PLATFORM_TRADE_TTL_SECONDS
from .config import (
    COOKIE_FILE,
    FORM_FIELDS,
    MODE_OPTIONS,
    PLATFORM_WINDOW_OPTIONS,
)
from .platform_fetcher import (
    platform_action_timestamp,
)
from .utils import (
    format_amount,
    format_decimal,
    format_signed_amount,
    format_signed_percent,
    format_time,
    html_text,
    normalize_date_text,
    normalize_text,
    safe_float,
    safe_int,
    strip_html,
)


def first_mapping_value(source: Dict[str, Any], key: str) -> str:
    value = source.get(key, "")
    if isinstance(value, list):
        value = value[0] if value else ""
    return normalize_text(value)

def default_form_values() -> Dict[str, str]:
    default_mode = "following-posts" if COOKIE_FILE.exists() else "group-manager"
    return {
        "mode": default_mode,
        "prod_code": "LONG_WIN",
        "manager_name": "",
        "group_url": "",
        "group_id": "",
        "user_name": "ETF拯救世界",
        "broker_user_id": "",
        "space_user_id": "",
        "keyword": "",
        "since": "",
        "until": "",
        "pages": "5",
        "page_size": "10",
        "auto_refresh": "",
        "platform_window": "all",
    }

def collect_form_values(source: Dict[str, Any]) -> Dict[str, str]:
    values = default_form_values()
    for key in FORM_FIELDS:
        value = first_mapping_value(source, key)
        if value:
            values[key] = value
    return values

def build_route_url(path: str, form_values: Dict[str, str], **overrides: Any) -> str:
    params: Dict[str, str] = {}
    for key in FORM_FIELDS:
        value = normalize_text(form_values.get(key))
        if value:
            params[key] = value
    for key, raw_value in overrides.items():
        if raw_value is None or raw_value is False:
            params.pop(key, None)
            continue
        if raw_value is True:
            params[key] = "1"
            continue
        value = normalize_text(raw_value)
        if value:
            params[key] = value
        else:
            params.pop(key, None)
    query = urlencode(params)
    return f"{path}?{query}" if query else path

def append_url_fragment(url: str, fragment: str) -> str:
    clean_fragment = normalize_text(fragment).lstrip("#")
    if not clean_fragment:
        return url
    return f"{url.split('#', 1)[0]}#{clean_fragment}"

def build_page_url(form_values: Dict[str, str], **overrides: Any) -> str:
    return build_route_url("/", form_values, **overrides)

def render_hidden_inputs(form_values: Dict[str, str], **extras: Any) -> str:
    parts: List[str] = []
    skipped = {key for key, raw_value in extras.items() if raw_value is None or raw_value is False}
    for key in FORM_FIELDS:
        if key in skipped:
            continue
        value = normalize_text(form_values.get(key))
        if value:
            parts.append(
                f'<input type="hidden" name="{html.escape(key)}" value="{html.escape(value)}">'
            )
    for key, raw_value in extras.items():
        if raw_value is None or raw_value is False:
            continue
        value = "1" if raw_value is True else normalize_text(raw_value)
        if not value:
            continue
        parts.append(
            f'<input type="hidden" name="{html.escape(str(key))}" value="{html.escape(value)}">'
        )
    return "".join(parts)

def metric_cards(snapshot: Optional[Dict[str, Any]]) -> str:
    if not snapshot:
        return '<div class="empty">还没有可展示的数据。</div>'
    stats = snapshot.get("stats") or {}
    cards = [
        ("总量", snapshot.get("count") or 0),
        ("最新时间", format_time(stats.get("latest_created_at") or snapshot.get("created_at"))),
        ("用户数", stats.get("unique_users") or 0),
        ("分组数", stats.get("unique_groups") or 0),
    ]
    if snapshot.get("snapshot_type") == "users":
        cards = [
            ("条目类型", "关注用户"),
            ("总量", snapshot.get("count") or 0),
            ("生成时间", format_time(snapshot.get("created_at"))),
            ("当前标题", snapshot.get("title") or "未命名"),
        ]
    if snapshot.get("snapshot_type") == "groups":
        cards = [
            ("条目类型", "已加入小组"),
            ("总量", snapshot.get("count") or 0),
            ("生成时间", format_time(snapshot.get("created_at"))),
            ("当前标题", snapshot.get("title") or "未命名"),
        ]
    if snapshot.get("snapshot_type") == "items":
        cards = [
            ("条目类型", "公开内容"),
            ("总量", snapshot.get("count") or 0),
            ("作者数", stats.get("unique_authors") or 0),
            ("生成时间", format_time(snapshot.get("created_at"))),
        ]
    return "".join(
        (
            '<div class="metric">'
            f'<small>{html.escape(str(label))}</small>'
            f'<strong>{html.escape(str(value))}</strong>'
            "</div>"
        )
        for label, value in cards
    )

def bar_chart(snapshot: Optional[Dict[str, Any]]) -> str:
    if not snapshot:
        return ""
    bars = list((snapshot.get("stats") or {}).get("by_day") or [])[:8]
    if not bars:
        return ""
    max_count = max(item.get("count") or 1 for item in bars)
    segments = []
    for item in reversed(bars):
        count = safe_int(item.get("count"))
        width = max(8, int(count / max_count * 100))
        label = normalize_date_text(item.get("date") or "")[5:] or "未知"
        segments.append(
            '<div class="activity-row">'
            f'<div class="activity-date">{html.escape(label)}</div>'
            f'<div class="activity-track"><div class="activity-fill" style="width:{width}%"></div></div>'
            f'<div class="activity-count">{count}</div>'
            "</div>"
        )
    return (
        '<div class="activity-chart">'
        '<div class="activity-head">'
        '<div class="activity-title">近 8 个活跃日分布</div>'
        '<div class="activity-subtitle">越长代表当天发言越多</div>'
        '</div>'
        f'<div class="activity-rows">{"".join(segments)}</div>'
        '</div>'
    )

def platform_action_date_text(action: Dict[str, Any]) -> str:
    date_text = normalize_date_text(normalize_text(action.get("txn_date") or action.get("created_at")))
    if date_text:
        return date_text
    action_ts = platform_action_timestamp(action)
    if action_ts > 0:
        try:
            return datetime.fromtimestamp(action_ts / 1000).strftime("%Y-%m-%d")
        except (TypeError, ValueError, OSError):
            return ""
    return ""

def _platform_monthly_overview_cache_key(actions: Any, limit_months: int) -> str:
    action_count = ""
    first_key = ""
    last_key = ""
    if isinstance(actions, list):
        action_count = str(len(actions))
        if actions:
            first = actions[0] if isinstance(actions[0], dict) else {}
            last = actions[-1] if isinstance(actions[-1], dict) else {}
            first_key = normalize_text(first.get("action_key")) or platform_action_date_text(first)
            last_key = normalize_text(last.get("action_key")) or platform_action_date_text(last)
    return "|".join([str(id(actions)), str(safe_int(limit_months)), action_count, first_key, last_key])

def build_platform_monthly_overview(actions: List[Dict[str, Any]], limit_months: int = 12) -> Dict[str, Any]:
    cache_key = _platform_monthly_overview_cache_key(actions, limit_months)
    now = time.time()
    cached = PLATFORM_MONTHLY_OVERVIEW_CACHE.get(cache_key)
    if cached and now - safe_float(cached.get("ts")) < PLATFORM_TRADE_TTL_SECONDS:
        data = cached.get("data")
        if isinstance(data, dict):
            return data

    buckets: Dict[str, Dict[str, Any]] = {}
    for action in actions:
        if not isinstance(action, dict):
            continue
        action_date = platform_action_date_text(action)
        if len(action_date) < 7:
            continue
        month_key = action_date[:7]
        if len(month_key) != 7:
            continue
        bucket = buckets.setdefault(
            month_key,
            {
                "month": month_key,
                "buy_count": 0,
                "sell_count": 0,
                "total_count": 0,
                "active_days": set(),
            },
        )
        side = normalize_text(action.get("side"))
        if side == "buy":
            bucket["buy_count"] = safe_int(bucket.get("buy_count")) + 1
        elif side == "sell":
            bucket["sell_count"] = safe_int(bucket.get("sell_count")) + 1
        bucket["total_count"] = safe_int(bucket.get("total_count")) + 1
        if action_date:
            active_days = bucket.get("active_days")
            if isinstance(active_days, set):
                active_days.add(action_date)

    items = sorted(buckets.values(), key=lambda item: normalize_text(item.get("month")), reverse=True)
    limit_value = safe_int(limit_months)
    if limit_value > 0:
        items = items[:limit_value]

    result_items: List[Dict[str, Any]] = []
    max_month_total = 0
    max_side_count = 0
    for item in items:
        buy_count = safe_int(item.get("buy_count"))
        sell_count = safe_int(item.get("sell_count"))
        total_count = safe_int(item.get("total_count"))
        active_days = item.get("active_days")
        active_day_count = len(active_days) if isinstance(active_days, set) else 0
        trades_per_active_day = round(total_count / active_day_count, 2) if active_day_count > 0 else 0.0
        result_items.append(
            {
                "month": normalize_text(item.get("month")),
                "buy_count": buy_count,
                "sell_count": sell_count,
                "total_count": total_count,
                "active_day_count": active_day_count,
                "trades_per_active_day": trades_per_active_day,
            }
        )
        max_month_total = max(max_month_total, total_count)
        max_side_count = max(max_side_count, buy_count, sell_count)

    month_count = len(result_items)
    total_count = sum(safe_int(item.get("total_count")) for item in result_items)
    buy_count = sum(safe_int(item.get("buy_count")) for item in result_items)
    sell_count = sum(safe_int(item.get("sell_count")) for item in result_items)
    overview = {
        "items": result_items,
        "month_count": month_count,
        "total_count": total_count,
        "buy_count": buy_count,
        "sell_count": sell_count,
        "avg_total_per_month": round(total_count / month_count, 1) if month_count else 0.0,
        "avg_buy_per_month": round(buy_count / month_count, 1) if month_count else 0.0,
        "avg_sell_per_month": round(sell_count / month_count, 1) if month_count else 0.0,
        "max_month_total": max_month_total,
        "max_side_count": max_side_count,
    }
    PLATFORM_MONTHLY_OVERVIEW_CACHE[cache_key] = {
        "ts": now,
        "data": overview,
    }
    return overview

def render_platform_trade_overview(actions: List[Dict[str, Any]], range_label: str, using_custom_range: bool) -> str:
    overview = build_platform_monthly_overview(actions, limit_months=12)
    items = [item for item in list(overview.get("items") or []) if isinstance(item, dict)]
    if not items:
        return '<div class="empty">当前时间范围内还没有可统计的月度调仓数据。</div>'
    max_side_count = max(1, safe_int(overview.get("max_side_count")))

    rows: List[str] = []
    for item in items:
        month = normalize_text(item.get("month")) or "未知月份"
        buy_count = safe_int(item.get("buy_count"))
        sell_count = safe_int(item.get("sell_count"))
        total_count = safe_int(item.get("total_count"))
        active_day_count = safe_int(item.get("active_day_count"))
        trade_freq = safe_float(item.get("trades_per_active_day"))
        buy_width = round((buy_count / max_side_count) * 100.0, 1) if buy_count > 0 else 0.0
        sell_width = round((sell_count / max_side_count) * 100.0, 1) if sell_count > 0 else 0.0
        rows.append(
            '<article class="trade-month-card">'
            f'<div class="trade-month-head"><strong>{html.escape(month)}</strong><span>总计 {total_count} 笔</span></div>'
            '<div class="trade-month-lines">'
            '<div class="trade-month-line buy">'
            '<span class="trade-side">买入</span>'
            f'<div class="trade-track"><div class="trade-fill buy" style="width:{buy_width:.1f}%"></div></div>'
            f'<span class="trade-value">{buy_count}</span>'
            '</div>'
            '<div class="trade-month-line sell">'
            '<span class="trade-side">卖出</span>'
            f'<div class="trade-track"><div class="trade-fill sell" style="width:{sell_width:.1f}%"></div></div>'
            f'<span class="trade-value">{sell_count}</span>'
            '</div>'
            '</div>'
            f'<div class="trade-month-meta">活跃 {active_day_count} 天 · 每活跃日 {trade_freq:.2f} 笔</div>'
            '</article>'
        )

    return (
        '<div class="trade-overview">'
        '<div class="trade-overview-head">'
        '<div>'
        '<h3>交易时间总览</h3>'
        f'<p class="muted">按月看买卖节奏，当前范围 {html.escape(range_label)}'
        f'{"（跟随左侧日期）" if using_custom_range else ""}。</p>'
        '</div>'
        '<span class="chip">近 12 个月窗口</span>'
        '</div>'
        '<div class="trade-overview-metrics">'
        f'<div class="trade-overview-metric"><small>覆盖月份</small><strong>{safe_int(overview.get("month_count"))}</strong></div>'
        f'<div class="trade-overview-metric"><small>月均交易</small><strong>{safe_float(overview.get("avg_total_per_month")):.1f}</strong></div>'
        f'<div class="trade-overview-metric"><small>买入月均</small><strong>{safe_float(overview.get("avg_buy_per_month")):.1f}</strong></div>'
        f'<div class="trade-overview-metric"><small>卖出月均</small><strong>{safe_float(overview.get("avg_sell_per_month")):.1f}</strong></div>'
        '</div>'
        f'<div class="trade-month-list">{"".join(rows)}</div>'
        '</div>'
    )

def snapshot_section_title(snapshot: Optional[Dict[str, Any]]) -> str:
    snapshot_type = normalize_text((snapshot or {}).get("snapshot_type"))
    if snapshot_type == "users":
        return "关注用户"
    if snapshot_type == "groups":
        return "已加入小组"
    if snapshot_type == "items":
        return "公开内容"
    return "论坛发言"

def render_reply_item(reply: Dict[str, Any], manager_broker_user_id: str) -> str:
    is_manager = normalize_text(reply.get("broker_user_id")) == normalize_text(manager_broker_user_id)
    manager_tag = '<span class="reply-tag">主理人</span>' if is_manager else ""
    target = f' 回复 {html_text(reply.get("to_user_name"))}' if normalize_text(reply.get("to_user_name")) else ""
    return (
        f'<div class="reply-card{" manager" if is_manager else ""}">'
        '<div class="reply-head">'
        f'<strong>{html_text(reply.get("user_name"))}</strong>'
        f'<span>{manager_tag}{target} · {html_text(format_time(reply.get("created_at")))}</span>'
        "</div>"
        f'<div class="comment-body">{html_text(reply.get("content"))}</div>'
        "</div>"
    )

def render_comment_item(comment: Dict[str, Any], manager_broker_user_id: str) -> str:
    is_manager = normalize_text(comment.get("broker_user_id")) == normalize_text(manager_broker_user_id)
    avatar = html_text((comment.get("user_name") or "用户")[:1])
    if normalize_text(comment.get("user_avatar_url")):
        avatar = f'<img src="{html.escape(normalize_text(comment.get("user_avatar_url")))}" alt="{html_text(comment.get("user_name"))}">'
    reply_count = safe_int(comment.get("reply_count"))
    meta_parts = [
        f"<span>{html_text(format_time(comment.get('created_at')))}</span>",
        f"<span>赞 {safe_int(comment.get('like_count'))}</span>",
    ]
    if reply_count:
        meta_parts.append(f"<span>回复 {reply_count}</span>")
    if normalize_text(comment.get("ip_location")):
        meta_parts.append(f"<span>{html_text(comment.get('ip_location'))}</span>")
    replies = comment.get("children") if isinstance(comment.get("children"), list) else []
    reply_html = "".join(render_reply_item(reply, manager_broker_user_id) for reply in replies)
    manager_badge = '<span class="comment-tag">主理人</span>' if is_manager else ""
    html_parts = [
        f'<div class="comment-card{" manager" if is_manager else ""}">'
        '<div class="comment-head">'
        '<div class="comment-author">'
        f'<span class="comment-avatar">{avatar}</span>'
        '<div>'
        f'<strong>{html_text(comment.get("user_name"))} {manager_badge}</strong>'
        f'<small>brokerUserId {html_text(comment.get("broker_user_id"))}</small>'
        "</div>"
        "</div>"
        f'<div class="comment-meta">{"".join(meta_parts)}</div>'
        "</div>"
        f'<div class="comment-body">{html_text(comment.get("content"))}</div>'
    ]
    if reply_html:
        html_parts.append(f'<div class="reply-list">{reply_html}</div>')
    html_parts.append("</div>")
    return "".join(html_parts)

def comment_controls_html(
    form_values: Dict[str, str],
    snapshot_name: str,
    post_id: int,
    comment_sort: str,
    comment_page: int,
    only_manager_replies: bool,
    active: bool,
    page_path: str = "/",
) -> str:
    hot_url = build_route_url(
        page_path,
        form_values,
        snapshot=snapshot_name,
        focus_post_id=post_id,
        comment_sort="hot",
        comment_page=1,
        only_manager_replies="1" if only_manager_replies else None,
    ) + f"#post-{post_id}"
    latest_url = build_route_url(
        page_path,
        form_values,
        snapshot=snapshot_name,
        focus_post_id=post_id,
        comment_sort="latest",
        comment_page=1,
        only_manager_replies="1" if only_manager_replies else None,
    ) + f"#post-{post_id}"
    replies_url = build_route_url(
        page_path,
        form_values,
        snapshot=snapshot_name,
        focus_post_id=post_id,
        comment_sort=comment_sort,
        comment_page=1,
        only_manager_replies=None if only_manager_replies else "1",
    ) + f"#post-{post_id}"
    collapse_url = build_route_url(
        page_path,
        form_values,
        snapshot=snapshot_name,
        focus_post_id=None,
        comment_sort=None,
        comment_page=None,
        only_manager_replies=None,
    )
    if not active:
        return (
            '<div class="record-actions">'
            f'<a class="mini-btn" href="{html.escape(hot_url)}">展开热评</a>'
            f'<a class="mini-btn" href="{html.escape(latest_url)}">展开最新评论</a>'
            "</div>"
        )
    toggle_label = "只看主理人回复过的评论" if not only_manager_replies else "恢复查看全部评论"
    return (
        '<div class="record-actions">'
        f'<a class="mini-btn{" active" if comment_sort == "hot" else ""}" href="{html.escape(hot_url)}">热评</a>'
        f'<a class="mini-btn{" active" if comment_sort == "latest" else ""}" href="{html.escape(latest_url)}">最新评论</a>'
        f'<a class="mini-btn{" active" if only_manager_replies else ""}" href="{html.escape(replies_url)}">{html.escape(toggle_label)}</a>'
        f'<a class="mini-btn" href="{html.escape(collapse_url)}">收起评论</a>'
        "</div>"
    )

def comments_panel_html(
    comments_payload: Optional[Dict[str, Any]],
    comment_error: str,
    form_values: Dict[str, str],
    snapshot_name: str,
    record: Dict[str, Any],
    comment_sort: str,
    comment_page: int,
    only_manager_replies: bool,
    page_path: str = "/",
) -> str:
    post_id = safe_int(record.get("post_id"))
    if not post_id:
        return ""
    manager_broker_user_id = normalize_text(record.get("broker_user_id"))
    if not comments_payload and not comment_error:
        return ""
    body = ""
    if comment_error:
        body = f'<div class="empty">{html.escape(comment_error)}</div>'
    else:
        comments = comments_payload.get("comments") if isinstance(comments_payload, dict) else []
        comments = comments if isinstance(comments, list) else []
        if comments:
            body = "".join(render_comment_item(comment, manager_broker_user_id) for comment in comments)
        else:
            body = '<div class="empty">这一页没有评论数据。</div>'
        if isinstance(comments_payload, dict) and comments_payload.get("has_more"):
            more_url = build_route_url(
                page_path,
                form_values,
                snapshot=snapshot_name,
                focus_post_id=post_id,
                comment_sort=comment_sort,
                comment_page=comment_page + 1,
                only_manager_replies="1" if only_manager_replies else None,
            ) + f"#post-{post_id}"
            body += f'<div class="comment-more"><a class="mini-btn" href="{html.escape(more_url)}">加载更多评论</a></div>'
    return f'<div class="comment-panel">{body}</div>'

def record_card_html(
    form_values: Dict[str, str],
    snapshot_name: str,
    record: Dict[str, Any],
    focus_post_id: int,
    comments_payload: Optional[Dict[str, Any]],
    comment_error: str,
    comment_sort: str,
    comment_page: int,
    only_manager_replies: bool,
    page_path: str = "/",
) -> str:
    post_id = safe_int(record.get("post_id"))
    title = strip_html(record.get("title") or record.get("intro") or f"帖子 {post_id or ''}")
    content_text = strip_html(record.get("content_text") or record.get("intro") or "无正文")
    active = post_id and post_id == focus_post_id
    card_class = "record-card focus" if active else "record-card"
    meta = [
        normalize_text(record.get("user_name") or record.get("broker_user_id") or "未知用户"),
        normalize_text(record.get("group_name") or "未标注小组"),
        format_time(record.get("created_at")),
        f"赞 {safe_int(record.get('like_count'))}",
        f"评 {safe_int(record.get('comment_count'))}",
        f"藏 {safe_int(record.get('collection_count'))}",
    ]
    details = (
        f'<div class="record-subline">postId {post_id or "未知"} · brokerUserId {html_text(record.get("broker_user_id") or "未知")}</div>'
        f'<div class="record-content">{html_text(content_text)}</div>'
    )
    controls = comment_controls_html(
        form_values=form_values,
        snapshot_name=snapshot_name,
        post_id=post_id,
        comment_sort=comment_sort,
        comment_page=comment_page,
        only_manager_replies=only_manager_replies,
        active=bool(active),
        page_path=page_path,
    )
    comment_html = ""
    if active:
        comment_html = comments_panel_html(
            comments_payload=comments_payload,
            comment_error=comment_error,
            form_values=form_values,
            snapshot_name=snapshot_name,
            record=record,
            comment_sort=comment_sort,
            comment_page=comment_page,
            only_manager_replies=only_manager_replies,
            page_path=page_path,
        )
    return (
        f'<article class="{card_class}" id="post-{post_id or "none"}">'
        '<div class="record-top">'
        '<div>'
        f'<h3 class="record-title">{html.escape(title)}</h3>'
        f'<div class="record-meta">{"".join(f"<span>{html.escape(item)}</span>" for item in meta if item)}</div>'
        "</div>"
        "</div>"
        f"{details}{controls}{comment_html}"
        "</article>"
    )

def generic_record_card_html(item: Dict[str, Any], title_key: str, body_key: str, fallback_title: str) -> str:
    title = strip_html(item.get(title_key) or fallback_title)
    content = strip_html(item.get(body_key) or item.get("content") or item.get("snippet") or "无内容")
    return (
        '<article class="record-card">'
        f'<h3 class="record-title">{html_text(title)}</h3>'
        f'<div class="record-content">{html_text(content)}</div>'
        "</article>"
    )

def records_html(
    snapshot: Optional[Dict[str, Any]],
    form_values: Dict[str, str],
    snapshot_name: str,
    focus_post_id: int,
    comments_payload: Optional[Dict[str, Any]],
    comment_error: str,
    comment_sort: str,
    comment_page: int,
    only_manager_replies: bool,
    page_path: str = "/",
) -> str:
    if not snapshot:
        return '<div class="empty">从左边发起一次实时抓取后，这里会显示最新数据。</div>'
    records = snapshot.get("records") if isinstance(snapshot.get("records"), list) else []
    if not records:
        return '<div class="empty">这份结果里没有可展示的记录。</div>'
    if snapshot.get("snapshot_type") == "posts":
        return "".join(
            record_card_html(
                form_values=form_values,
                snapshot_name=snapshot_name,
                record=record,
                focus_post_id=focus_post_id,
                comments_payload=comments_payload if safe_int(record.get("post_id")) == focus_post_id else None,
                comment_error=comment_error if safe_int(record.get("post_id")) == focus_post_id else "",
                comment_sort=comment_sort,
                comment_page=comment_page,
                only_manager_replies=only_manager_replies,
                page_path=page_path,
            )
            for record in records
        )
    if snapshot.get("snapshot_type") == "users":
        return "".join(generic_record_card_html(record, "user_name", "user_desc", "未知用户") for record in records)
    if snapshot.get("snapshot_type") == "groups":
        return "".join(generic_record_card_html(record, "group_name", "group_desc", "未命名小组") for record in records)
    return "".join(generic_record_card_html(record, "title", "content", "记录") for record in records if isinstance(record, dict))

def render_forum_preview_panel(
    snapshot: Optional[Dict[str, Any]],
    form_values: Dict[str, str],
    snapshot_name: str,
    source_label: str,
    limit: int = 4,
    focus_post_id: int = 0,
    comments_payload: Optional[Dict[str, Any]] = None,
    comment_error: str = "",
    comment_sort: str = "hot",
    comment_page: int = 1,
    only_manager_replies: bool = False,
    page_path: str = "/",
) -> str:
    section_title = snapshot_section_title(snapshot)
    detail_url = build_route_url(
        "/forum",
        form_values,
        snapshot=snapshot_name or None,
        focus_post_id=None,
        comment_sort=None,
        comment_page=None,
        only_manager_replies=None,
    )
    if not snapshot:
        return (
            '<section class="panel">'
            '<div class="snapshot-head"><div><h2>论坛发言</h2><p class="muted">首页现在只放摘要，完整正文和评论已经移到独立详情页。</p></div>'
            f'<a class="mini-btn" href="{html.escape(detail_url)}">打开论坛详情</a></div>'
            '<div class="empty">从左边发起一次实时抓取后，这里会显示最新发言。</div>'
            '</section>'
        )
    records = snapshot.get("records") if isinstance(snapshot.get("records"), list) else []
    max_cards = max(1, safe_int(limit) or 1)
    preview_records: List[Dict[str, Any]] = [item for item in records[:max_cards] if isinstance(item, dict)]
    if snapshot.get("snapshot_type") == "posts" and focus_post_id:
        has_focus = any(safe_int(item.get("post_id")) == focus_post_id for item in preview_records)
        if not has_focus:
            focus_record = next(
                (
                    item
                    for item in records
                    if isinstance(item, dict) and safe_int(item.get("post_id")) == focus_post_id
                ),
                None,
            )
            if isinstance(focus_record, dict):
                if max_cards > 1:
                    preview_records = preview_records[: max_cards - 1] + [focus_record]
                else:
                    preview_records = [focus_record]
    preview_snapshot = dict(snapshot)
    preview_snapshot["records"] = preview_records
    list_html = records_html(
        snapshot=preview_snapshot,
        form_values=form_values,
        snapshot_name=snapshot_name,
        focus_post_id=focus_post_id,
        comments_payload=comments_payload,
        comment_error=comment_error,
        comment_sort=comment_sort,
        comment_page=comment_page,
        only_manager_replies=only_manager_replies,
        page_path=page_path,
    )
    current_title = normalize_text(snapshot.get("title")) or "等待载入"
    current_subtitle = (
        f"{normalize_text(snapshot.get('subtitle') or snapshot.get('mode'))} · {safe_int(snapshot.get('count'))} 条 · {format_time(snapshot.get('created_at'))}"
    )
    subline = f"来源：{source_label or '未选择'}。首页只展示最近 {min(max_cards, len(records))} 条，完整正文和评论请进详情页。"
    if snapshot.get("snapshot_type") != "posts":
        subline += " 当前结果不是发帖类型，热评和主理人回复交互仅在发帖结果显示。"
    chips = [normalize_text(snapshot.get("kind_label")), normalize_text(snapshot.get("mode"))]
    filters = snapshot.get("filters") or {}
    if normalize_text(filters.get("user_name")):
        chips.append(f"用户 {normalize_text(filters.get('user_name'))}")
    if normalize_text(filters.get("keyword")):
        chips.append(f"关键词 {normalize_text(filters.get('keyword'))}")
    chips_html = "".join(f'<span class="chip">{html.escape(item)}</span>' for item in chips if item)
    return (
        '<section class="panel">'
        '<div class="snapshot-head">'
        f'<div><h2>{html.escape(section_title)}</h2><p class="muted">首页现在只放摘要，长正文、评论和展开操作已经移到独立详情页。</p></div>'
        f'<a class="mini-btn" href="{html.escape(detail_url)}">打开详情页</a>'
        '</div>'
        f'<div class="record-meta"><span>{html.escape(current_title)}</span><span>{html.escape(current_subtitle)}</span></div>'
        f'<div class="chips">{chips_html}</div>'
        f'<div class="metrics">{metric_cards(snapshot)}</div>'
        f'{bar_chart(snapshot)}'
        f'<div class="record-subline">{html.escape(subline)}</div>'
        f'<div class="records">{list_html}</div>'
        '</section>'
    )
