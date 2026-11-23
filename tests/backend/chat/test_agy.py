"""Pruebas del cliente oficial Antigravity CLI (`agy`) y del soporte multiproveedor."""

from __future__ import annotations

import json
import os
import stat
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

from harness.account.codex_usage import UsageError
from harness.chat.agy import (
    AgyClient,
    normalize_agy_usage,
    parse_agy_usage,
    parse_models_output,
    parse_stream_line,
    summarize_agy_tool,
)
from harness.chat.models import family
from harness.core.http import Cancelled, ServiceError, StreamControl
from harness.core.provider import ProviderStore, normalize_provider
from harness.core.server import HarnessServer
from tests.support.sessions import QueueOutput


class _OfflineSession:
    def account(self):
        return {
            "authenticated": False,
            "method": "none",
            "email": "",
            "plan": "",
            "plan_enabled": False,
            "accounts": [],
        }


class _FakeAgyClient:
    def __init__(self, models: list[dict] | None = None, turns: list[list[dict]] | None = None) -> None:
        self._models = models or [
            {
                "slug": "gemini-4-neon-high",
                "display_name": "Gemini 4 Neon (High)",
                "family": "gemini",
                "reasoning_efforts": [],
                "default_reasoning_effort": "",
            },
            {
                "slug": "claude-sonnet-5-5-medium",
                "display_name": "Claude Sonnet 5.5 (Medium)",
                "family": "claude",
                "reasoning_efforts": [],
                "default_reasoning_effort": "",
            },
        ]
        self._turns = list(turns or [])
        self.calls: list[dict] = []
        self.models_calls = 0

    def is_available(self) -> bool:
        return True

    def usage(self) -> dict:
        return {
            "source": "agy",
            "account": {"email": "", "plan": "Antigravity"},
            "limits": [
                {
                    "id": "gemini-models",
                    "name": "Gemini Models",
                    "description": "Gemini 4 Neon, Gemini 3.8 Flash",
                    "primary": {"used_percent": 46.3, "window_minutes": 300, "resets_at": 1795430256.0},
                    "secondary": {"used_percent": 53.3, "window_minutes": 10080, "resets_at": 1795981056.0},
                    "credits": None,
                },
                {
                    "id": "claude-and-gpt-models",
                    "name": "Claude and GPT models",
                    "description": "Claude Opus 5.5, Claude Sonnet 5.5, GPT-OSS 120B",
                    "primary": {"used_percent": 0.0, "window_minutes": 300, "resets_at": 1795437690.0},
                    "secondary": {"used_percent": 0.0, "window_minutes": 10080, "resets_at": 1796024490.0},
                    "credits": None,
                },
            ],
            "summary": None,
            "checked_at": "2026-11-23T07:45:00+00:00",
        }

    def close(self) -> None:
        pass

    def models(self, force: bool = False) -> list[dict]:
        self.models_calls += 1
        return [dict(row) for row in self._models]

    def stream_turn(self, prompt, model, workspace, control, *, conversation_id="", image="", mode="auto"):
        self.calls.append({
            "prompt": prompt,
            "model": model,
            "workspace": str(workspace),
            "conversation_id": conversation_id,
            "image": image,
            "mode": mode,
        })
        control.mark("request")
        control.mark("headers")
        events = self._turns.pop(0) if self._turns else [
            {"type": "init", "conversation_id": "agy-conv-1", "model": model},
            {"type": "text_delta", "conversation_id": "agy-conv-1", "step_index": 1, "state": "ACTIVE", "text": "Hola desde ", "done": False, "usage": None},
            {
                "type": "text_delta",
                "conversation_id": "agy-conv-1",
                "step_index": 1,
                "state": "DONE",
                "text": "Gemini.",
                "done": True,
                "usage": {
                    "input_tokens": 1200,
                    "output_tokens": 18,
                    "total_tokens": 1218,
                    "input_tokens_details": {"cached_tokens": 400},
                    "output_tokens_details": {"reasoning_tokens": 6},
                },
            },
            {
                "type": "result",
                "conversation_id": "agy-conv-1",
                "status": "SUCCESS",
                "response": "Hola desde Gemini.",
                "usage": {"input_tokens": 1200, "output_tokens": 18, "total_tokens": 1218},
                "error": "",
            },
        ]
        for event in events:
            control.check()
            yield event


