from __future__ import annotations

import html
import json
import re
import urllib.request
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from .config import (
    EASTMONEY_HEADERS,
    HTML_TAG_RE,
    MULTI_BLANK_RE,
    TRADE_ACTION_RULES,
    TRADE_ASSET_KEYWORDS,
    TRADE_EXECUTION_MARKERS,
    TRADE_NEGATIVE_MARKERS,
    TRADE_SENTENCE_SPLIT_RE,
)


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


def html_text(value: Any) -> str:
    return html.escape(normalize_text(value))


def first_mapping_value(source: Dict[str, Any], key: str) -> str:
    value = source.get(key, "")
    if isinstance(value, list):
        value = value[0] if value else ""
    return normalize_text(value)


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
    if stripped.startswith((""", """, "预订一个热评", "关于")):
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
