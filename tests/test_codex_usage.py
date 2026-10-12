"""Cuotas RPC, aislamiento de cuentas y limpieza, sin credenciales ni red externa."""

import json
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "backend"))

from fake_service import FakeSession
from test_harness import QueueOutput
from harness.codex_usage import CodexUsageReader, UsageError, normalize_limits
from harness.server import HarnessServer


class UsageReaderTests(unittest.TestCase):
    def reader(self, mode="ok", timeout=2):
        reader = CodexUsageReader(command=[sys.executable, str(PROJECT / "tests/fake_codex.py"), mode], timeout=timeout)
        self.addCleanup(reader.close)
        return reader

    def test_actual_pipes_notifications_multiple_limits_and_reported_windows(self):
        result = self.reader().read("fixture@example.invalid")
        self.assertEqual(result["account"], {"email": "fixture@example.invalid", "plan": "plus"})
        self.assertEqual(result["limits"][0]["primary"]["used_percent"], 25)
        self.assertEqual(result["limits"][0]["secondary"]["window_minutes"], 10080)
        self.assertEqual(result["limits"][0]["credits"]["balance"], "12.5")
        self.assertIsNone(result["limits"][1]["primary"])
        self.assertEqual(result["summary"]["lifetime_tokens"], 78714500)
        self.assertIn("+00:00", result["checked_at"])

    def test_unsupported_optional_summary_keeps_exact_limits(self):
        result = self.reader("optional").read("fixture@example.invalid")
        self.assertIsNone(result["summary"])
        self.assertEqual(result["limits"][0]["primary"]["used_percent"], 25)

    def test_login_and_identity_errors_never_return_another_accounts_quota(self):
        for mode, code in [("logged_out", "login_required"), ("api_key", "login_required"),
                           ("mismatch", "account_mismatch"), ("changed", "account_changed")]:
            with self.subTest(mode=mode), self.assertRaises(UsageError) as caught:
                self.reader(mode).read("fixture@example.invalid")
            self.assertEqual(caught.exception.code, code)

    def test_errors_are_bounded_sanitized_and_process_is_reaped(self):
        real_popen = subprocess.Popen
        for mode in ("timeout", "eof", "invalid_json", "oversized", "rpc_error", "invalid_number"):
            children = []
            def start(*args, **kwargs):
                process = real_popen(*args, **kwargs)
                children.append(process)
                return process
            with self.subTest(mode=mode), patch("harness.codex_usage.subprocess.Popen", side_effect=start):
                with self.assertRaises(UsageError) as caught:
                    self.reader(mode, timeout=.3).read("fixture@example.invalid")
                self.assertNotIn("DO_NOT_EXPOSE", str(caught.exception))
                self.assertIsNotNone(children[0].poll())
                self.assertTrue(children[0].stdout.closed)

    def test_missing_binary_does_not_spawn_or_read_a_session(self):
        with patch.dict("os.environ", {"AGENT_SHELL_CODEX_BINARY": ""}), patch("harness.codex_usage.shutil.which", return_value=None):
            with self.assertRaises(UsageError) as caught:
                CodexUsageReader().read()
            self.assertEqual(caught.exception.code, "codex_missing")

    def test_null_zero_legacy_and_empty_limits_remain_distinct(self):
        result = normalize_limits({"rateLimits": {"primary": {"usedPercent": 0}, "secondary": {}}})[0]
        self.assertEqual(result["primary"]["used_percent"], 0)
        self.assertIsNone(result["primary"]["resets_at"])
        self.assertIsNone(result["secondary"]["used_percent"])
        self.assertEqual(normalize_limits({"rateLimitsByLimitId": {}}), [])
        for invalid in (True, -1, float("nan"), float("inf"), "25"):
            with self.subTest(invalid=invalid), self.assertRaises(UsageError):
                normalize_limits({"rateLimits": {"primary": {"usedPercent": invalid}}})

    def test_close_interrupts_a_pending_child(self):
        reader = self.reader("timeout")
        entered = threading.Event()
        real_popen = subprocess.Popen
        children = []
        def start(*args, **kwargs):
            process = real_popen(*args, **kwargs)
            children.append(process)
            entered.set()
            return process
        errors = []
        def read():
            try:
                reader.read()
            except UsageError as error:
                errors.append(error)
        with patch("harness.codex_usage.subprocess.Popen", side_effect=start):
            worker = threading.Thread(target=read)
            worker.start()
            self.assertTrue(entered.wait(1))
            reader.close()
            worker.join(2)
        self.assertFalse(worker.is_alive())
        self.assertTrue(errors)
        self.assertIsNotNone(children[0].poll())


class UsageServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.session = FakeSession()
        self.output = QueueOutput()
        self.reader = CodexUsageReader(command=[sys.executable, str(PROJECT / "tests/fake_codex.py")])
        self.addCleanup(self.reader.close)
        self.server = HarnessServer(Path(self.temp.name) / "history", self.output, self.session, None,
                                    workspace=Path(self.temp.name), usage_reader=self.reader)

    def test_read_works_during_chat_and_does_not_create_history_or_change_chat(self):
        self.server.busy = True
        self.server.handle({"type": "usage.read", "request_id": "one"})
        result = self.output.wait_for("usage.state")
        self.output.wait_for("usage.finished")
        self.assertEqual(result["request_id"], "one")
        self.assertTrue(self.server.busy)
        self.assertFalse(self.server.usage_pending)
        self.assertEqual(self.server.history.list(), [])
        self.assertIsNone(self.server.conversation)

    def test_changed_active_account_discards_inflight_snapshot_and_finishes(self):
        entered, proceed = threading.Event(), threading.Event()
        def blocked(expected_email):
            entered.set()
            proceed.wait(2)
            return {"account": {"email": expected_email}, "limits": []}
        with patch.object(self.reader, "read", side_effect=blocked):
            self.server.handle({"type": "usage.read", "request_id": "old"})
            self.assertTrue(entered.wait(1))
            self.session.select_account("fixture-second")
            proceed.set()
            self.assertEqual(self.output.wait_for("usage.error")["code"], "account_changed")
            self.output.wait_for("usage.finished")
        self.assertFalse(self.server.usage_pending)
        self.assertNotIn('"usage.state"', self.output.getvalue())

    def test_duplicate_and_disconnected_requests_are_separate_from_chat_errors(self):
        self.server.usage_pending = True
        self.server.handle({"type": "usage.read", "request_id": "duplicate"})
        self.assertEqual(self.output.wait_for("usage.error")["code"], "busy")
        self.server.usage_pending = False
        self.session.connected = False
        self.server.handle({"type": "usage.read", "request_id": "offline"})
        self.assertEqual(self.output.wait_for("usage.error")["code"], "login_required")
        self.assertNotIn("error", [row["type"] for row in map(json.loads, self.output.getvalue().splitlines())])
