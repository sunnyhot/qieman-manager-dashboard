import unittest
from unittest.mock import patch

from dashboard import cache
from dashboard.html_pages import render_platform_page


class PlatformPageMarketPreloadTests(unittest.TestCase):
    def setUp(self) -> None:
        cache.FUND_HISTORY_CACHE.clear()
        cache.FUND_QUOTE_CACHE.clear()
        cache.PLATFORM_HOLDINGS_PRICING_CACHE.clear()
        cache.PLATFORM_ACTION_VALUATION_CACHE.clear()
        cache.PLATFORM_ACTION_PRESENTATION_CACHE.clear()

    def tearDown(self) -> None:
        cache.FUND_HISTORY_CACHE.clear()
        cache.FUND_QUOTE_CACHE.clear()
        cache.PLATFORM_HOLDINGS_PRICING_CACHE.clear()
        cache.PLATFORM_ACTION_VALUATION_CACHE.clear()
        cache.PLATFORM_ACTION_PRESENTATION_CACHE.clear()

    def test_platform_page_prewarms_holdings_and_visible_action_funds_once(self) -> None:
        platform_trades = {
            "supported": True,
            "prod_code": "LONG_WIN",
            "holdings": {
                "items": [
                    {
                        "fund_code": "000300",
                        "fund_name": "沪深300",
                        "label": "沪深300",
                        "current_units": 10,
                    }
                ]
            },
            "actions": [
                {
                    "action_key": "buy-1",
                    "adjustment_id": 1,
                    "action_title": "买入1份中证500",
                    "title": "中证500",
                    "fund_code": "000905",
                    "fund_name": "中证500",
                    "side": "buy",
                    "action": "买入",
                    "trade_unit": 1,
                    "txn_ts": 1_720_000_000_000,
                    "txn_date": "2024-07-04",
                    "created_at": "2024-07-04",
                }
            ],
        }

        market_data = (
            {"000300": {}, "000905": {}},
            {"000300": {}, "000905": {}},
        )
        with patch("dashboard.platform_fetcher.preload_selected_fund_market_data", return_value=market_data) as preload:
            render_platform_page(
                form_values={"prod_code": "LONG_WIN", "platform_window": "all"},
                current_snapshot_name="",
                platform_trades=platform_trades,
                signal_filter="all",
                timeline_asset="all",
                source_label="测试",
            )

        self.assertEqual(preload.call_count, 1)
        self.assertEqual(preload.call_args.args[0], ["000905"])
        self.assertEqual(preload.call_args.args[1], ["000300", "000905"])


if __name__ == "__main__":
    unittest.main()
