"""Pruebas de la suite de benchmarks, verificadores, auditoría y comparador A/B."""

import copy
import json
import tempfile
import unittest
from pathlib import Path

from benchmarks.metrics import (
    compare_reports,
    format_audit_report,
    format_comparison,
    format_run_report,
)
from benchmarks.runner import audit_history, compute_quota_delta, run_benchmark, save_report
from benchmarks.tasks import TASKS


class BenchmarkTaskTests(unittest.TestCase):
    def test_every_task_fails_verification_before_changes(self):
        for task in TASKS:
            with self.subTest(task=task.task_id):
                with tempfile.TemporaryDirectory() as tmp:
                    workspace = Path(tmp)
                    baseline = task.setup(workspace)
                    result = task.verify(workspace, ["Respuesta incompleta."], baseline)
                    self.assertFalse(
                        result["passed"],
                        f"La tarea {task.task_id} no debe aprobar sin resolverla",
                    )


class BenchmarkRunnerTests(unittest.TestCase):
    def test_full_mock_benchmark_passes_all_five_tasks_and_captures_wire_metrics(self):
        report = run_benchmark(live=False, suite="full", label="mock-full")
        summary = report["summary"]
        self.assertEqual(report["mode"], "mock")
        self.assertEqual(summary["tasks_total"], 5)
        self.assertEqual(summary["tasks_passed"], 5)
        self.assertEqual(summary["pass_rate"], 100.0)
        self.assertGreater(summary["model_calls"], 10)
        self.assertGreater(summary["tool_calls"], 5)
        self.assertGreater(summary["uncached_input_tokens"], 0)
        self.assertIsNotNone(summary["followup_cache_hit_rate"])
        self.assertIn("shell", summary["tools_offered"])
        self.assertIn("apply_patch", summary["tools_offered"])
        self.assertIn("read_file", summary["tools_offered"])
        self.assertIn("grep_files", summary["tools_offered"])
        self.assertTrue(summary["has_prompt_cache_key"])
        self.assertTrue(summary["parallel_tool_calls"])

        rendered = format_run_report(report)
        self.assertIn("t1_inspect_answer", rendered)
        self.assertIn("t5_multiturn_session", rendered)

        with tempfile.TemporaryDirectory() as tmp:
            saved = save_report(report, Path(tmp) / "out.json")
            loaded = json.loads(saved.read_text(encoding="utf-8"))
            self.assertEqual(loaded["summary"]["tasks_passed"], 5)

    def test_compare_reports_enforces_quality_gate_and_detects_improvements(self):
        baseline = run_benchmark(live=False, suite="quick", label="base")
        improved = copy.deepcopy(baseline)
        improved["label"] = "improved"
        for task in improved["tasks"]:
            task["metrics"]["uncached_input_tokens"] = task["metrics"]["uncached_input_tokens"] // 2
            task["metrics"]["followup_cache_hit_rate"] = 88.0
        improved["summary"]["uncached_input_tokens"] = baseline["summary"]["uncached_input_tokens"] // 2
        improved["summary"]["effective_billable_tokens"] = (
            improved["summary"]["uncached_input_tokens"] + improved["summary"]["output_tokens"]
        )
        improved["summary"]["followup_cache_hit_rate"] = 88.0

        diff_ok = compare_reports(baseline, improved)
        self.assertTrue(diff_ok["overall_verdict"].startswith("MEJORA"))
        self.assertIn("MEJORA", format_comparison(diff_ok))
        self.assertIn("| Métrica |", format_comparison(diff_ok, markdown=True))

        # Si cae la tasa de éxito, SIEMPRE debe ser REGRESIÓN aunque bajen los tokens.
        regressed = copy.deepcopy(improved)
        regressed["tasks"][0]["verified"]["passed"] = False
        regressed["summary"]["tasks_passed"] = baseline["summary"]["tasks_passed"] - 1
        diff_bad = compare_reports(baseline, regressed)
        self.assertTrue(diff_bad["overall_verdict"].startswith("REGRESIÓN"))

    def test_audit_history_aggregates_without_reading_images(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            chat = {
                "schema_version": 1,
                "area": "work",
                "performance": [
                    {
                        "model": "m1", "status": "completed", "model_calls": 4, "tool_calls": 3,
                        "context_tokens": 5000,
                        "usage": {"input_tokens": 10000, "cached_tokens": 2000, "output_tokens": 500,
                                  "reasoning_tokens": 100, "total_tokens": 10500},
                    },
                    {
                        "model": "m1", "status": "failed", "model_calls": 2, "tool_calls": 1,
                        "context_tokens": 3000,
                        "usage": {"input_tokens": 4000, "cached_tokens": 0, "output_tokens": 200,
                                  "reasoning_tokens": 0, "total_tokens": 4200},
                    },
                ],
            }
            (root / "a.json").write_text(json.dumps(chat), encoding="utf-8")
            audit = audit_history(root)
            self.assertEqual(audit["chat_files"], 1)
            self.assertEqual(audit["turns_with_usage"], 2)
            self.assertEqual(audit["overall"]["uncached_input_tokens"], 12000)
            self.assertEqual(audit["multicall_turns"], 2)
            self.assertEqual(audit["multicall_zero_cache"], 1)
            self.assertEqual(audit["wasted_tokens_failed"], 4200)
            self.assertIn("work", format_audit_report(audit))

    def test_quota_delta_handles_normal_increase_and_window_reset(self):
        before = {
            "plan": "plus",
            "primary": {"used_percent": 10.0, "resets_at": 1000},
            "secondary": {"used_percent": 20.0, "resets_at": 5000},
            "lifetime_tokens": 100000,
        }
        after = {
            "plan": "plus",
            "primary": {"used_percent": 14.5, "resets_at": 1000},
            "secondary": {"used_percent": 21.0, "resets_at": 5000},
            "lifetime_tokens": 125000,
        }
        delta = compute_quota_delta(before, after)
        self.assertTrue(delta["available"])
        self.assertEqual(delta["primary_delta_pct"], 4.5)
        self.assertEqual(delta["secondary_delta_pct"], 1.0)
        self.assertEqual(delta["lifetime_tokens_delta"], 25000)

        after_reset = copy.deepcopy(after)
        after_reset["primary"] = {"used_percent": 2.0, "resets_at": 2000}
        delta_reset = compute_quota_delta(before, after_reset)
        self.assertIsNone(delta_reset["primary_delta_pct"])
        self.assertTrue(delta_reset["primary_window_reset"])


if __name__ == "__main__":
    unittest.main()
