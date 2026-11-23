"""Pruebas del cliente oficial Claude Code CLI (`claude`) y su integración en HarnessServer."""

from __future__ import annotations

import json
import os
import stat
import sys
import tempfile
import threading
import time
import unittest
from datetime import datetime, timezone
from pathlib import Path

from harness.account.codex_usage import UsageError
from harness.chat.claude import (
    ClaudeClient,
    claude_catalog,
    normalize_claude_usage,
    parse_claude_auth_status,
    parse_claude_reset_time,
    parse_claude_stream_line,
    parse_claude_usage,
    resolve_cli_model,
    summarize_claude_tool,
)
from harness.core.http import Cancelled, StreamControl
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


class _FakeClaudeClient:
    def __init__(self, authenticated: bool = True, turns: list[list[dict]] | None = None) -> None:
        self._authenticated = authenticated
        self._turns = list(turns or [])
        self.calls: list[dict] = []

    def is_available(self) -> bool:
        return True

    def models(self) -> list[dict]:
        return claude_catalog()

    def close(self) -> None:
        pass

    def auth_status(self) -> dict:
        return {
            "authenticated": self._authenticated,
            "email": "dev@example.invalid" if self._authenticated else "",
            "plan": "pro" if self._authenticated else "",
            "method": "claude.ai" if self._authenticated else "none",
        }

    def usage(self) -> dict:
        return {
            "source": "claude",
            "account": {"email": "dev@example.invalid", "plan": "pro"},
            "limits": [{
                "id": "claude",
                "name": "Claude",
                "description": "",
                "primary": {"used_percent": 12.0, "window_minutes": 300, "resets_at": 1795439400.0},
                "secondary": {"used_percent": 3.0, "window_minutes": 10080, "resets_at": 1795719600.0},
                "credits": None,
            }],
            "summary": None,
            "checked_at": "2026-11-23T08:15:00+00:00",
        }

    def stream_turn(self, prompt, model, workspace, control, *, session_id="", effort="", image=""):
        self.calls.append({
            "prompt": prompt,
            "model": model,
            "effort": effort,
            "workspace": str(workspace),
            "session_id": session_id,
            "image": image,
        })
        control.mark("request")
        control.mark("headers")
        events = self._turns.pop(0) if self._turns else [
            {"type": "init", "session_id": "claude-sess-1", "model": "claude-sonnet-5-5"},
            {"type": "message_start", "session_id": "claude-sess-1", "message_id": "msg_1"},
            {"type": "text_delta", "session_id": "claude-sess-1", "message_id": "msg_1", "text": "Hola desde Claude."},
            {"type": "assistant_text", "session_id": "claude-sess-1", "message_id": "msg_1", "text": "Hola desde Claude."},
            {
                "type": "usage",
                "session_id": "claude-sess-1",
                "usage": {"input_tokens": 5000, "output_tokens": 20, "total_tokens": 5020},
            },
            {
                "type": "result",
                "session_id": "claude-sess-1",
                "is_error": False,
                "result": "Hola desde Claude.",
                "error": "",
                "usage": {"input_tokens": 5000, "output_tokens": 20, "total_tokens": 5020},
            },
        ]
        for event in events:
            control.check()
            yield event


