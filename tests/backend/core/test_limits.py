"""Límites de gasto y detección de fallos sin inferencia."""

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tests.support import paths  # noqa: F401
from harness.core.limits import AgentLimits, FailureTracker, LimitsStore, billable_tokens
from harness.tools.output import BoundedOutput


class LimitsTests(unittest.TestCase):
    def test_environment_defaults_and_overrides(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(AgentLimits.from_environment(), AgentLimits())
        with patch.dict(os.environ, {"AGENT_SHELL_MAX_STEPS": "48",
                                    "AGENT_SHELL_COMMAND_TIMEOUT": "600",
                                    "AGENT_SHELL_MAX_TURN_TOKENS": "40000",
                                    "AGENT_SHELL_COMPACT_THRESHOLD_TOKENS": "80000",
                                    "AGENT_SHELL_MAX_COMPACTIONS": "4"}, clear=True):
            limits = AgentLimits.from_environment()
        self.assertEqual(
            (limits.max_steps, limits.shell_timeout, limits.max_turn_tokens,
             limits.compact_threshold_tokens, limits.max_compactions),
            (48, 600, 40000, 80000, 4),
        )

    def test_invalid_limits_fail_explicitly_instead_of_enabling_unbounded_work(self):
        for name, value in (("AGENT_SHELL_MAX_STEPS", "0"), ("AGENT_SHELL_MAX_TOOL_CALLS", "-1"),
                            ("AGENT_SHELL_COMMAND_TIMEOUT", "forever"),
                            ("AGENT_SHELL_CONTEXT_OUTPUT_CHARS", "100000"),
                            ("AGENT_SHELL_MAX_TURN_TOKENS", "nan"),
                            ("AGENT_SHELL_MAX_TURN_BILLABLE_TOKENS", "500"),
                            ("AGENT_SHELL_REPEATED_FAILURES", "1"),
                            ("AGENT_SHELL_COMPACT_THRESHOLD_TOKENS", "500"),
                            ("AGENT_SHELL_MAX_COMPACTIONS", "0")):
            with self.subTest(name=name), patch.dict(os.environ, {name: value}, clear=True):
                with self.assertRaisesRegex(ValueError, name):
                    AgentLimits.from_environment()

    def test_failure_tracker_ignores_timing_and_resets_on_progress(self):
        tracker = FailureTracker(3)
        item = {"name": "shell", "arguments": '{"command":"false"}'}
        error = {"status": "error", "exit_code": 1, "output": "failure", "duration_ms": 10}
        self.assertFalse(tracker.observe(item, error))
        self.assertFalse(tracker.observe(item, {**error, "duration_ms": 20}))
        self.assertTrue(tracker.observe({**item, "arguments": '{ "command": "false" }'}, error))
        self.assertFalse(tracker.observe(item, {"status": "completed"}))
        self.assertFalse(tracker.observe(item, error))
        self.assertFalse(tracker.observe(item, {**error, "output": "new evidence"}))

    def test_output_bound_is_independent_of_fragmentation_and_unicode(self):
        source = "START" + "🎵á" * 100 + "FINAL"
        whole, fragmented = BoundedOutput(40), BoundedOutput(40)
        whole.append(source)
        for char in source:
            fragmented.append(char)
        self.assertEqual(whole.text, fragmented.text)
        self.assertEqual(len(whole.text), 40)
        self.assertTrue(whole.text.startswith("START"))
        self.assertTrue(whole.text.endswith("FINAL"))
        for limit in (0, 1, 3, 5):
            output = BoundedOutput(limit)
            output.append(source)
            self.assertLessEqual(len(output.text), limit)

    def test_presets_store_persistence_and_billable_tokens(self):
        self.assertEqual(AgentLimits().profile_name(), "equilibrado")
        ahorro = AgentLimits.preset("ahorro")
        self.assertEqual(ahorro.profile_name(), "ahorro")
        self.assertEqual((ahorro.compact_threshold_tokens, ahorro.max_turn_billable_tokens), (40000, 200000))
        custom = AgentLimits.from_dict({"compact_threshold_tokens": 50000}, base=ahorro)
        self.assertEqual(custom.profile_name(), "personalizado")

        with tempfile.TemporaryDirectory() as tmp:
            store = LimitsStore(Path(tmp))
            store.save(ahorro)
            self.assertEqual(store.path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(store.load(), ahorro)
            # Archivo corrupto vuelve a defaults sin crashear.
            store.path.write_text("{bad json", encoding="utf-8")
            self.assertEqual(store.load(), AgentLimits())
            # Enlace simbólico se rechaza al guardar.
            store.path.unlink()
            store.path.symlink_to(Path(tmp) / "other.json")
            with self.assertRaises(ValueError):
                store.save(ahorro)

        self.assertEqual(billable_tokens({"input_tokens": 10000, "cached_tokens": 9000, "output_tokens": 500}), 1500)
        self.assertEqual(billable_tokens(None), 0)
