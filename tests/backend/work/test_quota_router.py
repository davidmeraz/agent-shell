"""QuotaAwareRouter: provider selection, fallback, and exhaustion."""

import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import MagicMock

from harness.core.http import ServiceError, StreamControl
from harness.work.worker import WorkerResult, WorkerRouter
from harness.work.quota_router import QuotaAwareRouter, QuotaExhausted, WORKER_PRIORITY


class FakeStreamControl(StreamControl):
    def __init__(self):
        super().__init__()

    def check(self):
        pass


class StubWorkerRouter(WorkerRouter):
    """Router that returns canned results instead of calling real providers."""

    def __init__(self, results_by_provider=None):
        self.chatgpt = MagicMock()
        self.agy = MagicMock()
        self.agy.is_available = MagicMock(return_value=True)
        self.claude = MagicMock()
        self.session = None
        self.workspace = Path("/tmp")
        self._emit = MagicMock()
        self.shell_timeout = 120
        self._results = results_by_provider or {}
        self._calls = []

    def run(self, task, provider, model, control, max_steps=16):
        self._calls.append((provider, model))
        if provider in self._results:
            result = self._results[provider]
            if callable(result):
                return result(provider, model)
            return result
        return WorkerResult(status="completed", provider=provider, model=model,
                            summary="Done by " + provider)


class SelectionTests(unittest.TestCase):
    def test_preferred_provider_used_when_available(self):
        stub = StubWorkerRouter()
        router = QuotaAwareRouter(stub)
        provider, model = router.select_worker("agy", "gemini-2.5-flash")
        self.assertEqual(provider, "agy")
        self.assertEqual(model, "gemini-2.5-flash")

    def test_cheapest_selected_when_no_preference(self):
        stub = StubWorkerRouter()
        router = QuotaAwareRouter(stub)
        provider, model = router.select_worker()
        self.assertEqual(provider, "agy")
        self.assertEqual(model, "gemini-2.5-flash")

    def test_exhausted_provider_skipped(self):
        stub = StubWorkerRouter()
        router = QuotaAwareRouter(stub)
        router._exhausted.add("agy")
        router._exhausted_at["agy"] = time.monotonic()
        provider, model = router.select_worker()
        self.assertEqual(provider, "claude")

    def test_all_exhausted_raises(self):
        stub = StubWorkerRouter()
        router = QuotaAwareRouter(stub)
        for p, _m, _c in WORKER_PRIORITY:
            router._exhausted.add(p)
            router._exhausted_at[p] = time.monotonic()
        with self.assertRaises(QuotaExhausted):
            router.select_worker()

    def test_cooldown_resets_exhaustion(self):
        stub = StubWorkerRouter()
        router = QuotaAwareRouter(stub)
        router._cooldown = 0.01
        router._exhausted.add("agy")
        router._exhausted_at["agy"] = time.monotonic() - 1.0
        provider, model = router.select_worker()
        self.assertEqual(provider, "agy")
        self.assertNotIn("agy", router._exhausted)


class FallbackTests(unittest.TestCase):
    def test_fallback_on_quota_exhausted(self):
        call_count = {"n": 0}

        def agy_exhausted(provider, model):
            return WorkerResult(status="quota_exhausted", provider=provider, model=model,
                                error="quota exceeded")

        def claude_ok(provider, model):
            return WorkerResult(status="completed", provider=provider, model=model,
                                summary="Done by claude")

        stub = StubWorkerRouter({
            "agy": agy_exhausted,
            "claude": claude_ok,
        })
        router = QuotaAwareRouter(stub)
        result = router.run("Task", FakeStreamControl())
        self.assertEqual(result.status, "completed")
        self.assertEqual(result.provider, "claude")
        self.assertIn("agy", router._exhausted)

    def test_all_providers_exhausted_returns_quota_exhausted(self):
        def always_exhausted(provider, model):
            return WorkerResult(status="quota_exhausted", provider=provider, model=model,
                                error="quota exceeded")

        stub = StubWorkerRouter({
            "agy": always_exhausted,
            "claude": always_exhausted,
            "chatgpt": always_exhausted,
        })
        router = QuotaAwareRouter(stub)
        result = router.run("Task", FakeStreamControl(), max_retries=3)
        self.assertEqual(result.status, "quota_exhausted")

    def test_successful_first_try_no_fallback(self):
        stub = StubWorkerRouter()
        router = QuotaAwareRouter(stub)
        result = router.run("Task", FakeStreamControl(), preferred_provider="chatgpt")
        self.assertEqual(result.status, "completed")
        self.assertEqual(len(stub._calls), 1)
        self.assertEqual(stub._calls[0][0], "chatgpt")


class ResetTests(unittest.TestCase):
    def test_reset_specific_provider(self):
        stub = StubWorkerRouter()
        router = QuotaAwareRouter(stub)
        router._exhausted.add("agy")
        router._exhausted_at["agy"] = time.monotonic()
        router.reset_exhausted("agy")
        self.assertNotIn("agy", router._exhausted)

    def test_reset_all(self):
        stub = StubWorkerRouter()
        router = QuotaAwareRouter(stub)
        router._exhausted.update({"agy", "claude"})
        router.reset_exhausted()
        self.assertEqual(len(router._exhausted), 0)


class PriorityConfigTests(unittest.TestCase):
    def test_custom_priority(self):
        stub = StubWorkerRouter()
        custom = [("claude", "claude-haiku", 1), ("chatgpt", "gpt-4.1-mini", 2)]
        router = QuotaAwareRouter(stub, priority=custom)
        provider, model = router.select_worker()
        self.assertEqual(provider, "claude")
        self.assertEqual(model, "claude-haiku")

    def test_load_from_config_file(self):
        with tempfile.TemporaryDirectory() as config_dir:
            config_path = Path(config_dir)
            priority_file = config_path / "worker_priority.json"
            priority_file.write_text(json.dumps([
                ["chatgpt", "gpt-4.1-mini", 1],
                ["agy", "gemini-2.5-flash", 2],
            ]))
            stub = StubWorkerRouter()
            router = QuotaAwareRouter(stub, config_path=config_path)
            provider, model = router.select_worker()
            self.assertEqual(provider, "chatgpt")

    def test_missing_config_uses_default(self):
        stub = StubWorkerRouter()
        router = QuotaAwareRouter(stub, config_path=Path("/nonexistent"))
        self.assertEqual(len(router._priority), len(WORKER_PRIORITY))


if __name__ == "__main__":
    unittest.main()
