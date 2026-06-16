import time
import unittest
from unittest.mock import patch

from dashboard import cache
from dashboard import fund_fetcher


class FundFetcherCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        fund_fetcher.FUND_HISTORY_CACHE.clear()
        fund_fetcher.FUND_QUOTE_CACHE.clear()
        cache.FUND_HISTORY_LOCKS.clear()
        cache.FUND_QUOTE_LOCKS.clear()

    def tearDown(self) -> None:
        fund_fetcher.FUND_HISTORY_CACHE.clear()
        fund_fetcher.FUND_QUOTE_CACHE.clear()
        cache.FUND_HISTORY_LOCKS.clear()
        cache.FUND_QUOTE_LOCKS.clear()

    def test_preload_returns_fresh_cache_without_creating_executor(self) -> None:
        now = time.time()
        history = {
            "fund_code": "000300",
            "series": [{"date": "2026-06-15", "date_key": 20260615, "nav": 1.2, "ts": 1}],
            "keys": [20260615],
            "loaded_at": now,
        }
        quote = {
            "fund_code": "000300",
            "price": 1.23,
            "price_source": "estimate",
            "loaded_at": now,
        }
        fund_fetcher.FUND_HISTORY_CACHE["000300"] = history
        fund_fetcher.FUND_QUOTE_CACHE["000300"] = quote

        with patch(
            "dashboard.fund_fetcher.ThreadPoolExecutor",
            side_effect=AssertionError("fresh cache should not create a thread pool"),
        ):
            histories, quotes = fund_fetcher.preload_fund_market_data(["000300", "000300"])

        self.assertIs(histories["000300"], history)
        self.assertIs(quotes["000300"], quote)

    def test_quote_uses_official_nav_payload_without_history_fetch(self) -> None:
        payload = 'jsonpgz({"fundcode":"000300","name":"沪深300","gsz":"","dwjz":"1.234","jzrq":"2024-07-04","gszzl":""});'

        with patch("dashboard.fund_fetcher.fetch_remote_text", return_value=payload):
            with patch("dashboard.fund_fetcher.fetch_fund_history_series", return_value={"series": [], "keys": []}) as history_fetch:
                quote = fund_fetcher.fetch_fund_quote("000300")

        history_fetch.assert_not_called()
        self.assertEqual(quote["price"], 1.234)
        self.assertEqual(quote["price_source"], "official_nav")
        self.assertEqual(quote["price_source_label"], "最近净值")
        self.assertEqual(quote["official_nav_date"], "2024-07-04")

    def test_quote_cache_is_bounded(self) -> None:
        payload = 'jsonpgz({"fundcode":"000300","name":"沪深300","gsz":"","dwjz":"1.234","jzrq":"2024-07-04","gszzl":""});'

        with patch("dashboard.fund_fetcher.fetch_remote_text", return_value=payload):
            for index in range(cache.MAX_FUND_CACHE_ENTRIES + 5):
                fund_fetcher.fetch_fund_quote(f"{index:06d}")

        self.assertLessEqual(len(fund_fetcher.FUND_QUOTE_CACHE), cache.MAX_FUND_CACHE_ENTRIES)
        self.assertNotIn("000000", fund_fetcher.FUND_QUOTE_CACHE)

    def test_history_cache_is_bounded(self) -> None:
        payload = (
            'var fS_name = "测试基金";\n'
            'var Data_netWorthTrend = [{"x":1719964800000,"y":1.0}];'
        )

        with patch("dashboard.fund_fetcher.fetch_remote_text", return_value=payload):
            for index in range(cache.MAX_FUND_CACHE_ENTRIES + 5):
                fund_fetcher.fetch_fund_history_series(f"{index:06d}")

        self.assertLessEqual(len(fund_fetcher.FUND_HISTORY_CACHE), cache.MAX_FUND_CACHE_ENTRIES)
        self.assertNotIn("000000", fund_fetcher.FUND_HISTORY_CACHE)

    def test_fund_lock_maps_are_bounded(self) -> None:
        for index in range(cache.MAX_FUND_CACHE_ENTRIES + 5):
            cache.fund_history_lock(f"{index:06d}")
            cache.fund_quote_lock(f"{index:06d}")

        self.assertLessEqual(len(cache.FUND_HISTORY_LOCKS), cache.MAX_FUND_CACHE_ENTRIES)
        self.assertLessEqual(len(cache.FUND_QUOTE_LOCKS), cache.MAX_FUND_CACHE_ENTRIES)
        self.assertNotIn("000000", cache.FUND_HISTORY_LOCKS)
        self.assertNotIn("000000", cache.FUND_QUOTE_LOCKS)


if __name__ == "__main__":
    unittest.main()