def _make_fake_claude_script(directory: Path) -> Path:
    script = directory / "fake-claude"
    script.write_text(
        f"#!{sys.executable}\n"
        "import json, sys, time\n"
        "args = sys.argv[1:]\n"
        "if len(args) >= 2 and args[0] == 'auth' and args[1] == 'status':\n"
        "    sys.stdout.write(json.dumps({'loggedIn': True, 'authMethod': 'claude.ai', 'email': 'u@test.dev', 'planTier': 'pro'}) + '\\nB ')\n"
        "    sys.exit(0)\n"
        "prompt = args[args.index('-p') + 1] if '-p' in args else ''\n"
        "if prompt == '/usage':\n"
        "    print(json.dumps({\n"
        "        'type': 'result', 'is_error': False, 'local_command': 'usage',\n"
        "        'result': 'Current session: 14% used · resets Nov 23, 6:10am (America/Mazatlan)\\nCurrent week (all models): 4% used · resets Nov 26, 12pm (America/Mazatlan)'\n"
        "    }), flush=True)\n"
        "    sys.exit(0)\n"
        "sess = args[args.index('--resume') + 1] if '--resume' in args else 'sess-fake-99'\n"
        "if 'SLEEP_CANCEL' in prompt:\n"
        "    print(json.dumps({'type': 'system', 'subtype': 'init', 'session_id': sess, 'model': 'claude-sonnet-5-5'}), flush=True)\n"
        "    time.sleep(10)\n"
        "    sys.exit(0)\n"
        "print(json.dumps({'type': 'system', 'subtype': 'init', 'session_id': sess, 'model': 'claude-sonnet-5-5'}), flush=True)\n"
        "print(json.dumps({'type': 'stream_event', 'session_id': sess, 'api_message_id': 'm1', 'event': {'type': 'message_start', 'message': {'id': 'm1'}}}), flush=True)\n"
        "print(json.dumps({'type': 'stream_event', 'session_id': sess, 'api_message_id': 'm1', 'event': {'type': 'content_block_delta', 'delta': {'type': 'text_delta', 'text': 'OK:' + prompt[:12]}}}), flush=True)\n"
        "print(json.dumps({'type': 'assistant', 'session_id': sess, 'message': {'id': 'm1', 'content': [{'type': 'tool_use', 'id': 'tu_1', 'name': 'Bash', 'input': {'command': 'echo ok'}}], 'usage': {'input_tokens': 10, 'cache_creation_input_tokens': 400, 'cache_read_input_tokens': 100, 'output_tokens': 8}}}), flush=True)\n"
        "print(json.dumps({'type': 'user', 'session_id': sess, 'message': {'content': [{'type': 'tool_result', 'tool_use_id': 'tu_1', 'content': 'ok\\n', 'is_error': False}]}}), flush=True)\n"
        "print(json.dumps({'type': 'result', 'session_id': sess, 'is_error': False, 'result': 'OK:' + prompt[:12], 'usage': {'input_tokens': 10, 'cache_creation_input_tokens': 400, 'cache_read_input_tokens': 100, 'output_tokens': 8}}), flush=True)\n",
        encoding="utf-8",
    )
    script.chmod(script.stat().st_mode | stat.S_IXUSR)
    return script


class ClaudeParsingTests(unittest.TestCase):
    def test_auth_status_and_model_resolution(self):
        parsed = parse_claude_auth_status('{"loggedIn":true,"email":"a@b.c","planTier":"pro","authMethod":"claude.ai"}\nB ')
        self.assertEqual(parsed, {"authenticated": True, "email": "a@b.c", "plan": "pro", "method": "claude.ai"})
        self.assertFalse(parse_claude_auth_status("garbage")["authenticated"])
        self.assertEqual(resolve_cli_model("claude-sonnet"), "sonnet")
        self.assertEqual(resolve_cli_model("claude-opus"), "opus")
        self.assertEqual(resolve_cli_model("claude-haiku"), "haiku")
        self.assertEqual(resolve_cli_model("claude-opus-5-5"), "claude-opus-5-5")

    def test_usage_and_tool_summaries(self):
        ws = Path("/tmp/ws-demo")
        self.assertEqual(summarize_claude_tool("Bash", {"command": "git status"}, ws), "git status")
        self.assertEqual(summarize_claude_tool("Read", {"file_path": "/tmp/ws-demo/a.py"}, ws), "read_file a.py")
        self.assertEqual(summarize_claude_tool("Grep", {"pattern": "TODO"}, ws), "grep_files TODO")
        self.assertEqual(summarize_claude_tool("Edit", {"file_path": "/tmp/ws-demo/b.qml"}, ws), "apply_patch b.qml")

        usage = normalize_claude_usage({
            "input_tokens": 2,
            "cache_creation_input_tokens": 47400,
            "cache_read_input_tokens": 1000,
            "output_tokens": 27,
            "output_tokens_details": {"thinking_tokens": 11},
        })
        self.assertEqual(usage, {
            "input_tokens": 48402,
            "output_tokens": 27,
            "total_tokens": 48429,
            "input_tokens_details": {"cached_tokens": 1000},
            "output_tokens_details": {"reasoning_tokens": 11},
        })

    def test_parse_claude_usage_and_reset_time(self):
        now_ref = datetime(2026, 11, 23, 8, 0, tzinfo=timezone.utc)
        ts = parse_claude_reset_time("Nov 23, 6:10am (America/Mazatlan)", now_dt=now_ref)
        self.assertIsNotNone(ts)
        raw = json.dumps({
            "type": "result",
            "is_error": False,
            "result": (
                "You are currently using your subscription\n\n"
                "Current session: 2% used · resets Nov 23, 6:10am (America/Mazatlan)\n"
                "Current week (all models): 15% used · resets Nov 26, 12pm (America/Mazatlan)\n"
            ),
        })
        parsed = parse_claude_usage(raw, now_dt=now_ref)
        self.assertEqual(parsed["source"], "claude")
        bucket = parsed["limits"][0]
        self.assertEqual(bucket["primary"]["used_percent"], 2.0)
        self.assertEqual(bucket["primary"]["window_minutes"], 300)
        self.assertIsNotNone(bucket["primary"]["resets_at"])
        self.assertEqual(bucket["secondary"]["used_percent"], 15.0)
        self.assertEqual(bucket["secondary"]["window_minutes"], 10080)
        self.assertIsNotNone(bucket["secondary"]["resets_at"])
        with self.assertRaises(UsageError):
            parse_claude_usage("not-json")

    def test_parse_stream_error_and_tool_events(self):
        err_ev = parse_claude_stream_line(json.dumps({
            "type": "assistant",
            "error": "authentication_failed",
            "is_api_error_message": True,
            "message": {"content": [{"type": "text", "text": "Failed to authenticate"}]},
        }))
        self.assertEqual(len(err_ev), 1)
        self.assertEqual(err_ev[0]["type"], "error")
        self.assertIn("claude auth login", err_ev[0]["message"])


