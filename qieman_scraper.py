#!/usr/bin/env python3
"""
Scrape public Qieman content pages by keyword/manager name.

This script intentionally avoids unofficial signed API calls and instead:
1. Uses Bing RSS search to discover public Qieman URLs for a keyword.
2. Downloads matched pages.
3. Extracts title, author, publish date and plain-text content.
4. Writes JSON and/or Markdown results to disk.

Examples:
    python3 qieman_scraper.py --query "长期指数投资"
    python3 qieman_scraper.py --query "ETF拯救世界" --author "ETF拯救世界"
    python3 qieman_scraper.py --query "长赢计划" --limit 20 --markdown
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass
from datetime import datetime
from html import unescape
from pathlib import Path
from typing import Iterable, List, Optional


USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)

DEFAULT_OUTPUT_DIR = Path("/Users/xufan65/Documents/Codex/2026-04-17-new-chat/output")
ALLOWED_HOSTS = {"qieman.com", "www.qieman.com", "content.qieman.com"}
CONTENT_RE = re.compile(r"<div id=\"html-box\".*?>(.*?)</div><div class=\"jsx-", re.S)
TITLE_RE = re.compile(r"<title>(.*?)</title>", re.S | re.I)
H1_RE = re.compile(r"Header__Title[^>]*>(.*?)</div>", re.S)
AUTHOR_RE = re.compile(r"Header__Author[^>]*>(.*?)</span>", re.S)
DATE_RE = re.compile(r"Header__Date[^>]*>(.*?)</span>", re.S)
NEXT_DATA_RE = re.compile(
    r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
    re.S,
)
DATE_FALLBACK_RE = re.compile(r"(20\d{2}年\d{2}月\d{2}日)")
TAG_RE = re.compile(r"<[^>]+>")
SCRIPT_STYLE_RE = re.compile(r"<(script|style).*?>.*?</\\1>", re.S | re.I)
WHITESPACE_RE = re.compile(r"[ \t\r\f\v]+")
MULTI_NEWLINE_RE = re.compile(r"\n{3,}")


@dataclass
class SearchHit:
    title: str
    link: str
    snippet: str


@dataclass
class Article:
    query: str
    title: str
    author: str
    publish_date: str
    url: str
    source: str
    snippet: str
    content: str


def build_opener(cookie_header: Optional[str] = None) -> urllib.request.OpenerDirector:
    headers = [("User-Agent", USER_AGENT), ("Accept-Language", "zh-CN,zh;q=0.9")]
    if cookie_header:
        headers.append(("Cookie", cookie_header))

    opener = urllib.request.build_opener()
    opener.addheaders = headers
    return opener


def http_get(url: str, opener: urllib.request.OpenerDirector, timeout: int = 20) -> str:
    request = urllib.request.Request(url)
    with opener.open(request, timeout=timeout) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, errors="ignore")


def strip_html(html: str) -> str:
    html = SCRIPT_STYLE_RE.sub("", html)
    html = re.sub(r"<br\\s*/?>", "\n", html, flags=re.I)
    html = re.sub(r"</p>", "\n\n", html, flags=re.I)
    html = re.sub(r"</div>", "\n", html, flags=re.I)
    html = TAG_RE.sub("", html)
    html = unescape(html)
    html = html.replace("\xa0", " ")
    html = WHITESPACE_RE.sub(" ", html)
    html = re.sub(r" *\n *", "\n", html)
    return MULTI_NEWLINE_RE.sub("\n\n", html).strip()


def bing_search(query: str, opener: urllib.request.OpenerDirector, limit: int) -> List[SearchHit]:
    search_query = query
    rss_url = (
        "https://cn.bing.com/search?format=rss&q="
        + urllib.parse.quote(search_query, safe="")
    )
    xml_text = http_get(rss_url, opener)

    root = ET.fromstring(xml_text)
    hits: List[SearchHit] = []
    seen = set()
    for item in root.findall(".//item"):
        title = (item.findtext("title") or "").strip()
        link = (item.findtext("link") or "").strip()
        snippet = (item.findtext("description") or "").strip()
        host = urllib.parse.urlparse(link).netloc.lower()
        if not link or link in seen or host not in ALLOWED_HOSTS:
            continue
        seen.add(link)
        hits.append(SearchHit(title=title, link=link, snippet=snippet))
        if len(hits) >= limit:
            break
    return hits


def parse_article(query: str, url: str, html: str, search_snippet: str) -> Article:
    title = first_match(H1_RE, html) or first_match(TITLE_RE, html) or url
    author = first_match(AUTHOR_RE, html)
    publish_date = first_match(DATE_RE, html) or first_match(DATE_FALLBACK_RE, html)

    content_block = first_match(CONTENT_RE, html)
    if content_block:
        content = strip_html(content_block)
        source = "content-page"
    else:
        content = strip_html(html)
        source = "generic-page"

    content = content[:20000].strip()
    snippet = search_snippet or content[:180]

    return Article(
        query=query,
        title=clean_text(title),
        author=clean_text(author),
        publish_date=clean_text(publish_date),
        url=url,
        source=source,
        snippet=clean_text(snippet),
        content=content,
    )


def parse_article_from_next_data(query: str, url: str, html: str) -> Optional[Article]:
    match = NEXT_DATA_RE.search(html)
    if not match:
        return None

    try:
        data = json.loads(match.group(1))
    except json.JSONDecodeError:
        return None

    page_props = data.get("props", {}).get("pageProps", {})
    if page_props.get("err") or not page_props.get("item"):
        return None
    item = page_props.get("item") or {}
    article = item.get("article") or {}
    if not article or article.get("deleted"):
        return None

    title = clean_text(article.get("title", ""))
    author = clean_text(article.get("authorName", ""))
    ts = article.get("createDate")
    publish_date = format_timestamp(ts)
    content_html = article.get("content", "")
    content = strip_html(content_html)[:20000].strip()
    snippet = content[:180]
    return Article(
        query=query,
        title=title,
        author=author,
        publish_date=publish_date,
        url=url,
        source="content-next-data",
        snippet=snippet,
        content=content,
    )


def first_match(pattern: re.Pattern[str], text: str) -> str:
    match = pattern.search(text)
    return clean_text(match.group(1)) if match else ""


def clean_text(text: str) -> str:
    text = unescape(text or "")
    text = TAG_RE.sub("", text)
    text = text.replace("\xa0", " ")
    return WHITESPACE_RE.sub(" ", text).strip()


def format_timestamp(value: object) -> str:
    if not isinstance(value, (int, float)):
        return ""
    try:
        return datetime.fromtimestamp(value / 1000).strftime("%Y-%m-%d")
    except (OverflowError, OSError, ValueError):
        return ""


def slugify(text: str) -> str:
    value = re.sub(r"[^\w\u4e00-\u9fff-]+", "-", text.strip(), flags=re.U)
    value = re.sub(r"-{2,}", "-", value).strip("-")
    return value or "qieman"


def article_matches(article: Article, author: Optional[str]) -> bool:
    if not author:
        return True
    haystack = " ".join([article.author, article.title, article.content[:1000]])
    return author.lower() in haystack.lower()


def keyword_matches(article: Article, query: str) -> bool:
    if not query:
        return True
    haystack = " ".join([article.title, article.author, article.content[:4000]])
    return query.lower() in haystack.lower()


def fetch_public_item(
    item_id: int, query: str, opener: urllib.request.OpenerDirector
) -> Optional[Article]:
    url = f"https://content.qieman.com/items/{item_id}"
    html = http_get(url, opener)
    if "This page could not be found" in html or NEXT_DATA_RE.search(html):
        article = parse_article_from_next_data(query, url, html)
        return article
    if "This page could not be found" in html:
        return None
    return parse_article(query, url, html, "")


def find_latest_item_id(
    opener: urllib.request.OpenerDirector, latest_guess: int, probe_window: int
) -> Optional[int]:
    floor = max(1, latest_guess - probe_window)
    for item_id in range(latest_guess, floor - 1, -1):
        try:
            article = fetch_public_item(item_id, "", opener)
        except Exception:  # noqa: BLE001
            continue
        if article and article.title:
            return item_id
    return None


def crawl_recent_items(
    query: str,
    author: Optional[str],
    opener: urllib.request.OpenerDirector,
    latest_guess: int,
    probe_window: int,
    max_pages: int,
    step: int,
    sleep_seconds: float,
) -> List[Article]:
    latest = find_latest_item_id(opener, latest_guess, probe_window)
    if latest is None:
        return []

    articles: List[Article] = []
    for index in range(max_pages):
        item_id = latest - index * step
        if item_id <= 0:
            break
        try:
            article = fetch_public_item(item_id, query, opener)
            if not article:
                continue
            if keyword_matches(article, query) and article_matches(article, author):
                articles.append(article)
            time.sleep(sleep_seconds)
        except Exception as exc:  # noqa: BLE001
            print(f"[warn] 抓取失败: itemId={item_id} -> {exc}", file=sys.stderr)
    return articles


def save_json(path: Path, articles: Iterable[Article]) -> None:
    payload = [asdict(article) for article in articles]
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def save_markdown(path: Path, articles: Iterable[Article]) -> None:
    lines: List[str] = []
    for index, article in enumerate(articles, start=1):
        lines.append(f"# {index}. {article.title}")
        lines.append("")
        lines.append(f"- 查询词: {article.query}")
        lines.append(f"- 作者: {article.author or '未知'}")
        lines.append(f"- 日期: {article.publish_date or '未知'}")
        lines.append(f"- 链接: {article.url}")
        lines.append("")
        lines.append(article.content or article.snippet or "未提取到正文")
        lines.append("")
    path.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")


def run(args: argparse.Namespace) -> int:
    output_dir: Path = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    opener = build_opener(cookie_header=args.cookie)
    articles = crawl_recent_items(
        query=args.query,
        author=args.author,
        opener=opener,
        latest_guess=args.latest_guess,
        probe_window=args.probe_window,
        max_pages=args.limit,
        step=args.step,
        sleep_seconds=args.sleep,
    )

    if not articles:
        print("最近公开内容里没有匹配到指定主理人/关键词的正文。", file=sys.stderr)
        return 3

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    name = slugify(args.author or args.query)
    json_path = output_dir / f"{name}-{timestamp}.json"
    save_json(json_path, articles)

    md_path = None
    if args.markdown:
        md_path = output_dir / f"{name}-{timestamp}.md"
        save_markdown(md_path, articles)

    print(f"共抓取 {len(articles)} 篇内容")
    print(f"JSON: {json_path}")
    if md_path:
        print(f"Markdown: {md_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="抓取且慢平台公开投资内容")
    parser.add_argument("--query", required=True, help="搜索关键词，例如：长期指数投资、长赢计划")
    parser.add_argument("--author", help="可选，按主理人/作者名进一步过滤")
    parser.add_argument("--limit", type=int, default=120, help="最多扫描多少篇近期内容，默认 120")
    parser.add_argument("--latest-guess", type=int, default=18000, help="最近 itemId 猜测值，默认 18000")
    parser.add_argument("--probe-window", type=int, default=400, help="向下探测最新内容的窗口大小，默认 400")
    parser.add_argument("--step", type=int, default=6, help="内容 itemId 的步长，默认 6")
    parser.add_argument("--sleep", type=float, default=0.8, help="每次请求间隔秒数，默认 0.8")
    parser.add_argument(
        "--cookie",
        help="可选，原始 Cookie 字符串。某些受限页面需要登录态时使用。",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"输出目录，默认 {DEFAULT_OUTPUT_DIR}",
    )
    parser.add_argument(
        "--markdown",
        action="store_true",
        help="除 JSON 外，同时输出 Markdown 汇总文件",
    )
    return parser


if __name__ == "__main__":
    raise SystemExit(run(build_parser().parse_args()))
