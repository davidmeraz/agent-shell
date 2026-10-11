"""Pruebas del chat contra el protocolo de Codex, sin consumir la cuenta del usuario."""

import io
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import Mock

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "backend"))

from harness.codex import CodexClient, CodexError
from harness.server import HarnessServer


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = io.StringIO()
        self.server = HarnessServer(Path(self.temp.name), self.output, ["codex"])
        self.server.client = Mock()
        self.server.ready = True
        self.server.authenticated = True

    def events(self):
        return [json.loads(line) for line in self.output.getvalue().splitlines()]

    def test_account_requires_chatgpt_and_never_forwards_credentials(self):
        for account in (None, {"type": "apiKey"}, {"type": "chatgpt", "email": "a@b.test",
                         "planType": "plus", "accessToken": "never-forward-this"}):
            self.server.client.request.return_value = {"account": account}
            self.server._read_account()
            self.assertEqual(self.server.authenticated, bool(account and account["type"] == "chatgpt"))
        self.assertNotIn("never-forward-this", self.output.getvalue())

    def test_invalid_requests_and_unauthenticated_chat_never_call_provider(self):
        for request in ([], None, {"type": "unknown"}, {"type": "chat.send", "prompt": " "},
                        {"type": "chat.send", "prompt": 42}, {"type": "chat.send", "prompt": "x" * 16001}):
            self.server.handle(request)
        self.server.authenticated = False
        self.server.handle({"type": "chat.send", "prompt": "hola"})
        self.server.client.request.assert_not_called()
        self.assertTrue(all(e["type"] == "error" for e in self.events()))

    def test_first_turn_creates_thread_and_followup_reuses_it(self):
        self.server.client.request.side_effect = [
            {"thread": {"id": "thread-a"}, "model": "configured-model"},
            {"turn": {"id": "turn-1"}}, {"turn": {"id": "turn-2"}},
        ]
        self.server.busy = True
        self.server._start_turn("hola '🎵'")
        self.server._finish("completed")
        self.server.busy = True
        self.server._start_turn("continúa")
        calls = self.server.client.request.call_args_list
        self.assertEqual([c.args[0] for c in calls], ["thread/start", "turn/start", "turn/start"])
        self.assertEqual(calls[2].args[1]["threadId"], "thread-a")
        self.assertEqual(calls[0].args[1]["sandbox"], "read-only")
        self.assertEqual(calls[0].args[1]["modelProvider"], "openai")
        self.assertTrue(calls[0].args[1]["ephemeral"])
        self.assertFalse(calls[0].args[1]["config"]["features"]["shell_tool"])

    def test_cancel_before_turn_creation_skips_inference(self):
        self.server.busy = True
        self.server._cancel_pending = True
        self.server.client.request.return_value = {"thread": {"id": "thread-a"}}
        self.server._start_turn("hola")
        self.assertEqual(self.server.client.request.call_count, 1)
        self.assertFalse(self.server.busy)
        self.assertEqual(self.events()[-1]["data"]["status"], "interrupted")

    def test_turn_start_failure_releases_chat(self):
        self.server.busy = True
        self.server.client.request.side_effect = CodexError("falló")
        with self.assertRaises(CodexError):
            self.server._start_turn("hola")
        self.assertFalse(self.server.busy)
        self.assertEqual(self.events()[-1]["data"]["status"], "failed")

    def test_stream_ignores_other_threads_and_preserves_final_message(self):
        self.server.thread_id = "thread-a"
        self.server.busy = True
        self.server._on_message({"method": "item/agentMessage/delta", "params": {
            "threadId": "other", "itemId": "a", "delta": "ignore"}})
        self.server._on_message({"method": "item/agentMessage/delta", "params": {
            "threadId": "thread-a", "itemId": "a", "delta": "Hola"}})
        self.server._on_message({"method": "item/completed", "params": {
            "threadId": "thread-a", "item": {"type": "agentMessage", "id": "a", "text": "Hola final"}}})
        self.assertEqual([e["type"] for e in self.events()], ["chat.delta", "chat.message"])
        self.assertEqual(self.events()[-1]["data"]["text"], "Hola final")

    def test_finished_notification_wins_race_against_turn_start_response(self):
        self.server.thread_id = "thread-a"
        self.server.busy = True

        def response(method, params):
            self.server._on_message({"method": "turn/completed", "params": {
                "threadId": "thread-a", "turn": {"id": "turn-a", "status": "completed"}}})
            return {"turn": {"id": "turn-a"}}

        self.server.client.request.side_effect = response
        self.server._start_turn("hola")
        self.assertFalse(self.server.busy)
        self.assertIsNone(self.server.turn_id)

    def test_login_uses_managed_flow_and_rejects_unexpected_url(self):
        self.server.login_pending = True
        self.server.client.request.return_value = {
            "authUrl": "https://auth.openai.com/test", "loginId": "login-a"}
        self.server._login()
        self.server.client.request.assert_called_with("account/login/start", {"type": "chatgpt"})
        self.assertEqual(self.events()[-1]["type"], "auth.login.started")
        self.server.client.request.return_value = {"authUrl": "https://evil.test", "loginId": "bad"}
        with self.assertRaises(CodexError):
            self.server._login()
        self.assertFalse(self.server.login_pending)

    def test_cancel_login_before_url_arrives_does_not_open_browser(self):
        self.server.login_pending = True
        self.server._login_cancel_pending = True
        self.server.client.request.side_effect = [
            {"authUrl": "https://auth.openai.com/test", "loginId": "login-a"}, {},
        ]
        self.server._login()
        self.server.client.request.assert_called_with("account/login/cancel", {"loginId": "login-a"})
        self.assertNotIn("auth.login.started", [e["type"] for e in self.events()])

    def test_old_turn_response_does_not_replace_new_turn_id(self):
        self.server.thread_id = "thread-a"
        self.server.busy = True
        self.server._generation = 1

        def delayed_response(method, params):
            self.server._generation = 2
            self.server.turn_id = "new-turn"
            return {"turn": {"id": "old-turn"}}

        self.server.client.request.side_effect = delayed_response
        self.server._start_turn("hola", generation=1)
        self.assertEqual(self.server.turn_id, "new-turn")
        self.assertTrue(self.server.busy)

    def test_malformed_and_oversize_input_do_not_break_protocol(self):
        self.server.client.request.side_effect = [
            {}, {"account": {"type": "chatgpt", "email": "test@example.invalid"}},
        ]
        self.server.serve(io.StringIO("invalid\n" + "x" * 70000 + '\n{"type":"chat.new"}\n'))
        self.assertEqual([e["type"] for e in self.events()],
                         ["backend.ready", "auth.state", "error", "error", "chat.reset"])

    def test_server_approval_requests_are_denied(self):
        self.server._on_message({"id": 9, "method": "item/commandExecution/requestApproval"})
        self.server.client.reply.assert_called_with(9, {"decision": "decline"})

    def test_new_chat_clears_context_and_is_rejected_while_busy(self):
        self.server.thread_id = "thread-a"
        self.server.busy = True
        self.server.handle({"type": "chat.new"})
        self.assertEqual(self.server.thread_id, "thread-a")
        self.server.busy = False
        self.server.handle({"type": "chat.new"})
        self.assertIsNone(self.server.thread_id)
        self.assertEqual(self.events()[-1]["type"], "chat.reset")


class TransportTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "linux", "Comprueba hijos mediante /proc en Linux")
    def test_sigterm_of_backend_also_terminates_codex_child(self):
        with tempfile.TemporaryDirectory() as chat_root:
            process = subprocess.Popen([
                sys.executable, "-u", str(PROJECT / "backend/main.py"),
                "--chat-root", chat_root, "--codex-executable", str(PROJECT / "tests/fake_codex.py"),
            ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            watchdog = threading.Timer(5, process.kill)
            watchdog.start()
            try:
                while json.loads(process.stdout.readline())["type"] != "auth.state":
                    pass
                child_pids = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
                self.assertEqual(len(child_pids), 1)
                process.terminate()
                self.assertEqual(process.wait(timeout=5), 0)
                with self.assertRaises(ProcessLookupError):
                    os.kill(int(child_pids[0]), 0)
            finally:
                watchdog.cancel()
                if process.poll() is None:
                    process.kill()
                    process.wait()
                for stream in (process.stdin, process.stdout, process.stderr):
                    stream.close()

    def test_rpc_error_and_timeout_do_not_hang(self):
        client = CodexClient([sys.executable, str(PROJECT / "tests/fake_codex.py")], lambda _: None, lambda: None)
        client.start()
        self.addCleanup(client.close)
        self.assertIn("userAgent", client.request("initialize"))
        with self.assertRaisesRegex(CodexError, "Método no simulado"):
            client.request("unknown")
        # initialized es una notificación: el doble ignora su id para este caso.
        client._write = Mock()
        with self.assertRaisesRegex(CodexError, "no respondió"):
            client.request("never-answered", timeout=0.01)

    def test_missing_executable_has_readable_error(self):
        client = CodexClient(["/nonexistent/agent-shell-codex"], lambda _: None, lambda: None)
        with self.assertRaisesRegex(CodexError, "No se pudo iniciar"):
            client.start()

    def test_stdio_backend_chat_and_cancel_with_real_child_process(self):
        with tempfile.TemporaryDirectory() as chat_root:
            process = subprocess.Popen([
                sys.executable, "-u", str(PROJECT / "backend/main.py"),
                "--chat-root", chat_root, "--codex-executable", str(PROJECT / "tests/fake_codex.py"),
            ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            events = queue.Queue()
            reader = threading.Thread(target=lambda: [events.put(json.loads(line)) for line in process.stdout], daemon=True)
            reader.start()

            def wait_for(event_type):
                while True:
                    event = events.get(timeout=5)
                    if event["type"] == event_type:
                        return event

            def send(command):
                process.stdin.write(json.dumps(command) + "\n")
                process.stdin.flush()

            try:
                self.assertEqual(wait_for("auth.state")["data"]["method"], "chatgpt")
                send({"type": "chat.send", "prompt": "hola"})
                self.assertEqual(wait_for("chat.finished")["data"]["status"], "completed")
                send({"type": "chat.send", "prompt": "cancel"})
                wait_for("chat.delta")
                send({"type": "chat.cancel"})
                self.assertEqual(wait_for("chat.finished")["data"]["status"], "interrupted")
                process.stdin.close()
                self.assertEqual(process.wait(timeout=5), 0)
                self.assertEqual(process.stderr.read(), "")
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                reader.join(timeout=2)
                for stream in (process.stdin, process.stdout, process.stderr):
                    stream.close()


if __name__ == "__main__":
    unittest.main()
