"""Relojes controlados, conteos y recuperación de mediciones sin cuenta real."""

import math
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from harness.history import HistoryStore
from harness.performance import TurnPerformance, safe_usage


class PerformanceTests(unittest.TestCase):
    def setUp(self):
        self.now = 10.0
        self.metric = TurnPerformance("turn", "model", 10.0, clock=lambda: self.now)

    def test_local_request_and_text_timings_use_monotonic_durations(self):
        self.now = 10.02
        self.metric.mark("prepared")
        self.metric.mark("session_start")
        self.now = 10.12
        self.metric.mark("session_end")
        self.metric.mark("request")
        self.now = 10.32
        self.metric.mark("headers")
        self.now = 10.52
        self.metric.text("a", "Hola")
        self.now = 10.72
        self.metric.text("a", "Hola mundo")
        self.now = 10.92
        self.metric.finish("completed")
        row = self.metric.snapshot()
        self.assertEqual(row["prepare_ms"], 20)
        self.assertEqual(row["session_ms"], 100)
        self.assertEqual(row["headers_ms"], 200)
        self.assertEqual(row["first_text_ms"], 520)
        self.assertEqual(row["request_first_text_ms"], 400)
        self.assertEqual(row["total_ms"], 920)
        self.assertEqual(row["stream_ms"], 400)
        self.assertEqual(row["characters_per_second"], 30)
        self.now = 1000
        self.assertEqual(self.metric.snapshot(), row)

    def test_reconciled_text_and_multiple_parts_do_not_count_deltas_twice(self):
        self.metric.text("a", "Hola 🎵")
        self.now += 0.5
        self.metric.text("b", " mundo")
        row = self.metric.snapshot()
        self.now += 10
        self.metric.text("a", "Hola 🎵")
        self.metric.text("b", " mundo")
        reconciled = self.metric.snapshot()
        self.assertEqual(reconciled["characters"], len("Hola 🎵 mundo"))
        self.assertEqual(reconciled["characters_per_second"], row["characters_per_second"])
        self.assertNotIn("Hola", str(reconciled))

    def test_missing_text_or_single_chunk_does_not_invent_latency_or_speed(self):
        self.now += 1
        self.metric.finish("failed")
        row = self.metric.snapshot()
        self.assertIsNone(row["first_text_ms"])
        self.assertIsNone(row["characters_per_second"])
        self.assertEqual(row["characters"], 0)
        single = TurnPerformance("single", "model", self.now, clock=lambda: self.now)
        single.text("a", "Una respuesta completa")
        single.finish("completed")
        self.assertIsNone(single.snapshot()["characters_per_second"])

    def test_presentation_is_validated_and_recorded_only_once(self):
        self.assertFalse(self.metric.presented(100, 10))
        self.metric.text("a", "Hola")
        for first, frame in ((-1, 1), (10, 11), (True, 1), (math.nan, 1), (1, math.inf), (86400001, 1)):
            self.assertFalse(self.metric.presented(first, frame))
        self.assertTrue(self.metric.presented(600, 16))
        self.assertFalse(self.metric.presented(900, 200))
        self.assertEqual(self.metric.snapshot()["first_visible_ms"], 600)

    def test_short_burst_does_not_report_misleading_generation_speed(self):
        self.metric.text("a", "H")
        self.now += 0.001
        self.metric.text("a", "Hola.")
        self.assertIsNone(self.metric.snapshot()["characters_per_second"])

    def test_usage_keeps_only_actual_nonnegative_integer_counts(self):
        self.assertEqual(safe_usage({"input_tokens": 0, "output_tokens": 20, "total_tokens": 20,
            "output_tokens_details": {"reasoning_tokens": 4}, "message": "private"}),
            {"input_tokens": 0, "output_tokens": 20, "total_tokens": 20, "reasoning_tokens": 4})
        self.assertIsNone(safe_usage({"input_tokens": True, "output_tokens": -2, "total_tokens": 1.5}))


class PerformanceHistoryTests(unittest.TestCase):
    def test_optional_corrupt_measurements_do_not_hide_legacy_messages(self):
        with tempfile.TemporaryDirectory() as temporary:
            store = HistoryStore(Path(temporary))
            record = store.create("original")
            record["messages"] = [{"id": "a", "role": "user", "text": "original", "status": "completed"}]
            record["performance"] = [None, {}, {"status": "unknown"}]
            store.save(record)
            restored = store.load(record["chat_id"])
            self.assertEqual(restored["messages"], record["messages"])
            self.assertEqual(restored["performance"], [])

    def test_history_survives_restart_filters_private_fields_and_limits_recent_turns(self):
        with tempfile.TemporaryDirectory() as temporary:
            store = HistoryStore(Path(temporary))
            for day, status in (("01", "completed"), ("02", "streaming")):
                record = store.create("private prompt")
                row = TurnPerformance(day, "model", 0, clock=lambda: 1).snapshot()
                row.update(started_at="2026-10-" + day + "T00:00:00+00:00", status=status,
                           access_token="private", prompt="private", usage={"output_tokens": 10, "secret": "private"})
                record["performance"] = [row]
                store.save(record)
            restored = HistoryStore(Path(temporary)).performance(limit=1)
            self.assertEqual(len(restored), 1)
            self.assertEqual(restored[0]["turn_id"], "02")
            self.assertEqual(restored[0]["status"], "interrupted")
            self.assertNotIn("private", str(restored))
