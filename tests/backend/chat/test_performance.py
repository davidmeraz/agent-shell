"""Relojes controlados, conteos y recuperación de mediciones sin cuenta real."""

import math
import sys
import tempfile
import unittest
from pathlib import Path

from tests.support.paths import PROJECT

from harness.chat.history import HistoryStore
from harness.chat.performance import TurnPerformance, safe_measurement, safe_usage


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

    def test_context_is_latest_call_and_token_rate_excludes_time_between_requests(self):
        self.metric.begin_model_call()
        self.now = 11
        self.metric.mark("request")
        self.now = 13
        self.metric.complete_model_call({"input_tokens": 100, "output_tokens": 40, "total_tokens": 140,
                                        "output_tokens_details": {"reasoning_tokens": 12}})
        self.assertEqual(self.metric.snapshot()["context_tokens"], 100)
        self.assertIsNone(self.metric.snapshot()["tokens_per_second"])
        # Treinta segundos de terminal y un segundo de sesión/guardados no son tiempo HTTP.
        self.now = 43
        self.metric.tool_calls = 1
        self.metric.tool_ms = 30000
        self.metric.begin_model_call()
        self.assertIsNone(self.metric.snapshot()["context_tokens"])
        self.now = 44
        self.metric.mark("request")
        self.now = 47
        self.metric.complete_model_call({"input_tokens": 180, "output_tokens": 60, "total_tokens": 240})
        self.metric.finish("completed")
        row = self.metric.snapshot()
        self.assertEqual(row["context_tokens"], 180)
        self.assertEqual(row["usage"]["input_tokens"], 280)
        self.assertEqual(row["usage"]["output_tokens"], 100)
        self.assertEqual(row["model_request_ms"], 5000)
        self.assertEqual(row["tokens_per_second"], 20)
        self.assertEqual(row["total_ms"], 37000)
        self.now = 100
        self.assertEqual(self.metric.snapshot(), row)

    def test_missing_latest_usage_does_not_reuse_old_context_or_partial_token_rate(self):
        self.metric.begin_model_call()
        self.metric.mark("request")
        self.now += 1
        self.metric.complete_model_call({"input_tokens": 100, "output_tokens": 20})
        self.metric.begin_model_call()
        self.metric.mark("request")
        self.now += 1
        self.metric.complete_model_call(None)
        self.metric.finish("completed")
        row = self.metric.snapshot()
        self.assertIsNone(row["context_tokens"])
        self.assertIsNone(row["tokens_per_second"])
        self.assertEqual(row["usage"]["output_tokens"], 20)
        self.assertEqual(row["model_request_ms"], 2000)

    def test_missing_output_count_does_not_invent_speed_from_input_tokens(self):
        self.metric.begin_model_call()
        self.metric.mark("request")
        self.now += 1
        self.metric.complete_model_call({"input_tokens": 12400})
        self.metric.finish("completed")
        self.assertEqual(self.metric.snapshot()["context_tokens"], 12400)
        self.assertIsNone(self.metric.snapshot()["tokens_per_second"])

    def test_unknown_or_very_short_request_time_does_not_invent_token_speed(self):
        for seconds, timed in ((1, False), (0, True), (0.001, True)):
            with self.subTest(seconds=seconds, timed=timed):
                metric = TurnPerformance("turn", "model", self.now, clock=lambda: self.now)
                metric.begin_model_call()
                if timed:
                    metric.mark("request")
                self.now += seconds
                metric.complete_model_call({"input_tokens": 10, "output_tokens": 10})
                metric.finish("completed")
                self.assertIsNone(metric.snapshot()["tokens_per_second"])
                if not timed:
                    self.assertIsNone(metric.snapshot()["model_request_ms"])

    def test_cancelled_request_preserves_partial_time_but_has_no_token_rate(self):
        self.metric.begin_model_call()
        self.metric.mark("request")
        self.now += 1
        self.metric.complete_model_call({"input_tokens": 100, "output_tokens": 20})
        self.now += 30
        self.metric.begin_model_call()
        self.metric.mark("request")
        self.now += 4
        self.metric.finish("interrupted")
        row = self.metric.snapshot()
        self.assertEqual(row["model_request_ms"], 5000)
        self.assertIsNone(row["context_tokens"])
        self.assertIsNone(row["tokens_per_second"])
        self.assertEqual(row["usage"]["output_tokens"], 20)

    def test_zero_reported_tokens_are_valid_and_failed_calls_have_no_rate(self):
        for status in ("completed", "failed"):
            with self.subTest(status=status):
                metric = TurnPerformance("turn", "model", self.now, clock=lambda: self.now)
                metric.begin_model_call()
                metric.mark("request")
                self.now += 1
                metric.complete_model_call({"input_tokens": 0, "output_tokens": 0})
                metric.finish(status)
                self.assertEqual(metric.snapshot()["context_tokens"], 0)
                self.assertEqual(metric.snapshot()["tokens_per_second"], 0 if status == "completed" else None)

    def test_duplicate_response_cannot_double_usage_and_context_must_be_an_integer(self):
        self.metric.begin_model_call()
        self.metric.mark("request")
        self.now += 1
        self.metric.complete_model_call({"input_tokens": 12, "output_tokens": 20})
        self.metric.complete_model_call({"input_tokens": 12, "output_tokens": 20})
        self.metric.finish("completed")
        self.assertEqual(self.metric.snapshot()["usage"]["output_tokens"], 20)
        for invalid in (True, 1.5, -1, math.inf):
            row = dict(self.metric.snapshot(), context_tokens=invalid, tokens_per_second=math.nan)
            self.assertIsNone(safe_measurement(row)["context_tokens"])
            self.assertIsNone(safe_measurement(row)["tokens_per_second"])


class PerformanceHistoryTests(unittest.TestCase):
    def test_context_and_token_rate_survive_restart_and_legacy_values_remain_unknown(self):
        with tempfile.TemporaryDirectory() as temporary:
            store = HistoryStore(Path(temporary))
            record = store.create("Example")
            legacy = TurnPerformance("old", "model", 0, clock=lambda: 1).snapshot()
            for key in ("context_tokens", "tokens_per_second", "model_request_ms"):
                legacy.pop(key)
            current = dict(legacy, turn_id="new", context_tokens=12400, tokens_per_second=45.5, model_request_ms=3000)
            record["performance"] = [legacy, current]
            store.save(record)
            restored = HistoryStore(Path(temporary)).load(record["chat_id"])["performance"]
            for key in ("context_tokens", "tokens_per_second", "model_request_ms"):
                self.assertIsNone(restored[0][key])
                self.assertEqual(restored[1][key], current[key])

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
