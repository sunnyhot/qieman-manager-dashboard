from __future__ import annotations

import html
from datetime import datetime
from typing import Any, Dict, List, Optional
from urllib.parse import urlencode

from .config import (
    COOKIE_FILE,
    FORM_FIELDS,
    MODE_OPTIONS,
    PLATFORM_SIGNAL_SECTION_ID,
    PLATFORM_TIMELINE_SECTION_ID,
    PLATFORM_WINDOW_OPTIONS,
)
from .html_helpers import (
    append_url_fragment,
    bar_chart,
    build_page_url,
    build_route_url,
    collect_form_values,
    comment_controls_html,
    comments_panel_html,
    default_form_values,
    first_mapping_value,
    metric_cards,
    record_card_html,
    records_html,
    render_comment_item,
    render_forum_preview_panel,
    render_hidden_inputs,
    snapshot_section_title,
)
from .html_render import (
    build_meta_refresh,
    mode_options_html,
    render_platform_holdings_panel,
    render_platform_timeline_section,
    render_signal_panel,
)
from .performance import timed
from .platform_fetcher import (
    enrich_platform_holdings_with_pricing,
    filter_platform_actions,
    platform_effective_range,
    summarize_filtered_platform_actions,
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
)


@timed("render.dashboard")
def render_dashboard_page(
    *,
    form_values: Dict[str, str],
    current_snapshot: Optional[Dict[str, Any]],
    platform_trades: Optional[Dict[str, Any]],
    current_snapshot_name: str,
    source_label: str,
    notice: str = "",
    error: str = "",
    auth_result: Optional[Dict[str, Any]] = None,
    focus_post_id: int = 0,
    comments_payload: Optional[Dict[str, Any]] = None,
    comment_error: str = "",
    comment_sort: str = "hot",
    comment_page: int = 1,
    only_manager_replies: bool = False,
    signal_filter: str = "all",
    timeline_asset: str = "all",
) -> str:
    chips: List[str] = []
    if current_snapshot:
        chips.extend(
            [
                normalize_text(current_snapshot.get("kind_label")),
                normalize_text(current_snapshot.get("mode")),
            ]
        )
        filters = current_snapshot.get("filters") or {}
        if normalize_text(filters.get("user_name")):
            chips.append(f"用户 {normalize_text(filters.get('user_name'))}")
        if normalize_text(filters.get("keyword")):
            chips.append(f"关键词 {normalize_text(filters.get('keyword'))}")
    flash_blocks: List[str] = []
    if notice:
        flash_blocks.append(f'<div class="flash ok">{html.escape(notice)}</div>')
    if error:
        flash_blocks.append(f'<div class="flash fail">{html.escape(error)}</div>')
    if auth_result:
        auth_class = "ok" if auth_result.get("ok") else "fail"
        auth_lines = [
            normalize_text(auth_result.get("message")),
            f"userName: {normalize_text(auth_result.get('user_name') or '未知')}",
            f"brokerUserId: {normalize_text(auth_result.get('broker_user_id') or '未知')}",
        ]
        if normalize_text(auth_result.get("user_label")):
            auth_lines.append(f"userLabel: {normalize_text(auth_result.get('user_label'))}")
        auth_content = "<br>".join(html.escape(line) for line in auth_lines if line)
        flash_blocks.append(
            f'<div class="flash {auth_class} flash-transient" data-transient-seconds="8">'
            '<button type="button" class="flash-close" aria-label="关闭提示">×</button>'
            f'<div class="flash-body">{auth_content}</div>'
            '</div>'
        )
    current_title = normalize_text(current_snapshot.get("title")) if current_snapshot else "等待载入"
    current_subtitle = (
        f"{normalize_text(current_snapshot.get('subtitle') or current_snapshot.get('mode'))} · {safe_int(current_snapshot.get('count'))} 条 · {format_time(current_snapshot.get('created_at'))}"
        if current_snapshot
        else "最新抓取摘要会显示在这里。"
    )
    forum_badge_class = "ok" if current_snapshot else "fail"
    cookie_ok = COOKIE_FILE.exists()
    detail_meta = ""
    if current_snapshot:
        detail_meta = f"{normalize_text(current_snapshot.get('file_name') or '临时结果')} · {normalize_text(current_snapshot.get('file_path') or '内存结果')}"
    auto_refresh_options = [
        ("", "关闭"),
        ("30", "每 30 秒"),
        ("60", "每 60 秒"),
        ("300", "每 5 分钟"),
    ]
    auto_refresh_html = "".join(
        f'<option value="{value}"{" selected" if normalize_text(form_values.get("auto_refresh")) == value else ""}>{label}</option>'
        for value, label in auto_refresh_options
    )
    meta_refresh = build_meta_refresh(form_values, current_snapshot_name)
    group_hidden = ' class="field-group hidden"' if normalize_text(form_values.get("mode")) != "group-manager" else ' class="field-group"'
    user_hidden = (
        ' class="field-group hidden"'
        if normalize_text(form_values.get("mode")) not in {"following-posts", "space-items"}
        else ' class="field-group"'
    )
    comment_anchor = f"#post-{focus_post_id}" if focus_post_id else ""
    reload_url = build_page_url(form_values, snapshot=current_snapshot_name or None) + comment_anchor
    chips_html = "".join(f'<span class="chip">{html.escape(item)}</span>' for item in chips if item)
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>且慢主理人看板</title>
  {meta_refresh}
  <style>
    :root {{
      --bg: #f6efe6;
      --paper: rgba(255, 252, 247, 0.84);
      --paper-strong: #fffaf2;
      --ink: #17313b;
      --muted: #60727b;
      --line: rgba(23, 49, 59, 0.12);
      --accent: #0d8a76;
      --accent-2: #f47a55;
      --accent-3: #f4c95d;
      --danger: #c95746;
      --shadow: 0 22px 60px rgba(23, 49, 59, 0.12);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      color: var(--ink);
      font-family: "Avenir Next", "PingFang SC", "Hiragino Sans GB", "Noto Sans SC", sans-serif;
      background:
        radial-gradient(circle at top left, rgba(244, 201, 93, 0.3), transparent 30%),
        radial-gradient(circle at top right, rgba(13, 138, 118, 0.22), transparent 28%),
        linear-gradient(180deg, #faf6ef 0%, #f4ece1 100%);
      min-height: 100vh;
      overflow-x: hidden;
    }}
    a {{ color: inherit; text-decoration: none; }}
    .page {{ padding: 28px; max-width: 1380px; margin: 0 auto; }}
    .hero {{
      display: flex;
      justify-content: space-between;
      gap: 20px;
      align-items: end;
      margin-bottom: 22px;
    }}
    .hero h1 {{
      margin: 0;
      font-size: clamp(28px, 4vw, 44px);
      line-height: 1.02;
      letter-spacing: -0.03em;
    }}
    .hero p {{
      margin: 8px 0 0;
      max-width: 780px;
      color: var(--muted);
      font-size: 15px;
      line-height: 1.6;
    }}
    .hero-badges, .chips, .record-meta, .toolbar, .record-actions {{
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }}
    .hero-badges {{ justify-content: flex-end; }}
    .badge, .chip {{
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 9px 13px;
      border-radius: 999px;
      background: rgba(255, 250, 242, 0.82);
      border: 1px solid rgba(23, 49, 59, 0.08);
      font-size: 13px;
      box-shadow: 0 8px 24px rgba(23, 49, 59, 0.06);
    }}
    .chip {{
      padding: 7px 11px;
      font-size: 12px;
      background: rgba(13, 138, 118, 0.08);
      color: var(--accent);
      box-shadow: none;
    }}
    .dot {{
      width: 10px;
      height: 10px;
      border-radius: 999px;
      background: var(--accent-3);
      box-shadow: 0 0 0 4px rgba(244, 201, 93, 0.18);
    }}
    .dot.ok {{ background: var(--accent); box-shadow: 0 0 0 4px rgba(13, 138, 118, 0.16); }}
    .dot.fail {{ background: var(--danger); box-shadow: 0 0 0 4px rgba(201, 87, 70, 0.16); }}
    .layout {{
      display: grid;
      grid-template-columns: minmax(0, 1fr);
      gap: 16px;
      align-items: start;
    }}
    .controls {{
      order: 1;
      position: relative;
      overflow: hidden;
    }}
    .controls::before {{
      content: "";
      position: absolute;
      inset: 0;
      background:
        radial-gradient(circle at 18% -20%, rgba(13, 138, 118, 0.15), transparent 45%),
        radial-gradient(circle at 90% 5%, rgba(244, 122, 85, 0.14), transparent 35%);
      pointer-events: none;
    }}
    .content-grid {{
      order: 2;
      display: grid;
      gap: 12px;
      align-items: start;
    }}
    .flash-stack {{
      display: grid;
      gap: 10px;
    }}
    .priority-grid {{
      display: grid;
      grid-template-columns: minmax(0, 1.25fr) minmax(0, 1fr);
      gap: 12px;
      align-items: start;
    }}
    .priority-grid > section.panel {{
      min-width: 0;
    }}
    .panel {{
      background: var(--paper);
      border: 1px solid rgba(255, 255, 255, 0.5);
      backdrop-filter: blur(14px);
      border-radius: 26px;
      box-shadow: var(--shadow);
      padding: 18px;
    }}
    .controls-grid, .records, .timeline-list, .timeline-entries, .signal-list, .comment-panel, .reply-list {{
      display: grid;
      gap: 14px;
    }}
    .compact-controls {{
      position: relative;
      z-index: 1;
      gap: 12px;
    }}
    .query-head {{
      display: flex;
      justify-content: space-between;
      gap: 14px;
      align-items: start;
    }}
    .query-head h2 {{
      margin: 0;
      font-size: clamp(23px, 2.5vw, 30px);
      line-height: 1.1;
      letter-spacing: -0.02em;
    }}
    .query-head p {{
      margin: 6px 0 0;
      max-width: 780px;
    }}
    .query-summary {{
      display: grid;
      gap: 8px;
      min-width: min(420px, 100%);
    }}
    .query-summary .record-meta span {{
      font-size: 12px;
    }}
    .query-core {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 10px;
      align-items: end;
    }}
    .query-core .keyword-field {{
      grid-column: span 2;
    }}
    .field-grid {{
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
    }}
    .field-group {{
      display: grid;
      gap: 10px;
    }}
    label {{
      display: grid;
      gap: 6px;
      color: var(--muted);
      font-size: 13px;
    }}
    input, select, button {{
      font: inherit;
    }}
    input, select {{
      width: 100%;
      border-radius: 14px;
      border: 1px solid var(--line);
      padding: 11px 12px;
      background: rgba(255, 255, 255, 0.72);
      color: var(--ink);
      min-height: 44px;
    }}
    button, .mini-btn {{
      border: 0;
      border-radius: 14px;
      padding: 11px 14px;
      min-height: 42px;
      font-weight: 600;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
    }}
    .btn-primary {{ background: linear-gradient(135deg, var(--accent), #0c6a76); color: white; }}
    .btn-secondary {{ background: linear-gradient(135deg, #f8d978, var(--accent-2)); color: #352518; }}
    .btn-ghost, .mini-btn {{
      background: rgba(255, 255, 255, 0.76);
      color: var(--ink);
      border: 1px solid var(--line);
      box-shadow: none;
    }}
    .btn-ghost[disabled] {{
      cursor: wait;
      opacity: 0.66;
    }}
    .mini-btn.active {{
      background: linear-gradient(135deg, var(--accent), #0c6a76);
      color: white;
      border-color: transparent;
    }}
    .action-row {{
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 10px;
    }}
    .action-row-main {{
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
    }}
    .action-row-tools {{
      margin-left: auto;
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
    }}
    .advanced-panel {{
      border-radius: 16px;
      border: 1px dashed rgba(23, 49, 59, 0.18);
      background: rgba(255, 255, 255, 0.52);
      padding: 2px 12px 12px;
    }}
    .advanced-panel summary {{
      cursor: pointer;
      color: var(--muted);
      font-size: 13px;
      font-weight: 700;
      padding: 10px 0;
      list-style: none;
    }}
    .advanced-panel summary::-webkit-details-marker {{
      display: none;
    }}
    .advanced-grid {{
      display: grid;
      gap: 10px;
    }}
    .muted {{
      color: var(--muted);
      font-size: 13px;
      line-height: 1.6;
    }}
    .flash {{
      position: relative;
      padding: 14px 16px;
      padding-right: 44px;
      border-radius: 18px;
      border: 1px solid rgba(23, 49, 59, 0.08);
      background: rgba(255, 255, 255, 0.82);
      line-height: 1.7;
      font-size: 14px;
      transition: opacity 0.2s ease, transform 0.2s ease;
    }}
    .flash.flash-hiding {{
      opacity: 0;
      transform: translateY(-4px);
    }}
    .flash-close {{
      position: absolute;
      top: 8px;
      right: 10px;
      border: 0;
      background: transparent;
      color: var(--muted);
      font-size: 18px;
      line-height: 1;
      cursor: pointer;
      padding: 4px;
      min-height: auto;
      border-radius: 8px;
    }}
    .flash-close:hover {{
      background: rgba(23, 49, 59, 0.08);
      color: var(--ink);
    }}
    .flash.ok {{ border-color: rgba(13, 138, 118, 0.28); }}
    .flash.fail {{ border-color: rgba(201, 87, 70, 0.28); }}
    .status-line, .snapshot-head, .record-top, .history-top, .timeline-card-head {{
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
    }}
    .metrics {{
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
    }}
    .metric {{
      padding: 16px;
      border-radius: 18px;
      background: linear-gradient(180deg, rgba(255,255,255,0.82), rgba(255,255,255,0.62));
      border: 1px solid rgba(23, 49, 59, 0.08);
    }}
    .metric small {{
      color: var(--muted);
      display: block;
      margin-bottom: 8px;
    }}
    .metric strong {{
      display: block;
      font-size: 24px;
      letter-spacing: -0.03em;
      line-height: 1.05;
    }}
    .trade-overview {{
      margin-top: 14px;
      padding: 14px;
      border-radius: 20px;
      border: 1px solid rgba(23, 49, 59, 0.08);
      background: linear-gradient(180deg, rgba(255,255,255,0.84), rgba(255,255,255,0.62));
      display: grid;
      gap: 12px;
    }}
    .trade-overview-head {{
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
    }}
    .trade-overview-head h3 {{
      margin: 0;
      font-size: 18px;
      line-height: 1.2;
      letter-spacing: -0.02em;
    }}
    .trade-overview-head p {{
      margin: 6px 0 0;
      font-size: 12px;
      line-height: 1.6;
    }}
    .trade-overview-metrics {{
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;
    }}
    .trade-overview-metric {{
      padding: 12px;
      border-radius: 14px;
      border: 1px solid rgba(23, 49, 59, 0.08);
      background: rgba(255, 255, 255, 0.7);
    }}
    .trade-overview-metric small {{
      display: block;
      color: var(--muted);
      font-size: 11px;
      margin-bottom: 6px;
    }}
    .trade-overview-metric strong {{
      display: block;
      font-size: 19px;
      line-height: 1.1;
      letter-spacing: -0.02em;
    }}
    .trade-month-list {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 10px;
    }}
    .trade-month-card {{
      border-radius: 16px;
      border: 1px solid rgba(23, 49, 59, 0.08);
      background: rgba(255, 255, 255, 0.72);
      padding: 12px;
      display: grid;
      gap: 8px;
    }}
    .trade-month-head {{
      display: flex;
      justify-content: space-between;
      gap: 10px;
      align-items: baseline;
    }}
    .trade-month-head strong {{
      font-size: 14px;
      line-height: 1.2;
    }}
    .trade-month-head span {{
      font-size: 12px;
      color: var(--muted);
    }}
    .trade-month-lines {{
      display: grid;
      gap: 8px;
    }}
    .trade-month-line {{
      display: grid;
      grid-template-columns: 36px minmax(0, 1fr) 28px;
      gap: 8px;
      align-items: center;
    }}
    .trade-side {{
      font-size: 12px;
      color: var(--muted);
    }}
    .trade-track {{
      height: 8px;
      border-radius: 999px;
      background: rgba(23, 49, 59, 0.08);
      overflow: hidden;
    }}
    .trade-fill {{
      height: 100%;
      border-radius: 999px;
      width: 0;
      min-width: 0;
    }}
    .trade-fill.buy {{ background: linear-gradient(90deg, #0d8a76 0%, #57b0a3 100%); }}
    .trade-fill.sell {{ background: linear-gradient(90deg, #f47a55 0%, #c95746 100%); }}
    .trade-value {{
      text-align: right;
      font-size: 12px;
      font-weight: 700;
      color: var(--ink);
    }}
    .trade-month-meta {{
      color: var(--muted);
      font-size: 12px;
      line-height: 1.5;
    }}
    .activity-chart {{ margin-top: 14px; display: grid; gap: 12px; }}
    .activity-head {{ display: flex; justify-content: space-between; gap: 12px; align-items: baseline; }}
    .activity-title {{ font-size: 13px; font-weight: 700; letter-spacing: 0.01em; }}
    .activity-subtitle {{ color: var(--muted); font-size: 12px; }}
    .activity-rows {{ display: grid; gap: 10px; }}
    .activity-row {{ display: grid; grid-template-columns: 56px minmax(0, 1fr) 38px; gap: 12px; align-items: center; }}
    .activity-date {{ font-size: 12px; font-weight: 700; color: var(--ink); }}
    .activity-track {{ height: 10px; border-radius: 999px; background: rgba(23, 49, 59, 0.08); overflow: hidden; }}
    .activity-fill {{
      height: 100%;
      border-radius: 999px;
      background: linear-gradient(90deg, #0d8a76 0%, #57b0a3 55%, #efb15d 100%);
      min-width: 8px;
    }}
    .activity-count {{ text-align: right; color: var(--muted); font-size: 12px; }}
    .record-card, .signal-card, .timeline-card, .history-item {{
      border-radius: 22px;
      padding: 18px;
      background: linear-gradient(180deg, rgba(255,255,255,0.9), rgba(255,255,255,0.72));
      border: 1px solid rgba(23, 49, 59, 0.08);
    }}
    .record-card.focus {{
      border-color: rgba(13, 138, 118, 0.42);
      box-shadow: 0 0 0 4px rgba(13, 138, 118, 0.12);
    }}
    .record-title, .signal-title, .timeline-card h4 {{
      margin: 0;
      line-height: 1.35;
    }}
    .record-subline {{
      color: var(--muted);
      font-size: 12px;
      margin-top: 10px;
    }}
    .record-meta span {{
      display: inline-flex;
      padding: 6px 9px;
      border-radius: 999px;
      background: rgba(23, 49, 59, 0.06);
      font-size: 12px;
      color: var(--muted);
    }}
    .record-content, .comment-body, .signal-summary, .timeline-entry-title {{
      white-space: pre-wrap;
      word-break: break-word;
      line-height: 1.75;
      font-size: 14px;
    }}
    .comment-panel {{
      margin-top: 12px;
      border-top: 1px solid rgba(23, 49, 59, 0.08);
      padding-top: 12px;
    }}
    .comment-card, .reply-card {{
      padding: 14px 16px;
      border-radius: 16px;
      background: rgba(23, 49, 59, 0.045);
      border: 1px solid rgba(23, 49, 59, 0.06);
    }}
    .comment-card.manager, .reply-card.manager {{
      border-color: rgba(13, 138, 118, 0.32);
      background: rgba(13, 138, 118, 0.06);
    }}
    .comment-head, .reply-head {{
      display: flex;
      justify-content: space-between;
      gap: 10px;
      align-items: start;
      margin-bottom: 8px;
    }}
    .comment-author {{
      display: flex;
      gap: 10px;
      align-items: center;
    }}
    .comment-avatar {{
      width: 34px;
      height: 34px;
      border-radius: 999px;
      background: linear-gradient(135deg, rgba(13,138,118,0.18), rgba(244,122,85,0.18));
      border: 1px solid rgba(23, 49, 59, 0.08);
      overflow: hidden;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      color: var(--muted);
      font-size: 11px;
      flex: 0 0 auto;
    }}
    .comment-avatar img {{
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }}
    .comment-tag, .reply-tag {{
      display: inline-flex;
      margin-left: 6px;
      padding: 4px 8px;
      border-radius: 999px;
      background: rgba(13, 138, 118, 0.14);
      color: var(--accent);
      font-size: 11px;
      font-weight: 700;
    }}
    .signal-card.buy {{ border-left: 5px solid #0d8a76; }}
    .signal-card.sell {{ border-left: 5px solid #f47a55; }}
    .signal-card.watch {{ border-left: 5px solid #f4c95d; }}
    .signal-badge {{
      display: inline-flex;
      align-items: center;
      padding: 7px 11px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 700;
      color: white;
      background: rgba(23, 49, 59, 0.18);
    }}
    .signal-badge.buy {{ background: linear-gradient(135deg, #16a085, #0d8a76); }}
    .signal-badge.sell {{ background: linear-gradient(135deg, #f47a55, #c95746); }}
    .timeline-entry {{
      display: grid;
      grid-template-columns: 124px minmax(0, 1fr);
      gap: 12px;
      align-items: start;
      padding-top: 10px;
      border-top: 1px solid rgba(23, 49, 59, 0.08);
    }}
    .timeline-entry:first-child {{ border-top: 0; padding-top: 0; }}
    .timeline-time {{
      color: var(--muted);
      font-size: 12px;
      line-height: 1.6;
    }}
    .history-list {{
      display: grid;
      gap: 10px;
      max-height: none;
      overflow: auto;
      padding-right: 4px;
    }}
    .history-item.active {{
      border-color: rgba(13, 138, 118, 0.42);
      box-shadow: 0 0 0 3px rgba(13, 138, 118, 0.12);
    }}
    .history-item h4 {{
      margin: 0 0 6px;
      font-size: 15px;
      line-height: 1.35;
    }}
    .history-item p {{
      margin: 0 0 8px;
      color: var(--muted);
      font-size: 12px;
      line-height: 1.5;
    }}
    .hidden {{ display: none !important; }}
    .empty {{
      padding: 28px 18px;
      text-align: center;
      color: var(--muted);
      border: 1px dashed rgba(23, 49, 59, 0.16);
      border-radius: 18px;
    }}
    .footer-note {{
      margin-top: 12px;
      color: var(--muted);
      font-size: 12px;
      line-height: 1.5;
    }}
    @media (max-width: 1320px) {{
      .priority-grid {{ grid-template-columns: 1fr; }}
      .query-head {{ display: grid; }}
      .query-summary {{ min-width: 0; }}
      .query-core .keyword-field {{ grid-column: auto; }}
      .metrics {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
      .trade-overview-metrics {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
      .holdings-list {{ grid-template-columns: 1fr; }}
    }}
    @media (max-width: 980px) {{
      .page {{ padding: 18px; }}
      .hero {{ display: grid; }}
      .layout {{ grid-template-columns: 1fr; }}
      .metrics, .field-grid, .query-core {{ grid-template-columns: 1fr; }}
      .trade-overview-head {{ display: grid; }}
      .trade-overview-metrics {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
      .trade-month-list {{ grid-template-columns: 1fr; }}
      .action-row {{ align-items: stretch; }}
      .action-row-main, .action-row-tools {{ width: 100%; margin-left: 0; }}
      .action-row-main > *, .action-row-tools > * {{ flex: 1 1 0; }}
      .timeline-entry {{ grid-template-columns: 1fr; }}
    }}
  </style>
</head>
<body>
  <div class="page">
    <header class="hero">
      <div>
        <h1>且慢主理人看板</h1>
        <p>这是 IAB 兼容版。首页现在只保留摘要和最近几条，长列表已经拆到独立详情页里，不用一进来就滚很久。</p>
      </div>
      <div class="hero-badges">
        <div class="badge"><span class="dot {'ok' if cookie_ok else 'fail'}"></span><span>{'已发现本地 Cookie' if cookie_ok else '未发现本地 Cookie'}</span></div>
        <div class="badge"><span class="dot ok"></span><span>默认进入即拉取最新</span></div>
      </div>
    </header>

    <div class="layout">
      <section class="panel controls">
        <form method="post" class="controls-grid compact-controls">
          <div class="query-head">
            <div>
              <h2>实时查询</h2>
              <p class="muted">顶部改成紧凑查询条：保留高频参数和操作按钮，高级参数折叠起来，默认进入页面就会自动拉取最新数据。</p>
            </div>
            <div class="query-summary">
              <div class="badge"><span class="dot {forum_badge_class}"></span><span>{'已载入当前结果' if current_snapshot else '等待首次刷新'}</span></div>
              <div class="record-meta"><span>{html.escape(current_title)}</span><span>{html.escape(current_subtitle)}</span></div>
              <div class="chips">{chips_html or '<span class="chip">默认最新</span>'}</div>
            </div>
          </div>

          <div class="query-core">
            <label>模式
              <select name="mode">{mode_options_html(normalize_text(form_values.get("mode")))}</select>
            </label>
            <label>产品代码
              <input name="prod_code" placeholder="LONG_WIN" value="{html.escape(normalize_text(form_values.get("prod_code")))}">
            </label>
            <label class="keyword-field">关键词
              <input name="keyword" placeholder="指数 / 红利 / 创业板" value="{html.escape(normalize_text(form_values.get("keyword")))}">
            </label>
            <label>起始日期
              <input name="since" placeholder="2026-04-01" value="{html.escape(normalize_text(form_values.get("since")))}">
            </label>
            <label>结束日期
              <input name="until" placeholder="2026-04-17" value="{html.escape(normalize_text(form_values.get("until")))}">
            </label>
            <label>页数
              <input name="pages" value="{html.escape(normalize_text(form_values.get("pages")))}" placeholder="5">
            </label>
          </div>

          <div class="action-row">
            <div class="action-row-main">
              <button class="btn-primary" type="submit" name="action" value="fetch-preview">立即刷新</button>
            </div>
            <div class="action-row-tools">
              <button id="auth-check-btn" class="btn-ghost" type="submit" name="action" value="auth-check">验证登录态</button>
              <a class="mini-btn" href="{html.escape(reload_url)}">重载当前筛选</a>
            </div>
          </div>

          <details class="advanced-panel">
            <summary>高级参数（按模式启用：主理人 / 用户ID / 自动刷新）</summary>
            <div class="advanced-grid">
              <div class="field-grid">
                <label>每页条数
                  <input name="page_size" value="{html.escape(normalize_text(form_values.get("page_size")))}" placeholder="10">
                </label>
                <label>自动刷新
                  <select name="auto_refresh">{auto_refresh_html}</select>
                </label>
              </div>

              <div{group_hidden}>
                <div class="field-grid">
                  <label>主理人
                    <input name="manager_name" placeholder="ETF拯救世界" value="{html.escape(normalize_text(form_values.get("manager_name")))}">
                  </label>
                  <label>groupId
                    <input name="group_id" placeholder="43" value="{html.escape(normalize_text(form_values.get("group_id")))}">
                  </label>
                </div>
                <div class="field-grid">
                  <label>小组链接
                    <input name="group_url" placeholder="https://qieman.com/content/group-detail/43" value="{html.escape(normalize_text(form_values.get("group_url")))}">
                  </label>
                </div>
              </div>

              <div{user_hidden}>
                <div class="field-grid">
                  <label>用户昵称
                    <input name="user_name" placeholder="ETF拯救世界" value="{html.escape(normalize_text(form_values.get("user_name")))}">
                  </label>
                  <label>brokerUserId
                    <input name="broker_user_id" placeholder="793413" value="{html.escape(normalize_text(form_values.get("broker_user_id")))}">
                  </label>
                </div>
                <div class="field-grid">
                  <label>spaceUserId
                    <input name="space_user_id" placeholder="123456" value="{html.escape(normalize_text(form_values.get("space_user_id")))}">
                  </label>
                </div>
              </div>
            </div>
          </details>

          <p class="muted">{html.escape(detail_meta or "主页每次打开都会自动抓取最新数据。")}</p>

          {render_hidden_inputs(form_values, snapshot=current_snapshot_name or None)}
        </form>
      </section>

      <main class="content-grid">
        <div id="flash-stack" class="flash-stack">{''.join(flash_blocks)}</div>
        <div class="priority-grid">
          {render_signal_panel(platform_trades or {}, form_values, current_snapshot_name, signal_filter, timeline_asset, page_path="/", card_limit=8, home_mode=True, section_anchor=PLATFORM_SIGNAL_SECTION_ID)}
          {render_forum_preview_panel(current_snapshot, form_values, current_snapshot_name, source_label, limit=6, focus_post_id=focus_post_id, comments_payload=comments_payload, comment_error=comment_error, comment_sort=comment_sort, comment_page=comment_page, only_manager_replies=only_manager_replies, page_path="/")}
        </div>
      </main>
    </div>
  </div>
  <script>
    (function () {{
      function escapeHtml(value) {{
        return String(value || "")
          .replace(/&/g, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;")
          .replace(/"/g, "&quot;")
          .replace(/'/g, "&#39;");
      }}

      function dismissFlash(node) {{
        if (!node) return;
        node.classList.add("flash-hiding");
        window.setTimeout(function () {{
          if (node && node.parentNode) node.parentNode.removeChild(node);
        }}, 220);
      }}

      function bindFlash(node) {{
        if (!node || node.dataset.bound === "1") return;
        node.dataset.bound = "1";
        var closeBtn = node.querySelector(".flash-close");
        if (closeBtn) {{
          closeBtn.addEventListener("click", function () {{
            dismissFlash(node);
          }});
        }}
        var seconds = Number(node.getAttribute("data-transient-seconds") || "0");
        if (seconds > 0) {{
          window.setTimeout(function () {{
            dismissFlash(node);
          }}, seconds * 1000);
        }}
      }}

      function bindAllFlashes() {{
        var nodes = document.querySelectorAll(".flash");
        for (var i = 0; i < nodes.length; i += 1) {{
          bindFlash(nodes[i]);
        }}
      }}

      function pushFlash(ok, lines, seconds) {{
        var stack = document.getElementById("flash-stack");
        if (!stack) return;
        var root = document.createElement("div");
        root.className = "flash " + (ok ? "ok" : "fail") + " flash-transient";
        root.setAttribute("data-transient-seconds", String(seconds || 8));
        var closeBtn = document.createElement("button");
        closeBtn.type = "button";
        closeBtn.className = "flash-close";
        closeBtn.setAttribute("aria-label", "关闭提示");
        closeBtn.textContent = "×";
        var body = document.createElement("div");
        body.className = "flash-body";
        body.innerHTML = (lines || []).map(function (line) {{ return escapeHtml(line); }}).join("<br>");
        root.appendChild(closeBtn);
        root.appendChild(body);
        stack.insertBefore(root, stack.firstChild);
        bindFlash(root);
      }}

      function setupAuthCheckButton() {{
        var button = document.getElementById("auth-check-btn");
        if (!button) return;
        button.addEventListener("click", function (event) {{
          event.preventDefault();
          if (button.disabled) return;
          var originLabel = button.textContent || "验证登录态";
          button.disabled = true;
          button.textContent = "验证中...";
          fetch("/api/check-auth", {{ cache: "no-store" }})
            .then(function (response) {{
              return response.json().then(function (payload) {{
                return {{ ok: response.ok, payload: payload || {{}} }};
              }});
            }})
            .then(function (result) {{
              if (!result.ok) {{
                throw new Error(result.payload.error || "登录校验失败");
              }}
              var payload = result.payload || {{}};
              var lines = [payload.message || (payload.ok ? "登录态有效" : "登录态无效")];
              if (payload.user_name) lines.push("userName: " + payload.user_name);
              if (payload.broker_user_id) lines.push("brokerUserId: " + payload.broker_user_id);
              if (payload.user_label) lines.push("userLabel: " + payload.user_label);
              pushFlash(!!payload.ok, lines, 8);
            }})
            .catch(function (error) {{
              pushFlash(false, [error && error.message ? error.message : "登录校验失败"], 8);
            }})
            .finally(function () {{
              button.disabled = false;
              button.textContent = originLabel;
            }});
        }});
      }}

      bindAllFlashes();
      setupAuthCheckButton();
    }})();
  </script>
</body>
</html>"""

@timed("render.platform")
def render_platform_page(
    *,
    form_values: Dict[str, str],
    current_snapshot_name: str,
    platform_trades: Optional[Dict[str, Any]],
    signal_filter: str,
    timeline_asset: str,
    source_label: str,
) -> str:
    cookie_ok = COOKIE_FILE.exists()
    meta_refresh = build_meta_refresh(form_values, current_snapshot_name, path="/platform")
    product_code = normalize_text(form_values.get("prod_code")) or "未填写"
    chips = [
        f"产品 {product_code}",
        f"来源 {source_label or '未选择'}",
        f"时间范围 {normalize_text(platform_effective_range(form_values).get('label')) or '全部'}",
    ]
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>且慢平台调仓</title>
  {meta_refresh}
  <style>
    :root {{
      --bg: #f6efe6;
      --paper: rgba(255, 252, 247, 0.88);
      --ink: #17313b;
      --muted: #60727b;
      --line: rgba(23, 49, 59, 0.12);
      --accent: #0d8a76;
      --danger: #c95746;
      --shadow: 0 22px 60px rgba(23, 49, 59, 0.12);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      overflow-x: hidden;
      color: var(--ink);
      font-family: "Avenir Next", "PingFang SC", "Hiragino Sans GB", "Noto Sans SC", sans-serif;
      background:
        radial-gradient(circle at top left, rgba(244, 201, 93, 0.3), transparent 30%),
        radial-gradient(circle at top right, rgba(13, 138, 118, 0.22), transparent 28%),
        linear-gradient(180deg, #faf6ef 0%, #f4ece1 100%);
      min-height: 100vh;
    }}
    a {{ color: inherit; text-decoration: none; }}
    .page {{ padding: 28px; max-width: 1380px; margin: 0 auto; }}
    .hero {{ display: flex; justify-content: space-between; gap: 20px; align-items: end; margin-bottom: 22px; }}
    .hero h1 {{ margin: 0; font-size: clamp(28px, 4vw, 42px); line-height: 1.02; letter-spacing: -0.03em; }}
    .hero p {{ margin: 8px 0 0; color: var(--muted); font-size: 15px; line-height: 1.6; max-width: 860px; }}
    .hero-badges, .chips, .toolbar, .record-meta, .record-actions {{ display: flex; gap: 8px; flex-wrap: wrap; }}
    .badge, .chip {{
      display: inline-flex; align-items: center; gap: 8px; padding: 9px 13px; border-radius: 999px;
      background: rgba(255, 250, 242, 0.82); border: 1px solid rgba(23, 49, 59, 0.08); font-size: 13px;
      box-shadow: 0 8px 24px rgba(23, 49, 59, 0.06);
    }}
    .chip {{ padding: 7px 11px; font-size: 12px; background: rgba(13, 138, 118, 0.08); color: var(--accent); box-shadow: none; }}
    .dot {{ width: 10px; height: 10px; border-radius: 999px; background: var(--accent); box-shadow: 0 0 0 4px rgba(13, 138, 118, 0.16); }}
    .dot.fail {{ background: var(--danger); box-shadow: 0 0 0 4px rgba(201, 87, 70, 0.16); }}
    .panel {{
      background: var(--paper); border: 1px solid rgba(255, 255, 255, 0.5); backdrop-filter: blur(14px);
      border-radius: 26px; box-shadow: var(--shadow); padding: 18px; margin-bottom: 18px;
    }}
    .snapshot-head, .record-top {{ display: flex; justify-content: space-between; gap: 12px; align-items: start; }}
    .muted {{ color: var(--muted); font-size: 13px; line-height: 1.6; }}
    .metrics {{ display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }}
    .metric {{
      padding: 16px; border-radius: 18px; background: linear-gradient(180deg, rgba(255,255,255,0.82), rgba(255,255,255,0.62));
      border: 1px solid rgba(23, 49, 59, 0.08);
    }}
    .metric small {{ color: var(--muted); display: block; margin-bottom: 8px; }}
    .metric strong {{ display: block; font-size: 24px; letter-spacing: -0.03em; line-height: 1.05; }}
    .trade-overview {{
      margin-top: 14px;
      padding: 14px;
      border-radius: 20px;
      border: 1px solid rgba(23, 49, 59, 0.08);
      background: linear-gradient(180deg, rgba(255,255,255,0.84), rgba(255,255,255,0.62));
      display: grid;
      gap: 12px;
    }}
    .trade-overview-head {{
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
    }}
    .trade-overview-head h3 {{
      margin: 0;
      font-size: 18px;
      line-height: 1.2;
      letter-spacing: -0.02em;
    }}
    .trade-overview-head p {{
      margin: 6px 0 0;
      font-size: 12px;
      line-height: 1.6;
    }}
    .trade-overview-metrics {{
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;
    }}
    .trade-overview-metric {{
      padding: 12px;
      border-radius: 14px;
      border: 1px solid rgba(23, 49, 59, 0.08);
      background: rgba(255, 255, 255, 0.7);
    }}
    .trade-overview-metric small {{
      display: block;
      color: var(--muted);
      font-size: 11px;
      margin-bottom: 6px;
    }}
    .trade-overview-metric strong {{
      display: block;
      font-size: 19px;
      line-height: 1.1;
      letter-spacing: -0.02em;
    }}
    .trade-month-list {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 10px;
    }}
    .trade-month-card {{
      border-radius: 16px;
      border: 1px solid rgba(23, 49, 59, 0.08);
      background: rgba(255, 255, 255, 0.72);
      padding: 12px;
      display: grid;
      gap: 8px;
    }}
    .trade-month-head {{
      display: flex;
      justify-content: space-between;
      gap: 10px;
      align-items: baseline;
    }}
    .trade-month-head strong {{ font-size: 14px; line-height: 1.2; }}
    .trade-month-head span {{ font-size: 12px; color: var(--muted); }}
    .trade-month-lines {{ display: grid; gap: 8px; }}
    .trade-month-line {{
      display: grid;
      grid-template-columns: 36px minmax(0, 1fr) 28px;
      gap: 8px;
      align-items: center;
    }}
    .trade-side {{ font-size: 12px; color: var(--muted); }}
    .trade-track {{
      height: 8px;
      border-radius: 999px;
      background: rgba(23, 49, 59, 0.08);
      overflow: hidden;
    }}
    .trade-fill {{
      height: 100%;
      border-radius: 999px;
      width: 0;
      min-width: 0;
    }}
    .trade-fill.buy {{ background: linear-gradient(90deg, #0d8a76 0%, #57b0a3 100%); }}
    .trade-fill.sell {{ background: linear-gradient(90deg, #f47a55 0%, #c95746 100%); }}
    .trade-value {{
      text-align: right;
      font-size: 12px;
      font-weight: 700;
      color: var(--ink);
    }}
    .trade-month-meta {{ color: var(--muted); font-size: 12px; line-height: 1.5; }}
    .mini-btn {{
      border: 1px solid var(--line); border-radius: 14px; padding: 11px 14px; min-height: 42px; font: inherit;
      font-weight: 600; cursor: pointer; display: inline-flex; align-items: center; justify-content: center;
      background: rgba(255, 255, 255, 0.76); color: var(--ink);
    }}
    .mini-btn.active {{ background: linear-gradient(135deg, var(--accent), #0c6a76); color: white; border-color: transparent; }}
    .signal-list {{ display: grid; gap: 14px; }}
    .signal-card {{
      border-radius: 22px; padding: 18px; background: linear-gradient(180deg, rgba(255,255,255,0.9), rgba(255,255,255,0.72));
      border: 1px solid rgba(23, 49, 59, 0.08);
    }}
    .signal-card.buy {{ border-left: 5px solid #0d8a76; }}
    .signal-card.sell {{ border-left: 5px solid #f47a55; }}
    .signal-card.watch {{ border-left: 5px solid #f4c95d; }}
    .allocation-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; margin: 14px 0; }}
    .allocation-card {{
      border-radius: 18px; padding: 14px 15px; background: linear-gradient(180deg, rgba(255,255,255,0.84), rgba(255,255,255,0.68));
      border: 1px solid rgba(23, 49, 59, 0.08);
    }}
    .allocation-row {{ display: flex; justify-content: space-between; gap: 12px; align-items: baseline; }}
    .allocation-row strong {{ font-size: 14px; line-height: 1.3; }}
    .allocation-row span {{ font-size: 22px; font-weight: 700; letter-spacing: -0.03em; }}
    .allocation-track {{ height: 8px; margin-top: 10px; border-radius: 999px; background: rgba(23, 49, 59, 0.08); overflow: hidden; }}
    .allocation-fill {{
      height: 100%;
      border-radius: 999px;
      background: linear-gradient(90deg, #0d8a76 0%, #57b0a3 60%, #efb15d 100%);
      min-width: 8px;
    }}
    .allocation-meta {{ margin-top: 8px; color: var(--muted); font-size: 12px; }}
    .allocation-note {{ margin-top: 6px; color: var(--muted); font-size: 12px; line-height: 1.6; }}
    .holdings-list {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 14px; }}
    .holding-card {{
      border-radius: 22px; padding: 18px; background: linear-gradient(180deg, rgba(255,255,255,0.9), rgba(255,255,255,0.72));
      border: 1px solid rgba(23, 49, 59, 0.08);
    }}
    .holding-top {{ display: flex; justify-content: space-between; gap: 12px; align-items: start; }}
    .holding-name {{ margin: 0; line-height: 1.35; }}
    .holding-fund-name {{ margin-top: 8px; color: var(--muted); font-size: 13px; line-height: 1.6; }}
    .holding-units {{ min-width: 92px; text-align: right; }}
    .holding-units strong {{ display: block; font-size: 30px; letter-spacing: -0.04em; line-height: 1; }}
    .holding-units small {{ display: block; margin-top: 6px; color: var(--muted); font-size: 12px; }}
    .holding-valuation {{
      margin-top: 12px;
      padding-top: 12px;
      border-top: 1px solid rgba(23, 49, 59, 0.08);
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
    }}
    .holding-valuation-item {{
      padding: 10px 12px;
      border-radius: 16px;
      background: rgba(23, 49, 59, 0.045);
      border: 1px solid rgba(23, 49, 59, 0.06);
    }}
    .holding-valuation-item small {{
      display: block;
      color: var(--muted);
      font-size: 11px;
      margin-bottom: 6px;
    }}
    .holding-valuation-item strong {{
      display: block;
      font-size: 16px;
      line-height: 1.2;
      letter-spacing: -0.02em;
    }}
    .holding-valuation-item.up strong {{ color: var(--accent); }}
    .holding-valuation-item.down strong {{ color: var(--danger); }}
    .holding-valuation-note {{
      margin-top: 10px;
      color: var(--muted);
      font-size: 12px;
      line-height: 1.6;
    }}
    .holding-note {{ margin-top: 10px; color: var(--muted); font-size: 13px; line-height: 1.7; }}
    .signal-top {{ display: flex; justify-content: space-between; gap: 12px; align-items: start; }}
    .signal-title {{ margin: 0; line-height: 1.35; }}
    .signal-badge {{
      display: inline-flex; align-items: center; padding: 7px 11px; border-radius: 999px; font-size: 12px; font-weight: 700; color: white;
      background: rgba(23, 49, 59, 0.18);
    }}
    .signal-badge.buy {{ background: linear-gradient(135deg, #16a085, #0d8a76); }}
    .signal-badge.sell {{ background: linear-gradient(135deg, #f47a55, #c95746); }}
    .record-meta span {{
      display: inline-flex; padding: 6px 9px; border-radius: 999px; background: rgba(23, 49, 59, 0.06); font-size: 12px; color: var(--muted);
    }}
    .signal-events {{ display: grid; gap: 6px; margin-top: 12px; }}
    .signal-line {{ white-space: pre-wrap; word-break: break-word; line-height: 1.7; font-size: 14px; }}
    .record-subline {{
      color: var(--muted); font-size: 12px; margin-top: 10px; margin-bottom: 14px;
    }}
    .empty {{
      padding: 28px 18px; text-align: center; color: var(--muted); border: 1px dashed rgba(23, 49, 59, 0.16); border-radius: 18px;
    }}
    @media (max-width: 1100px) {{
      .metrics {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
      .trade-overview-metrics {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
      .holdings-list {{ grid-template-columns: 1fr; }}
      .allocation-grid {{ grid-template-columns: 1fr; }}
    }}
    @media (max-width: 980px) {{
      .page {{ padding: 18px; }}
      .hero {{ display: grid; }}
      .metrics {{ grid-template-columns: 1fr; }}
      .trade-overview-head {{ display: grid; }}
      .trade-overview-metrics {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
      .trade-month-list {{ grid-template-columns: 1fr; }}
      .allocation-grid {{ grid-template-columns: 1fr; }}
      .activity-head {{ display: grid; }}
      .activity-row {{ grid-template-columns: 52px minmax(0, 1fr) 34px; gap: 10px; }}
      .signal-top {{ display: grid; }}
    }}
  </style>
</head>
<body>
  <div class="page">
    <header class="hero">
      <div>
        <h1>平台调仓详情</h1>
        <p>这里放完整的真实调仓动作列表。左侧起止日期现在会和论坛发言一起生效；如果没填日期，再用这里的 30 天、60 天、今年这些快捷时间范围。</p>
      </div>
      <div class="hero-badges">
        <div class="badge"><span class="dot {'ok' if cookie_ok else 'fail'}"></span><span>{'已发现本地 Cookie' if cookie_ok else '未发现本地 Cookie'}</span></div>
        <div class="badge"><span class="dot"></span><span>产品 {html.escape(product_code)}</span></div>
      </div>
    </header>

    <section class="panel">
      <div class="record-meta">{''.join(f'<span>{html.escape(item)}</span>' for item in chips if item)}</div>
    </section>

    {render_platform_holdings_panel(platform_trades or {{}})}

    {render_signal_panel(platform_trades or {{}}, form_values, current_snapshot_name, signal_filter, timeline_asset, page_path="/platform", card_limit=120, home_mode=False, section_anchor=PLATFORM_SIGNAL_SECTION_ID)}
  </div>
</body>
</html>"""

@timed("render.forum")
def render_forum_page(
    *,
    form_values: Dict[str, str],
    current_snapshot: Optional[Dict[str, Any]],
    current_snapshot_name: str,
    source_label: str,
    focus_post_id: int,
    comments_payload: Optional[Dict[str, Any]],
    comment_error: str,
    comment_sort: str,
    comment_page: int,
    only_manager_replies: bool,
) -> str:
    cookie_ok = COOKIE_FILE.exists()
    meta_refresh = build_meta_refresh(form_values, current_snapshot_name, path="/forum")
    section_title = snapshot_section_title(current_snapshot)
    current_title = normalize_text(current_snapshot.get("title")) if current_snapshot else "等待载入"
    current_subtitle = (
        f"{normalize_text(current_snapshot.get('subtitle') or current_snapshot.get('mode'))} · {safe_int(current_snapshot.get('count'))} 条 · {format_time(current_snapshot.get('created_at'))}"
        if current_snapshot
        else "发起一次实时抓取后，这里会显示最新数据。"
    )
    chips = [normalize_text(source_label or "未选择"), current_title, current_subtitle]
    if current_snapshot:
        detail_bits = [
            normalize_text(current_snapshot.get("file_name") or "临时结果"),
            normalize_text(source_label or "论坛发言"),
            f"{safe_int(current_snapshot.get('count'))} 条",
            format_time(current_snapshot.get("created_at")),
        ]
        detail_meta = " · ".join(bit for bit in detail_bits if bit and bit != "未记录")
    else:
        detail_meta = ""
    dashboard_url = build_route_url(
        "/",
        form_values,
        snapshot=current_snapshot_name or None,
        focus_post_id=None,
        comment_sort=None,
        comment_page=None,
        only_manager_replies=None,
    )
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>且慢论坛详情</title>
  {meta_refresh}
  <style>
    :root {{
      --bg: #f6efe6;
      --paper: rgba(255, 252, 247, 0.88);
      --ink: #17313b;
      --muted: #60727b;
      --line: rgba(23, 49, 59, 0.12);
      --accent: #0d8a76;
      --danger: #c95746;
      --shadow: 0 22px 60px rgba(23, 49, 59, 0.12);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      overflow-x: hidden;
      color: var(--ink);
      font-family: "Avenir Next", "PingFang SC", "Hiragino Sans GB", "Noto Sans SC", sans-serif;
      background:
        radial-gradient(circle at top left, rgba(244, 201, 93, 0.3), transparent 30%),
        radial-gradient(circle at top right, rgba(13, 138, 118, 0.22), transparent 28%),
        linear-gradient(180deg, #faf6ef 0%, #f4ece1 100%);
      min-height: 100vh;
    }}
    a {{ color: inherit; text-decoration: none; }}
    .page {{ padding: 28px; max-width: 1380px; margin: 0 auto; }}
    .hero {{ display: flex; justify-content: space-between; gap: 20px; align-items: end; margin-bottom: 22px; }}
    .hero h1 {{ margin: 0; font-size: clamp(28px, 4vw, 42px); line-height: 1.02; letter-spacing: -0.03em; }}
    .hero p {{ margin: 8px 0 0; color: var(--muted); font-size: 15px; line-height: 1.6; max-width: 860px; }}
    .hero-badges, .chips, .record-meta, .record-actions {{ display: flex; gap: 8px; flex-wrap: wrap; }}
    .badge, .chip {{
      display: inline-flex; align-items: center; gap: 8px; padding: 9px 13px; border-radius: 999px;
      background: rgba(255, 250, 242, 0.82); border: 1px solid rgba(23, 49, 59, 0.08); font-size: 13px;
      box-shadow: 0 8px 24px rgba(23, 49, 59, 0.06);
    }}
    .chip {{ padding: 7px 11px; font-size: 12px; background: rgba(13, 138, 118, 0.08); color: var(--accent); box-shadow: none; }}
    .dot {{ width: 10px; height: 10px; border-radius: 999px; background: var(--accent); box-shadow: 0 0 0 4px rgba(13, 138, 118, 0.16); }}
    .dot.fail {{ background: var(--danger); box-shadow: 0 0 0 4px rgba(201, 87, 70, 0.16); }}
    .panel {{
      background: var(--paper); border: 1px solid rgba(255, 255, 255, 0.5); backdrop-filter: blur(14px);
      border-radius: 26px; box-shadow: var(--shadow); padding: 18px; margin-bottom: 18px;
    }}
    .snapshot-head, .record-top, .comment-head, .reply-head {{
      display: flex; justify-content: space-between; gap: 12px; align-items: start;
    }}
    .muted {{ color: var(--muted); font-size: 13px; line-height: 1.6; }}
    .metrics {{ display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }}
    .metric {{
      padding: 16px; border-radius: 18px; background: linear-gradient(180deg, rgba(255,255,255,0.82), rgba(255,255,255,0.62));
      border: 1px solid rgba(23, 49, 59, 0.08);
    }}
    .metric small {{ color: var(--muted); display: block; margin-bottom: 8px; }}
    .metric strong {{ display: block; font-size: 24px; letter-spacing: -0.03em; line-height: 1.05; }}
    .mini-btn {{
      border: 1px solid var(--line); border-radius: 14px; padding: 11px 14px; min-height: 42px; font: inherit;
      font-weight: 600; cursor: pointer; display: inline-flex; align-items: center; justify-content: center;
      background: rgba(255, 255, 255, 0.76); color: var(--ink);
    }}
    .mini-btn.active {{ background: linear-gradient(135deg, var(--accent), #0c6a76); color: white; border-color: transparent; }}
    .activity-chart {{ margin-top: 14px; display: grid; gap: 12px; }}
    .activity-head {{ display: flex; justify-content: space-between; gap: 12px; align-items: baseline; }}
    .activity-title {{ font-size: 13px; font-weight: 700; letter-spacing: 0.01em; }}
    .activity-subtitle {{ color: var(--muted); font-size: 12px; }}
    .activity-rows, .records, .reply-list {{ display: grid; gap: 14px; }}
    .activity-row {{ display: grid; grid-template-columns: 56px minmax(0, 1fr) 38px; gap: 12px; align-items: center; }}
    .activity-date {{ font-size: 12px; font-weight: 700; color: var(--ink); }}
    .activity-track {{ height: 10px; border-radius: 999px; background: rgba(23, 49, 59, 0.08); overflow: hidden; }}
    .activity-fill {{
      height: 100%;
      border-radius: 999px;
      background: linear-gradient(90deg, #0d8a76 0%, #57b0a3 55%, #efb15d 100%);
      min-width: 8px;
    }}
    .activity-count {{ text-align: right; color: var(--muted); font-size: 12px; }}
    .record-card {{
      border-radius: 22px; padding: 18px; background: linear-gradient(180deg, rgba(255,255,255,0.9), rgba(255,255,255,0.72));
      border: 1px solid rgba(23, 49, 59, 0.08);
    }}
    .record-card.focus {{ border-color: rgba(13, 138, 118, 0.42); box-shadow: 0 0 0 4px rgba(13, 138, 118, 0.12); }}
    .record-title {{ margin: 0; line-height: 1.35; }}
    .record-subline {{ color: var(--muted); font-size: 12px; margin-top: 10px; }}
    .record-meta span {{
      display: inline-flex; padding: 6px 9px; border-radius: 999px; background: rgba(23, 49, 59, 0.06); font-size: 12px; color: var(--muted);
    }}
    .record-content, .comment-body {{
      white-space: pre-wrap; word-break: break-word; line-height: 1.75; font-size: 14px;
    }}
    .comment-panel {{ margin-top: 12px; border-top: 1px solid rgba(23, 49, 59, 0.08); padding-top: 12px; display: grid; gap: 14px; }}
    .comment-card, .reply-card {{
      padding: 14px 16px; border-radius: 16px; background: rgba(23, 49, 59, 0.045); border: 1px solid rgba(23, 49, 59, 0.06);
    }}
    .comment-card.manager, .reply-card.manager {{ border-color: rgba(13, 138, 118, 0.32); background: rgba(13, 138, 118, 0.06); }}
    .comment-author {{ display: flex; gap: 10px; align-items: center; }}
    .comment-avatar {{
      width: 34px; height: 34px; border-radius: 999px; background: linear-gradient(135deg, rgba(13,138,118,0.18), rgba(244,122,85,0.18));
      border: 1px solid rgba(23, 49, 59, 0.08); overflow: hidden; display: inline-flex; align-items: center; justify-content: center; color: var(--muted);
      font-size: 11px; flex: 0 0 auto;
    }}
    .comment-avatar img {{ width: 100%; height: 100%; object-fit: cover; display: block; }}
    .comment-tag, .reply-tag {{ display: inline-flex; margin-left: 6px; padding: 4px 8px; border-radius: 999px; background: rgba(13, 138, 118, 0.14); color: var(--accent); font-size: 11px; font-weight: 700; }}
    .empty {{ padding: 28px 18px; text-align: center; color: var(--muted); border: 1px dashed rgba(23, 49, 59, 0.16); border-radius: 18px; }}
    @media (max-width: 1100px) {{
      .metrics {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
    }}
    @media (max-width: 980px) {{
      .page {{ padding: 18px; }}
      .hero {{ display: grid; }}
      .metrics {{ grid-template-columns: 1fr; }}
      .activity-head {{ display: grid; }}
      .activity-row {{ grid-template-columns: 52px minmax(0, 1fr) 34px; gap: 10px; }}
    }}
  </style>
</head>
<body>
  <div class="page">
    <header class="hero">
      <div>
        <h1>{html.escape(section_title)}详情</h1>
        <p>完整正文、评论展开和主理人回复筛选都放在这里。首页只保留摘要，避免主页面过长。</p>
      </div>
      <div class="hero-badges">
        <div class="badge"><span class="dot {'ok' if cookie_ok else 'fail'}"></span><span>{'已发现本地 Cookie' if cookie_ok else '未发现本地 Cookie'}</span></div>
        <div class="badge"><span class="dot"></span><span>{html.escape(source_label or "未选择来源")}</span></div>
      </div>
    </header>

    <section class="panel">
      <div class="snapshot-head">
        <div>
          <h2>{html.escape(section_title)}</h2>
          <p class="muted">{html.escape(detail_meta or "发起一次实时抓取后，这里会显示最新数据。")}</p>
        </div>
        <div class="record-actions"><a class="mini-btn" href="{html.escape(dashboard_url)}">返回主理人看板</a></div>
      </div>
      <div class="record-meta">{''.join(f'<span>{html.escape(item)}</span>' for item in chips if item)}</div>
    </section>

    <section class="panel">
      <div class="metrics">{metric_cards(current_snapshot)}</div>
      {bar_chart(current_snapshot)}
    </section>

    <section class="panel">
      <div class="records">{records_html(current_snapshot, form_values, current_snapshot_name, focus_post_id, comments_payload, comment_error, comment_sort, comment_page, only_manager_replies, page_path="/forum")}</div>
    </section>
  </div>
</body>
</html>"""

@timed("render.timeline")
def render_timeline_page(
    *,
    form_values: Dict[str, str],
    current_snapshot_name: str,
    platform_trades: Optional[Dict[str, Any]],
    signal_filter: str,
    timeline_asset: str,
    source_label: str,
) -> str:
    cookie_ok = COOKIE_FILE.exists()
    meta_refresh = build_meta_refresh(form_values, current_snapshot_name, path="/timeline")
    product_code = normalize_text(form_values.get("prod_code")) or "未填写"
    user_name = normalize_text(form_values.get("user_name")) or normalize_text(form_values.get("manager_name")) or "未指定"
    chips = [
        f"产品 {product_code}",
        f"来源 {source_label or '未选择'}",
        f"对象 {user_name}",
    ]
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>且慢调仓时间线</title>
  {meta_refresh}
  <style>
    :root {{
      --bg: #f6efe6;
      --paper: rgba(255, 252, 247, 0.88);
      --ink: #17313b;
      --muted: #60727b;
      --line: rgba(23, 49, 59, 0.12);
      --accent: #0d8a76;
      --danger: #c95746;
      --shadow: 0 22px 60px rgba(23, 49, 59, 0.12);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      overflow-x: hidden;
      color: var(--ink);
      font-family: "Avenir Next", "PingFang SC", "Hiragino Sans GB", "Noto Sans SC", sans-serif;
      background:
        radial-gradient(circle at top left, rgba(244, 201, 93, 0.3), transparent 30%),
        radial-gradient(circle at top right, rgba(13, 138, 118, 0.22), transparent 28%),
        linear-gradient(180deg, #faf6ef 0%, #f4ece1 100%);
      min-height: 100vh;
    }}
    a {{ color: inherit; text-decoration: none; }}
    .page {{ padding: 28px; max-width: 1380px; margin: 0 auto; }}
    .hero {{
      display: flex;
      justify-content: space-between;
      gap: 20px;
      align-items: end;
      margin-bottom: 22px;
    }}
    .hero h1 {{
      margin: 0;
      font-size: clamp(28px, 4vw, 42px);
      line-height: 1.02;
      letter-spacing: -0.03em;
    }}
    .hero p {{
      margin: 8px 0 0;
      color: var(--muted);
      font-size: 15px;
      line-height: 1.6;
      max-width: 860px;
    }}
    .hero-badges, .chips, .toolbar, .record-meta {{
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }}
    .badge, .chip {{
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 9px 13px;
      border-radius: 999px;
      background: rgba(255, 250, 242, 0.82);
      border: 1px solid rgba(23, 49, 59, 0.08);
      font-size: 13px;
      box-shadow: 0 8px 24px rgba(23, 49, 59, 0.06);
    }}
    .chip {{
      padding: 7px 11px;
      font-size: 12px;
      background: rgba(13, 138, 118, 0.08);
      color: var(--accent);
      box-shadow: none;
    }}
    .dot {{
      width: 10px;
      height: 10px;
      border-radius: 999px;
      background: var(--accent);
      box-shadow: 0 0 0 4px rgba(13, 138, 118, 0.16);
    }}
    .dot.fail {{
      background: var(--danger);
      box-shadow: 0 0 0 4px rgba(201, 87, 70, 0.16);
    }}
    .panel {{
      background: var(--paper);
      border: 1px solid rgba(255, 255, 255, 0.5);
      backdrop-filter: blur(14px);
      border-radius: 26px;
      box-shadow: var(--shadow);
      padding: 18px;
      margin-bottom: 18px;
    }}
    .snapshot-head, .timeline-card-head {{
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
    }}
    .muted {{
      color: var(--muted);
      font-size: 13px;
      line-height: 1.6;
    }}
    .metrics {{
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
    }}
    .metric {{
      padding: 16px;
      border-radius: 18px;
      background: linear-gradient(180deg, rgba(255,255,255,0.82), rgba(255,255,255,0.62));
      border: 1px solid rgba(23, 49, 59, 0.08);
    }}
    .metric small {{
      color: var(--muted);
      display: block;
      margin-bottom: 8px;
    }}
    .metric strong {{
      display: block;
      font-size: 24px;
      letter-spacing: -0.03em;
      line-height: 1.05;
    }}
    .mini-btn {{
      border: 1px solid var(--line);
      border-radius: 14px;
      padding: 11px 14px;
      min-height: 42px;
      font: inherit;
      font-weight: 600;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      background: rgba(255, 255, 255, 0.76);
      color: var(--ink);
    }}
    .mini-btn.active {{
      background: linear-gradient(135deg, var(--accent), #0c6a76);
      color: white;
      border-color: transparent;
    }}
    .timeline-list, .timeline-entries {{
      display: grid;
      gap: 14px;
    }}
    .timeline-card {{
      border-radius: 22px;
      padding: 18px;
      background: linear-gradient(180deg, rgba(255,255,255,0.9), rgba(255,255,255,0.72));
      border: 1px solid rgba(23, 49, 59, 0.08);
    }}
    .timeline-card h4 {{
      margin: 0;
      line-height: 1.35;
    }}
    .record-meta span {{
      display: inline-flex;
      padding: 6px 9px;
      border-radius: 999px;
      background: rgba(23, 49, 59, 0.06);
      font-size: 12px;
      color: var(--muted);
    }}
    .timeline-entry {{
      display: grid;
      grid-template-columns: 124px minmax(0, 1fr);
      gap: 12px;
      align-items: start;
      padding-top: 10px;
      border-top: 1px solid rgba(23, 49, 59, 0.08);
    }}
    .timeline-entry:first-child {{ border-top: 0; padding-top: 0; }}
    .timeline-time {{
      color: var(--muted);
      font-size: 12px;
      line-height: 1.6;
    }}
    .timeline-entry-title {{
      white-space: pre-wrap;
      word-break: break-word;
      line-height: 1.75;
      font-size: 14px;
    }}
    .empty {{
      padding: 28px 18px;
      text-align: center;
      color: var(--muted);
      border: 1px dashed rgba(23, 49, 59, 0.16);
      border-radius: 18px;
    }}
    @media (max-width: 1100px) {{
      .metrics {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
      .timeline-entry {{ grid-template-columns: 1fr; }}
    }}
    @media (max-width: 980px) {{
      .page {{ padding: 18px; }}
      .hero {{ display: grid; }}
      .metrics {{ grid-template-columns: 1fr; }}
      .timeline-entry {{ grid-template-columns: 1fr; }}
    }}
  </style>
</head>
<body>
  <div class="page">
    <header class="hero">
      <div>
        <h1>调仓时间线</h1>
        <p>这个页面只看平台真实调仓，并且按标的把买入和卖出串起来。主页里不再塞这块，避免把论坛发言和调仓信息混在一起。</p>
      </div>
      <div class="hero-badges">
        <div class="badge"><span class="dot {'ok' if cookie_ok else 'fail'}"></span><span>{'已发现本地 Cookie' if cookie_ok else '未发现本地 Cookie'}</span></div>
        <div class="badge"><span class="dot"></span><span>产品 {html.escape(product_code)}</span></div>
      </div>
    </header>

    <section class="panel">
      <div class="record-meta">{''.join(f'<span>{html.escape(item)}</span>' for item in chips if item)}</div>
    </section>

    {render_platform_timeline_section(platform_trades or {{}}, form_values, current_snapshot_name, signal_filter, timeline_asset)}
  </div>
</body>
</html>"""
