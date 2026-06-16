import unittest
from unittest.mock import patch

from dashboard import cache
from dashboard.platform_fetcher import get_priced_platform_holdings


class PlatformHoldingsPricingCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        cache.PLATFORM_HOLDINGS_PRICING_CACHE.clear()

    def tearDown(self) -> None:
        cache.PLATFORM_HOLDINGS_PRICING_CACHE.clear()

    def test_reuses_priced_holdings_for_same_platform_payload(self) -> None:
        platform_trades = {
            "supported": True,
            "prod_code": "LONG_WIN",
            "actions": [
                {
                    "action_key": "501:000300:buy:1",
                    "fund_code": "000300",
                    "side": "buy",
                    "txn_ts": 1_720_000_000_000,
                }
            ],
            "holdings": {
                "items": [
                    {
                        "fund_code": "000300",
                        "current_units": 100,
                    }
                ]
            },
        }
        priced_holdings = {"items": [{"fund_code": "000300", "current_price": 1.23}]}

        with patch(
            "dashboard.platform_fetcher.enrich_platform_holdings_with_pricing",
            return_value=priced_holdings,
        ) as enrich:
            first = get_priced_platform_holdings(platform_trades)
            second = get_priced_platform_holdings(platform_trades)

        self.assertIs(first, priced_holdings)
        self.assertIs(second, priced_holdings)
        self.assertEqual(enrich.call_count, 1)


if __name__ == "__main__":
    unittest.main()