class ClaudeSubprocessTests(unittest.TestCase):
    def test_client_status_usage_stream_and_cancel(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_bin = _make_fake_claude_script(root)
            client = ClaudeClient(binary=str(fake_bin))
            self.assertTrue(client.is_available())
            self.assertTrue(client.auth_status()["authenticated"])

            usage = client.usage()
            self.assertEqual(usage["limits"][0]["primary"]["used_percent"], 14.0)
            self.assertEqual(usage["limits"][0]["secondary"]["used_percent"], 4.0)

            events = list(client.stream_turn("Hola", "claude-sonnet", root, StreamControl(), effort="low"))
            types = [e["type"] for e in events]
            self.assertIn("init", types)
            self.assertIn("text_delta", types)
            self.assertIn("tool_start", types)
            self.assertIn("tool_done", types)
            self.assertIn("result", types)

            cancel_control = StreamControl()
            started = time.monotonic()

            def _cancel():
                time.sleep(0.15)
                cancel_control.cancel()

            t = threading.Thread(target=_cancel, daemon=True)
            t.start()
            with self.assertRaises(Cancelled):
                for _ in client.stream_turn("SLEEP_CANCEL", "claude-sonnet", root, cancel_control):
                    pass
            t.join(2)
            self.assertLess(time.monotonic() - started, 3.0)

            old = os.environ.get("AGENT_SHELL_DISABLE_CLAUDE")
            try:
                os.environ["AGENT_SHELL_DISABLE_CLAUDE"] = "1"
                self.assertFalse(client.is_available())
            finally:
                if old is None:
                    os.environ.pop("AGENT_SHELL_DISABLE_CLAUDE", None)
                else:
                    os.environ["AGENT_SHELL_DISABLE_CLAUDE"] = old


class HarnessClaudeIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = QueueOutput()
        self.claude = _FakeClaudeClient(turns=[
            [
                {"type": "init", "session_id": "claude-sess-xyz", "model": "claude-sonnet-5-5"},
                {"type": "message_start", "session_id": "claude-sess-xyz", "message_id": "m1"},
                {"type": "tool_start", "session_id": "claude-sess-xyz", "tool_use_id": "tu1", "tool_name": "Bash", "parameters": {"command": "pwd"}},
                {"type": "tool_done", "session_id": "claude-sess-xyz", "tool_use_id": "tu1", "output": "/tmp/ws\n", "truncated": False, "is_error": False},
                {"type": "text_delta", "session_id": "claude-sess-xyz", "message_id": "m1", "text": "Hecho con Claude."},
                {"type": "assistant_text", "session_id": "claude-sess-xyz", "message_id": "m1", "text": "Hecho con Claude."},
                {"type": "usage", "session_id": "claude-sess-xyz", "usage": {"input_tokens": 4100, "output_tokens": 15, "total_tokens": 4115}},
                {"type": "result", "session_id": "claude-sess-xyz", "is_error": False, "result": "Hecho con Claude.", "error": "", "usage": {"input_tokens": 4100, "output_tokens": 15, "total_tokens": 4115}},
            ],
            [
                {"type": "init", "session_id": "claude-sess-xyz", "model": "claude-opus-5-5"},
                {"type": "text_delta", "session_id": "claude-sess-xyz", "message_id": "m2", "text": "Turno 2 con Opus."},
                {"type": "result", "session_id": "claude-sess-xyz", "is_error": False, "result": "Turno 2 con Opus.", "error": "", "usage": {"input_tokens": 4500, "output_tokens": 10, "total_tokens": 4510}},
            ],
        ])
        self.server = HarnessServer(
            self.root / "chats",
            self.output,
            _OfflineSession(),
            client=None,
            workspace=self.root,
            config_root=self.root / "config",
            claude_client=self.claude,
        )
        self.addCleanup(self._stop)

    def _stop(self):
        self.server._stream.cancel()
        self.server.project_runner.close()
        for worker in self.server._workers:
            worker.join(3)

    def test_select_claude_runs_tools_resumes_session_and_reads_usage(self):
        self.assertTrue(self.server.claude_available)
        self.server.handle({"type": "provider.select", "provider": "claude"})
        self.output.wait_for("provider.refresh.finished")
        self.assertEqual(self.server.provider, "claude")
        self.assertTrue(self.server.claude_authenticated)
        self.assertEqual(self.server.model, "claude-sonnet")

        # Turno 1 sin sesión de ChatGPT.
        self.server.handle({"type": "chat.send", "prompt": "Comprueba pwd"})
        finished = self.output.wait_for("chat.finished")
        self.assertEqual(finished["status"], "completed")
        self.assertEqual(self.claude.calls[0]["session_id"], "")
        self.assertEqual(self.claude.calls[0]["model"], "claude-sonnet")

        chat_id = self.server.conversation["chat_id"]
        saved = self.server.history.load(chat_id)
        self.assertEqual(saved["provider"], "claude")
        self.assertEqual(saved["claude_session_id"], "claude-sess-xyz")
        self.assertEqual(saved["messages"][-1]["text"], "Hecho con Claude.")
        self.assertEqual(len(saved["tool_calls"]), 1)
        self.assertEqual(saved["tool_calls"][0]["source"], "claude")
        self.assertEqual(saved["tool_calls"][0]["output"], "/tmp/ws\n")
        self.assertEqual(saved["performance"][-1]["context_tokens"], 4100)

        # Seleccionar Claude Opus con esfuerzo high y enviar turno 2: reutiliza claude_session_id.
        self.server.handle({"type": "model.select", "model": "claude-opus", "reasoning_effort": "high"})
        self.output.wait_for("model.selected")
        self.server.handle({"type": "chat.send", "prompt": "Continúa"})
        finished2 = self.output.wait_for("chat.finished")
        self.assertEqual(finished2["status"], "completed")
        self.assertEqual(self.claude.calls[1]["session_id"], "claude-sess-xyz")
        self.assertEqual(self.claude.calls[1]["model"], "claude-opus")
        self.assertEqual(self.claude.calls[1]["effort"], "high")

        # Consultar uso en Claude.
        self.server.handle({"type": "usage.read", "request_id": "claude-u1"})
        usage_state = self.output.wait_for("usage.state")
        self.output.wait_for("usage.finished")
        self.assertEqual(usage_state["source"], "claude")
        self.assertEqual(usage_state["limits"][0]["primary"]["used_percent"], 12.0)

        # Reinicio conserva proveedor, modelo y esfuerzo de Claude.
        restarted = HarnessServer(
            self.root / "chats",
            QueueOutput(),
            _OfflineSession(),
            client=None,
            workspace=self.root,
            config_root=self.root / "config",
            claude_client=self.claude,
        )
        self.assertEqual(restarted.provider, "claude")
        self.assertEqual(restarted.model, "claude-opus")
        self.assertEqual(restarted.reasoning_effort, "high")


if __name__ == "__main__":
    unittest.main()
