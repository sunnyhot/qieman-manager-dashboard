import unittest
from unittest.mock import patch

from dashboard import cache
from dashboard.platform_fetcher import (
    enrich_platform_actions_with_valuation,
    enrich_platform_holdings_with_pricing,
)


class PlatformSelectiveMarketPreloadTests(unittest.TestCase):
    def setUp(self) -> None:
        cache.FUND_HISTORY_CACHE.clear()
        cache.FUND_QUOTE_CACHE.clear()

    def tearDown(self) -> None:
        cache.FUND_HISTORY_CACHE.clear()
        cache.FUND_QUOTE_CACHE.clear()

    def test_action_valuation_skips_history_fetch_when_trade_nav_is_present(self) -> None:
        actions = [
            {
                "action_key": "buy-1",
                "fund_code": "000300",
                "side": "buy",
                "nav": "1.0000",
                "nav_date": "2024-07-04",
                "txn_date": "2024-07-04",
                "created_at": "2024-07-04",
            }
        ]
        quote = {
            "fund_code": "000300",
            "price": 1.2,
            "price_time": "2024-07-05",
            "price_source_label": "当前估值",
        }

        with patch("dashboard.fund_fetcher.fetch_fund_history_series", return_value={"series": [], "keys": []}) as history_fetch:
            with patch("dashboard.fund_fetcher.fetch_fund_quote", return_value=quote) as quote_fetch:
                enriched = enrich_platform_actions_with_valuation(actions)

        history_fetch.assert_not_called()
        quote_fetch.assert_called_once_with("000300")
        self.assertEqual(enriched[0]["trade_valuation"], 1.0)
        self.assertEqual(enriched[0]["current_valuation"], 1.2)

    def test_holdings_pricing_skips_history_fetch_when_all_relevant_actions_have_nav(self) -> None:
        holdings = {
            "items": [
                {
                    "fund_code": "000300",
                    "label": "沪深300",
                    "current_units": 10,
                }
            ]
        }
        actions = [
            {
                "fund_code": "000300",
                "side": "buy",
                "trade_unit": 10,
                "nav": "1.0000",
                "txn_date": "2024-07-04",
                "created_at": "2024-07-04",
            }
        ]
        quote = {
            "fund_code": "000300",
            "price": 1.2,
            "price_time": "2024-07-05",
            "price_source": "estimate",
            "price_source_label": "当前估值",
        }

        with patch("dashboard.fund_fetcher.fetch_fund_history_series", return_value={"series": [], "keys": []}) as history_fetch:
            with patch("dashboard.fund_fetcher.fetch_fund_quote", return_value=quote) as quote_fetch:
                enriched = enrich_platform_holdings_with_pricing(holdings, actions)

        history_fetch.assert_not_called()
        quote_fetch.assert_called_once_with("000300")
        item = enriched["items"][0]
        self.assertEqual(item["avg_cost"], 1.0)
        self.assertEqual(item["current_price"], 1.2)
        self.assertTrue(item["cost_ready"])


if __name__ == "__main__":
    unittest.main()
