"""Configuración del modo unificado: validación, valores por defecto y persistencia atómica."""

import json
import tempfile
import unittest
from pathlib import Path

from tests.support import paths  # noqa: F401
from harness.work.unified_config import (
    ArchitectStep,
    UnifiedConfig,
    UnifiedConfigStore,
    WorkerSlotConfig,
)


class UnifiedConfigTests(unittest.TestCase):
    def test_defaults_match_cascade_and_two_dedicated_workers(self):
        cfg = UnifiedConfig.default()
        self.assertEqual(cfg.quota_threshold, 35)
        self.assertTrue(cfg.parallel_workers)
        self.assertEqual(
            [(step.provider, step.model, step.effort) for step in cfg.architect_cascade],
            [
                ("agy", "gemini-4-neon-xhigh", "xhigh"),
                ("claude", "claude-opus", "xhigh"),
                ("chatgpt", "gpt-6.2-astra", "high"),
            ],
        )
        self.assertEqual(
            [(worker.slot, worker.provider, worker.tier, worker.effort) for worker in cfg.workers],
            [
                ("chatgpt", "chatgpt", "balanced", "medium"),
                ("claude", "claude", "balanced", "medium"),
            ],
        )

    def test_validation_rejects_bad_inputs(self):
        for payload in (
            {"quota_threshold": -1},
            {"quota_threshold": 96},
            {"quota_threshold": True},
            {"parallel_workers": "yes"},
            {"architect_cascade": []},
            {"architect_cascade": [{"provider": "unknown"}]},
            {"architect_cascade": [{"provider": "agy", "effort": "turbo"}]},
            {"workers": []},
            {"workers": [
                {"slot": "chatgpt", "provider": "chatgpt"},
                {"slot": "chatgpt", "provider": "chatgpt"},
            ]},
            {"workers": [{"slot": "chatgpt", "provider": "chatgpt", "tier": "ultra"}]},
            {"unknown_field": 1},
        ):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                UnifiedConfig.from_dict(payload)

    def test_store_roundtrip_corruption_fallback_and_symlink_protection(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "config"
            store = UnifiedConfigStore(root)
            self.assertEqual(store.load(), UnifiedConfig.default())

            custom = UnifiedConfig(
                quota_threshold=25,
                parallel_workers=False,
                architect_cascade=(
                    ArchitectStep("claude", "claude-opus", "max"),
                    ArchitectStep("chatgpt", "gpt-6.2-astra", "xhigh"),
                ),
                workers=(
                    WorkerSlotConfig("chatgpt", "chatgpt", "gpt-6.2-sol", "high", "strong"),
                    WorkerSlotConfig("claude", "claude", "claude-sonnet", "medium", "balanced"),
                ),
            )
            store.save(custom)
            self.assertEqual(store.load(), custom)
            self.assertEqual(store.path.stat().st_mode & 0o777, 0o600)

            store.path.write_text("{corrupt json", encoding="utf-8")
            self.assertEqual(store.load(), UnifiedConfig.default())

            store.path.write_text(json.dumps({"schema_version": 99}), encoding="utf-8")
            self.assertEqual(store.load(), UnifiedConfig.default())

            target = Path(tmp) / "outside.json"
            target.write_text("{}", encoding="utf-8")
            store.path.unlink()
            store.path.symlink_to(target)
            self.assertEqual(store.load(), UnifiedConfig.default())
            with self.assertRaises(ValueError):
                store.save(custom)


if __name__ == "__main__":
    unittest.main()
