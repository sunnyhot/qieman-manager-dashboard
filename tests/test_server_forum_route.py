import unittest
from unittest.mock import patch

from dashboard import cache
from dashboard import server


class ServerForumRouteTests(unittest.TestCase):
    def setUp(self) -> None:
        cache.LIVE_SNAPSHOT = {
            "snapshot_type": "posts",
            "title": "ETF拯救世界",
            "subtitle": "长赢指数投资计划",
            "count": 0,
            "records": [],
            "stats": {},
        }

    def tearDown(self) -> None:
        cache.LIVE_SNAPSHOT = None

    def test_forum_page_does_not_fetch_platform_trades(self) -> None:
        handler = object.__new__(server.DashboardHandler)
        handler.path = "/forum?snapshot=__live__"

        with (
            patch("dashboard.server.fetch_platform_trade_data", return_value={"supported": True}) as fetch_platform,
            patch("dashboard.server.load_comments_for_view", return_value=(None, "")),
            patch("dashboard.server.render_forum_page", return_value="<html>forum</html>"),
            patch.object(server.DashboardHandler, "respond_html") as respond_html,
        ):
            server.DashboardHandler.do_GET(handler)

        fetch_platform.assert_not_called()
        respond_html.assert_called_once_with("<html>forum</html>")

    def test_platform_auto_refresh_does_not_fetch_forum_snapshot(self) -> None:
        handler = object.__new__(server.DashboardHandler)
        handler.path = "/platform?auto_run=1"

        with (
            patch("dashboard.server.run_fetch", return_value={"records": []}) as run_fetch,
            patch("dashboard.server.fetch_platform_trade_data", return_value={"supported": True}) as fetch_platform,
            patch("dashboard.server.render_platform_page", return_value="<html>platform</html>"),
            patch.object(server.DashboardHandler, "respond_html") as respond_html,
        ):
            server.DashboardHandler.do_GET(handler)

        run_fetch.assert_not_called()
        fetch_platform.assert_called_once()
        respond_html.assert_called_once_with("<html>platform</html>")

    def test_timeline_auto_refresh_does_not_fetch_forum_snapshot(self) -> None:
        handler = object.__new__(server.DashboardHandler)
        handler.path = "/timeline?auto_run=1"

        with (
            patch("dashboard.server.run_fetch", return_value={"records": []}) as run_fetch,
            patch("dashboard.server.fetch_platform_trade_data", return_value={"supported": True}) as fetch_platform,
            patch("dashboard.server.render_timeline_page", return_value="<html>timeline</html>"),
            patch.object(server.DashboardHandler, "respond_html") as respond_html,
        ):
            server.DashboardHandler.do_GET(handler)

        run_fetch.assert_not_called()
        fetch_platform.assert_called_once()
        respond_html.assert_called_once_with("<html>timeline</html>")


if __name__ == "__main__":
    unittest.main()
