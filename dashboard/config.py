from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any, Dict, List, Optional


PROJECT_DIR = Path(__file__).resolve().parent.parent
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
