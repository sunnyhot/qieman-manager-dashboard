#!/usr/bin/env python3
from __future__ import annotations

import argparse
import bisect
import html
import json
import os
import re
import subprocess
import tempfile
import time
import textwrap
import urllib.request
import webbrowser
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.parse import parse_qs, urlencode, urlparse

from qieman_community_scraper import (
    QiemanApiError,
    QiemanCommunityClient,
    extract_access_token,
)


PROJECT_DIR = Path(__file__).resolve().parent
RUNTIME_DATA_DIR = Path(
    os.environ.get("QIEMAN_DATA_DIR", str(PROJECT_DIR))
).expanduser().resolve()
OUTPUT_DIR = Path(
    os.environ.get("QIEMAN_OUTPUT_DIR", str(RUNTIME_DATA_DIR / "output"))
).expanduser().resolve()
COOKIE_FILE = Path(
    os.environ.get("QIEMAN_COOKIE_FILE", str(RUNTIME_DATA_DIR / "qieman.cookie"))
).expanduser().resolve()
SCRAPER_FILE = PROJECT_DIR / "qieman_community_scraper.py"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

JSON_LINE_RE = re.compile(r"^JSON:\s*(.+)$", re.M)
HTML_TAG_RE = re.compile(r"<[^>]+>")
MULTI_BLANK_RE = re.compile(r"\n{3,}")
TRADE_SENTENCE_SPLIT_RE = re.compile(r"(?:\n+|(?<=[。！？!?；;]))")
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
AUTO_FETCH_TIMEOUT_SECONDS = 6
MANUAL_FETCH_TIMEOUT_SECONDS = 120
HOME_PLATFORM_FETCH_TIMEOUT_SECONDS = 4
PLATFORM_FETCH_TIMEOUT_SECONDS = 10
LIVE_SNAPSHOT: Optional[Dict[str, Any]] = None
PLATFORM_TRADE_CACHE: Dict[str, Dict[str, Any]] = {}
PLATFORM_TRADE_TTL_SECONDS = 120
FUND_HISTORY_CACHE: Dict[str, Dict[str, Any]] = {}
FUND_QUOTE_CACHE: Dict[str, Dict[str, Any]] = {}
FUND_HISTORY_TTL_SECONDS = 12 * 60 * 60
FUND_QUOTE_TTL_SECONDS = 5 * 60
EASTMONEY_HEADERS = {
    "User-Agent": "Mozilla/5.0",
    "Referer": "https://fund.eastmoney.com/",
}
PLATFORM_ORDER_SIDE_MAP = {
    "022": ("buy", "买入"),
    "024": ("sell", "卖出"),
}

PLATFORM_WINDOW_OPTIONS = [
    ("all", "全部"),
    ("30d", "近30天"),
    ("60d", "近60天"),
    ("ytd", "今年"),
    ("365d", "近1年"),
]
PLATFORM_SIGNAL_SECTION_ID = "platform-actions"
PLATFORM_TIMELINE_SECTION_ID = "timeline-actions"

FORM_FIELDS = [
    "mode",
    "prod_code",
    "manager_name",
    "group_url",
    "group_id",
    "user_name",
    "broker_user_id",
    "space_user_id",
    "keyword",
    "since",
    "until",
    "pages",
    "page_size",
    "auto_refresh",
    "platform_window",
    "history_search",
]

MODE_OPTIONS = [
    ("following-posts", "关注动态"),
    ("group-manager", "公开主理人流"),
    ("following-users", "关注用户"),
    ("my-groups", "已加入小组"),
    ("space-items", "个人空间动态"),
]

TRADE_ACTION_RULES = [
    {"label": "清仓", "side": "sell", "keywords": ["清仓", "卖光", "全部卖出", "全部离场"]},
    {"label": "减仓", "side": "sell", "keywords": ["减仓", "减持", "继续减", "大量减", "适度减", "降低仓位"]},
    {"label": "卖出", "side": "sell", "keywords": ["卖出", "卖了", "止盈", "赎回", "落袋", "下车"]},
    {"label": "加仓", "side": "buy", "keywords": ["加仓", "补仓", "继续加", "再买一份", "多买一份"]},
    {"label": "建仓", "side": "buy", "keywords": ["建仓", "开仓", "上车"]},
    {"label": "买入", "side": "buy", "keywords": ["买入", "买了", "继续买", "买回来", "布局", "发车"]},
]

TRADE_EXECUTION_MARKERS = [
    "今天",
    "刚刚",
    "已经",
    "继续",
    "再次",
    "又",
    "最终",
    "这车",
    "这一车",
    "全部",
    "大量",
    "适度",
    "开始",
    "正式",
]

TRADE_NEGATIVE_MARKERS = [
    "关于",
    "为什么",
    "不是说",
    "如果",
    "假如",
    "比如",
    "建议",
    "提醒",
    "逻辑",
    "目标",
    "估值",
    "免费",
    "申购费",
    "投顾费",
    "热评",
    "汇金",
    "没卖",
    "不卖",
    "不会卖",
    "不会清仓",
    "永远不会",
    "一分钱也没卖",
    "不要买",
    "别买",
    "的话",
    "有谁",
    "什么时候",
    "考虑",
    "我会",
    "该上的",
    "补仓提醒",
]

TRADE_ASSET_KEYWORDS = [
    "恒生医疗",
    "建信500",
    "300ETF",
    "创业板",
    "创业",
    "中证红利",
    "红利",
    "医疗C",
    "医疗",
    "医药",
    "消费",
    "环保",
    "新能源",
    "证券保险",
    "证券",
    "保险",
    "金融地产",
    "传媒",
    "信息",
    "宽基",
    "债基",
    "债券",
    "纳指",
    "沪深300",
    "500",
    "恒生",
    "白酒",
    "黄金",
]

HOLDING_CATEGORY_ORDER = [
    "宽基指数",
    "行业主题",
    "红利策略",
    "主动权益",
    "海外权益",
    "海外债券",
    "债券固收",
    "黄金",
    "其他",
]

HOLDING_BROAD_INDEX_KEYWORDS = [
    "沪深300",
    "中证500",
    "上证50",
    "富国300",
    "建信500",
    "富国500",
    "宽基",
    "全市场",
]

HOLDING_INDEX_MARKERS = [
    "指数",
    "ETF",
    "联接",
    "LOF",
    "中证",
    "沪深",
    "上证",
    "恒生",
    "标普",
    "纳指",
]

HOLDING_THEME_KEYWORDS = [
    "医药",
    "医疗",
    "养老",
    "消费",
    "金融",
    "证券",
    "环保",
    "科技",
    "互联网",
    "传媒",
    "信息",
    "生物",
    "白酒",
    "地产",
]

HOLDING_OVERSEAS_BOND_KEYWORDS = [
    "美元债",
    "全球债",
    "海外债",
]


def safe_int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def safe_float(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def normalize_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def normalize_date_text(value: str) -> str:
    text = normalize_text(value)
    return text[:10] if len(text) >= 10 else text


def format_file_time(path: Path) -> str:
    return datetime.fromtimestamp(path.stat().st_mtime).isoformat(timespec="seconds")


def format_time(value: Any) -> str:
    text = normalize_text(value)
    if not text:
        return "未记录"
    return text.replace("T", " ")[:19]


def format_timestamp_ms(value: Any) -> str:
    try:
        return datetime.fromtimestamp(float(value) / 1000).isoformat(timespec="seconds")
    except (TypeError, ValueError, OSError):
        return ""


def format_decimal(value: Any, digits: int = 4) -> str:
    number = safe_float(value)
    return f"{number:.{digits}f}"


def format_amount(value: Any) -> str:
    return f"{safe_float(value):.2f}"


def format_signed_amount(value: Any) -> str:
    return f"{safe_float(value):+.2f}"


def format_signed_percent(value: Any) -> str:
    return f"{safe_float(value):+.2f}%"


def date_key_from_text(value: Any) -> int:
    text = normalize_date_text(normalize_text(value))
    if not text:
        return 0
    try:
        return int(text.replace("-", ""))
    except ValueError:
        return 0


def date_key_to_text(value: int) -> str:
    text = str(safe_int(value))
    if len(text) != 8:
        return ""
    return f"{text[:4]}-{text[4:6]}-{text[6:8]}"


def fetch_remote_text(url: str, timeout: int = 12) -> str:
    request = urllib.request.Request(url, headers=EASTMONEY_HEADERS)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = response.read()
    return payload.decode("utf-8", "ignore")


def strip_html(value: Any) -> str:
    text = normalize_text(value)
    if not text:
        return ""
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.I)
    text = re.sub(r"</p\s*>", "\n", text, flags=re.I)
    text = re.sub(r"</div\s*>", "\n", text, flags=re.I)
    text = HTML_TAG_RE.sub("", text)
    text = html.unescape(text).replace("\xa0", " ")
    lines = [line.strip() for line in text.splitlines()]
    text = "\n".join(line for line in lines if line)
    return MULTI_BLANK_RE.sub("\n\n", text).strip()


def truncate_text(value: Any, limit: int = 160) -> str:
    text = normalize_text(value)
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 1)].rstrip() + "…"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def sorted_json_files(directory: Path) -> List[Path]:
    if not directory.exists():
        return []
    return sorted(directory.glob("*.json"), key=lambda item: item.stat().st_mtime, reverse=True)