def _make_fake_agy_script(directory: Path) -> Path:
    script = directory / "fake-agy"
    script.write_text(
        f"#!{sys.executable}\n"
        "import json, sys, time\n"
        "args = sys.argv[1:]\n"
        "if args and args[0] == 'models':\n"
        "    sys.stdout.write('\\x1b[36m⠋ Loading...\\r\\x1b[0mgemini-4-neon-high              Gemini 4 Neon (High)\\n')\n"
        "    sys.stdout.write('claude-opus-5-5-high            Claude Opus 5.5 (High)\\n')\n"
        "    sys.stdout.write('gpt-oss-120b-medium             GPT-OSS 120B (Medium)\\n')\n"
        "    sys.exit(0)\n"
        "prompt = args[args.index('-p') + 1] if '-p' in args else ''\n"
        "if prompt == '/usage':\n"
        "    print(json.dumps({\n"
        "        'status': 'SUCCESS',\n"
        "        'command': {'name': 'usage', 'data': {'groups': [\n"
        "            {'name': 'Gemini Models', 'description': 'Models within this group: Gemini 4 Neon, Gemini 3.8 Flash', 'buckets': [\n"
        "                {'id': 'gemini-weekly', 'window': 'weekly', 'remaining_fraction': 0.467, 'reset_time': '2026-11-29T19:37:36Z'},\n"
        "                {'id': 'gemini-5h', 'window': '5h', 'remaining_fraction': 0.537, 'reset_time': '2026-11-23T10:37:36Z'},\n"
        "            ]},\n"
        "            {'name': 'Claude and GPT models', 'description': 'Models within this group: Claude Opus 5.5, Claude Sonnet 5.5, GPT-OSS 120B', 'buckets': [\n"
        "                {'id': '3p-weekly', 'window': 'weekly', 'remaining_fraction': 1.0, 'reset_time': '2026-11-30T07:41:30Z'},\n"
        "                {'id': '3p-5h', 'window': '5h', 'remaining_fraction': 1.0, 'reset_time': '2026-11-23T12:41:30Z'},\n"
        "            ]},\n"
        "            {'name': 'Gemini 4 Argon', 'description': 'Separate quota', 'buckets': [\n"
        "                {'id': 'argon-weekly', 'window': 'weekly', 'remaining_fraction': 0.0, 'reset_time': '2026-11-30T00:58:53Z'},\n"
        "            ]},\n"
        "        ]}},\n"
        "    }), flush=True)\n"
        "    sys.exit(0)\n"
        "model = args[args.index('--model') + 1] if '--model' in args else 'gemini-4-neon-high'\n"
        "conv = args[args.index('--conversation') + 1] if '--conversation' in args else 'conv-fake-42'\n"
        "if 'SLEEP_CANCEL' in prompt:\n"
        "    print(json.dumps({'event': 'init', 'conversation_id': conv, 'init': {'model': model}}), flush=True)\n"
        "    time.sleep(10)\n"
        "    sys.exit(0)\n"
        "print(json.dumps({'event': 'init', 'conversation_id': conv, 'init': {'model': model}}), flush=True)\n"
        "print(json.dumps({'event': 'step_update', 'step_update': {'conversation_id': conv, 'step_index': 1, 'state': 'ACTIVE', 'step_type': 'tool', 'tool_name': 'run_command', 'tool_info': {'name': 'run_command', 'parameters': {'CommandLine': 'echo hi'}}}}), flush=True)\n"
        "print(json.dumps({'event': 'step_update', 'step_update': {'conversation_id': conv, 'step_index': 1, 'state': 'DONE', 'step_type': 'tool', 'tool_name': 'run_command', 'duration_seconds': 0.05, 'tool_info': {'name': 'run_command', 'parameters': {'CommandLine': 'echo hi'}, 'output': 'hi\\n'}}}), flush=True)\n"
        "print(json.dumps({'event': 'step_update', 'step_update': {'conversation_id': conv, 'step_index': 2, 'state': 'ACTIVE', 'step_type': 'agent_response', 'text_delta': f'Echo:{prompt[:20]}'}}), flush=True)\n"
        "print(json.dumps({'event': 'step_update', 'step_update': {'conversation_id': conv, 'step_index': 2, 'state': 'DONE', 'step_type': 'agent_response', 'text_delta': '', 'usage': {'input_tokens': 500, 'output_tokens': 12, 'thinking_tokens': 4, 'cache_read_tokens': 100, 'total_tokens': 512}}}), flush=True)\n"
        "print(json.dumps({'event': 'result', 'result': {'conversation_id': conv, 'status': 'SUCCESS', 'response': f'Echo:{prompt[:20]}', 'usage': {'input_tokens': 500, 'output_tokens': 12, 'thinking_tokens': 4, 'cache_read_tokens': 100, 'total_tokens': 512}}}), flush=True)\n",
        encoding="utf-8",
    )
    script.chmod(script.stat().st_mode | stat.S_IXUSR)
    return script


