import json
import unittest
from pathlib import Path
from unittest.mock import patch

from dashboard.platform_fetcher import build_platform_trade_data
from dashboard.snapshot import normalize_snapshot


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "macos-app" / "Tests" / "QiemanDashboardTests" / "Fixtures"


class ContractFixtureTests(unittest.TestCase):
    def test_macos_bundle_script_embeds_dashboard_package(self) -> None:
        script = (ROOT / "scripts" / "build_macos_app.sh").read_text(encoding="utf-8")

        self.assertIn('cp -R "$ROOT_DIR/dashboard" "$PAYLOAD_DIR/"', script)

    def test_post_snapshot_fixture_matches_python_normalizer(self) -> None:
        payload = normalize_snapshot(FIXTURES / "post-snapshot.json", include_records=True)

        self.assertEqual(payload["snapshot_type"], "posts")
        self.assertEqual(payload["mode"], "group-manager")
        self.assertEqual(payload["title"], "ETF拯救世界")
        self.assertEqual(payload["subtitle"], "长赢指数投资计划")
        self.assertEqual(payload["count"], 2)
        self.assertEqual(payload["records"][0]["post_id"], 9001)
        self.assertEqual(payload["records"][0]["title"], "本周调仓说明")
        self.assertEqual(payload["stats"]["count"], 2)

    def test_platform_adjustment_fixture_matches_python_builder_without_network(self) -> None:
        raw_items = json.loads((FIXTURES / "platform-adjustments.json").read_text(encoding="utf-8"))

        quote_stubs = {"000300": {}, "000922": {}}
        with patch("dashboard.platform_fetcher.preload_fund_market_data", return_value=({}, quote_stubs)):
            payload = build_platform_trade_data("LONG_WIN", raw_items)

        self.assertTrue(payload["supported"])
        self.assertEqual(payload["prod_code"], "LONG_WIN")
        self.assertEqual(payload["count"], 2)
        self.assertEqual(payload["buy_count"], 1)
        self.assertEqual(payload["sell_count"], 1)
        self.assertEqual(payload["adjustment_count"], 1)
        self.assertEqual(payload["actions"][0]["adjustment_id"], 501)
        self.assertEqual(payload["actions"][0]["side"], "buy")
        self.assertEqual(payload["holdings"]["asset_count"], 1)


if __name__ == "__main__":
    unittest.main()