def build_post_stats(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    day_counter: Counter[str] = Counter()
    unique_users = set()
    unique_groups = set()
    total_likes = 0
    total_comments = 0
    latest_created_at = ""
    oldest_created_at = ""
    for record in records:
        created_at = normalize_text(record.get("created_at") or record.get("publish_date"))
        if not latest_created_at and created_at:
            latest_created_at = created_at
        if created_at:
            oldest_created_at = created_at
            day_counter[normalize_date_text(created_at)] += 1
        unique_users.add(normalize_text(record.get("user_name") or record.get("author") or record.get("broker_user_id")))
        unique_groups.add(normalize_text(record.get("group_name")))
        total_likes += safe_int(record.get("like_count") or record.get("likes"))
        total_comments += safe_int(record.get("comment_count") or record.get("comments"))
    bars = [
        {"date": day, "count": count}
        for day, count in sorted(day_counter.items(), key=lambda item: item[0], reverse=True)
    ]
    return {
        "count": len(records),
        "latest_created_at": latest_created_at,
        "oldest_created_at": oldest_created_at,
        "unique_users": len({item for item in unique_users if item}),
        "unique_groups": len({item for item in unique_groups if item}),
        "total_likes": total_likes,
        "total_comments": total_comments,
        "by_day": bars,
    }


def build_list_stats(records: List[Dict[str, Any]], kind: str) -> Dict[str, Any]:
    return {
        "count": len(records),
        "kind": kind,
    }


def build_generic_stats(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    day_counter: Counter[str] = Counter()
    authors = set()
    for record in records:
        date_text = normalize_text(record.get("publish_date") or record.get("created_at"))
        if date_text:
            day_counter[normalize_date_text(date_text)] += 1
        authors.add(normalize_text(record.get("author")))
    return {
        "count": len(records),
        "unique_authors": len({item for item in authors if item}),
        "by_day": [
            {"date": day, "count": count}
            for day, count in sorted(day_counter.items(), key=lambda item: item[0], reverse=True)
        ],
    }


def normalize_post_records(records: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return sorted(records, key=lambda item: normalize_text(item.get("created_at")), reverse=True)


def build_signal_source_text(record: Dict[str, Any]) -> str:
    title = strip_html(record.get("title") or record.get("intro"))
    body = strip_html(record.get("content_text") or record.get("intro"))
    if title and body.startswith(title):
        return body
    return "\n".join(part for part in [title, body] if part).strip()


def find_trade_assets(text: str) -> List[str]:
    found: List[str] = []
    for keyword in TRADE_ASSET_KEYWORDS:
        if keyword in text and keyword not in found:
            found.append(keyword)
    return found[:4]


def build_signal_excerpt(text: str, position: int) -> str:
    clean = normalize_text(text)
    if not clean:
        return ""
    if position < 0:
        return clean[:150]
    start = max(0, position - 36)
    end = min(len(clean), position + 120)
    snippet = clean[start:end].strip()
    if start > 0:
        snippet = "…" + snippet
    if end < len(clean):
        snippet = snippet + "…"
    return snippet


def split_trade_sentences(text: str) -> List[str]:
    return [normalize_text(part) for part in TRADE_SENTENCE_SPLIT_RE.split(text) if normalize_text(part)]


def sentence_has_negative_trade_context(sentence: str) -> bool:
    stripped = normalize_text(sentence)
    if not stripped:
        return True
    if stripped.startswith(("“", "\"", "预订一个热评", "关于")):
        return True
    return any(marker in stripped for marker in TRADE_NEGATIVE_MARKERS)


def sentence_has_execution_context(sentence: str) -> bool:
    return any(marker in sentence for marker in TRADE_EXECUTION_MARKERS)


def extract_trade_event_from_sentence(sentence: str) -> Optional[Dict[str, Any]]:
    if sentence_has_negative_trade_context(sentence):
        return None

    assets = find_trade_assets(sentence)
    has_execution_context = sentence_has_execution_context(sentence)
    if not assets:
        return None

    matches: List[Dict[str, Any]] = []
    for rule in TRADE_ACTION_RULES:
        positions = [(sentence.find(keyword), keyword) for keyword in rule["keywords"] if sentence.find(keyword) >= 0]
        if not positions:
            continue
        position, keyword = sorted(positions, key=lambda item: item[0])[0]
        matches.append(
            {
                "label": rule["label"],
                "side": rule["side"],
                "position": position,
                "keyword": keyword,
            }
        )

    if not matches:
        return None

    primary = sorted(matches, key=lambda item: item["position"])[0]
    keyword = primary["keyword"]
    executed_patterns = [
        f"{keyword}了",
        f"{keyword}的一份",
        f"{keyword}一份",
        f"今天{keyword}",
        f"刚刚{keyword}",
        f"继续{keyword}",
    ]
    if not has_execution_context and not any(pattern in sentence for pattern in executed_patterns):
        return None

    return {
        "action": primary["label"],
        "side": primary["side"],
        "assets": assets,
        "sentence": sentence,
        "position": primary["position"],
    }


def classify_post_signal(record: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    text = build_signal_source_text(record)
    if not text:
        return None

    events: List[Dict[str, Any]] = []
    seen: set[tuple[str, str, str]] = set()
    for sentence in split_trade_sentences(text):
        event = extract_trade_event_from_sentence(sentence)
        if not event:
            continue
        dedupe_key = (
            event["action"],
            "|".join(event["assets"]),
            event["sentence"],
        )
        if dedupe_key in seen:
            continue
        seen.add(dedupe_key)
        events.append(event)

    if not events:
        return None

    primary = events[0]
    post_title = normalize_text(record.get("title") or record.get("intro") or f"帖子 {record.get('post_id') or ''}")
    matched_actions: List[str] = []
    all_assets: List[str] = []
    for event in events:
        if event["action"] not in matched_actions:
            matched_actions.append(event["action"])
        for asset in event["assets"]:
            if asset not in all_assets:
                all_assets.append(asset)

    excerpt_parts = [event["sentence"] for event in events[:3]]

    return {
        "post_id": safe_int(record.get("post_id")),
        "title": primary["sentence"],
        "post_title": post_title,
        "created_at": normalize_text(record.get("created_at")),
        "detail_url": normalize_text(record.get("detail_url")),
        "content_text": text,
        "action": primary["action"],
        "side": primary["side"],
        "matched_actions": matched_actions,
        "assets": all_assets[:6],
        "events": [
            {
                "action": event["action"],
                "side": event["side"],
                "assets": event["assets"],
                "sentence": event["sentence"],
            }
            for event in events
        ],
        "excerpt": "\n".join(excerpt_parts),
        "like_count": safe_int(record.get("like_count")),
        "comment_count": safe_int(record.get("comment_count")),
    }


def build_signal_stats(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    items: List[Dict[str, Any]] = []
    asset_counter: Counter[str] = Counter()
    action_counter: Counter[str] = Counter()
    side_counter: Counter[str] = Counter()
    event_count = 0

    for record in normalize_post_records(records):
        signal = classify_post_signal(record)
        if not signal:
            continue
        items.append(signal)
        for event in signal.get("events") or []:
            event_count += 1
            side_counter[event["side"]] += 1
            action_counter[event["action"]] += 1
            asset_counter.update(event["assets"])

    timeline_map: Dict[str, Dict[str, Any]] = {}
    for item in items:
        for event in item.get("events") or []:
            for asset in event.get("assets") or []:
                bucket = timeline_map.setdefault(
                    asset,
                    {
                        "label": asset,
                        "buy_count": 0,
                        "sell_count": 0,
                        "event_count": 0,
                        "entries": [],
                    },
                )
                bucket["event_count"] += 1
                if event["side"] == "buy":
                    bucket["buy_count"] += 1
                if event["side"] == "sell":
                    bucket["sell_count"] += 1
                bucket["entries"].append(
                    {
                        "post_id": item.get("post_id"),
                        "title": item.get("title"),
                        "post_title": item.get("post_title"),
                        "created_at": item.get("created_at"),
                        "action": event.get("action"),
                        "side": event.get("side"),
                        "sentence": event.get("sentence"),
                    }
                )

    timeline = []
    for asset, bucket in timeline_map.items():
        entries = sorted(
            bucket["entries"],
            key=lambda entry: normalize_text(entry.get("created_at")),
            reverse=True,
        )
        timeline.append(
            {
                "label": asset,
                "buy_count": bucket["buy_count"],
                "sell_count": bucket["sell_count"],
                "event_count": bucket["event_count"],
                "latest_created_at": normalize_text(entries[0].get("created_at")) if entries else "",
                "latest_action": normalize_text(entries[0].get("action")) if entries else "",
                "entries": entries[:12],
            }
        )
    timeline = sorted(
        timeline,
        key=lambda item: (
            -safe_int(item.get("event_count")),
            normalize_text(item.get("latest_created_at")),
            item.get("label", ""),
        ),
        reverse=False,
    )

    return {
        "count": len(items),
        "event_count": event_count,
        "latest": items[0] if items else None,
        "counts": {
            "buy": side_counter.get("buy", 0),
            "sell": side_counter.get("sell", 0),
        },
        "top_actions": [
            {"label": label, "count": count}
            for label, count in action_counter.most_common(4)
        ],
        "top_assets": [
            {"label": label, "count": count}
            for label, count in asset_counter.most_common(6)
        ],
        "timeline": timeline[:16],
        "items": items[:24],
    }


def infer_title_from_file(path: Path) -> str:
    stem = path.stem
    parts = stem.split("-")
    if len(parts) >= 3 and parts[-1].isdigit():
        return "-".join(parts[:-2]) or stem
    if len(parts) >= 2 and parts[-1].isdigit():
        return "-".join(parts[:-1]) or stem
    return stem


def normalize_snapshot(path: Path, include_records: bool) -> Dict[str, Any]:
    raw = load_json(path)
    created_at = format_file_time(path)

    if isinstance(raw, dict) and "posts" in raw:
        records = normalize_post_records(raw.get("posts") or [])
        group = raw.get("group") or {}
        meta = raw.get("meta") or {}
        auth_user = meta.get("auth_user") or {}
        first_record = records[0] if records else {}
        filters = raw.get("filters") or meta.get("filters") or {}
        mode = normalize_text(meta.get("mode")) or "group-manager"
        title = (
            normalize_text((meta.get("space_user") or {}).get("user_name"))
            or normalize_text(group.get("manager_name"))
            or normalize_text(filters.get("user_name"))
            or normalize_text(first_record.get("user_name"))
            or normalize_text(auth_user.get("user_name"))
            or normalize_text(auth_user.get("broker_user_id"))
            or normalize_text(group.get("group_name"))
            or infer_title_from_file(path)
        )
        subtitle = (
            normalize_text(group.get("group_name"))
            or normalize_text(first_record.get("group_name"))
            or normalize_text(meta.get("mode"))
            or "帖子流"
        )
        return {
            "file_name": path.name,
            "file_path": str(path),
            "snapshot_type": "posts",
            "kind_label": "帖子",
            "mode": mode,
            "title": title,
            "subtitle": subtitle,
            "created_at": created_at,
            "count": len(records),
            "filters": filters,
            "group": group,
            "meta": meta,
            "stats": build_post_stats(records),
            "signals": build_signal_stats(records),
            "records": records if include_records else [],
        }

    if isinstance(raw, dict) and "users" in raw:
        records = raw.get("users") or []
        meta = raw.get("meta") or {}
        auth_user = meta.get("auth_user") or {}
        return {
            "file_name": path.name,
            "file_path": str(path),
            "snapshot_type": "users",
            "kind_label": "用户",
            "mode": normalize_text(meta.get("mode")) or "following-users",
            "title": normalize_text(auth_user.get("user_name")) or normalize_text(auth_user.get("broker_user_id")) or "关注用户",
            "subtitle": "关注列表",
            "created_at": created_at,
            "count": len(records),
            "filters": {},
            "group": {},
            "meta": meta,
            "stats": build_list_stats(records, "users"),
            "signals": {},
            "records": records if include_records else [],
        }

    if isinstance(raw, dict) and "groups" in raw:
        records = raw.get("groups") or []
        meta = raw.get("meta") or {}
        auth_user = meta.get("auth_user") or {}
        return {
            "file_name": path.name,
            "file_path": str(path),
            "snapshot_type": "groups",
            "kind_label": "小组",
            "mode": normalize_text(meta.get("mode")) or "my-groups",
            "title": normalize_text(auth_user.get("user_name")) or normalize_text(auth_user.get("broker_user_id")) or "已加入小组",
            "subtitle": "小组列表",
            "created_at": created_at,
            "count": len(records),
            "filters": {},
            "group": {},
            "meta": meta,
            "stats": build_list_stats(records, "groups"),
            "signals": {},
            "records": records if include_records else [],
        }

    if isinstance(raw, list):
        records = raw
        query = normalize_text(records[0].get("query")) if records and isinstance(records[0], dict) else ""
        return {
            "file_name": path.name,
            "file_path": str(path),
            "snapshot_type": "items",
            "kind_label": "内容",
            "mode": "public-content",
            "title": query or infer_title_from_file(path),
            "subtitle": "公开内容检索",
            "created_at": created_at,
            "count": len(records),
            "filters": {"query": query} if query else {},
            "group": {},
            "meta": {},
            "stats": build_generic_stats(records if all(isinstance(item, dict) for item in records) else []),
            "signals": {},
            "records": records if include_records else [],
        }

    return {
        "file_name": path.name,
        "file_path": str(path),
        "snapshot_type": "unknown",
        "kind_label": "未知",
        "mode": "unknown",
        "title": infer_title_from_file(path),
        "subtitle": "未识别结构",
        "created_at": created_at,
        "count": 0,
        "filters": {},
        "group": {},
        "meta": {},
        "stats": {},
        "signals": {},
        "records": raw if include_records else [],
    }


def history_summaries() -> List[Dict[str, Any]]:
    items = []
    for path in sorted_json_files(OUTPUT_DIR):
        try:
            snapshot = normalize_snapshot(path, include_records=False)
        except Exception as exc:
            items.append(
                {
                    "file_name": path.name,
                    "file_path": str(path),
                    "snapshot_type": "error",
                    "kind_label": "错误",
                    "mode": "error",
                    "title": path.stem,
                    "subtitle": str(exc),
                    "created_at": format_file_time(path),
                    "count": 0,
                    "filters": {},
                    "meta": {},
                    "group": {},
                    "stats": {},
                    "records": [],
                }
            )
            continue
        items.append(snapshot)
    return items


def preferred_snapshot_name(history: List[Dict[str, Any]], prefer_posts: bool = False) -> str:
    if not history:
        return ""
    if prefer_posts:
        for item in history:
            if normalize_text(item.get("snapshot_type")) != "posts":
                continue
            name = normalize_text(item.get("file_name"))
            if name:
                return name
    return normalize_text(history[0].get("file_name"))


def snapshot_path_from_name(name: str) -> Path:
    path = (OUTPUT_DIR / Path(name).name).resolve()
    if path.parent != OUTPUT_DIR.resolve() or not path.exists():
        raise FileNotFoundError(name)
    return path


def build_scraper_command(payload: Dict[str, Any], output_dir: Path) -> List[str]:
    mode = normalize_text(payload.get("mode")) or "following-posts"
    command = [
        "python3",
        str(SCRAPER_FILE),
        "--mode",
        mode,
        "--output-dir",
        str(output_dir),
    ]
    if COOKIE_FILE.exists():
        command.extend(["--cookie-file", str(COOKIE_FILE)])

    option_map = {
        "group_id": "--group-id",
        "group_url": "--group-url",
        "prod_code": "--prod-code",
        "manager_name": "--manager-name",
        "broker_user_id": "--broker-user-id",
        "user_name": "--user-name",
        "space_user_id": "--space-user-id",
        "keyword": "--keyword",
        "since": "--since",
        "until": "--until",
    }
    for key, flag in option_map.items():
        value = normalize_text(payload.get(key))
        if value:
            command.extend([flag, value])

    pages = normalize_text(payload.get("pages"))
    page_size = normalize_text(payload.get("page_size"))
    if pages:
        command.extend(["--pages", pages])
    if page_size:
        command.extend(["--page-size", page_size])
    return command


def run_fetch(payload: Dict[str, Any], timeout_seconds: Optional[int] = None) -> Dict[str, Any]:
    persist = bool(payload.get("persist"))
    target_dir: Optional[tempfile.TemporaryDirectory[str]] = None
    output_dir = OUTPUT_DIR
    if not persist:
        target_dir = tempfile.TemporaryDirectory(prefix="qieman-live-")
        output_dir = Path(target_dir.name)

    command = build_scraper_command(payload, output_dir)
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            cwd=PROJECT_DIR,
            timeout=timeout_seconds if timeout_seconds and timeout_seconds > 0 else None,
        )
    except subprocess.TimeoutExpired:
        if target_dir:
            target_dir.cleanup()
        hint = "请稍后重试，或缩小时间范围/页数后再刷新。"
        raise RuntimeError(f"抓取超时（>{safe_int(timeout_seconds)}秒），{hint}")
    stdout = result.stdout.strip()
    stderr = result.stderr.strip()
    if result.returncode != 0:
        if target_dir:
            target_dir.cleanup()
        message = stderr or stdout or "抓取失败"
        raise RuntimeError(message)

    match = JSON_LINE_RE.search(stdout)
    if not match:
        if target_dir:
            target_dir.cleanup()
        raise RuntimeError(stdout or "没有解析到 JSON 输出文件")

    json_path = Path(match.group(1).strip())
    snapshot = normalize_snapshot(json_path, include_records=True)
    snapshot["persisted"] = persist
    snapshot["command"] = command
    snapshot["stdout"] = stdout
    if target_dir:
        target_dir.cleanup()
    return snapshot


def run_auth_check() -> Dict[str, Any]:
    if not COOKIE_FILE.exists():
        return {
            "ok": False,
            "message": "未发现 qieman.cookie",
            "user_name": "",
            "broker_user_id": "",
            "user_label": "",
        }

    command = [
        "python3",
        str(SCRAPER_FILE),
        "--mode",
        "auth-check",
        "--cookie-file",
        str(COOKIE_FILE),
    ]
    result = subprocess.run(command, capture_output=True, text=True, cwd=PROJECT_DIR)
    output = (result.stdout or result.stderr).strip()
    if result.returncode != 0:
        return {
            "ok": False,
            "message": output or "登录校验失败",
            "user_name": "",
            "broker_user_id": "",
            "user_label": "",
        }

    values: Dict[str, str] = {}
    for line in output.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        values[key.strip()] = value.strip()
    return {
        "ok": True,
        "message": "登录态有效",
        "user_name": values.get("userName", ""),
        "broker_user_id": values.get("brokerUserId", ""),
        "user_label": values.get("userLabel", ""),
    }


def build_dashboard_client() -> QiemanCommunityClient:
    cookie = COOKIE_FILE.read_text(encoding="utf-8").strip() if COOKIE_FILE.exists() else None
    access_token = extract_access_token(cookie or "")
    return QiemanCommunityClient(access_token=access_token, cookie=cookie)


def normalize_comment(item: Dict[str, Any]) -> Dict[str, Any]:
    children = item.get("children") if isinstance(item.get("children"), list) else []
    return {
        "id": safe_int(item.get("id")),
        "post_id": safe_int(item.get("postId")),
        "user_name": normalize_text(item.get("userName")) or normalize_text(item.get("brokerUserId")) or "未知用户",
        "user_avatar_url": normalize_text(item.get("userAvatarUrl")),
        "broker_user_id": normalize_text(item.get("brokerUserId")),
        "content": normalize_text(item.get("content")),
        "created_at": normalize_text(item.get("createdAt")),
        "like_count": safe_int(item.get("likeNum")),
        "reply_count": safe_int(item.get("commentNum")),
        "ip_location": normalize_text(item.get("ipLocation")),
        "to_user_name": normalize_text(item.get("toUserName")),
        "children": [normalize_comment(child) for child in children if isinstance(child, dict)],
    }


def comment_thread_has_broker_user(comment: Dict[str, Any], broker_user_id: str) -> bool:
    target = normalize_text(broker_user_id)
    if not target:
        return False
    if normalize_text(comment.get("broker_user_id")) == target:
        return True
    children = comment.get("children") if isinstance(comment.get("children"), list) else []
    return any(comment_thread_has_broker_user(child, target) for child in children if isinstance(child, dict))


def fetch_post_comments(
    post_id: int,
    page_size: int = 10,
    sort_type: str = "hot",
    page_num: int = 1,
    manager_broker_user_id: str = "",
) -> Dict[str, Any]:
    client = build_dashboard_client()
    params: Dict[str, Any] = {
        "pageNum": page_num,
        "pageSize": page_size,
        "postId": post_id,
    }
    normalized_sort_type = sort_type.lower()
    if normalized_sort_type == "hot":
        params["sortType"] = "HOT"
    try:
        payload = client.get(
            "/community/comment/list",
            params,
        )
    except QiemanApiError as exc:
        raise RuntimeError(exc.describe()) from exc

    if not isinstance(payload, list):
        raise RuntimeError("评论接口返回结构异常")

    comments = [normalize_comment(item) for item in payload if isinstance(item, dict)]
    if manager_broker_user_id:
        comments = [comment for comment in comments if comment_thread_has_broker_user(comment, manager_broker_user_id)]

    return {
        "post_id": post_id,
        "page_num": page_num,
        "page_size": page_size,
        "sort_type": normalized_sort_type,
        "has_more": len(payload) >= page_size,
        "comments": comments,
    }


def api_status() -> Dict[str, Any]:
    history = history_summaries()
    visible_history = [
        item for item in history
        if not normalize_text(item.get("file_name")).startswith("watch-state-")
    ]
    latest = visible_history[0] if visible_history else (history[0] if history else None)
    preferred_name = preferred_snapshot_name(visible_history or history, prefer_posts=True)
    return {
        "cookie_exists": COOKIE_FILE.exists(),
        "cookie_file": str(COOKIE_FILE),
        "output_dir": str(OUTPUT_DIR),
        "snapshot_count": len(history),
        "latest_snapshot": latest,
        "preferred_snapshot_name": preferred_name,
        "default_form": {
            "mode": "following-posts" if COOKIE_FILE.exists() else "group-manager",
            "prod_code": "LONG_WIN",
            "user_name": "ETF拯救世界",
            "pages": "5",
            "page_size": "10",
        },
    }


def api_bootstrap() -> Dict[str, Any]:
    history = history_summaries()
    preferred_name = preferred_snapshot_name(history, prefer_posts=True)
    preferred_snapshot = {}
    if preferred_name:
        try:
            preferred_snapshot = get_snapshot_by_name(preferred_name)
        except FileNotFoundError:
            preferred_snapshot = {}
    return {
        "status": api_status(),
        "history": history,
        "preferred_snapshot_name": preferred_name,
        "preferred_snapshot": preferred_snapshot,
    }


def api_platform(prod_code: str) -> Dict[str, Any]:
    target = normalize_text(prod_code) or normalize_text(api_status().get("default_form", {}).get("prod_code")) or "LONG_WIN"
    return fetch_platform_trade_data(target)


def html_text(value: Any) -> str:
    return html.escape(normalize_text(value))


def first_mapping_value(source: Dict[str, Any], key: str) -> str:
    value = source.get(key, "")
    if isinstance(value, list):
        value = value[0] if value else ""
    return normalize_text(value)


def default_form_values() -> Dict[str, str]:
    defaults = api_status().get("default_form") or {}
    return {
        "mode": normalize_text(defaults.get("mode")) or "following-posts",
        "prod_code": normalize_text(defaults.get("prod_code")) or "",
        "manager_name": normalize_text(defaults.get("manager_name")) or "",
        "group_url": "",
        "group_id": "",
        "user_name": normalize_text(defaults.get("user_name")) or "",
        "broker_user_id": "",
        "space_user_id": "",
        "keyword": "",
        "since": "",
        "until": "",
        "pages": normalize_text(defaults.get("pages")) or "5",
        "page_size": normalize_text(defaults.get("page_size")) or "10",
        "auto_refresh": "",
        "platform_window": "all",
        "history_search": "",
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


def get_snapshot_by_name(name: str) -> Dict[str, Any]:
    global LIVE_SNAPSHOT
    target = normalize_text(name)
    if target == "__live__":
        if LIVE_SNAPSHOT:
            return LIVE_SNAPSHOT
        raise FileNotFoundError(target)
    path = snapshot_path_from_name(target)
    return normalize_snapshot(path, include_records=True)


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


def fetch_fund_history_series(fund_code: str) -> Dict[str, Any]:
    target = normalize_text(fund_code)
    if not target:
        return {}
    cached = FUND_HISTORY_CACHE.get(target)
    now = time.time()
    if cached and now - safe_float(cached.get("loaded_at")) < FUND_HISTORY_TTL_SECONDS:
        return cached
    result: Dict[str, Any] = {
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
        if not trend_match:
            FUND_HISTORY_CACHE[target] = result
            return result
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
            date_text = datetime.fromtimestamp(ts / 1000).strftime("%Y-%m-%d")
            date_key = date_key_from_text(date_text)
            if not date_key:
                continue
            keys.append(date_key)
            series.append(
                {
                    "date": date_text,
                    "date_key": date_key,
                    "nav": nav,
                    "ts": ts,
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
    FUND_HISTORY_CACHE[target] = result
    return result


def lookup_fund_nav_by_date(history: Dict[str, Any], date_text: Any) -> Dict[str, Any]:
    keys = [safe_int(value) for value in list(history.get("keys") or [])]
    series = [item for item in list(history.get("series") or []) if isinstance(item, dict)]
    target_key = date_key_from_text(date_text)
    if not keys or not series or not target_key:
        return {}
    index = bisect.bisect_right(keys, target_key) - 1
    if index < 0 or index >= len(series):
        return {}
    return series[index]


def fetch_fund_quote(fund_code: str) -> Dict[str, Any]:
    target = normalize_text(fund_code)
    if not target:
        return {}
    cached = FUND_QUOTE_CACHE.get(target)
    now = time.time()
    if cached and now - safe_float(cached.get("loaded_at")) < FUND_QUOTE_TTL_SECONDS:
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
        "loaded_at": now,
    }
    try:
        text = fetch_remote_text(f"https://fundgz.1234567.com.cn/js/{target}.js?rt={int(now)}")
        match = re.search(r"jsonpgz\((\{[\s\S]*\})\);", text)
        if match:
            payload = json.loads(match.group(1))
            estimate_price = safe_float(payload.get("gsz"))
            if estimate_price > 0:
                result = {
                    "fund_code": target,
                    "fund_name": normalize_text(payload.get("name")),
                    "price": estimate_price,
                    "price_time": normalize_text(payload.get("gztime")),
                    "price_source": "estimate",
                    "price_source_label": "盘中估值",
                    "official_nav": safe_float(payload.get("dwjz")),
                    "official_nav_date": normalize_text(payload.get("jzrq")),
                    "estimate_change_pct": safe_float(payload.get("gszzl")),
                    "loaded_at": now,
                }
    except Exception:
        pass
    if safe_float(result.get("price")) <= 0:
        history = fetch_fund_history_series(target)
        series = [item for item in list(history.get("series") or []) if isinstance(item, dict)]
        latest = series[-1] if series else {}
        if latest:
            result = {
                "fund_code": target,
                "fund_name": normalize_text(history.get("fund_name")),
                "price": safe_float(latest.get("nav")),
                "price_time": normalize_text(latest.get("date")),
                "price_source": "official_nav",
                "price_source_label": "最近净值",
                "official_nav": safe_float(latest.get("nav")),
                "official_nav_date": normalize_text(latest.get("date")),
                "estimate_change_pct": 0.0,
                "loaded_at": now,
            }
    FUND_QUOTE_CACHE[target] = result
    return result


def preload_fund_market_data(fund_codes: List[str]) -> tuple[Dict[str, Dict[str, Any]], Dict[str, Dict[str, Any]]]:
    unique_codes = [code for code in dict.fromkeys(normalize_text(code) for code in fund_codes) if code]
    histories: Dict[str, Dict[str, Any]] = {}
    quotes: Dict[str, Dict[str, Any]] = {}
    max_workers = max(1, min(8, len(unique_codes)))
    if not unique_codes:
        return histories, quotes
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        history_futures = {executor.submit(fetch_fund_history_series, code): code for code in unique_codes}
        for future in as_completed(history_futures):
            code = history_futures[future]
            try:
                histories[code] = future.result()
            except Exception:
                histories[code] = {}
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        quote_futures = {executor.submit(fetch_fund_quote, code): code for code in unique_codes}
        for future in as_completed(quote_futures):
            code = quote_futures[future]
            try:
                quotes[code] = future.result()
            except Exception:
                quotes[code] = {}
    return histories, quotes


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


def platform_window_label(value: str) -> str:
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


def platform_action_timestamp(action: Dict[str, Any]) -> int:
    return safe_int(action.get("txn_ts")) or safe_int(action.get("created_ts"))


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


def fetch_platform_trade_data(prod_code: str, timeout_seconds: int = PLATFORM_FETCH_TIMEOUT_SECONDS) -> Dict[str, Any]:
    target = normalize_text(prod_code)
    if not target:
        return {
            "supported": False,
            "error": "没有产品代码，无法直拉平台调仓记录。",
            "prod_code": "",
        }
    cached = PLATFORM_TRADE_CACHE.get(target)
    now = time.time()
    if cached and now - float(cached.get("ts", 0)) < PLATFORM_TRADE_TTL_SECONDS:
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
    return data


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
            ("快照时间", format_time(snapshot.get("created_at"))),
            ("当前标题", snapshot.get("title") or "未命名"),
        ]
    if snapshot.get("snapshot_type") == "groups":
        cards = [
            ("条目类型", "已加入小组"),
            ("总量", snapshot.get("count") or 0),
            ("快照时间", format_time(snapshot.get("created_at"))),
            ("当前标题", snapshot.get("title") or "未命名"),
        ]
    if snapshot.get("snapshot_type") == "items":
        cards = [
            ("条目类型", "公开内容"),
            ("总量", snapshot.get("count") or 0),
            ("作者数", stats.get("unique_authors") or 0),
            ("快照时间", format_time(snapshot.get("created_at"))),
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


def build_platform_monthly_overview(actions: List[Dict[str, Any]], limit_months: int = 12) -> Dict[str, Any]:
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
    return {
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


def history_list_html(history: List[Dict[str, Any]], current_name: str, form_values: Dict[str, str]) -> str:
    query = normalize_text(form_values.get("history_search")).lower()
    items = []
    for item in history:
        haystack = " ".join(
            [
                normalize_text(item.get("file_name")),
                normalize_text(item.get("title")),
                normalize_text(item.get("subtitle")),
                normalize_text(item.get("mode")),
            ]
        ).lower()
        if query and query not in haystack:
            continue
        items.append(item)
    if not items:
        return '<div class="empty">没有匹配到历史快照。</div>'
    parts = []
    for item in items:
        name = normalize_text(item.get("file_name"))
        active = " active" if name and name == current_name else ""
        href = build_page_url(
            form_values,
            snapshot=name,
            focus_post_id=None,
            comment_sort=None,
            comment_page=None,
            only_manager_replies=None,
            signal_filter=None,
            timeline_asset=None,
            auto_run=None,
        )
        parts.append(
            f'<a class="history-item{active}" href="{html.escape(href)}">'
            f'<h4>{html_text(item.get("title") or item.get("file_name"))}</h4>'
            f'<p>{html_text(item.get("subtitle") or item.get("mode"))} · {safe_int(item.get("count"))} 条 · {html_text(format_time(item.get("created_at")))}</p>'
            '<div class="chips">'
            f'<span class="chip">{html_text(item.get("kind_label"))}</span>'
            f'<span class="chip">{html_text(item.get("mode"))}</span>'
            "</div>"
            "</a>"
        )
    return "".join(parts)


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
        return '<div class="empty">点击右侧历史快照，或者从左边发起一次实时抓取。</div>'
    records = snapshot.get("records") if isinstance(snapshot.get("records"), list) else []
    if not records:
        return '<div class="empty">这份快照里没有可展示的记录。</div>'
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
    since_value = normalize_date_text(normalize_text(form_values.get("since")))
    until_value = normalize_date_text(normalize_text(form_values.get("until")))
    using_history_snapshot = normalize_text(source_label) == "历史快照"
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
            '<div class="empty">点击右侧历史快照，或者从左边发起一次实时抓取。</div>'
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
        subline += " 当前快照不是发帖类型，热评和主理人回复交互仅在发帖快照显示。"
    if using_history_snapshot and (since_value or until_value):
        subline += " 当前论坛区还是右侧选中的历史快照；如果想让论坛也按左侧日期对齐，请点一次“仅刷新最新”或“刷新并保存”。"
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
        '<div class="record-subline">下面这组占比按行业里更常见的资产分类口径和“当前份数”计算，不是按实时市值。因为平台这条接口稳定给到的是 `postPlanUnit`，没有稳定的实时持仓金额字段。</div>'
        f'<div class="record-subline">每张卡片里新增了“平均成本 / 当前估值 / 按当前份数估值 / 相对成本”。盘中拿不到估值的基金，会回退到最近官方净值。目前有 {safe_int(pricing_summary.get("estimate_count"))} 只使用盘中估值，{safe_int(pricing_summary.get("fallback_count"))} 只使用最近净值回退。这里的“按当前份数估值”是归一化比较值，不等于你真实账户金额。</div>'
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


def render_dashboard_page(
    *,
    history: List[Dict[str, Any]],
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
    }}
    a {{ color: inherit; text-decoration: none; }}
    .page {{ padding: 28px; }}
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
              <button class="btn-secondary" type="submit" name="action" value="fetch-save">刷新并保存</button>
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

          <p class="muted">{html.escape(detail_meta or "当前不展示历史快照卡片，主页每次打开都会自动抓取最新。")}</p>

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
        else "点击右侧历史快照，或者从左边发起一次实时抓取。"
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
          <p class="muted">{html.escape(detail_meta or "点击右侧历史快照，或者从左边发起一次实时抓取。")}</p>
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


def load_comments_for_view(
    snapshot: Optional[Dict[str, Any]],
    focus_post_id: int,
    comment_sort: str,
    comment_page: int,
    only_manager_replies: bool,
) -> tuple[Optional[Dict[str, Any]], str]:
    if not snapshot or snapshot.get("snapshot_type") != "posts" or not focus_post_id:
        return None, ""
    records = snapshot.get("records") if isinstance(snapshot.get("records"), list) else []
    target = None
    for record in records:
        if safe_int(record.get("post_id")) == focus_post_id:
            target = record
            break
    if not isinstance(target, dict):
        return None, "未找到这条发言。"
    manager_broker_user_id = normalize_text(target.get("broker_user_id")) if only_manager_replies else ""
    try:
        payload = fetch_post_comments(
            post_id=focus_post_id,
            page_size=max(1, safe_int(snapshot.get("meta", {}).get("page_size")) or 10),
            sort_type=comment_sort,
            page_num=max(1, comment_page),
            manager_broker_user_id=manager_broker_user_id,
        )
        return payload, ""
    except Exception as exc:
        return None, str(exc)


INDEX_HTML = """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>且慢主理人看板</title>
  <style>
    :root {
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
    }

    * { box-sizing: border-box; }
    body {
      margin: 0;
      color: var(--ink);
      font-family: "Avenir Next", "PingFang SC", "Hiragino Sans GB", "Noto Sans SC", sans-serif;
      background:
        radial-gradient(circle at top left, rgba(244, 201, 93, 0.3), transparent 30%),
        radial-gradient(circle at top right, rgba(13, 138, 118, 0.22), transparent 28%),
        linear-gradient(180deg, #faf6ef 0%, #f4ece1 100%);
      min-height: 100vh;
    }

    .page {
      padding: 28px;
    }

    .hero {
      display: flex;
      justify-content: space-between;
      gap: 20px;
      align-items: end;
      margin-bottom: 22px;
    }

    .hero h1 {
      margin: 0;
      font-size: clamp(28px, 4vw, 44px);
      line-height: 1.02;
      letter-spacing: -0.03em;
    }

    .hero p {
      margin: 8px 0 0;
      max-width: 780px;
      color: var(--muted);
      font-size: 15px;
      line-height: 1.6;
    }

    .hero-badges {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      justify-content: flex-end;
    }

    .badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 10px 14px;
      border-radius: 999px;
      background: rgba(255, 250, 242, 0.8);
      border: 1px solid rgba(23, 49, 59, 0.08);
      font-size: 13px;
      color: var(--ink);
      box-shadow: 0 8px 24px rgba(23, 49, 59, 0.06);
    }

    .dot {
      width: 10px;
      height: 10px;
      border-radius: 999px;
      background: var(--accent-3);
      box-shadow: 0 0 0 4px rgba(244, 201, 93, 0.18);
    }

    .dot.ok { background: var(--accent); box-shadow: 0 0 0 4px rgba(13, 138, 118, 0.16); }
    .dot.fail { background: var(--danger); box-shadow: 0 0 0 4px rgba(201, 87, 70, 0.16); }

    .layout {
      display: grid;
      grid-template-columns: 330px minmax(0, 1fr) 320px;
      gap: 18px;
      align-items: start;
    }

    .panel {
      background: var(--paper);
      border: 1px solid rgba(255, 255, 255, 0.5);
      backdrop-filter: blur(14px);
      border-radius: 26px;
      box-shadow: var(--shadow);
      padding: 18px;
    }

    .panel h2, .panel h3 {
      margin: 0;
      letter-spacing: -0.02em;
    }

    .controls-grid {
      display: grid;
      gap: 14px;
    }

    .field-group {
      display: grid;
      gap: 8px;
    }

    .field-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
    }

    label {
      font-size: 13px;
      color: var(--muted);
      display: grid;
      gap: 6px;
    }

    input, select, button, textarea {
      font: inherit;
    }

    input, select {
      width: 100%;
      border-radius: 14px;
      border: 1px solid var(--line);
      padding: 11px 12px;
      background: rgba(255, 255, 255, 0.72);
      color: var(--ink);
      min-height: 44px;
    }

    button {
      border: 0;
      border-radius: 14px;
      padding: 12px 14px;
      min-height: 46px;
      font-weight: 600;
      cursor: pointer;
      transition: transform 0.15s ease, box-shadow 0.15s ease, opacity 0.15s ease;
    }

    button:hover {
      transform: translateY(-1px);
    }

    button:disabled {
      cursor: wait;
      opacity: 0.65;
      transform: none;
    }

    .btn-primary {
      background: linear-gradient(135deg, var(--accent), #0c6a76);
      color: white;
      box-shadow: 0 16px 30px rgba(13, 138, 118, 0.22);
    }

    .btn-secondary {
      background: linear-gradient(135deg, #f8d978, var(--accent-2));
      color: #352518;
      box-shadow: 0 14px 30px rgba(244, 122, 85, 0.2);
    }

    .btn-ghost {
      background: rgba(255, 255, 255, 0.72);
      color: var(--ink);
      border: 1px solid var(--line);
    }

    .action-row {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
    }

    .single-action-row {
      display: grid;
      gap: 10px;
    }

    .muted {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.5;
    }

    .viewer {
      display: grid;
      gap: 18px;
    }

    .status-line {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 14px;
      margin-bottom: 12px;
    }

    .status-line p {
      margin: 6px 0 0;
      color: var(--muted);
      font-size: 14px;
      line-height: 1.6;
    }

    .metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
    }

    .metric {
      padding: 16px;
      border-radius: 18px;
      background: linear-gradient(180deg, rgba(255,255,255,0.82), rgba(255,255,255,0.62));
      border: 1px solid rgba(23, 49, 59, 0.08);
    }

    .metric small {
      color: var(--muted);
      display: block;
      margin-bottom: 8px;
    }

    .metric strong {
      display: block;
      font-size: 24px;
      letter-spacing: -0.03em;
      line-height: 1.05;
    }

    .snapshot-head {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
      margin-bottom: 14px;
    }

    .snapshot-head h2 {
      font-size: 24px;
      line-height: 1.1;
    }

    .chips {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 10px;
    }

    .chip {
      display: inline-flex;
      padding: 7px 11px;
      border-radius: 999px;
      background: rgba(13, 138, 118, 0.09);
      color: var(--accent);
      font-size: 12px;
      border: 1px solid rgba(13, 138, 118, 0.12);
    }

    .bars {
      display: flex;
      align-items: end;
      gap: 8px;
      min-height: 120px;
      padding: 10px 0 0;
    }

    .bar {
      flex: 1;
      min-width: 0;
      display: grid;
      gap: 8px;
      align-items: end;
    }

    .bar-fill {
      border-radius: 14px 14px 6px 6px;
      background: linear-gradient(180deg, rgba(244, 122, 85, 0.9), rgba(13, 138, 118, 0.92));
      min-height: 8px;
    }

    .bar-label {
      color: var(--muted);
      font-size: 11px;
      text-align: center;
    }

    .records {
      display: grid;
      gap: 12px;
    }

    .record-card {
      border-radius: 22px;
      padding: 18px;
      background: linear-gradient(180deg, rgba(255,255,255,0.9), rgba(255,255,255,0.72));
      border: 1px solid rgba(23, 49, 59, 0.08);
      scroll-margin-top: 24px;
    }

    .record-card.record-focus {
      border-color: rgba(13, 138, 118, 0.42);
      box-shadow: 0 0 0 4px rgba(13, 138, 118, 0.12);
    }

    .record-top {
      display: flex;
      justify-content: space-between;
      gap: 14px;
      align-items: start;
      margin-bottom: 12px;
    }

    .record-title {
      margin: 0;
      font-size: 18px;
      line-height: 1.35;
    }

    .record-meta {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      color: var(--muted);
      font-size: 12px;
    }

    .record-meta span {
      display: inline-flex;
      padding: 6px 9px;
      border-radius: 999px;
      background: rgba(23, 49, 59, 0.06);
    }

    details {
      border-top: 1px solid rgba(23, 49, 59, 0.08);
      margin-top: 12px;
      padding-top: 10px;
    }

    summary {
      cursor: pointer;
      color: var(--accent);
      font-weight: 600;
    }

    .record-content {
      color: var(--ink);
      line-height: 1.75;
      font-size: 14px;
      white-space: pre-wrap;
      word-break: break-word;
      margin-top: 10px;
    }

    .comment-details {
      margin-top: 12px;
    }

    .comment-list {
      display: grid;
      gap: 10px;
      margin-top: 12px;
    }

    .comment-toolbar {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      margin-top: 10px;
    }

    .comment-sort-btn {
      border: 1px solid rgba(23, 49, 59, 0.08);
      background: rgba(255,255,255,0.72);
      color: var(--muted);
      min-height: 34px;
      padding: 8px 12px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 600;
      box-shadow: none;
    }

    .comment-sort-btn.active {
      color: white;
      background: linear-gradient(135deg, var(--accent), #0c6a76);
      border-color: transparent;
    }

    .comment-card {
      padding: 14px 16px;
      border-radius: 16px;
      background: rgba(23, 49, 59, 0.045);
      border: 1px solid rgba(23, 49, 59, 0.06);
    }

    .comment-head {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
      margin-bottom: 8px;
    }

    .comment-author {
      display: flex;
      gap: 10px;
      align-items: center;
    }

    .comment-author strong {
      display: block;
      font-size: 14px;
    }

    .comment-author small {
      color: var(--muted);
      display: block;
      margin-top: 2px;
    }

    .comment-avatar {
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
    }

    .comment-avatar img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }

    .comment-meta {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      color: var(--muted);
      font-size: 12px;
    }

    .comment-meta span {
      display: inline-flex;
      padding: 5px 8px;
      border-radius: 999px;
      background: rgba(255,255,255,0.72);
    }

    .comment-body {
      white-space: pre-wrap;
      line-height: 1.7;
      font-size: 14px;
      word-break: break-word;
    }

    .reply-list {
      display: grid;
      gap: 8px;
      margin-top: 10px;
      padding-left: 14px;
      border-left: 2px solid rgba(13, 138, 118, 0.12);
    }

    .reply-card {
      padding: 10px 12px;
      border-radius: 14px;
      background: rgba(255,255,255,0.75);
      border: 1px solid rgba(23, 49, 59, 0.06);
    }

    .reply-head {
      display: flex;
      justify-content: space-between;
      gap: 10px;
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 6px;
    }

    .comment-loading {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.6;
      padding: 10px 0 4px;
    }

    .comment-footer {
      margin-top: 10px;
    }

    .comment-more-btn {
      border: 1px solid rgba(23, 49, 59, 0.08);
      background: rgba(255,255,255,0.82);
      color: var(--ink);
      min-height: 38px;
      padding: 9px 14px;
      border-radius: 999px;
      font-size: 13px;
      font-weight: 600;
      box-shadow: none;
    }

    .signal-stats {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
      margin-bottom: 14px;
    }

    .signal-stat {
      padding: 16px;
      border-radius: 18px;
      background: linear-gradient(180deg, rgba(255,255,255,0.86), rgba(255,255,255,0.68));
      border: 1px solid rgba(23, 49, 59, 0.08);
    }

    .signal-stat small {
      display: block;
      color: var(--muted);
      margin-bottom: 8px;
    }

    .signal-stat strong {
      display: block;
      font-size: 22px;
      letter-spacing: -0.03em;
      line-height: 1.15;
    }

    .signal-toolbar {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      margin-bottom: 14px;
    }

    .signal-filter-btn {
      min-height: 36px;
      padding: 8px 12px;
      border-radius: 999px;
      border: 1px solid rgba(23, 49, 59, 0.08);
      background: rgba(255,255,255,0.78);
      color: var(--muted);
      font-size: 12px;
      box-shadow: none;
    }

    .signal-filter-btn.active {
      background: linear-gradient(135deg, var(--accent), #0c6a76);
      color: white;
      border-color: transparent;
    }

    .signal-list {
      display: grid;
      gap: 12px;
    }

    .timeline-block {
      margin-top: 18px;
      border-top: 1px solid rgba(23, 49, 59, 0.08);
      padding-top: 18px;
    }

    .timeline-head {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
      margin-bottom: 12px;
    }

    .timeline-head h3 {
      font-size: 20px;
      line-height: 1.2;
    }

    .timeline-list {
      display: grid;
      gap: 12px;
    }

    .timeline-card {
      padding: 16px 18px;
      border-radius: 20px;
      border: 1px solid rgba(23, 49, 59, 0.08);
      background: linear-gradient(180deg, rgba(255,255,255,0.88), rgba(255,255,255,0.7));
    }

    .timeline-card-head {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
      margin-bottom: 12px;
    }

    .timeline-card-head h4 {
      margin: 0;
      font-size: 18px;
      line-height: 1.3;
    }

    .timeline-counts {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      color: var(--muted);
      font-size: 12px;
      margin-top: 8px;
    }

    .timeline-counts span {
      display: inline-flex;
      padding: 6px 9px;
      border-radius: 999px;
      background: rgba(23, 49, 59, 0.06);
    }

    .timeline-entries {
      display: grid;
      gap: 10px;
    }

    .timeline-entry {
      display: grid;
      grid-template-columns: 124px minmax(0, 1fr);
      gap: 12px;
      align-items: start;
      padding-top: 10px;
      border-top: 1px solid rgba(23, 49, 59, 0.08);
    }

    .timeline-entry:first-child {
      border-top: 0;
      padding-top: 0;
    }

    .timeline-time {
      color: var(--muted);
      font-size: 12px;
      line-height: 1.6;
    }

    .timeline-entry-main {
      display: grid;
      gap: 8px;
    }

    .timeline-entry-top {
      display: flex;
      justify-content: space-between;
      gap: 10px;
      align-items: center;
      flex-wrap: wrap;
    }

    .timeline-entry-title {
      font-size: 14px;
      line-height: 1.6;
      color: var(--ink);
      white-space: pre-wrap;
      word-break: break-word;
    }

    .timeline-jump {
      min-height: 34px;
      padding: 8px 12px;
      border-radius: 999px;
      border: 1px solid rgba(13, 138, 118, 0.12);
      background: rgba(13, 138, 118, 0.06);
      color: var(--accent);
      font-size: 12px;
      font-weight: 700;
      box-shadow: none;
    }

    .signal-card {
      padding: 16px 18px;
      border-radius: 20px;
      border: 1px solid rgba(23, 49, 59, 0.08);
      background: linear-gradient(180deg, rgba(255,255,255,0.9), rgba(255,255,255,0.7));
      position: relative;
      overflow: hidden;
    }

    .signal-card::before {
      content: "";
      position: absolute;
      inset: 0 auto 0 0;
      width: 5px;
      background: rgba(23, 49, 59, 0.12);
    }

    .signal-card.buy::before {
      background: linear-gradient(180deg, #16a085, #0d8a76);
    }

    .signal-card.sell::before {
      background: linear-gradient(180deg, #f47a55, #c95746);
    }

    .signal-card.watch::before {
      background: linear-gradient(180deg, #f4c95d, #d9a93d);
    }

    .signal-top {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
    }

    .signal-title {
      margin: 0;
      font-size: 17px;
      line-height: 1.4;
    }

    .signal-badge {
      display: inline-flex;
      align-items: center;
      padding: 7px 11px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 700;
      color: white;
      background: rgba(23, 49, 59, 0.18);
      flex: 0 0 auto;
    }

    .signal-badge.buy {
      background: linear-gradient(135deg, #16a085, #0d8a76);
    }

    .signal-badge.sell {
      background: linear-gradient(135deg, #f47a55, #c95746);
    }

    .signal-badge.watch {
      color: #4f3b10;
      background: linear-gradient(135deg, #f4d777, #f0c256);
    }

    .signal-summary {
      margin-top: 10px;
      color: var(--ink);
      font-size: 14px;
      line-height: 1.75;
      white-space: pre-wrap;
      word-break: break-word;
    }

    .signal-link {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      margin-top: 10px;
      color: var(--accent);
      font-size: 13px;
      text-decoration: none;
      font-weight: 600;
      border: 1px solid rgba(13, 138, 118, 0.12);
      background: rgba(13, 138, 118, 0.06);
      border-radius: 999px;
      padding: 9px 14px;
    }

    .signal-link:hover {
      text-decoration: underline;
    }

    .history-top {
      display: flex;
      justify-content: space-between;
      gap: 10px;
      align-items: start;
      margin-bottom: 12px;
    }

    .history-search {
      margin-bottom: 10px;
    }

    .history-list {
      display: grid;
      gap: 10px;
      max-height: calc(100vh - 220px);
      overflow: auto;
      padding-right: 4px;
    }

    .history-item {
      border: 1px solid rgba(23, 49, 59, 0.08);
      border-radius: 18px;
      background: rgba(255,255,255,0.72);
      padding: 14px;
      cursor: pointer;
    }

    .history-item.active {
      border-color: rgba(13, 138, 118, 0.42);
      box-shadow: 0 0 0 3px rgba(13, 138, 118, 0.12);
    }

    .history-item h4 {
      margin: 0 0 6px;
      font-size: 15px;
      line-height: 1.35;
    }

    .history-item p {
      margin: 0;
      color: var(--muted);
      font-size: 12px;
      line-height: 1.5;
    }

    .empty {
      padding: 28px 18px;
      text-align: center;
      color: var(--muted);
      border: 1px dashed rgba(23, 49, 59, 0.16);
      border-radius: 18px;
    }

    .hidden { display: none !important; }

    .footer-note {
      margin-top: 12px;
      color: var(--muted);
      font-size: 12px;
      line-height: 1.5;
    }

    @media (max-width: 1320px) {
      .layout {
        grid-template-columns: 300px minmax(0, 1fr);
      }
      .history {
        grid-column: 1 / -1;
      }
      .history-list {
        max-height: none;
      }
    }

    @media (max-width: 980px) {
      .page { padding: 18px; }
      .hero { display: grid; }
      .layout {
        grid-template-columns: 1fr;
      }
      .metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
      .signal-stats {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
      .timeline-entry {
        grid-template-columns: 1fr;
      }
      .field-grid, .action-row {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>
  <div class="page">
    <header class="hero">
      <div>
        <h1>且慢主理人看板</h1>
        <p>把公开历史、登录后的关注动态、关键词筛选和临时实时刷新放进一个本地页面里。你以后想看主理人的历史发言，或者想临时刷新一下最新动态，都可以在这里直接完成。</p>
      </div>
      <div class="hero-badges">
        <div class="badge"><span id="cookieDot" class="dot"></span><span id="cookieStatus">正在检查 Cookie</span></div>
        <div class="badge"><span class="dot ok"></span><span id="snapshotStatus">载入历史中</span></div>
      </div>
    </header>

    <div class="layout">
      <section class="panel controls">
        <div class="controls-grid">
          <div>
            <h2>实时查询</h2>
            <p class="muted">左边改条件，点刷新，最新结果会显示在中间。自动刷新默认不会写入历史；“刷新并保存”才会落进 `output/`。</p>
          </div>

          <div class="field-group">
            <label>模式
              <select id="mode">
                <option value="following-posts">关注动态</option>
                <option value="group-manager">公开主理人流</option>
                <option value="following-users">关注用户</option>
                <option value="my-groups">已加入小组</option>
                <option value="space-items">个人空间动态</option>
              </select>
            </label>
          </div>

          <div id="groupFields" class="field-group">
            <div class="field-grid">
              <label>产品代码
                <input id="prod_code" placeholder="LONG_WIN">
              </label>
              <label>主理人
                <input id="manager_name" placeholder="ETF拯救世界">
              </label>
            </div>
            <div class="field-grid">
              <label>小组链接
                <input id="group_url" placeholder="https://qieman.com/content/group-detail/43">
              </label>
              <label>groupId
                <input id="group_id" placeholder="43">
              </label>
            </div>
          </div>

          <div id="userFields" class="field-group">
            <div class="field-grid">
              <label>用户昵称
                <input id="user_name" placeholder="ETF拯救世界">
              </label>
              <label>brokerUserId
                <input id="broker_user_id" placeholder="793413">
              </label>
            </div>
            <div class="field-grid">
              <label>spaceUserId
                <input id="space_user_id" placeholder="123456">
              </label>
              <label>关键词
                <input id="keyword" placeholder="指数 / 红利 / 创业板">
              </label>
            </div>
          </div>

          <div class="field-grid">
            <label>起始日期
              <input id="since" placeholder="2026-04-01">
            </label>
            <label>结束日期
              <input id="until" placeholder="2026-04-17">
            </label>
          </div>

          <div class="field-grid">
            <label>页数
              <input id="pages" value="5" placeholder="5">
            </label>
            <label>每页条数
              <input id="page_size" value="10" placeholder="10">
            </label>
          </div>

          <div class="field-grid">
            <label>自动刷新
              <select id="auto_refresh">
                <option value="">关闭</option>
                <option value="30">每 30 秒</option>
                <option value="60">每 60 秒</option>
                <option value="300">每 5 分钟</option>
              </select>
            </label>
            <label>历史搜索
              <input id="historySearch" class="history-search" placeholder="搜文件名 / 标题 / 模式">
            </label>
          </div>

          <div class="action-row">
            <button id="fetchBtn" class="btn-primary">仅刷新最新</button>
            <button id="saveBtn" class="btn-secondary">刷新并保存</button>
          </div>

          <div class="single-action-row">
            <button id="authBtn" class="btn-ghost">验证登录态</button>
          </div>

          <div id="formHint" class="muted">当前推荐：如果你是想盯 `ETF拯救世界` 的最新发言，直接用“关注动态 + 用户昵称”就够了。</div>
        </div>
      </section>

      <main class="viewer">
        <section class="panel">
          <div class="status-line">
            <div>
              <h2 id="currentTitle">等待载入</h2>
              <p id="currentSubtitle">历史快照和最新抓取结果会显示在这里。</p>
            </div>
            <div class="badge"><span class="dot ok"></span><span id="sourceBadge">尚未选择数据</span></div>
          </div>
          <div class="chips" id="currentChips"></div>
        </section>

        <section class="panel">
          <div class="metrics" id="metrics"></div>
          <div id="barsWrap" class="hidden">
            <div class="bars" id="bars"></div>
          </div>
        </section>

        <section id="signalPanel" class="panel hidden">
          <div class="snapshot-head">
            <div>
              <h2>高置信交易动作</h2>
              <p id="signalMeta" class="muted">这里只统计主理人明确表达“已经执行”的买入、卖出、减仓、清仓。</p>
            </div>
            <div class="chips" id="signalSummaryChips"></div>
          </div>
          <div id="signalStats" class="signal-stats"></div>
          <div id="signalToolbar" class="signal-toolbar"></div>
          <div id="signalList" class="signal-list"></div>
          <div class="timeline-block">
            <div class="timeline-head">
              <div>
                <h3>按标的聚合时间线</h3>
                <p id="timelineMeta" class="muted">同一个标的最近被买入、卖出、减仓、清仓的顺序，会在这里串起来。</p>
              </div>
            </div>
            <div id="timelineToolbar" class="signal-toolbar"></div>
            <div id="timelineList" class="timeline-list"></div>
          </div>
        </section>

        <section class="panel">
          <div class="snapshot-head">
            <div>
              <h2>明细</h2>
              <p id="detailMeta" class="muted">点击右侧历史快照，或者从左边发起一次实时抓取。</p>
            </div>
          </div>
          <div id="records" class="records">
            <div class="empty">还没有选中任何数据。</div>
          </div>
        </section>
      </main>

      <aside class="panel history">
        <div class="history-top">
          <div>
            <h2>历史快照</h2>
            <p class="muted">直接读取本地 `output/` 的 JSON 文件。</p>
          </div>
          <button id="reloadHistoryBtn" class="btn-ghost">重载历史</button>
        </div>
        <div id="historyList" class="history-list">
          <div class="empty">历史快照读取中。</div>
        </div>
        <div class="footer-note">这个看板默认只监听 `127.0.0.1`。Cookie 仍然只保存在本机文件里，不会在页面里直接展示原文。</div>
      </aside>
    </div>
  </div>

  <script>
    window.__dashboardMainReady = false;
    const state = {
      history: [],
      current: null,
      currentSource: "",
      activeHistoryName: "",
      autoTimer: null,
      commentCache: new Map(),
      signalFilter: "all",
      timelineAssetFilter: "all",
    };

    const els = {
      mode: document.getElementById("mode"),
      prod_code: document.getElementById("prod_code"),
      manager_name: document.getElementById("manager_name"),
      group_url: document.getElementById("group_url"),
      group_id: document.getElementById("group_id"),
      user_name: document.getElementById("user_name"),
      broker_user_id: document.getElementById("broker_user_id"),
      space_user_id: document.getElementById("space_user_id"),
      keyword: document.getElementById("keyword"),
      since: document.getElementById("since"),
      until: document.getElementById("until"),
      pages: document.getElementById("pages"),
      page_size: document.getElementById("page_size"),
      auto_refresh: document.getElementById("auto_refresh"),
      fetchBtn: document.getElementById("fetchBtn"),
      saveBtn: document.getElementById("saveBtn"),
      authBtn: document.getElementById("authBtn"),
      reloadHistoryBtn: document.getElementById("reloadHistoryBtn"),
      historySearch: document.getElementById("historySearch"),
      historyList: document.getElementById("historyList"),
      currentTitle: document.getElementById("currentTitle"),
      currentSubtitle: document.getElementById("currentSubtitle"),
      currentChips: document.getElementById("currentChips"),
      metrics: document.getElementById("metrics"),
      barsWrap: document.getElementById("barsWrap"),
      bars: document.getElementById("bars"),
      signalPanel: document.getElementById("signalPanel"),
      signalMeta: document.getElementById("signalMeta"),
      signalSummaryChips: document.getElementById("signalSummaryChips"),
      signalStats: document.getElementById("signalStats"),
      signalToolbar: document.getElementById("signalToolbar"),
      signalList: document.getElementById("signalList"),
      timelineMeta: document.getElementById("timelineMeta"),
      timelineToolbar: document.getElementById("timelineToolbar"),
      timelineList: document.getElementById("timelineList"),
      detailMeta: document.getElementById("detailMeta"),
      records: document.getElementById("records"),
      sourceBadge: document.getElementById("sourceBadge"),
      cookieDot: document.getElementById("cookieDot"),
      cookieStatus: document.getElementById("cookieStatus"),
      snapshotStatus: document.getElementById("snapshotStatus"),
      groupFields: document.getElementById("groupFields"),
      userFields: document.getElementById("userFields"),
      formHint: document.getElementById("formHint"),
    };

    function requestJsonWithXHR(path, options = {}) {
      return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open(options.method || "GET", path, true);
        const headers = options.headers || {};
        Object.keys(headers).forEach((key) => {
          xhr.setRequestHeader(key, headers[key]);
        });
        xhr.onreadystatechange = () => {
          if (xhr.readyState !== 4) {
            return;
          }
          let data = {};
          try {
            data = xhr.responseText ? JSON.parse(xhr.responseText) : {};
          } catch (error) {
            reject(new Error("返回结果不是合法 JSON"));
            return;
          }
          if (xhr.status >= 200 && xhr.status < 300) {
            resolve(data);
            return;
          }
          reject(new Error(data.error || "请求失败"));
        };
        xhr.onerror = () => reject(new Error("网络请求失败"));
        xhr.send(options.body || null);
      });
    }

    async function api(path, options = {}) {
      if (typeof fetch === "function") {
        const response = await fetch(path, options);
        const data = await response.json();
        if (!response.ok) {
          throw new Error(data.error || "请求失败");
        }
        return data;
      }
      return requestJsonWithXHR(path, options);
    }

    function setBusy(isBusy) {
      [els.fetchBtn, els.saveBtn, els.authBtn, els.reloadHistoryBtn].forEach((button) => {
        button.disabled = isBusy;
      });
    }

    function setInitError(message) {
      els.cookieStatus.textContent = "页面初始化失败";
      els.cookieDot.className = "dot fail";
      els.snapshotStatus.textContent = normalizeText(message || "未知错误");
    }

    function normalizeText(value) {
      return String(value || "").replace(/\s+/g, " ").trim();
    }

    function collectPayload() {
      return {
        mode: els.mode.value,
        prod_code: els.prod_code.value.trim(),
        manager_name: els.manager_name.value.trim(),
        group_url: els.group_url.value.trim(),
        group_id: els.group_id.value.trim(),
        user_name: els.user_name.value.trim(),
        broker_user_id: els.broker_user_id.value.trim(),
        space_user_id: els.space_user_id.value.trim(),
        keyword: els.keyword.value.trim(),
        since: els.since.value.trim(),
        until: els.until.value.trim(),
        pages: els.pages.value.trim(),
        page_size: els.page_size.value.trim(),
      };
    }

    function formatTime(value) {
      if (!value) return "未记录";
      return value.replace("T", " ").slice(0, 19);
    }

    function escapeHtml(value) {
      return String(value || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
    }

    function applyModeVisibility() {
      const mode = els.mode.value;
      const groupModes = new Set(["group-manager"]);
      const userModes = new Set(["following-posts", "space-items"]);
      els.groupFields.classList.toggle("hidden", !groupModes.has(mode));
      els.userFields.classList.toggle("hidden", !userModes.has(mode));

      const hints = {
        "following-posts": "推荐先用“关注动态”，它最适合盯你已经关注的主理人最新发言。",
        "group-manager": "公开模式适合按产品代码或小组去追主理人发言，不依赖登录。",
        "following-users": "这个模式只导出你当前账号关注了哪些主理人。",
        "my-groups": "这个模式会尝试读取你已加入的小组列表。",
        "space-items": "个人空间动态需要 `spaceUserId`，或者在你已登录时按昵称自动反查。",
      };
      els.formHint.textContent = hints[mode] || "";
    }

    function renderHistory() {
      const query = els.historySearch.value.trim().toLowerCase();
      const items = state.history.filter((item) => {
        if (!query) return true;
        return [item.file_name, item.title, item.subtitle, item.mode]
          .join(" ")
          .toLowerCase()
          .includes(query);
      });

      if (!items.length) {
        els.historyList.innerHTML = '<div class="empty">没有匹配到历史快照。</div>';
        return;
      }

      els.historyList.innerHTML = items.map((item) => `
        <div class="history-item ${state.activeHistoryName === item.file_name ? "active" : ""}" data-name="${escapeHtml(item.file_name)}">
          <h4>${escapeHtml(item.title || item.file_name)}</h4>
          <p>${escapeHtml(item.subtitle || item.mode)} · ${item.count} 条 · ${formatTime(item.created_at)}</p>
          <div class="chips">
            <span class="chip">${escapeHtml(item.kind_label)}</span>
            <span class="chip">${escapeHtml(item.mode)}</span>
          </div>
        </div>
      `).join("");

      els.historyList.querySelectorAll(".history-item").forEach((node) => {
        node.addEventListener("click", () => loadSnapshot(node.dataset.name));
      });
    }

    function renderMetrics(snapshot) {
      const stats = snapshot.stats || {};
      const cards = [
        ["总量", snapshot.count || 0],
        ["最新时间", formatTime(stats.latest_created_at || snapshot.created_at)],
        ["用户数", stats.unique_users || 0],
        ["分组数", stats.unique_groups || 0],
      ];
      if (snapshot.snapshot_type === "users") {
        cards[1] = ["快照时间", formatTime(snapshot.created_at)];
        cards[2] = ["条目类型", "关注用户"];
        cards[3] = ["总量", snapshot.count || 0];
      }
      if (snapshot.snapshot_type === "groups") {
        cards[1] = ["快照时间", formatTime(snapshot.created_at)];
        cards[2] = ["条目类型", "已加入小组"];
        cards[3] = ["总量", snapshot.count || 0];
      }
      if (snapshot.snapshot_type === "items") {
        cards[1] = ["快照时间", formatTime(snapshot.created_at)];
        cards[2] = ["作者数", stats.unique_authors || 0];
        cards[3] = ["总量", snapshot.count || 0];
      }

      els.metrics.innerHTML = cards.map(([label, value]) => `
        <div class="metric">
          <small>${escapeHtml(label)}</small>
          <strong>${escapeHtml(String(value))}</strong>
        </div>
      `).join("");

      const bars = (stats.by_day || []).slice(0, 8);
      if (!bars.length) {
        els.barsWrap.classList.add("hidden");
        els.bars.innerHTML = "";
        return;
      }
      const max = bars.reduce((currentMax, item) => Math.max(currentMax, item.count), 1);
      els.barsWrap.classList.remove("hidden");
      els.bars.innerHTML = bars.reverse().map((item) => {
        const height = Math.max(10, Math.round((item.count / max) * 92));
        return `
          <div class="bar">
            <div class="bar-fill" style="height:${height}px"></div>
            <div class="bar-label">${escapeHtml(item.date.slice(5))}<br>${item.count}</div>
          </div>
        `;
      }).join("");
    }

    function renderSignalToolbar(filter, counts) {
      const items = [
        ["all", "全部", (counts.buy || 0) + (counts.sell || 0)],
        ["buy", "买入侧", counts.buy || 0],
        ["sell", "卖出侧", counts.sell || 0],
      ];
      return items.map(([value, label, count]) => `
        <button type="button" class="signal-filter-btn ${filter === value ? "active" : ""}" data-signal-filter="${escapeHtml(value)}">
          ${escapeHtml(label)} · ${escapeHtml(String(count))}
        </button>
      `).join("");
    }

    function renderTimelineToolbar(filter, timeline) {
      const items = [["all", "全部标的", timeline.length]];
      timeline.slice(0, 8).forEach((asset) => {
        items.push([asset.label, asset.label, asset.event_count || 0]);
      });
      return items.map(([value, label, count]) => `
        <button type="button" class="signal-filter-btn ${filter === value ? "active" : ""}" data-timeline-filter="${escapeHtml(value)}">
          ${escapeHtml(label)} · ${escapeHtml(String(count))}
        </button>
      `).join("");
    }

    function renderSignalCard(signal) {
      const metaChips = [];
      if (signal.created_at) {
        metaChips.push(formatTime(signal.created_at));
      }
      (signal.assets || []).forEach((item) => {
        metaChips.push(`标的 ${item}`);
      });
      (signal.matched_actions || []).slice(0, 3).forEach((item) => {
        metaChips.push(`动作 ${item}`);
      });
      if (signal.post_title && signal.post_title !== signal.title) {
        metaChips.push(`原帖 ${signal.post_title}`);
      }
      const eventLines = (signal.events || []).map((event) => {
        const eventAssets = (event.assets || []).length ? ` [${event.assets.join(" / ")}]` : "";
        return `${event.action}${eventAssets} ${event.sentence || ""}`.trim();
      });
      return `
        <article class="signal-card ${escapeHtml(signal.side || "sell")}">
          <div class="signal-top">
            <div>
              <h3 class="signal-title">${escapeHtml(signal.title || ("帖子 " + (signal.post_id || "")))}</h3>
              <div class="record-meta">
                ${metaChips.map((chip) => `<span>${escapeHtml(chip)}</span>`).join("")}
                <span>赞 ${escapeHtml(signal.like_count || 0)}</span>
                <span>评 ${escapeHtml(signal.comment_count || 0)}</span>
              </div>
            </div>
            <span class="signal-badge ${escapeHtml(signal.side || "sell")}">${escapeHtml(signal.action || "交易")}</span>
          </div>
          ${eventLines.length ? `<div class="record-content">${escapeHtml(eventLines.join("\n"))}</div>` : ""}
          <div class="signal-summary">${escapeHtml(signal.content_text || signal.excerpt || "这条发言没有提炼到正文。")}</div>
          ${signal.post_id ? `<button type="button" class="signal-link" data-jump-post-id="${escapeHtml(signal.post_id)}">定位到原始发言</button>` : ""}
        </article>
      `;
    }

    function attachSignalInteractions() {
      document.querySelectorAll("[data-jump-post-id]").forEach((button) => {
        button.addEventListener("click", () => {
          const postId = button.dataset.jumpPostId || "";
          if (!postId) {
            return;
          }
          const recordNode = document.querySelector(`[data-post-record-id="${postId}"]`);
          if (!recordNode) {
            return;
          }
          recordNode.classList.add("record-focus");
          const contentDetails = recordNode.querySelector(".post-content-details");
          if (contentDetails) {
            contentDetails.open = true;
          }
          recordNode.scrollIntoView({ behavior: "smooth", block: "start" });
          window.setTimeout(() => recordNode.classList.remove("record-focus"), 2200);
        });
      });
    }

    function renderTimelineCard(asset, isFocused) {
      const entries = (asset.entries || []).slice(0, isFocused ? 12 : 5);
      return `
        <article class="timeline-card">
          <div class="timeline-card-head">
            <div>
              <h4>${escapeHtml(asset.label || "未标注标的")}</h4>
              <div class="timeline-counts">
                <span>动作 ${escapeHtml(asset.event_count || 0)}</span>
                <span>买入 ${escapeHtml(asset.buy_count || 0)}</span>
                <span>卖出 ${escapeHtml(asset.sell_count || 0)}</span>
                <span>最近 ${escapeHtml(asset.latest_action || "未知")} · ${escapeHtml(formatTime(asset.latest_created_at))}</span>
              </div>
            </div>
          </div>
          <div class="timeline-entries">
            ${entries.map((entry) => `
              <div class="timeline-entry">
                <div class="timeline-time">${escapeHtml(formatTime(entry.created_at))}</div>
                <div class="timeline-entry-main">
                  <div class="timeline-entry-top">
                    <span class="signal-badge ${escapeHtml(entry.side || "sell")}">${escapeHtml(entry.action || "交易")}</span>
                    ${entry.post_id ? `<button type="button" class="timeline-jump" data-jump-post-id="${escapeHtml(entry.post_id)}">定位原帖</button>` : ""}
                  </div>
                  <div class="timeline-entry-title">${escapeHtml(entry.sentence || entry.title || "无交易描述")}</div>
                  ${entry.post_title && entry.post_title !== entry.sentence ? `<div class="muted">${escapeHtml(entry.post_title)}</div>` : ""}
                </div>
              </div>
            `).join("")}
          </div>
        </article>
      `;
    }

    function renderSignalPanel(snapshot) {
      const signals = snapshot.signals || {};
      const items = signals.items || [];
      const timeline = signals.timeline || [];
      if (snapshot.snapshot_type !== "posts" || !items.length) {
        els.signalPanel.classList.add("hidden");
        els.signalSummaryChips.innerHTML = "";
        els.signalStats.innerHTML = "";
        els.signalToolbar.innerHTML = "";
        els.signalList.innerHTML = "";
        els.timelineToolbar.innerHTML = "";
        els.timelineList.innerHTML = "";
        return;
      }

      const counts = signals.counts || {};
      const latest = signals.latest || null;
      els.signalPanel.classList.remove("hidden");
      els.signalMeta.textContent = latest
        ? `最近一次识别到的已执行交易是“${latest.action || "交易"}”，时间 ${formatTime(latest.created_at)}。`
        : "当前快照里还没有识别到高置信的已执行交易。";

      const summaryChips = [];
      (signals.top_assets || []).slice(0, 4).forEach((item) => {
        summaryChips.push(`${item.label} ${item.count}`);
      });
      (signals.top_actions || []).slice(0, 3).forEach((item) => {
        summaryChips.push(`${item.label} ${item.count}`);
      });
      els.signalSummaryChips.innerHTML = summaryChips.map((chip) => `<span class="chip">${escapeHtml(chip)}</span>`).join("");

      const statCards = [
        ["交易帖子", signals.count || 0],
        ["交易动作", signals.event_count || 0],
        ["买入侧", counts.buy || 0],
        ["卖出侧", counts.sell || 0],
      ];
      els.signalStats.innerHTML = statCards.map(([label, value]) => `
        <div class="signal-stat">
          <small>${escapeHtml(label)}</small>
          <strong>${escapeHtml(String(value))}</strong>
        </div>
      `).join("");

      els.signalToolbar.innerHTML = renderSignalToolbar(state.signalFilter, counts);
      const filtered = items.filter((item) => state.signalFilter === "all" || item.side === state.signalFilter);
      els.signalList.innerHTML = filtered.length
        ? filtered.map(renderSignalCard).join("")
        : '<div class="empty">这个筛选下还没有识别到高置信交易动作。</div>';

      els.timelineMeta.textContent = timeline.length
        ? `当前快照里共识别到 ${timeline.length} 个标的的真实交易轨迹。`
        : "当前快照里还没有可聚合的标的交易轨迹。";
      els.timelineToolbar.innerHTML = renderTimelineToolbar(state.timelineAssetFilter, timeline);
      const filteredTimeline = timeline.filter((asset) => state.timelineAssetFilter === "all" || asset.label === state.timelineAssetFilter);
      els.timelineList.innerHTML = filteredTimeline.length
        ? filteredTimeline.map((asset) => renderTimelineCard(asset, state.timelineAssetFilter !== "all")).join("")
        : '<div class="empty">这个标的下还没有可展示的交易时间线。</div>';

      attachSignalInteractions();

      els.signalToolbar.querySelectorAll("[data-signal-filter]").forEach((button) => {
        button.addEventListener("click", () => {
          state.signalFilter = button.dataset.signalFilter || "all";
          renderSignalPanel(snapshot);
        });
      });

      els.timelineToolbar.querySelectorAll("[data-timeline-filter]").forEach((button) => {
        button.addEventListener("click", () => {
          state.timelineAssetFilter = button.dataset.timelineFilter || "all";
          renderSignalPanel(snapshot);
        });
      });
    }

    function renderRecords(snapshot) {
      const records = snapshot.records || [];
      if (!records.length) {
        els.records.innerHTML = '<div class="empty">这份快照里没有可展示的记录。</div>';
        return;
      }

      if (snapshot.snapshot_type === "posts") {
        els.records.innerHTML = records.map((post) => `
          <article id="post-record-${escapeHtml(post.post_id || "")}" class="record-card" data-post-record-id="${escapeHtml(post.post_id || "")}">
            <div class="record-top">
              <div>
                <h3 class="record-title">${escapeHtml(post.title || post.intro || ("帖子 " + (post.post_id || "")))}</h3>
                <div class="record-meta">
                  <span>${escapeHtml(post.user_name || post.broker_user_id || "未知用户")}</span>
                  <span>${escapeHtml(post.group_name || "未标注小组")}</span>
                  <span>${escapeHtml(formatTime(post.created_at))}</span>
                </div>
              </div>
              <div class="record-meta">
                <span>赞 ${escapeHtml(post.like_count || 0)}</span>
                <span>评 ${escapeHtml(post.comment_count || 0)}</span>
                <span>藏 ${escapeHtml(post.collection_count || 0)}</span>
              </div>
            </div>
            <div class="muted">postId ${escapeHtml(post.post_id || "未知")} · brokerUserId ${escapeHtml(post.broker_user_id || "未知")}</div>
            <details class="post-content-details">
              <summary>展开正文</summary>
              <div class="record-content">${escapeHtml(post.content_text || post.intro || "无正文")}</div>
            </details>
            <details class="comment-details" data-comment-post-id="${escapeHtml(post.post_id || "")}" data-comment-manager-id="${escapeHtml(post.broker_user_id || "")}">
              <summary>${Number(post.comment_count || 0) ? `展开评论（${escapeHtml(post.comment_count || 0)}）` : "暂无评论"}</summary>
              ${Number(post.comment_count || 0) ? renderCommentButtons(post.post_id || "", "hot", false) : ""}
              <div class="comment-list">
                <div class="comment-loading">${Number(post.comment_count || 0) ? "展开后加载热评…" : "这条发言还没有评论。"}</div>
              </div>
              <div class="comment-footer"></div>
            </details>
          </article>
        `).join("");
        attachCommentInteractions();
        return;
      }

      if (snapshot.snapshot_type === "users") {
        els.records.innerHTML = records.map((user) => `
          <article class="record-card">
            <div class="record-top">
              <div>
                <h3 class="record-title">${escapeHtml(user.user_name || "未知用户")}</h3>
                <div class="record-meta">
                  <span>brokerUserId ${escapeHtml(user.broker_user_id || "未知")}</span>
                  <span>spaceUserId ${escapeHtml(user.space_user_id || "未提供")}</span>
                </div>
              </div>
            </div>
            <div class="record-content">${escapeHtml(user.user_desc || "无简介")}</div>
          </article>
        `).join("");
        return;
      }

      if (snapshot.snapshot_type === "groups") {
        els.records.innerHTML = records.map((group) => `
          <article class="record-card">
            <div class="record-top">
              <div>
                <h3 class="record-title">${escapeHtml(group.group_name || ("小组 " + (group.group_id || "")))}</h3>
                <div class="record-meta">
                  <span>groupId ${escapeHtml(group.group_id || "未知")}</span>
                  <span>${escapeHtml(group.manager_name || "未知主理人")}</span>
                  <span>${escapeHtml(group.manager_label || "未标注")}</span>
                </div>
              </div>
            </div>
            <div class="record-content">${escapeHtml(group.group_desc || "无简介")}</div>
          </article>
        `).join("");
        return;
      }

      els.records.innerHTML = records.map((item) => `
        <article class="record-card">
          <div class="record-top">
            <div>
              <h3 class="record-title">${escapeHtml(item.title || item.url || "记录")}</h3>
              <div class="record-meta">
                <span>${escapeHtml(item.author || "未知作者")}</span>
                <span>${escapeHtml(formatTime(item.publish_date || snapshot.created_at))}</span>
              </div>
            </div>
          </div>
          <div class="record-content">${escapeHtml(item.snippet || item.content || "无内容")}</div>
        </article>
      `).join("");
    }

    function renderSnapshot(snapshot, sourceLabel) {
      state.current = snapshot;
      state.currentSource = sourceLabel;
      state.signalFilter = "all";
      state.timelineAssetFilter = "all";
      els.currentTitle.textContent = snapshot.title || "未命名快照";
      els.currentSubtitle.textContent = `${snapshot.subtitle || snapshot.mode || "未知模式"} · ${snapshot.count || 0} 条 · ${formatTime(snapshot.created_at)}`;
      els.sourceBadge.textContent = sourceLabel;
      const filters = snapshot.filters || {};
      const chips = [
        snapshot.kind_label,
        snapshot.mode,
        filters.user_name ? `用户 ${filters.user_name}` : "",
        filters.keyword ? `关键词 ${filters.keyword}` : "",
        filters.query ? `检索 ${filters.query}` : "",
        filters.since ? `起 ${filters.since}` : "",
        filters.until ? `止 ${filters.until}` : "",
      ].filter(Boolean);
      els.currentChips.innerHTML = chips.map((chip) => `<span class="chip">${escapeHtml(chip)}</span>`).join("");
      els.detailMeta.textContent = `${snapshot.file_name || "临时结果"} · ${snapshot.file_path || "内存结果"}`;
      renderMetrics(snapshot);
      renderSignalPanel(snapshot);
      renderRecords(snapshot);
    }

    function renderCommentAvatar(url, userName) {
      if (url) {
        return `<span class="comment-avatar"><img src="${escapeHtml(url)}" alt="${escapeHtml(userName || "avatar")}"></span>`;
      }
      return `<span class="comment-avatar">${escapeHtml((userName || "?").slice(0, 1))}</span>`;
    }

    function renderReplyItem(reply) {
      const replyPrefix = reply.to_user_name ? `回复 ${reply.to_user_name}：` : "";
      return `
        <div class="reply-card">
          <div class="reply-head">
            <span>${escapeHtml(reply.user_name || "未知用户")}</span>
            <span>${escapeHtml(formatTime(reply.created_at))}</span>
          </div>
          <div class="comment-body">${escapeHtml(replyPrefix + (reply.content || ""))}</div>
        </div>
      `;
    }

    function renderCommentItem(comment) {
      return `
        <div class="comment-card">
          <div class="comment-head">
            <div class="comment-author">
              ${renderCommentAvatar(comment.user_avatar_url, comment.user_name)}
              <div>
                <strong>${escapeHtml(comment.user_name || "未知用户")}</strong>
                <small>${escapeHtml(formatTime(comment.created_at))}</small>
              </div>
            </div>
            <div class="comment-meta">
              <span>赞 ${escapeHtml(comment.like_count || 0)}</span>
              ${comment.ip_location ? `<span>${escapeHtml(comment.ip_location)}</span>` : ""}
            </div>
          </div>
          <div class="comment-body">${escapeHtml(comment.content || "无评论内容")}</div>
          ${comment.children && comment.children.length ? `<div class="reply-list">${comment.children.map(renderReplyItem).join("")}</div>` : ""}
        </div>
      `;
    }

    function renderCommentButtons(postId, activeSort, managerOnly) {
      return `
        <div class="comment-toolbar">
          <button type="button" class="comment-sort-btn ${activeSort === "hot" ? "active" : ""}" data-comment-action="sort" data-post-id="${escapeHtml(postId)}" data-sort-type="hot">热评</button>
          <button type="button" class="comment-sort-btn ${activeSort === "latest" ? "active" : ""}" data-comment-action="sort" data-post-id="${escapeHtml(postId)}" data-sort-type="latest">最新评论</button>
          <button type="button" class="comment-sort-btn ${managerOnly ? "active" : ""}" data-comment-action="manager-filter" data-post-id="${escapeHtml(postId)}" data-manager-only="${managerOnly ? "1" : "0"}">只看主理人回复</button>
        </div>
      `;
    }

    function renderCommentMoreButton(postId, sortType, nextPage, managerOnly) {
      return `<button type="button" class="comment-more-btn" data-comment-action="more" data-post-id="${escapeHtml(postId)}" data-sort-type="${escapeHtml(sortType)}" data-next-page="${escapeHtml(nextPage)}" data-manager-only="${managerOnly ? "1" : "0"}">加载更多评论</button>`;
    }

    function setCommentButtonsState(container, activeSort, managerOnly) {
      container.querySelectorAll("[data-comment-action='sort']").forEach((button) => {
        button.classList.toggle("active", button.dataset.sortType === activeSort);
      });
      container.querySelectorAll("[data-comment-action='manager-filter']").forEach((button) => {
        button.classList.toggle("active", Boolean(managerOnly));
        button.dataset.managerOnly = managerOnly ? "1" : "0";
      });
    }

    async function loadComments(postId, targetNode, sortType = "hot", toolbarNode = null, footerNode = null, pageNum = 1, append = false, managerBrokerUserId = "", managerOnly = false, detailsNode = null) {
      const cacheKey = `${postId}:${sortType}:${pageNum}:${managerOnly ? managerBrokerUserId : "all"}`;
      if (toolbarNode) {
        setCommentButtonsState(toolbarNode, sortType, managerOnly);
      }
      if (detailsNode) {
        detailsNode.dataset.commentSortType = sortType;
        detailsNode.dataset.commentManagerOnly = managerOnly ? "1" : "0";
      }
      if (state.commentCache.has(cacheKey)) {
        const cached = state.commentCache.get(cacheKey) || { comments: [], hasMore: false };
        if (!cached.comments.length && pageNum === 1) {
          const emptyMessage = managerOnly
            ? '当前页还没有主理人回复，继续加载更多评论试试看。'
            : '这条发言暂时没有抓到评论。';
          targetNode.innerHTML = `<div class="comment-loading">${emptyMessage}</div>`;
          if (footerNode) {
            footerNode.innerHTML = cached.hasMore ? renderCommentMoreButton(postId, sortType, pageNum + 1, managerOnly) : "";
          }
          return;
        }
        const html = cached.comments.map(renderCommentItem).join("");
        targetNode.innerHTML = append ? `${targetNode.innerHTML}${html}` : html;
        if (footerNode) {
          footerNode.innerHTML = cached.hasMore ? renderCommentMoreButton(postId, sortType, pageNum + 1, managerOnly) : "";
        }
        return;
      }
      if (!append) {
        targetNode.innerHTML = '<div class="comment-loading">评论加载中…</div>';
      } else if (footerNode) {
        footerNode.innerHTML = '<div class="comment-loading">更多评论加载中…</div>';
      }
      try {
        const managerQuery = managerOnly && managerBrokerUserId
          ? `&manager_broker_user_id=${encodeURIComponent(managerBrokerUserId)}`
          : "";
        const data = await api(`/api/comments?post_id=${encodeURIComponent(postId)}&page_size=10&sort_type=${encodeURIComponent(sortType)}&page_num=${encodeURIComponent(pageNum)}${managerQuery}`);
        const comments = data.comments || [];
        const cacheValue = { comments, hasMore: Boolean(data.has_more) };
        state.commentCache.set(cacheKey, cacheValue);
        if (!comments.length && pageNum === 1) {
          const emptyMessage = managerOnly
            ? '当前页还没有主理人回复，继续加载更多评论试试看。'
            : '这条发言暂时没有抓到评论。';
          targetNode.innerHTML = `<div class="comment-loading">${emptyMessage}</div>`;
          if (footerNode) {
            footerNode.innerHTML = data.has_more ? renderCommentMoreButton(postId, sortType, pageNum + 1, managerOnly) : "";
          }
          return;
        }
        const html = comments.map(renderCommentItem).join("");
        targetNode.innerHTML = append ? `${targetNode.innerHTML}${html}` : html;
        if (footerNode) {
          footerNode.innerHTML = data.has_more ? renderCommentMoreButton(postId, sortType, pageNum + 1, managerOnly) : "";
        }
      } catch (error) {
        if (append && footerNode) {
          footerNode.innerHTML = `<div class="comment-loading">加载失败：${escapeHtml(error.message || String(error))}</div>`;
        } else {
          targetNode.innerHTML = `<div class="comment-loading">评论加载失败：${escapeHtml(error.message || String(error))}</div>`;
        }
      }
    }

    function attachCommentInteractions() {
      els.records.querySelectorAll("details[data-comment-post-id]").forEach((node) => {
        node.addEventListener("toggle", () => {
          if (!node.open || node.dataset.loaded === "true") {
            return;
          }
          node.dataset.loaded = "true";
          const postId = node.dataset.commentPostId;
          const managerBrokerUserId = node.dataset.commentManagerId || "";
          const listNode = node.querySelector(".comment-list");
          const toolbarNode = node.querySelector(".comment-toolbar");
          const footerNode = node.querySelector(".comment-footer");
          if (postId && listNode) {
            loadComments(postId, listNode, "hot", toolbarNode, footerNode, 1, false, managerBrokerUserId, false, node);
          }
        });
      });

      els.records.querySelectorAll("[data-comment-action='sort']").forEach((button) => {
        button.addEventListener("click", (event) => {
          event.preventDefault();
          event.stopPropagation();
          const sortType = button.dataset.sortType || "hot";
          const postId = button.dataset.postId || "";
          const detailsNode = button.closest("details[data-comment-post-id]");
          const managerBrokerUserId = detailsNode ? (detailsNode.dataset.commentManagerId || "") : "";
          const managerOnly = detailsNode ? detailsNode.dataset.commentManagerOnly === "1" : false;
          const listNode = detailsNode ? detailsNode.querySelector(".comment-list") : null;
          const toolbarNode = detailsNode ? detailsNode.querySelector(".comment-toolbar") : null;
          const footerNode = detailsNode ? detailsNode.querySelector(".comment-footer") : null;
          if (postId && listNode) {
            loadComments(postId, listNode, sortType, toolbarNode, footerNode, 1, false, managerBrokerUserId, managerOnly, detailsNode);
          }
        });
      });

      els.records.querySelectorAll("[data-comment-action='manager-filter']").forEach((button) => {
        button.addEventListener("click", (event) => {
          event.preventDefault();
          event.stopPropagation();
          const postId = button.dataset.postId || "";
          const detailsNode = button.closest("details[data-comment-post-id]");
          const managerBrokerUserId = detailsNode ? (detailsNode.dataset.commentManagerId || "") : "";
          const managerOnly = !(detailsNode && detailsNode.dataset.commentManagerOnly === "1");
          const sortType = detailsNode ? (detailsNode.dataset.commentSortType || "hot") : "hot";
          const listNode = detailsNode ? detailsNode.querySelector(".comment-list") : null;
          const toolbarNode = detailsNode ? detailsNode.querySelector(".comment-toolbar") : null;
          const footerNode = detailsNode ? detailsNode.querySelector(".comment-footer") : null;
          if (postId && listNode) {
            loadComments(postId, listNode, sortType, toolbarNode, footerNode, 1, false, managerBrokerUserId, managerOnly, detailsNode);
          }
        });
      });

      els.records.querySelectorAll("[data-comment-action='more']").forEach((button) => {
        button.addEventListener("click", (event) => {
          event.preventDefault();
          event.stopPropagation();
          const sortType = button.dataset.sortType || "hot";
          const postId = button.dataset.postId || "";
          const nextPage = Number(button.dataset.nextPage || "2");
          const detailsNode = button.closest("details[data-comment-post-id]");
          const managerBrokerUserId = detailsNode ? (detailsNode.dataset.commentManagerId || "") : "";
          const managerOnly = button.dataset.managerOnly === "1";
          const listNode = detailsNode ? detailsNode.querySelector(".comment-list") : null;
          const toolbarNode = detailsNode ? detailsNode.querySelector(".comment-toolbar") : null;
          const footerNode = detailsNode ? detailsNode.querySelector(".comment-footer") : null;
          if (postId && listNode) {
            loadComments(postId, listNode, sortType, toolbarNode, footerNode, nextPage, true, managerBrokerUserId, managerOnly, detailsNode);
          }
        });
      });
    }

    async function loadStatus() {
      const data = await api("/api/status");
      els.cookieStatus.textContent = data.cookie_exists ? "已发现本地 Cookie" : "未发现本地 Cookie";
      els.cookieDot.className = `dot ${data.cookie_exists ? "ok" : "fail"}`;
      els.snapshotStatus.textContent = `历史 ${data.snapshot_count} 份`;

      const defaults = data.default_form || {};
      els.mode.value = defaults.mode || "group-manager";
      els.prod_code.value = defaults.prod_code || "";
      els.manager_name.value = defaults.manager_name || "";
      els.user_name.value = defaults.user_name || "";
      els.pages.value = defaults.pages || "5";
      els.page_size.value = defaults.page_size || "10";
      applyModeVisibility();
    }

    async function loadHistory() {
      const data = await api("/api/history");
      state.history = data.items || [];
      els.snapshotStatus.textContent = `历史 ${state.history.length} 份`;
      renderHistory();
      if (!state.current && state.history.length) {
        await loadSnapshot(state.history[0].file_name);
      }
    }

    async function loadSnapshot(name) {
      const data = await api(`/api/snapshot?name=${encodeURIComponent(name)}`);
      state.activeHistoryName = name;
      renderHistory();
      renderSnapshot(data.snapshot, "历史快照");
    }

    async function fetchLive(persist) {
      setBusy(true);
      try {
        const payload = collectPayload();
        payload.persist = persist;
        const data = await api("/api/fetch", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        state.activeHistoryName = persist ? data.snapshot.file_name : "";
        renderHistory();
        renderSnapshot(data.snapshot, persist ? "最新并已保存" : "临时实时结果");
        if (persist) {
          await loadHistory();
        }
      } catch (error) {
        alert(error.message || String(error));
      } finally {
        setBusy(false);
      }
    }

    async function checkAuth() {
      setBusy(true);
      try {
        const data = await api("/api/check-auth");
        if (data.ok) {
          alert(`登录态有效\\nuserName: ${data.user_name || "未知"}\\nbrokerUserId: ${data.broker_user_id || "未知"}\\nuserLabel: ${data.user_label || "未知"}`);
        } else {
          alert(data.message || "登录态无效");
        }
      } catch (error) {
        alert(error.message || String(error));
      } finally {
        setBusy(false);
      }
    }

    function resetAutoRefresh() {
      if (state.autoTimer) {
        clearInterval(state.autoTimer);
        state.autoTimer = null;
      }
      const value = Number(els.auto_refresh.value || 0);
      if (!value) return;
      state.autoTimer = setInterval(() => {
        fetchLive(false);
      }, value * 1000);
    }

    els.mode.addEventListener("change", applyModeVisibility);
    els.fetchBtn.addEventListener("click", () => fetchLive(false));
    els.saveBtn.addEventListener("click", () => fetchLive(true));
    els.authBtn.addEventListener("click", checkAuth);
    els.reloadHistoryBtn.addEventListener("click", loadHistory);
    els.historySearch.addEventListener("input", renderHistory);
    els.auto_refresh.addEventListener("change", resetAutoRefresh);

    window.addEventListener("error", (event) => {
      setInitError(event && event.message ? event.message : "脚本运行失败");
    });

    window.__dashboardMainReady = true;
    Promise.resolve()
      .then(loadStatus)
      .then(loadHistory)
      .catch((error) => {
        setInitError(error && error.message ? error.message : String(error));
        alert(error.message || String(error));
      });
  </script>
  <script>
    (function () {
      if (window.__dashboardMainReady) {
        return;
      }

      function byId(id) {
        return document.getElementById(id);
      }

      function escapeHtml(value) {
        return String(value || "")
          .replace(/&/g, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;")
          .replace(/"/g, "&quot;");
      }

      function normalizeText(value) {
        return String(value || "").replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "");
      }

      function formatTime(value) {
        if (!value) {
          return "未记录";
        }
        return String(value).replace("T", " ").slice(0, 19);
      }

      function xhrJson(method, path, body, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open(method, path, true);
        xhr.setRequestHeader("Accept", "application/json");
        if (body) {
          xhr.setRequestHeader("Content-Type", "application/json");
        }
        xhr.onreadystatechange = function () {
          var data;
          if (xhr.readyState !== 4) {
            return;
          }
          try {
            data = xhr.responseText ? JSON.parse(xhr.responseText) : {};
          } catch (error) {
            callback(new Error("返回结果不是合法 JSON"));
            return;
          }
          if (xhr.status >= 200 && xhr.status < 300) {
            callback(null, data);
            return;
          }
          callback(new Error((data && data.error) || "请求失败"));
        };
        xhr.onerror = function () {
          callback(new Error("网络请求失败"));
        };
        xhr.send(body ? JSON.stringify(body) : null);
      }

      var state = {
        history: [],
        activeHistoryName: "",
        currentSnapshot: null
      };

      var els = {
        mode: byId("mode"),
        prod_code: byId("prod_code"),
        manager_name: byId("manager_name"),
        group_url: byId("group_url"),
        group_id: byId("group_id"),
        user_name: byId("user_name"),
        broker_user_id: byId("broker_user_id"),
        space_user_id: byId("space_user_id"),
        keyword: byId("keyword"),
        since: byId("since"),
        until: byId("until"),
        pages: byId("pages"),
        page_size: byId("page_size"),
        auto_refresh: byId("auto_refresh"),
        fetchBtn: byId("fetchBtn"),
        saveBtn: byId("saveBtn"),
        authBtn: byId("authBtn"),
        reloadHistoryBtn: byId("reloadHistoryBtn"),
        historySearch: byId("historySearch"),
        historyList: byId("historyList"),
        currentTitle: byId("currentTitle"),
        currentSubtitle: byId("currentSubtitle"),
        currentChips: byId("currentChips"),
        metrics: byId("metrics"),
        barsWrap: byId("barsWrap"),
        bars: byId("bars"),
        detailMeta: byId("detailMeta"),
        records: byId("records"),
        sourceBadge: byId("sourceBadge"),
        cookieDot: byId("cookieDot"),
        cookieStatus: byId("cookieStatus"),
        snapshotStatus: byId("snapshotStatus"),
        groupFields: byId("groupFields"),
        userFields: byId("userFields"),
        formHint: byId("formHint"),
        signalPanel: byId("signalPanel")
      };

      function setBusy(isBusy) {
        var buttons = [els.fetchBtn, els.saveBtn, els.authBtn, els.reloadHistoryBtn];
        var i;
        for (i = 0; i < buttons.length; i += 1) {
          if (buttons[i]) {
            buttons[i].disabled = !!isBusy;
          }
        }
      }

      function setCookieStatus(ok, text) {
        if (els.cookieDot) {
          els.cookieDot.className = "dot " + (ok ? "ok" : "fail");
        }
        if (els.cookieStatus) {
          els.cookieStatus.textContent = text;
        }
      }

      function setSnapshotStatus(text) {
        if (els.snapshotStatus) {
          els.snapshotStatus.textContent = text;
        }
      }

      function setHintForMode(mode) {
        var hints = {
          "following-posts": "兼容模式已启用。推荐先用“关注动态 + 用户昵称”来看主理人最近发言。",
          "group-manager": "兼容模式已启用。公开模式适合按产品代码或小组查主理人发言。",
          "following-users": "兼容模式已启用。这个模式会读取你当前账号关注的主理人。",
          "my-groups": "兼容模式已启用。这个模式会读取你已加入的小组列表。",
          "space-items": "兼容模式已启用。这个模式会读取某个个人空间动态。"
        };
        if (els.formHint) {
          els.formHint.textContent = hints[mode] || "兼容模式已启用。";
        }
      }

      function applyModeVisibility() {
        var mode = els.mode ? els.mode.value : "following-posts";
        var showGroup = mode === "group-manager";
        var showUser = mode === "following-posts" || mode === "space-items";
        if (els.groupFields) {
          els.groupFields.style.display = showGroup ? "" : "none";
        }
        if (els.userFields) {
          els.userFields.style.display = showUser ? "" : "none";
        }
        setHintForMode(mode);
      }

      function renderMetrics(snapshot) {
        var stats = (snapshot && snapshot.stats) || {};
        var cards = [
          ["总量", snapshot && snapshot.count ? snapshot.count : 0],
          ["最新时间", formatTime(stats.latest_created_at || (snapshot && snapshot.created_at))],
          ["用户数", stats.unique_users || 0],
          ["分组数", stats.unique_groups || 0]
        ];
        var html = "";
        var i;
        for (i = 0; i < cards.length; i += 1) {
          html += '<div class="metric"><small>' + escapeHtml(cards[i][0]) + '</small><strong>' + escapeHtml(String(cards[i][1])) + '</strong></div>';
        }
        if (els.metrics) {
          els.metrics.innerHTML = html;
        }
        if (els.barsWrap) {
          els.barsWrap.className = "hidden";
        }
        if (els.bars) {
          els.bars.innerHTML = "";
        }
      }

      function renderRecords(snapshot) {
        var records = (snapshot && snapshot.records) || [];
        var html = "";
        var i;
        if (!records.length) {
          if (els.records) {
            els.records.innerHTML = '<div class="empty">这份快照里没有可展示的记录。</div>';
          }
          return;
        }
        if (snapshot.snapshot_type === "posts") {
          for (i = 0; i < records.length; i += 1) {
            html += '<article class="record-card">';
            html += '<div class="record-top"><div>';
            html += '<h3 class="record-title">' + escapeHtml(records[i].title || records[i].intro || ("帖子 " + (records[i].post_id || ""))) + '</h3>';
            html += '<div class="record-meta">';
            html += '<span>' + escapeHtml(records[i].user_name || records[i].broker_user_id || "未知用户") + '</span>';
            html += '<span>' + escapeHtml(records[i].group_name || "未标注小组") + '</span>';
            html += '<span>' + escapeHtml(formatTime(records[i].created_at)) + '</span>';
            html += '</div></div><div class="record-meta">';
            html += '<span>赞 ' + escapeHtml(records[i].like_count || 0) + '</span>';
            html += '<span>评 ' + escapeHtml(records[i].comment_count || 0) + '</span>';
            html += '<span>藏 ' + escapeHtml(records[i].collection_count || 0) + '</span>';
            html += '</div></div>';
            html += '<div class="muted">postId ' + escapeHtml(records[i].post_id || "未知") + ' · brokerUserId ' + escapeHtml(records[i].broker_user_id || "未知") + '</div>';
            html += '<div class="record-content">' + escapeHtml(records[i].content_text || records[i].intro || "无正文") + '</div>';
            html += '</article>';
          }
        } else if (snapshot.snapshot_type === "users") {
          for (i = 0; i < records.length; i += 1) {
            html += '<article class="record-card"><h3 class="record-title">' + escapeHtml(records[i].user_name || "未知用户") + '</h3>';
            html += '<div class="record-content">' + escapeHtml(records[i].user_desc || "无简介") + '</div></article>';
          }
        } else {
          for (i = 0; i < records.length; i += 1) {
            html += '<article class="record-card"><h3 class="record-title">' + escapeHtml(records[i].title || "记录") + '</h3>';
            html += '<div class="record-content">' + escapeHtml(records[i].content || records[i].snippet || "无内容") + '</div></article>';
          }
        }
        if (els.records) {
          els.records.innerHTML = html;
        }
      }

      function renderSnapshot(snapshot, sourceLabel) {
        var filters = (snapshot && snapshot.filters) || {};
        var chips = [];
        if (!snapshot) {
          return;
        }
        state.currentSnapshot = snapshot;
        if (els.currentTitle) {
          els.currentTitle.textContent = snapshot.title || "未命名快照";
        }
        if (els.currentSubtitle) {
          els.currentSubtitle.textContent = (snapshot.subtitle || snapshot.mode || "未知模式") + " · " + (snapshot.count || 0) + " 条 · " + formatTime(snapshot.created_at);
        }
        if (els.sourceBadge) {
          els.sourceBadge.textContent = sourceLabel || "兼容模式";
        }
        chips.push(snapshot.kind_label || "");
        chips.push(snapshot.mode || "");
        if (filters.user_name) {
          chips.push("用户 " + filters.user_name);
        }
        if (filters.keyword) {
          chips.push("关键词 " + filters.keyword);
        }
        if (els.currentChips) {
          els.currentChips.innerHTML = "";
          for (var i = 0; i < chips.length; i += 1) {
            if (chips[i]) {
              els.currentChips.innerHTML += '<span class="chip">' + escapeHtml(chips[i]) + '</span>';
            }
          }
        }
        if (els.detailMeta) {
          els.detailMeta.textContent = (snapshot.file_name || "临时结果") + " · " + (snapshot.file_path || "内存结果");
        }
        if (els.signalPanel) {
          els.signalPanel.className = "panel hidden";
        }
        renderMetrics(snapshot);
        renderRecords(snapshot);
      }

      function renderHistory() {
        var query = normalizeText(els.historySearch ? els.historySearch.value : "").toLowerCase();
        var items = [];
        var html = "";
        var i;
        for (i = 0; i < state.history.length; i += 1) {
          var item = state.history[i];
          var haystack = [item.file_name, item.title, item.subtitle, item.mode].join(" ").toLowerCase();
          if (!query || haystack.indexOf(query) >= 0) {
            items.push(item);
          }
        }
        if (!items.length) {
          if (els.historyList) {
            els.historyList.innerHTML = '<div class="empty">没有匹配到历史快照。</div>';
          }
          return;
        }
        for (i = 0; i < items.length; i += 1) {
          html += '<div class="history-item' + (state.activeHistoryName === items[i].file_name ? ' active' : '') + '" data-name="' + escapeHtml(items[i].file_name) + '">';
          html += '<h4>' + escapeHtml(items[i].title || items[i].file_name) + '</h4>';
          html += '<p>' + escapeHtml((items[i].subtitle || items[i].mode) + ' · ' + items[i].count + ' 条 · ' + formatTime(items[i].created_at)) + '</p>';
          html += '<div class="chips"><span class="chip">' + escapeHtml(items[i].kind_label || "") + '</span><span class="chip">' + escapeHtml(items[i].mode || "") + '</span></div>';
          html += '</div>';
        }
        if (els.historyList) {
          els.historyList.innerHTML = html;
          var nodes = els.historyList.querySelectorAll(".history-item");
          for (i = 0; i < nodes.length; i += 1) {
            nodes[i].onclick = function () {
              loadSnapshot(this.getAttribute("data-name"));
            };
          }
        }
      }

      function loadSnapshot(name) {
        xhrJson("GET", "/api/snapshot?name=" + encodeURIComponent(name), null, function (error, data) {
          if (error) {
            alert(error.message || String(error));
            return;
          }
          state.activeHistoryName = name;
          renderHistory();
          renderSnapshot(data.snapshot, "历史快照 · 兼容模式");
        });
      }

      function loadHistory() {
        xhrJson("GET", "/api/history", null, function (error, data) {
          if (error) {
            setSnapshotStatus("历史读取失败");
            alert(error.message || String(error));
            return;
          }
          state.history = data.items || [];
          setSnapshotStatus("历史 " + state.history.length + " 份");
          renderHistory();
          if (!state.currentSnapshot && state.history.length) {
            loadSnapshot(state.history[0].file_name);
          }
        });
      }

      function loadStatus() {
        xhrJson("GET", "/api/status", null, function (error, data) {
          var defaults;
          if (error) {
            setCookieStatus(false, "状态读取失败");
            setSnapshotStatus(normalizeText(error.message || String(error)));
            return;
          }
          setCookieStatus(!!data.cookie_exists, data.cookie_exists ? "已发现本地 Cookie · 兼容模式" : "未发现本地 Cookie · 兼容模式");
          setSnapshotStatus("历史 " + (data.snapshot_count || 0) + " 份");
          defaults = data.default_form || {};
          if (els.mode) { els.mode.value = defaults.mode || "following-posts"; }
          if (els.prod_code) { els.prod_code.value = defaults.prod_code || ""; }
          if (els.manager_name) { els.manager_name.value = defaults.manager_name || ""; }
          if (els.user_name) { els.user_name.value = defaults.user_name || ""; }
          if (els.pages) { els.pages.value = defaults.pages || "5"; }
          if (els.page_size) { els.page_size.value = defaults.page_size || "10"; }
          applyModeVisibility();
        });
      }

      function collectPayload() {
        return {
          mode: els.mode ? normalizeText(els.mode.value) : "",
          prod_code: els.prod_code ? normalizeText(els.prod_code.value) : "",
          manager_name: els.manager_name ? normalizeText(els.manager_name.value) : "",
          group_url: els.group_url ? normalizeText(els.group_url.value) : "",
          group_id: els.group_id ? normalizeText(els.group_id.value) : "",
          user_name: els.user_name ? normalizeText(els.user_name.value) : "",
          broker_user_id: els.broker_user_id ? normalizeText(els.broker_user_id.value) : "",
          space_user_id: els.space_user_id ? normalizeText(els.space_user_id.value) : "",
          keyword: els.keyword ? normalizeText(els.keyword.value) : "",
          since: els.since ? normalizeText(els.since.value) : "",
          until: els.until ? normalizeText(els.until.value) : "",
          pages: els.pages ? normalizeText(els.pages.value) : "",
          page_size: els.page_size ? normalizeText(els.page_size.value) : ""
        };
      }

      function fetchLive(persist) {
        var payload = collectPayload();
        payload.persist = !!persist;
        setBusy(true);
        xhrJson("POST", "/api/fetch", payload, function (error, data) {
          setBusy(false);
          if (error) {
            alert(error.message || String(error));
            return;
          }
          state.activeHistoryName = persist ? ((data.snapshot && data.snapshot.file_name) || "") : "";
          renderHistory();
          renderSnapshot(data.snapshot, persist ? "最新并已保存 · 兼容模式" : "临时实时结果 · 兼容模式");
          if (persist) {
            loadHistory();
          }
        });
      }

      function checkAuth() {
        setBusy(true);
        xhrJson("GET", "/api/check-auth", null, function (error, data) {
          setBusy(false);
          if (error) {
            alert(error.message || String(error));
            return;
          }
          if (data.ok) {
            alert("登录态有效\nuserName: " + (data.user_name || "未知") + "\nbrokerUserId: " + (data.broker_user_id || "未知") + "\nuserLabel: " + (data.user_label || "未知"));
            return;
          }
          alert(data.message || "登录态无效");
        });
      }

      if (els.mode) {
        els.mode.onchange = applyModeVisibility;
      }
      if (els.fetchBtn) {
        els.fetchBtn.onclick = function () { fetchLive(false); };
      }
      if (els.saveBtn) {
        els.saveBtn.onclick = function () { fetchLive(true); };
      }
      if (els.authBtn) {
        els.authBtn.onclick = checkAuth;
      }
      if (els.reloadHistoryBtn) {
        els.reloadHistoryBtn.onclick = loadHistory;
      }
      if (els.historySearch) {
        els.historySearch.oninput = renderHistory;
      }

      setCookieStatus(false, "兼容模式启动中");
      setSnapshotStatus("历史读取中");
      applyModeVisibility();
      loadStatus();
      loadHistory();
    }());
  </script>
</body>
</html>
"""


class DashboardHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        global LIVE_SNAPSHOT
        parsed = urlparse(self.path)
        if parsed.path in {"/", "/timeline", "/platform", "/forum"}:
            params = parse_qs(parsed.query)
            form_values = collect_form_values(params)
            history = history_summaries()
            selected_name = first_mapping_value(params, "snapshot")
            auto_run = first_mapping_value(params, "auto_run") == "1"
            source_label = "尚未选择数据"
            notice = ""
            error = ""
            current_snapshot: Optional[Dict[str, Any]] = None

            should_fetch_latest_default = parsed.path == "/" and not selected_name and not auto_run

            if auto_run or should_fetch_latest_default:
                try:
                    payload = dict(form_values)
                    payload["persist"] = False
                    current_snapshot = run_fetch(payload, timeout_seconds=AUTO_FETCH_TIMEOUT_SECONDS)
                    LIVE_SNAPSHOT = current_snapshot
                    selected_name = "__live__"
                    source_label = "自动刷新结果" if auto_run else "默认实时结果"
                    notice_prefix = "已自动刷新" if auto_run else "已默认获取最新数据"
                    notice = f"{notice_prefix} {format_time(datetime.now().isoformat(timespec='seconds'))}"
                except Exception as exc:
                    error = str(exc)
                    if history:
                        fallback_name = preferred_snapshot_name(history, prefer_posts=True)
                        if fallback_name:
                            current_snapshot = get_snapshot_by_name(fallback_name)
                            selected_name = fallback_name
                            source_label = "历史快照"
                            notice = "默认抓取超时，已先展示最近快照。可点击“立即刷新”重试。"
                            error = ""
            elif selected_name:
                try:
                    current_snapshot = get_snapshot_by_name(selected_name)
                    source_label = "临时实时结果" if selected_name == "__live__" else "历史快照"
                except FileNotFoundError:
                    error = "未找到所选快照。"

            if not current_snapshot and parsed.path == "/" and selected_name == "__live__":
                try:
                    payload = dict(form_values)
                    payload["persist"] = False
                    current_snapshot = run_fetch(payload, timeout_seconds=AUTO_FETCH_TIMEOUT_SECONDS)
                    LIVE_SNAPSHOT = current_snapshot
                    selected_name = "__live__"
                    source_label = "默认实时结果"
                    notice = f"已默认获取最新数据 {format_time(datetime.now().isoformat(timespec='seconds'))}"
                    error = ""
                except Exception as exc:
                    error = str(exc)
                    if history:
                        fallback_name = preferred_snapshot_name(history, prefer_posts=True)
                        if fallback_name:
                            current_snapshot = get_snapshot_by_name(fallback_name)
                            selected_name = fallback_name
                            source_label = "历史快照"
                            notice = "默认抓取超时，已先展示最近快照。可点击“立即刷新”重试。"
                            error = ""

            if not current_snapshot and history and parsed.path != "/":
                fallback_name = preferred_snapshot_name(
                    history,
                    prefer_posts=parsed.path in {"/", "/forum"},
                )
                if fallback_name:
                    current_snapshot = get_snapshot_by_name(fallback_name)
                    selected_name = fallback_name
                    source_label = "历史快照"

            focus_post_id = safe_int(first_mapping_value(params, "focus_post_id"))
            comment_sort = first_mapping_value(params, "comment_sort") or "hot"
            comment_page = safe_int(first_mapping_value(params, "comment_page")) or 1
            only_manager_replies = first_mapping_value(params, "only_manager_replies") == "1"
            signal_filter = first_mapping_value(params, "signal_filter") or "all"
            timeline_asset = first_mapping_value(params, "timeline_asset") or "all"
            platform_timeout = HOME_PLATFORM_FETCH_TIMEOUT_SECONDS if parsed.path == "/" else PLATFORM_FETCH_TIMEOUT_SECONDS
            platform_trades = fetch_platform_trade_data(
                normalize_text(form_values.get("prod_code")),
                timeout_seconds=platform_timeout,
            )
            if parsed.path == "/timeline":
                self.respond_html(
                    render_timeline_page(
                        form_values=form_values,
                        current_snapshot_name=selected_name,
                        platform_trades=platform_trades,
                        signal_filter=signal_filter,
                        timeline_asset=timeline_asset,
                        source_label=source_label,
                    )
                )
                return
            if parsed.path == "/platform":
                self.respond_html(
                    render_platform_page(
                        form_values=form_values,
                        current_snapshot_name=selected_name,
                        platform_trades=platform_trades,
                        signal_filter=signal_filter,
                        timeline_asset=timeline_asset,
                        source_label=source_label,
                    )
                )
                return
            comments_payload, comment_error = load_comments_for_view(
                snapshot=current_snapshot,
                focus_post_id=focus_post_id,
                comment_sort=comment_sort,
                comment_page=comment_page,
                only_manager_replies=only_manager_replies,
            )
            if parsed.path == "/forum":
                self.respond_html(
                    render_forum_page(
                        form_values=form_values,
                        current_snapshot=current_snapshot,
                        current_snapshot_name=selected_name,
                        source_label=source_label,
                        focus_post_id=focus_post_id,
                        comments_payload=comments_payload,
                        comment_error=comment_error,
                        comment_sort=comment_sort,
                        comment_page=comment_page,
                        only_manager_replies=only_manager_replies,
                    )
                )
                return
            self.respond_html(
                render_dashboard_page(
                    history=history,
                    form_values=form_values,
                    current_snapshot=current_snapshot,
                    platform_trades=platform_trades,
                    current_snapshot_name=selected_name,
                    source_label=source_label,
                    notice=notice,
                    error=error,
                    focus_post_id=focus_post_id,
                    comments_payload=comments_payload,
                    comment_error=comment_error,
                    comment_sort=comment_sort,
                    comment_page=comment_page,
                    only_manager_replies=only_manager_replies,
                    signal_filter=signal_filter,
                    timeline_asset=timeline_asset,
                )
            )
            return
        if parsed.path == "/api/status":
            self.respond_json(api_status())
            return
        if parsed.path == "/api/bootstrap":
            self.respond_json(api_bootstrap())
            return
        if parsed.path == "/api/history":
            self.respond_json({"items": history_summaries()})
            return
        if parsed.path == "/api/platform":
            params = parse_qs(parsed.query)
            prod_code = normalize_text(params.get("prod_code", [""])[0])
            self.respond_json(api_platform(prod_code))
            return
        if parsed.path == "/api/snapshot":
            params = parse_qs(parsed.query)
            name = normalize_text(params.get("name", [""])[0])
            if not name:
                self.respond_error(HTTPStatus.BAD_REQUEST, "缺少快照名称")
                return
            try:
                path = snapshot_path_from_name(name)
                snapshot = normalize_snapshot(path, include_records=True)
            except FileNotFoundError:
                self.respond_error(HTTPStatus.NOT_FOUND, "未找到快照")
                return
            self.respond_json({"snapshot": snapshot})
            return
        if parsed.path == "/api/check-auth":
            self.respond_json(run_auth_check())
            return
        if parsed.path == "/api/comments":
            params = parse_qs(parsed.query)
            post_id = safe_int(normalize_text(params.get("post_id", [""])[0]))
            page_size = safe_int(normalize_text(params.get("page_size", ["10"])[0])) or 10
            sort_type = normalize_text(params.get("sort_type", ["hot"])[0]) or "hot"
            page_num = safe_int(normalize_text(params.get("page_num", ["1"])[0])) or 1
            manager_broker_user_id = normalize_text(params.get("manager_broker_user_id", [""])[0])
            if not post_id:
                self.respond_error(HTTPStatus.BAD_REQUEST, "缺少 post_id")
                return
            try:
                payload = fetch_post_comments(
                    post_id=post_id,
                    page_size=page_size,
                    sort_type=sort_type,
                    page_num=page_num,
                    manager_broker_user_id=manager_broker_user_id,
                )
            except Exception as exc:
                self.respond_error(HTTPStatus.BAD_REQUEST, str(exc))
                return
            self.respond_json(payload)
            return
        self.respond_error(HTTPStatus.NOT_FOUND, "未找到接口")

    def do_POST(self) -> None:
        global LIVE_SNAPSHOT
        parsed = urlparse(self.path)
        if parsed.path == "/":
            length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(length).decode("utf-8")
            form_data = parse_qs(raw_body, keep_blank_values=True)
            form_values = collect_form_values(form_data)
            action = first_mapping_value(form_data, "action")
            history = history_summaries()
            current_snapshot_name = first_mapping_value(form_data, "snapshot")
            current_snapshot: Optional[Dict[str, Any]] = None
            source_label = "尚未选择数据"
            notice = ""
            error = ""
            auth_result: Optional[Dict[str, Any]] = None

            if action == "fetch-preview":
                try:
                    payload = dict(form_values)
                    payload["persist"] = False
                    current_snapshot = run_fetch(payload, timeout_seconds=MANUAL_FETCH_TIMEOUT_SECONDS)
                    LIVE_SNAPSHOT = current_snapshot
                    current_snapshot_name = "__live__"
                    source_label = "临时实时结果"
                    notice = "已经刷新到最新结果。"
                except Exception as exc:
                    error = str(exc)
            elif action == "fetch-save":
                try:
                    payload = dict(form_values)
                    payload["persist"] = True
                    current_snapshot = run_fetch(payload, timeout_seconds=MANUAL_FETCH_TIMEOUT_SECONDS)
                    current_snapshot_name = normalize_text(current_snapshot.get("file_name"))
                    source_label = "最新并已保存"
                    history = history_summaries()
                    notice = f"已保存到 {current_snapshot_name}"
                except Exception as exc:
                    error = str(exc)
            elif action == "auth-check":
                auth_result = run_auth_check()
                notice = ""

            if not current_snapshot and current_snapshot_name:
                try:
                    current_snapshot = get_snapshot_by_name(current_snapshot_name)
                    source_label = "临时实时结果" if current_snapshot_name == "__live__" else "历史快照"
                except FileNotFoundError:
                    current_snapshot_name = ""
                    if not error:
                        error = "未找到所选快照。"
            if not current_snapshot and history:
                fallback_name = preferred_snapshot_name(history, prefer_posts=True)
                if fallback_name:
                    current_snapshot = get_snapshot_by_name(fallback_name)
                    current_snapshot_name = fallback_name
                    if not source_label or source_label == "尚未选择数据":
                        source_label = "历史快照"

            focus_post_id = safe_int(first_mapping_value(form_data, "focus_post_id"))
            comment_sort = first_mapping_value(form_data, "comment_sort") or "hot"
            comment_page = safe_int(first_mapping_value(form_data, "comment_page")) or 1
            only_manager_replies = first_mapping_value(form_data, "only_manager_replies") == "1"
            signal_filter = first_mapping_value(form_data, "signal_filter") or "all"
            timeline_asset = first_mapping_value(form_data, "timeline_asset") or "all"
            platform_trades = fetch_platform_trade_data(
                normalize_text(form_values.get("prod_code")),
                timeout_seconds=PLATFORM_FETCH_TIMEOUT_SECONDS,
            )
            comments_payload, comment_error = load_comments_for_view(
                snapshot=current_snapshot,
                focus_post_id=focus_post_id,
                comment_sort=comment_sort,
                comment_page=comment_page,
                only_manager_replies=only_manager_replies,
            )
            self.respond_html(
                render_dashboard_page(
                    history=history,
                    form_values=form_values,
                    current_snapshot=current_snapshot,
                    platform_trades=platform_trades,
                    current_snapshot_name=current_snapshot_name,
                    source_label=source_label,
                    notice=notice,
                    error=error,
                    auth_result=auth_result,
                    focus_post_id=focus_post_id,
                    comments_payload=comments_payload,
                    comment_error=comment_error,
                    comment_sort=comment_sort,
                    comment_page=comment_page,
                    only_manager_replies=only_manager_replies,
                    signal_filter=signal_filter,
                    timeline_asset=timeline_asset,
                )
            )
            return
        if parsed.path != "/api/fetch":
            self.respond_error(HTTPStatus.NOT_FOUND, "未找到接口")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            payload = json.loads(body.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self.respond_error(HTTPStatus.BAD_REQUEST, "请求体不是合法 JSON")
            return

        try:
            snapshot = run_fetch(
                payload if isinstance(payload, dict) else {},
                timeout_seconds=MANUAL_FETCH_TIMEOUT_SECONDS,
            )
        except Exception as exc:
            self.respond_error(HTTPStatus.BAD_REQUEST, str(exc))
            return

        self.respond_json({"snapshot": snapshot})

    def log_message(self, format: str, *args: Any) -> None:
        return

    def respond_html(self, html: str) -> None:
        body = html.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def respond_json(self, payload: Dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def respond_error(self, status: HTTPStatus, message: str) -> None:
        body = json.dumps({"error": message}, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="本地且慢主理人看板")
    parser.add_argument("--host", default=DEFAULT_HOST, help=f"监听地址，默认 {DEFAULT_HOST}")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"监听端口，默认 {DEFAULT_PORT}")
    parser.add_argument("--open", action="store_true", help="启动后自动打开浏览器")
    return parser


def run_server(host: str, port: int, open_browser: bool) -> int:
    server = ThreadingHTTPServer((host, port), DashboardHandler)
    url = f"http://{host}:{port}"
    print(textwrap.dedent(
        f"""
        Dashboard 已启动
        地址: {url}
        输出目录: {OUTPUT_DIR}
        Cookie 文件: {COOKIE_FILE}
        按 Ctrl+C 停止服务
        """
    ).strip())
    if open_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\\nDashboard 已停止")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    args = build_parser().parse_args()
    raise SystemExit(run_server(args.host, args.port, args.open))
