"""Límites de gasto y detección de fallos sin inferencia."""

import os
import unittest
from unittest.mock import patch

from tests.support import paths  # noqa: F401
from harness.core.limits import AgentLimits, FailureTracker
from harness.tools.output import BoundedOutput


class LimitsTests(unittest.TestCase):
    def test_environment_defaults_and_overrides(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(AgentLimits.from_environment(), AgentLimits())
        with patch.dict(os.environ, {"AGENT_SHELL_MAX_STEPS": "48",
                                    "AGENT_SHELL_COMMAND_TIMEOUT": "600",
                                    "AGENT_SHELL_MAX_TURN_TOKENS": "40000"}, clear=True):
            limits = AgentLimits.from_environment()
        self.assertEqual((limits.max_steps, limits.shell_timeout, limits.max_turn_tokens), (48, 600, 40000))

    def test_invalid_limits_fail_explicitly_instead_of_enabling_unbounded_work(self):
        for name, value in (("AGENT_SHELL_MAX_STEPS", "0"), ("AGENT_SHELL_MAX_TOOL_CALLS", "-1"),
                            ("AGENT_SHELL_COMMAND_TIMEOUT", "forever"),
                            ("AGENT_SHELL_CONTEXT_OUTPUT_CHARS", "100000"),
                            ("AGENT_SHELL_MAX_TURN_TOKENS", "nan"),
                            ("AGENT_SHELL_REPEATED_FAILURES", "1")):
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
