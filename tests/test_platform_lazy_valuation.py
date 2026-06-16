import unittest
from unittest.mock import patch

from dashboard.html_render import render_signal_panel
from dashboard.platform_fetcher import build_platform_trade_data


class PlatformLazyValuationTests(unittest.TestCase):
    def test_platform_trade_data_does_not_preload_action_valuations(self) -> None:
        raw_items = [
            {
                "adjustmentId": 501,
                "adjustCreateTime": 1_720_000_000_000,
                "adjustTxnDate": 1_720_000_000_000,
                "comment": "调仓说明",
                "orders": [
                    {
                        "orderCode": "022",
                        "tradeUnit": 100,
                        "postPlanUnit": 100,
                        "fund": {
                            "fundCode": "000300",
                            "fundName": "沪深300",
                        },
                    }
                ],
            }
        ]

        with patch("dashboard.platform_fetcher.preload_fund_market_data") as preload:
            payload = build_platform_trade_data("LONG_WIN", raw_items)

        preload.assert_not_called()
        self.assertEqual(payload["count"], 1)
        self.assertNotIn("current_valuation", payload["actions"][0])

    def test_signal_panel_enriches_only_displayed_action_cards(self) -> None:
        actions = [
            {
                "action_key": f"buy-{index}",
                "adjustment_id": index,
                "action_title": f"买入{index}份沪深300",
                "title": "沪深300",
                "fund_code": f"00030{index}",
                "fund_name": "沪深300",
                "side": "buy",
                "action": "买入",
                "trade_unit": index,
                "txn_ts": 1_720_000_000_000 - index,
                "txn_date": "2024-07-04",
                "created_at": "2024-07-04",
            }
            for index in range(1, 4)
        ]
        platform_trades = {
            "supported": True,
            "prod_code": "LONG_WIN",
            "actions": actions,
        }

        def enrich(displayed_actions):
            return [
                {
                    **action,
                    "trade_valuation": 1.0,
                    "trade_valuation_date": "2024-07-04",
                    "current_valuation": 1.2,
                    "current_valuation_source": "当前估值",
                    "current_valuation_time": "2024-07-05",
                    "valuation_change_pct": 20.0,
                }
                for action in displayed_actions
            ]

        with patch("dashboard.html_render.enrich_platform_actions_with_valuation", side_effect=enrich) as enrich_mock:
            html = render_signal_panel(
                platform_trades,
                {"platform_window": "all"},
                "",
                "all",
                "all",
                card_limit=2,
            )

        displayed_actions = enrich_mock.call_args.args[0]
        self.assertEqual([action["action_key"] for action in displayed_actions], ["buy-1", "buy-2"])
        self.assertIn("变化 +20.00%", html)
        self.assertNotIn("买入3份沪深300", html)


if __name__ == "__main__":
    unittest.main()