class AgyParsingTests(unittest.TestCase):
    def test_provider_store_round_trip_and_symlink_protection(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "config"
            store = ProviderStore(root)
            self.assertEqual(store.load(), {"provider": "chatgpt", "agy_model": ""})
            saved = store.save("agy", "gemini-4-neon-high")
            self.assertEqual(saved, {"provider": "agy", "agy_model": "gemini-4-neon-high"})
            self.assertEqual(store.load(), {"provider": "agy", "agy_model": "gemini-4-neon-high"})
            with self.assertRaises(ValueError):
                normalize_provider("invalid")
            target = Path(tmp) / "outside.json"
            target.write_text("{}", encoding="utf-8")
            store.path.unlink()
            store.path.symlink_to(target)
            self.assertEqual(store.load(), {"provider": "chatgpt", "agy_model": ""})
            with self.assertRaises(OSError):
                store.save("agy")

    def test_parse_models_output_handles_ansi_spinner_and_families(self):
        raw = (
            "\x1b[33m⠋ Loading models...\r\x1b[0m"
            "gemini-4-neon-high\tGemini 4 Neon (High)\n"
            "gemini-4-neon-high              Duplicate Ignored\n"
            "claude-sonnet-5-5-medium        Claude Sonnet 5.5 (Medium)\n"
            "gpt-oss-120b-medium\tGPT-OSS 120B (Medium)\n"
            "Header line without separator\n"
        )
        rows = parse_models_output(raw)
        self.assertEqual([r["slug"] for r in rows], [
            "gemini-4-neon-high",
            "claude-sonnet-5-5-medium",
            "gpt-oss-120b-medium",
        ])
        self.assertEqual([r["family"] for r in rows], ["gemini", "claude", "otros"])
        self.assertEqual(family("gemini-3.8-flash-high"), "gemini")
        self.assertEqual(family("claude-opus-5-5-low"), "claude")
        self.assertEqual(family("gpt-6.1-sol"), "gpt-6")
        self.assertTrue(all(r["reasoning_efforts"] == [] for r in rows))

    def test_summarize_agy_tool_and_usage_normalization(self):
        ws = Path("/tmp/demo-ws")
        self.assertEqual(summarize_agy_tool("run_command", {"CommandLine": "pytest -q"}, ws), "pytest -q")
        self.assertEqual(summarize_agy_tool("read_file", {"Path": "/tmp/demo-ws/src/app.py"}, ws), "read_file src/app.py")
        self.assertEqual(summarize_agy_tool("grep_search", {"Query": "HarnessServer"}, ws), "grep_files HarnessServer")
        self.assertEqual(summarize_agy_tool("edit_file", {"TargetFile": "/tmp/demo-ws/ui/App.qml"}, ws), "apply_patch ui/App.qml")

        usage = normalize_agy_usage({
            "input_tokens": 14065,
            "output_tokens": 822,
            "thinking_tokens": 733,
            "cache_read_tokens": 13828,
            "total_tokens": 14887,
        })
        self.assertEqual(usage, {
            "input_tokens": 14065,
            "output_tokens": 822,
            "total_tokens": 14887,
            "input_tokens_details": {"cached_tokens": 13828},
            "output_tokens_details": {"reasoning_tokens": 733},
        })

    def test_parse_stream_line_variants(self):
        self.assertIsNone(parse_stream_line("   "))
        self.assertIsNone(parse_stream_line("not json"))
        init_ev = parse_stream_line(json.dumps({
            "event": "init", "conversation_id": "abc", "init": {"model": "gemini-4-neon-high"},
        }))
        self.assertEqual(init_ev, {"type": "init", "conversation_id": "abc", "model": "gemini-4-neon-high"})
        delta_ev = parse_stream_line(json.dumps({
            "event": "step_update",
            "step_update": {
                "conversation_id": "abc", "step_index": 1, "state": "ACTIVE",
                "step_type": "agent_response", "text_delta": "Hola",
            },
        }))
        self.assertEqual(delta_ev["type"], "text_delta")
        self.assertEqual(delta_ev["text"], "Hola")
        self.assertFalse(delta_ev["done"])
        tool_ev = parse_stream_line(json.dumps({
            "event": "step_update",
            "step_update": {
                "conversation_id": "abc", "step_index": 2, "state": "DONE",
                "step_type": "tool", "tool_name": "run_command", "duration_seconds": 0.125,
                "tool_info": {"name": "run_command", "parameters": {"CommandLine": "ls"}, "output": "a\nb\n"},
            },
        }))
        self.assertEqual(tool_ev["type"], "tool")
        self.assertEqual(tool_ev["duration_seconds"], 0.125)
        self.assertEqual(tool_ev["output"], "a\nb\n")


    def test_parse_agy_usage_orders_5h_before_weekly_and_extracts_models(self):
        raw = json.dumps({
            "status": "SUCCESS",
            "command": {
                "name": "usage",
                "data": {
                    "groups": [
                        {
                            "name": "Gemini Models",
                            "description": "Models within this group: Gemini 4 Neon, Gemini 3.8 Flash",
                            "buckets": [
                                {"id": "gemini-weekly", "window": "weekly", "remaining_fraction": 0.467, "reset_time": "2026-11-29T19:37:36Z"},
                                {"id": "gemini-5h", "window": "5h", "remaining_fraction": 0.537, "reset_time": "2026-11-23T10:37:36Z"},
                            ],
                        },
                        {
                            "name": "Gemini 4 Argon",
                            "description": "Separate quota",
                            "buckets": [
                                {"id": "argon-weekly", "window": "weekly", "remaining_fraction": 0.001, "reset_time": "2026-11-30T00:58:53Z"},
                            ],
                        },
                    ],
                },
            },
        })
        parsed = parse_agy_usage(raw)
        self.assertEqual(parsed["source"], "agy")
        self.assertEqual(len(parsed["limits"]), 2)
        gemini = parsed["limits"][0]
        self.assertEqual(gemini["name"], "Gemini Models")
        self.assertEqual(gemini["description"], "Gemini 4 Neon, Gemini 3.8 Flash")
        self.assertEqual(gemini["primary"]["window_minutes"], 300)
        self.assertAlmostEqual(gemini["primary"]["used_percent"], 46.3, places=1)
        self.assertEqual(gemini["secondary"]["window_minutes"], 10080)
        self.assertAlmostEqual(gemini["secondary"]["used_percent"], 53.3, places=1)
        self.assertIsNotNone(gemini["primary"]["resets_at"])
        argon = parsed["limits"][1]
        self.assertEqual(argon["primary"]["window_minutes"], 10080)
        self.assertAlmostEqual(argon["primary"]["used_percent"], 99.9, places=1)
        self.assertIsNone(argon["secondary"])

        with self.assertRaises(UsageError):
            parse_agy_usage("not-json")


class AgySubprocessTests(unittest.TestCase):
    def test_client_models_stream_and_cancel_with_fake_binary(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_bin = _make_fake_agy_script(root)
            client = AgyClient(binary=str(fake_bin))
            self.assertTrue(client.is_available())

            models = client.models()
            self.assertEqual([m["slug"] for m in models], [
                "gemini-4-neon-high", "claude-opus-5-5-high", "gpt-oss-120b-medium",
            ])

            usage = client.usage()
            self.assertEqual(usage["source"], "agy")
            self.assertEqual([g["name"] for g in usage["limits"]], [
                "Gemini Models", "Claude and GPT models", "Gemini 4 Argon",
            ])
            self.assertEqual(usage["limits"][0]["primary"]["window_minutes"], 300)
            self.assertEqual(usage["limits"][1]["primary"]["used_percent"], 0.0)
            self.assertEqual(usage["limits"][2]["primary"]["used_percent"], 100.0)

            control = StreamControl()
            events = list(client.stream_turn("Hola", "gemini-4-neon-high", root, control))
            types = [e["type"] for e in events]
            self.assertIn("init", types)
            self.assertIn("tool", types)
            self.assertIn("text_delta", types)
            self.assertIn("result", types)

            cancel_control = StreamControl()
            started = time.monotonic()

            def _cancel_soon():
                time.sleep(0.15)
                cancel_control.cancel()

            canceller = threading.Thread(target=_cancel_soon, daemon=True)
            canceller.start()
            with self.assertRaises(Cancelled):
                for _ in client.stream_turn("SLEEP_CANCEL", "gemini-4-neon-high", root, cancel_control):
                    pass
            canceller.join(2)
            self.assertLess(time.monotonic() - started, 3.0)

            old = os.environ.get("AGENT_SHELL_DISABLE_AGY")
            try:
                os.environ["AGENT_SHELL_DISABLE_AGY"] = "1"
                self.assertFalse(client.is_available())
                with self.assertRaises(ServiceError):
                    client.models(force=True)
            finally:
                if old is None:
                    os.environ.pop("AGENT_SHELL_DISABLE_AGY", None)
                else:
                    os.environ["AGENT_SHELL_DISABLE_AGY"] = old


class HarnessAgyIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = QueueOutput()
        self.agy = _FakeAgyClient(turns=[
            [
                {"type": "init", "conversation_id": "agy-conv-abc", "model": "gemini-4-neon-high"},
                {
                    "type": "tool", "conversation_id": "agy-conv-abc", "step_index": 1, "state": "ACTIVE",
                    "tool_name": "run_command", "parameters": {"CommandLine": "pwd"},
                    "output": "", "truncated": False, "duration_seconds": None, "error": "",
                },
                {
                    "type": "tool", "conversation_id": "agy-conv-abc", "step_index": 1, "state": "DONE",
                    "tool_name": "run_command", "parameters": {"CommandLine": "pwd"},
                    "output": "/tmp/ws\n", "truncated": False, "duration_seconds": 0.04, "error": "",
                },
                {
                    "type": "text_delta", "conversation_id": "agy-conv-abc", "step_index": 2, "state": "ACTIVE",
                    "text": "Todo listo.", "done": False, "usage": None,
                },
                {
                    "type": "text_delta", "conversation_id": "agy-conv-abc", "step_index": 2, "state": "DONE",
                    "text": "", "done": True,
                    "usage": {
                        "input_tokens": 2400, "output_tokens": 12, "total_tokens": 2412,
                        "input_tokens_details": {"cached_tokens": 1000},
                        "output_tokens_details": {"reasoning_tokens": 3},
                    },
                },
                {
                    "type": "result", "conversation_id": "agy-conv-abc", "status": "SUCCESS",
                    "response": "Todo listo.", "usage": {"input_tokens": 2400, "output_tokens": 12, "total_tokens": 2412},
                    "error": "",
                },
            ],
            [
                {"type": "init", "conversation_id": "agy-conv-abc", "model": "claude-sonnet-5-5-medium"},
                {
                    "type": "text_delta", "conversation_id": "agy-conv-abc", "step_index": 1, "state": "DONE",
                    "text": "Seguimos en la misma sesión.", "done": True,
                    "usage": {"input_tokens": 3000, "output_tokens": 10, "total_tokens": 3010},
                },
                {
                    "type": "result", "conversation_id": "agy-conv-abc", "status": "SUCCESS",
                    "response": "Seguimos en la misma sesión.",
                    "usage": {"input_tokens": 3000, "output_tokens": 10, "total_tokens": 3010},
                    "error": "",
                },
            ],
        ])
        self.server = HarnessServer(
            self.root / "chats",
            self.output,
            _OfflineSession(),
            client=None,
            workspace=self.root,
            config_root=self.root / "config",
            agy_client=self.agy,
        )
        self.addCleanup(self._stop)

    def _stop(self):
        self.server._stream.cancel()
        self.server.project_runner.close()
        for worker in self.server._workers:
            worker.join(3)

    def test_select_agy_without_chatgpt_auth_runs_tools_and_resumes_conversation(self):
        self.assertEqual(self.server.provider, "chatgpt")
        self.assertTrue(self.server.agy_available)

        self.server.handle({"type": "provider.select", "provider": "agy"})
        self.output.wait_for("provider.refresh.finished")
        self.assertEqual(self.server.provider, "agy")
        self.assertEqual(self.server.model, "gemini-4-neon-high")

        # Enviar primer turno sin sesión de ChatGPT.
        self.server.handle({"type": "chat.send", "prompt": "Revisa el directorio"})
        finished = self.output.wait_for("chat.finished")
        self.assertEqual(finished["status"], "completed")
        self.assertEqual(len(self.agy.calls), 1)
        self.assertEqual(self.agy.calls[0]["conversation_id"], "")
        self.assertEqual(self.agy.calls[0]["model"], "gemini-4-neon-high")

        chat_id = self.server.conversation["chat_id"]
        saved = self.server.history.load(chat_id)
        self.assertEqual(saved["provider"], "agy")
        self.assertEqual(saved["agy_conversation_id"], "agy-conv-abc")
        self.assertEqual(len(saved["tool_calls"]), 1)
        self.assertEqual(saved["tool_calls"][0]["source"], "agy")
        self.assertEqual(saved["tool_calls"][0]["status"], "completed")
        self.assertEqual(saved["tool_calls"][0]["output"], "/tmp/ws\n")
        self.assertEqual(saved["messages"][-1]["text"], "Todo listo.")
        self.assertEqual(saved["performance"][-1]["context_tokens"], 2400)

        # Cambiar modelo a Claude dentro de agy y enviar segundo turno: reutiliza agy_conversation_id.
        self.server.handle({"type": "model.select", "model": "claude-sonnet-5-5-medium"})
        self.output.wait_for("model.selected")
        self.server.handle({"type": "chat.send", "prompt": "¿Qué viste?"})
        finished2 = self.output.wait_for("chat.finished")
        self.assertEqual(finished2["status"], "completed")
        self.assertEqual(len(self.agy.calls), 2)
        self.assertEqual(self.agy.calls[1]["conversation_id"], "agy-conv-abc")
        self.assertEqual(self.agy.calls[1]["model"], "claude-sonnet-5-5-medium")

        # /compact informa que agy gestiona su propia compactación.
        self.server.handle({"type": "chat.compact"})
        compacted = self.output.wait_for("chat.compacted")
        self.assertEqual(compacted["status"], "failed")
        self.assertIn("Antigravity", compacted["message"])

        # Nuevo servidor restaura proveedor y modelo guardados de agy.
        restarted = HarnessServer(
            self.root / "chats",
            QueueOutput(),
            _OfflineSession(),
            client=None,
            workspace=self.root,
            config_root=self.root / "config",
            agy_client=self.agy,
        )
        self.assertEqual(restarted.provider, "agy")
        self.assertEqual(restarted.model, "claude-sonnet-5-5-medium")

        # Consultar uso en agy funciona sin sesión de ChatGPT y devuelve todos los grupos de modelos.
        self.server.handle({"type": "usage.read", "request_id": "agy-u1"})
        usage_state = self.output.wait_for("usage.state")
        self.output.wait_for("usage.finished")
        self.assertEqual(usage_state["request_id"], "agy-u1")
        self.assertEqual(usage_state["source"], "agy")
        self.assertEqual([g["name"] for g in usage_state["limits"]], ["Gemini Models", "Claude and GPT models"])

        # Cambiar a ChatGPT y volver a agy usa la caché sin re-consultar `agy models`.
        models_calls_before = self.agy.models_calls
        self.server.handle({"type": "provider.select", "provider": "chatgpt"})
        self.assertEqual(self.server.provider, "chatgpt")
        self.server.handle({"type": "provider.select", "provider": "agy"})
        self.assertEqual(self.server.provider, "agy")
        self.assertEqual(self.agy.models_calls, models_calls_before)


if __name__ == "__main__":
    unittest.main()
