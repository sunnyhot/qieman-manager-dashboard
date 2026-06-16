import io
import os
import unittest
from contextlib import redirect_stderr
from unittest.mock import patch

from dashboard.performance import measure, performance_start, record_performance, timed


class PerformanceLoggingTests(unittest.TestCase):
    def test_logging_is_disabled_without_environment_flag(self) -> None:
        stream = io.StringIO()

        with patch.dict(os.environ, {}, clear=True), redirect_stderr(stream):
            started_at = performance_start()
            record_performance("dashboard.disabled", started_at, route="/platform")

        self.assertEqual(stream.getvalue(), "")

    def test_measure_logs_elapsed_time_and_redacts_sensitive_metadata(self) -> None:
        stream = io.StringIO()

        with patch.dict(os.environ, {"QIEMAN_PERF_LOG": "1"}, clear=True), redirect_stderr(stream):
            with measure(
                "dashboard.request",
                route="/platform",
                row_count=3,
                cookie="access_token=secret",
                authorization="Bearer secret",
            ):
                pass

        output = stream.getvalue()
        self.assertIn("[perf] dashboard.request", output)
        self.assertIn("route=/platform", output)
        self.assertIn("row_count=3", output)
        self.assertIn("cookie=<redacted>", output)
        self.assertIn("authorization=<redacted>", output)
        self.assertNotIn("access_token=secret", output)
        self.assertNotIn("Bearer secret", output)

    def test_timed_decorator_preserves_return_value(self) -> None:
        stream = io.StringIO()

        @timed("decorated.operation")
        def sample(value: str) -> str:
            return f"{value}-done"

        with patch.dict(os.environ, {"QIEMAN_PERF_LOG": "1"}, clear=True), redirect_stderr(stream):
            self.assertEqual(sample("refresh"), "refresh-done")

        self.assertIn("[perf] decorated.operation", stream.getvalue())


if __name__ == "__main__":
    unittest.main()
