import time
import unittest
from unittest.mock import patch

from dashboard import fund_fetcher


class FundFetcherCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        fund_fetcher.FUND_HISTORY_CACHE.clear()
        fund_fetcher.FUND_QUOTE_CACHE.clear()

    def tearDown(self) -> None:
        fund_fetcher.FUND_HISTORY_CACHE.clear()
        fund_fetcher.FUND_QUOTE_CACHE.clear()

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


if __name__ == "__main__":
    unittest.main()
