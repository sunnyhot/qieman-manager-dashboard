import json
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

    def test_quote_uses_latest_nav_api_and_current_day_change_when_legacy_quote_is_empty(self) -> None:
        today = fund_fetcher._current_market_date_text()

        def remote(url: str, **_: object) -> str:
            if "fundgz.1234567.com.cn" in url:
                raise AssertionError("current-day official NAV must stop the fallback chain")
            if "api.fund.eastmoney.com" in url:
                return json.dumps(
                    {
                        "ErrCode": 0,
                        "Data": {
                            "LSJZList": [
                                {"DWJZ": "1.0250", "FSRQ": today, "JZZZL": "2.50"}
                            ]
                        },
                    }
                )
            raise AssertionError(f"unexpected URL: {url}")

        with patch("dashboard.fund_fetcher.fetch_remote_text", side_effect=remote):
            with patch("dashboard.fund_fetcher.fetch_fund_history_series") as history_fetch:
                quote = fund_fetcher.fetch_fund_quote("000001")

        history_fetch.assert_not_called()
        self.assertEqual(quote["price"], 1.025)
        self.assertEqual(quote["official_nav_date"], today)
        self.assertEqual(quote["estimate_change_pct"], 2.5)
        self.assertTrue(quote["daily_change_available"])

    def test_quote_uses_sina_current_estimate_when_legacy_source_is_empty(self) -> None:
        today = fund_fetcher._current_market_date_text()

        def remote(url: str, **kwargs: object) -> str:
            if "api.fund.eastmoney.com" in url:
                return json.dumps(
                    {
                        "ErrCode": 0,
                        "Data": {"LSJZList": [{"DWJZ": "5.1120", "FSRQ": "2026-07-17", "JZZZL": "-5.99"}]},
                    }
                )
            if "fundgz.1234567.com.cn" in url:
                return "jsonpgz();"
            if "hq.sinajs.cn" in url:
                headers = kwargs.get("headers") or {}
                self.assertEqual(headers.get("Referer"), "https://finance.sina.com.cn/")
                return (
                    'var hq_str_fu_163415="兴全商业模式混合(LOF)A,16:04:00,'
                    f'5.0374,5.1120,5.9720,0,-1.4593,{today},5.0679,-0.8627";'
                )
            raise AssertionError(f"unexpected URL: {url}")

        with patch("dashboard.fund_fetcher.fetch_remote_text", side_effect=remote):
            quote = fund_fetcher.fetch_fund_quote("163415")

        self.assertEqual(quote["price"], 5.0374)
        self.assertEqual(quote["price_source"], "sina_estimate")
        self.assertEqual(quote["price_source_label"], "新浪盘中估值")
        self.assertEqual(quote["estimate_change_pct"], -1.4593)
        self.assertTrue(quote["daily_change_available"])

    def test_quote_uses_market_proxy_for_provider_coverage_gap(self) -> None:
        def remote(url: str, **_: object) -> str:
            if "api.fund.eastmoney.com" in url:
                return json.dumps(
                    {
                        "ErrCode": 0,
                        "Data": {"LSJZList": [{"DWJZ": "1.6280", "FSRQ": "2026-07-16", "JZZZL": "-1.52"}]},
                    }
                )
            if "fundgz.1234567.com.cn" in url:
                return "jsonpgz();"
            if "hq.sinajs.cn" in url:
                return 'var hq_str_fu_019524="";'
            if "qt.gtimg.cn" in url:
                self.assertIn("usNDX", url)
                parts = [""] * 33
                parts[1] = "纳斯达克100"
                parts[2] = ".NDX"
                parts[3] = "28592.66"
                parts[4] = "29025.77"
                parts[30] = "2026-07-17 17:15:59"
                parts[32] = "-1.49"
                return f'v_proxy="{"~".join(parts)}";'
            raise AssertionError(f"unexpected URL: {url}")

        history = {
            "fund_name": "华泰柏瑞纳斯达克100ETF联接(QDII)A",
            "series": [],
            "keys": [],
        }
        with patch("dashboard.fund_fetcher.fetch_remote_text", side_effect=remote):
            with patch("dashboard.fund_fetcher.fetch_fund_history_series", return_value=history):
                quote = fund_fetcher.fetch_fund_quote("019524")

        self.assertAlmostEqual(quote["price"], 1.6037428, places=6)
        self.assertEqual(quote["price_source"], "market_proxy_estimate")
        self.assertEqual(quote["price_source_label"], "纳斯达克100代理估算")
        self.assertEqual(quote["estimate_change_pct"], -1.49)
        self.assertTrue(quote["daily_change_available"])

    def test_overseas_internet_fund_uses_china_internet_etf_proxy(self) -> None:
        symbol, label, _, _, _ = fund_fetcher._fund_estimate_proxy(
            "易方达中证海外互联网50ETF联接(QDII)A"
        )

        self.assertEqual(symbol, "sh513050")
        self.assertEqual(label, "中概互联网ETF")

    def test_quote_returns_stable_empty_payload_when_every_source_is_unavailable(self) -> None:
        def remote(url: str, **_: object) -> str:
            if "api.fund.eastmoney.com" in url:
                return json.dumps({"ErrCode": 0, "Data": {"LSJZList": []}})
            return 'var empty="";'

        with patch("dashboard.fund_fetcher.fetch_remote_text", side_effect=remote):
            with patch(
                "dashboard.fund_fetcher.fetch_fund_history_series",
                return_value={"fund_name": "", "series": [], "keys": []},
            ):
                quote = fund_fetcher.fetch_fund_quote("999999")

        self.assertEqual(quote["fund_code"], "999999")
        self.assertEqual(quote["price"], 0.0)
        self.assertFalse(quote["daily_change_available"])

    def test_quote_uses_current_index_future_when_last_close_matches_official_date(self) -> None:
        today = fund_fetcher._current_market_date_text()

        def remote(url: str, **_: object) -> str:
            if "api.fund.eastmoney.com" in url:
                return json.dumps(
                    {
                        "ErrCode": 0,
                        "Data": {"LSJZList": [{"DWJZ": "1.6280", "FSRQ": "2026-07-17", "JZZZL": "-1.52"}]},
                    }
                )
            if "fundgz.1234567.com.cn" in url:
                return "jsonpgz();"
            if "fu_019524" in url:
                return 'var hq_str_fu_019524="";'
            if "qt.gtimg.cn" in url:
                parts = [""] * 33
                parts[30] = "2026-07-17 17:15:59"
                parts[32] = "-0.86"
                return f'v_proxy="{"~".join(parts)}";'
            if "hf_NQ" in url:
                return (
                    'var hq_str_hf_NQ="29000.000,,28990.000,28995.000,29010.000,28700.000,'
                    f'18:20:00,28750.000,28740.000,0,1,1,{today},纳斯达克指数期货,0";'
                )
            raise AssertionError(f"unexpected URL: {url}")

        history = {
            "fund_name": "华泰柏瑞纳斯达克100ETF联接(QDII)A",
            "series": [],
            "keys": [],
        }
        with patch("dashboard.fund_fetcher.fetch_remote_text", side_effect=remote):
            with patch("dashboard.fund_fetcher.fetch_fund_history_series", return_value=history):
                quote = fund_fetcher.fetch_fund_quote("019524")

        expected_change_pct = (29000.0 / 28750.0 - 1) * 100
        self.assertAlmostEqual(quote["estimate_change_pct"], expected_change_pct, places=7)
        self.assertEqual(quote["price_source_label"], "纳指100期货代理估算")
        self.assertEqual(quote["price_time"], f"{today} 18:20:00")
        self.assertTrue(quote["daily_change_available"])

    def test_quote_uses_current_usdcny_for_dollar_bond_after_last_close(self) -> None:
        today = fund_fetcher._current_market_date_text()

        def remote(url: str, **_: object) -> str:
            if "api.fund.eastmoney.com" in url:
                return json.dumps(
                    {
                        "ErrCode": 0,
                        "Data": {"LSJZList": [{"DWJZ": "1.2042", "FSRQ": "2026-07-17", "JZZZL": "-0.08"}]},
                    }
                )
            if "fundgz.1234567.com.cn" in url:
                return "jsonpgz();"
            if "fu_002286" in url:
                return 'var hq_str_fu_002286="";'
            if "qt.gtimg.cn" in url:
                parts = [""] * 33
                parts[30] = "2026-07-17 16:00:00"
                parts[32] = "-0.20"
                return f'v_proxy="{"~".join(parts)}";'
            if "fx_susdcny" in url:
                return (
                    'var hq_str_fx_susdcny="18:25:26,6.7682,6.7698,6.7752,234,6.7677,6.7768,'
                    f'6.7534,6.7690,美元人民币,-0.0915,-0.0062,0.0234,行情,0,0,,{today}";'
                )
            raise AssertionError(f"unexpected URL: {url}")

        history = {
            "fund_name": "中银美元债债券(QDII)A",
            "series": [],
            "keys": [],
        }
        with patch("dashboard.fund_fetcher.fetch_remote_text", side_effect=remote):
            with patch("dashboard.fund_fetcher.fetch_fund_history_series", return_value=history):
                quote = fund_fetcher.fetch_fund_quote("002286")

        expected_change_pct = (6.7690 / 6.7752 - 1) * 100
        self.assertAlmostEqual(quote["estimate_change_pct"], expected_change_pct, places=7)
        self.assertEqual(quote["price_source_label"], "美元兑人民币代理估算")
        self.assertEqual(quote["price_time"], f"{today} 18:25:26")
        self.assertTrue(quote["daily_change_available"])

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
