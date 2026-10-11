"""Chat HTTP/SSE, contrato Qt y ciclo de vida sin Codex ni una cuenta real."""

import io
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "backend"))

from fake_service import FakeService, FakeSession
from harness.chatgpt import ChatGPTClient
from harness.http import HttpClient, ServiceError, StreamControl, read_sse, service_error
from harness.server import HarnessServer


class QueueOutput(io.StringIO):
    def __init__(self):
        super().__init__()
        self.events = queue.Queue()

    def write(self, text):
        result = super().write(text)
        self.events.put(json.loads(text))
        return result

    def wait_for(self, kind):
        deadline = time.monotonic() + 5
        while True:
            event = self.events.get(timeout=max(0.001, deadline - time.monotonic()))
            if event["type"] == kind:
                return event["data"]


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.service = FakeService().__enter__()
        self.addCleanup(self.service.__exit__)
        self.output = QueueOutput()
        self.session = FakeSession()
        self.client = ChatGPTClient(self.session, HttpClient(allow_loopback=True, timeout=2), self.service.url)
        self.server = HarnessServer(Path(self.temp.name), self.output, self.session, self.client)
        self.server._refresh_account()
        self.addCleanup(self.stop)

    def stop(self):
        self.server._stream.cancel()
        for worker in self.server._workers:
            worker.join(timeout=3)

    def send(self, prompt):
        self.server.handle({"type": "chat.send", "prompt": prompt})
        return self.output.wait_for("chat.finished")

    def test_stream_and_followup_send_local_context_without_remote_thread(self):
        self.assertEqual(self.send("hola")["status"], "completed")
        self.assertEqual(self.send("continúa")["status"], "completed")
        request = self.service.requests[-1]
        self.assertEqual(request["path"], "/v1/responses")
        self.assertEqual(request["authorization"], "Bearer test-only-access-token")
        self.assertFalse(request["body"]["store"])
        self.assertTrue(request["body"]["stream"])
        self.assertNotIn("tools", request["body"])
        self.assertEqual([item["role"] for item in request["body"]["input"]], ["user", "assistant", "user"])
        self.assertEqual(request["body"]["input"][1]["content"], "Hola desde ChatGPT. 🎵")
        self.assertEqual(len(self.server.conversation["messages"]), 4)

    def test_cancel_closes_http_stream_and_keeps_partial_answer(self):
        self.server.handle({"type": "chat.send", "prompt": "cancel"})
        self.output.wait_for("chat.delta")
        self.server.handle({"type": "chat.cancel"})
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "interrupted")
        self.assertTrue(self.service.disconnected.wait(2))
        saved = self.server.history.load(self.server.conversation["chat_id"])
        self.assertEqual(saved["messages"][-1]["text"], "Hola ")
        self.assertEqual(saved["messages"][-1]["status"], "interrupted")
        self.assertEqual(self.send("otra vez")["status"], "completed")

    def test_stream_without_content_type_still_reads_events_and_completes(self):
        self.service.stream_content_type = None
        self.assertEqual(self.send("hola")["status"], "completed")
        self.assertEqual(self.server.conversation["messages"][-1]["text"], "Hola desde ChatGPT. 🎵")
        self.assertEqual(self.server.conversation["messages"][-1]["status"], "completed")

    def test_stream_without_content_type_still_requires_completed_event(self):
        self.service.stream_content_type = None
        self.assertEqual(self.send("disconnect")["status"], "failed")

    def test_stream_with_explicit_incompatible_content_type_is_rejected(self):
        self.service.stream_content_type = "application/json"
        result = self.send("hola")
        self.assertEqual(result["status"], "failed")
        self.assertIn("respuesta progresiva", result["message"])

    def test_failed_incomplete_and_disconnected_stream_are_not_success(self):
        for prompt in ("fail", "incomplete", "disconnect"):
            with self.subTest(prompt=prompt):
                result = self.send(prompt)
                self.assertEqual(result["status"], "failed")
                self.assertNotIn("private diagnostics", result["message"])
                self.assertFalse(self.server.busy)

    def test_old_events_cannot_mutate_next_response(self):
        self.send("hola")
        self.server.busy = True
        self.server._generation += 1
        before = len(self.server.conversation["messages"])
        stopped = self.server._response_event({"type": "response.output_text.delta",
                                              "item_id": "late", "delta": "ignore"}, self.server._generation - 1)
        self.assertTrue(stopped)
        self.assertEqual(len(self.server.conversation["messages"]), before)
        self.assertTrue(self.server.busy)
        self.server.busy = False

    def test_history_from_codex_version_continues_using_saved_messages(self):
        record = self.server.history.create("Chat anterior")
        record.update(thread_id="old-codex-thread", model="old-model")
        record["messages"] = [
            {"id": "u", "role": "user", "text": "Pregunta anterior", "status": "completed"},
            {"id": "a", "role": "assistant", "text": "Respuesta anterior", "status": "completed"},
        ]
        self.server.history.save(record)
        self.server.handle({"type": "chat.open", "chat_id": record["chat_id"]})
        self.assertEqual(self.send("continúa")["status"], "completed")
        inputs = self.service.requests[-1]["body"]["input"]
        self.assertEqual([item["content"] for item in inputs], ["Pregunta anterior", "Respuesta anterior", "continúa"])
        self.assertEqual(self.server.conversation["chat_id"], record["chat_id"])

    def test_offline_history_browsing_and_validation_do_not_call_service(self):
        record = self.server.history.create("Sin conexión")
        self.server.authenticated = False
        self.server.handle({"type": "chat.open", "chat_id": record["chat_id"]})
        self.assertEqual(self.server.conversation["chat_id"], record["chat_id"])
        for prompt in ("hola", "", "x" * 16001, None):
            self.server.handle({"type": "chat.send", "prompt": prompt})
            self.assertEqual(self.output.wait_for("chat.finished")["status"], "failed")
        self.assertEqual(self.service.requests, [])

    def test_model_selector_accepts_only_visible_account_models(self):
        self.assertEqual([row["slug"] for row in self.server.models], ["test-model", "other-model"])
        self.server.handle({"type": "model.select", "model": "hidden-model"})
        self.assertEqual(self.server.model, "test-model")
        self.server.handle({"type": "model.select", "model": "other-model"})
        self.send("hola")
        self.assertEqual(self.service.requests[-1]["body"]["model"], "other-model")

    def test_delete_active_chat_clears_context_metrics_and_ignores_late_events(self):
        self.send("borrar")
        chat_id = self.server.conversation["chat_id"]
        turn_id = self.server._performance.turn_id
        generation = self.server._generation
        self.server.handle({"type": "chat.delete", "chat_id": chat_id})
        self.assertEqual(self.output.wait_for("chat.deleted")["chat_id"], chat_id)
        self.assertIsNone(self.server.conversation)
        self.assertIsNone(self.server._performance)
        self.assertEqual(self.server.history.list(), [])
        self.assertEqual(self.output.wait_for("performance.list")["measurements"], [])
        self.server.handle({"type": "performance.presented", "turn_id": turn_id,
                            "first_visible_ms": 250, "ui_frame_ms": 12})
        self.server._response_event({"type": "response.completed", "response": {"status": "completed"}}, generation)
        self.assertEqual(list(self.server.history.root.glob("*.json")), [])
        self.send("nuevo")
        self.assertNotEqual(self.server.conversation["chat_id"], chat_id)
        self.assertEqual(len(self.service.requests[-1]["body"]["input"]), 1)

    def test_delete_inactive_chat_preserves_current_context_and_works_offline(self):
        self.send("conservar")
        current = self.server.conversation
        metrics = self.server._performance
        other = self.server.history.create("borrar")
        self.server.authenticated = False
        requests = len(self.service.requests)
        self.server.handle({"type": "chat.delete", "chat_id": other["chat_id"]})
        self.assertEqual(self.output.wait_for("chat.deleted")["chat_id"], other["chat_id"])
        self.assertIs(self.server.conversation, current)
        self.assertIs(self.server._performance, metrics)
        self.assertEqual(self.server.history.list()[0]["chat_id"], current["chat_id"])
        self.assertEqual(len(self.output.wait_for("performance.list")["measurements"]), 1)
        self.assertEqual(len(self.service.requests), requests)

    def test_delete_failure_preserves_active_chat_and_reports_error(self):
        self.send("conservar")
        current = self.server.conversation
        metrics = self.server._performance
        with patch.object(self.server.history, "delete", side_effect=OSError("permission denied")):
            self.server.handle({"type": "chat.delete", "chat_id": current["chat_id"]})
        self.assertIn("No se pudo borrar", self.output.wait_for("error")["message"])
        self.assertIs(self.server.conversation, current)
        self.assertIs(self.server._performance, metrics)
        self.assertEqual(len(self.server.history.list()), 1)
        events = [json.loads(line)["type"] for line in self.output.getvalue().splitlines()]
        self.assertNotIn("chat.deleted", events)
        self.assertNotIn("chat.reset", events)

    def test_delete_is_rejected_during_streaming_or_login(self):
        record = self.server.history.create("conservar")
        for field in ("busy", "login_pending"):
            with self.subTest(field=field):
                setattr(self.server, field, True)
                self.server.handle({"type": "chat.delete", "chat_id": record["chat_id"]})
                self.assertIn("Espera", self.output.wait_for("error")["message"])
                self.assertEqual(self.server.history.load(record["chat_id"])["title"], "conservar")
                setattr(self.server, field, False)

    def test_missing_or_invalid_delete_target_does_not_clear_active_chat(self):
        self.send("conservar")
        current = self.server.conversation
        for chat_id in (None, "../outside", "a" * 32):
            with self.subTest(chat_id=chat_id):
                self.server.handle({"type": "chat.delete", "chat_id": chat_id})
                self.assertIn("No se pudo borrar", self.output.wait_for("error")["message"])
                self.assertIs(self.server.conversation, current)
        self.assertEqual(len(self.server.history.list()), 1)

    def test_shutdown_preserves_partial_text(self):
        self.server.handle({"type": "chat.send", "prompt": "cancel"})
        self.output.wait_for("chat.delta")
        self.server.serve(io.StringIO(""))
        record = self.server.history.load(self.server.conversation["chat_id"])
        self.assertEqual(record["messages"][-1]["status"], "interrupted")

    def test_stream_fragments_are_saved_in_batches_and_on_completion(self):
        self.server.client = Mock()
        events = [{"type": "response.output_text.delta", "item_id": "a", "delta": "x"} for _ in range(100)]
        events.append({"type": "response.completed", "response": {"status": "completed"}})
        self.server.client.stream.return_value = iter(events)
        original = self.server.history.save
        self.server.history.save = Mock(wraps=original)
        self.send("hola")
        self.assertLess(self.server.history.save.call_count, 10)
        saved = self.server.history.load(self.server.conversation["chat_id"])
        self.assertEqual(saved["messages"][-1]["text"], "x" * 100)

    def test_performance_counts_usage_context_and_saves_only_one_measurement_per_turn(self):
        self.send("hola")
        first = self.server.conversation["performance"][0]
        self.assertEqual(first["status"], "completed")
        self.assertEqual(first["characters"], len("Hola desde ChatGPT. 🎵"))
        self.assertEqual(first["input_characters"], len("hola"))
        self.assertEqual(first["context_messages"], 1)
        self.assertEqual(first["usage"]["reasoning_tokens"], 2)
        for key in ("prepare_ms", "session_ms", "headers_ms", "first_text_ms", "request_first_text_ms", "total_ms"):
            self.assertGreaterEqual(first[key], 0)
        self.assertGreaterEqual(first["first_text_ms"], first["prepare_ms"])
        self.send("continúa")
        self.assertEqual(len(self.server.conversation["performance"]), 2)
        second = self.server.conversation["performance"][1]
        self.assertEqual(second["context_messages"], 3)
        self.assertNotEqual(first["turn_id"], second["turn_id"])
        self.assertEqual(self.server.conversation["messages"][1]["turn_id"], first["turn_id"])
        saved = self.server.history.load(self.server.conversation["chat_id"])
        self.assertEqual(saved["performance"], self.server.conversation["performance"])
        self.assertNotIn("test-only-access-token", str(saved["performance"]))

    def test_failed_and_cancelled_turns_keep_distinct_metrics_and_partial_counts(self):
        self.send("fail")
        self.assertEqual(self.server.conversation["performance"][-1]["status"], "failed")
        self.server.handle({"type": "chat.send", "prompt": "cancel"})
        self.output.wait_for("chat.delta")
        self.server.handle({"type": "chat.cancel"})
        self.output.wait_for("chat.finished")
        row = self.server.conversation["performance"][-1]
        self.assertEqual(row["status"], "interrupted")
        self.assertEqual(row["characters"], 5)
        self.assertIsNone(row["usage"])
        before = self.server.conversation["performance"].copy()
        self.server._response_event({"type": "response.output_text.delta", "item_id": "late", "delta": "ignore"}, self.server._generation)
        self.assertEqual(self.server.conversation["performance"], before)

    def test_presentation_ack_is_saved_after_completion_and_stale_ack_is_ignored(self):
        self.send("hola")
        turn = self.server.conversation["performance"][-1]["turn_id"]
        self.server.handle({"type": "performance.presented", "turn_id": turn, "first_visible_ms": 250, "ui_frame_ms": 12})
        saved = self.server.history.load(self.server.conversation["chat_id"])
        self.assertEqual(saved["performance"][-1]["ui_frame_ms"], 12)
        self.send("continúa")
        self.server.handle({"type": "performance.presented", "turn_id": turn, "first_visible_ms": 900, "ui_frame_ms": 50})
        row = self.server.conversation["performance"][-1]
        self.assertIsNone(row["first_visible_ms"])
        self.server.handle({"type": "performance.list"})
        listed = self.output.wait_for("performance.list")["measurements"]
        self.assertEqual(len(listed), 2)
        self.assertNotIn("continúa", str(listed))

    def test_performance_list_can_be_read_offline_and_does_not_call_service(self):
        self.send("hola")
        self.server.authenticated = False
        before = len(self.service.requests)
        self.server.handle({"type": "performance.list"})
        self.assertEqual(len(self.output.wait_for("performance.list")["measurements"]), 1)
        self.assertEqual(len(self.service.requests), before)

    def test_performance_without_deltas_measures_final_text_and_no_invented_speed(self):
        self.server.client = Mock()
        self.server.client.stream.return_value = iter([{"type": "response.completed", "response": {
            "status": "completed", "output": [{"id": "final-only", "type": "message", "role": "assistant",
            "content": [{"type": "output_text", "text": "Hola"}]}]}}])
        self.send("hola")
        row = self.server.conversation["performance"][-1]
        self.assertEqual(row["characters"], 4)
        self.assertIsNotNone(row["first_text_ms"])
        self.assertIsNone(row["characters_per_second"])
        self.assertIsNone(row["usage"])

    def test_failure_before_text_keeps_unknown_timings_and_initial_measurement_is_persisted(self):
        self.server._spawn = Mock()
        self.server.handle({"type": "chat.send", "prompt": "hola"})
        saved = self.server.history.load(self.server.conversation["chat_id"])
        self.assertEqual(saved["performance"][-1]["status"], "streaming")
        self.assertEqual(saved["performance"][-1]["input_characters"], 4)
        self.server.client = Mock()
        self.server.client.stream.side_effect = ServiceError("Sin conexión")
        self.server._start_turn([], self.server.model, self.server._stream, self.server._generation)
        row = self.server.conversation["performance"][-1]
        self.assertEqual(row["status"], "failed")
        self.assertEqual(row["characters"], 0)
        self.assertIsNone(row["first_text_ms"])
        self.assertIsNone(row["headers_ms"])

    def test_failed_initial_save_does_not_leave_phantom_measurement_or_call_openai(self):
        self.send("hola")
        before = self.server.conversation["performance"].copy()
        requests = len(self.service.requests)
        with patch.object(self.server.history, "save", side_effect=OSError("disk full")):
            self.assertEqual(self.send("otra")["status"], "failed")
        self.assertEqual(self.server.conversation["performance"], before)
        self.assertEqual(len(self.service.requests), requests)


class SSETests(unittest.TestCase):
    def test_multiline_unicode_comments_and_done(self):
        source = io.BytesIO(': heartbeat\r\nevent: response.output_text.delta\r\ndata: {"type":\r\ndata: "test", "text": "🎵"}\r\n\r\ndata: [DONE]\n\n'.encode())
        self.assertEqual(list(read_sse(source)), [{"type": "test", "text": "🎵"}])

    def test_malformed_truncated_and_oversize_events_fail(self):
        for payload in (b"data: broken\n\n", b'data: {"type":"test"}\n', b"x" * (1024 * 1024 + 1)):
            with self.subTest(size=len(payload)), self.assertRaises(ServiceError):
                list(read_sse(io.BytesIO(payload)))

    def test_http_errors_do_not_expose_provider_diagnostics(self):
        self.assertNotIn("secret-token", str(service_error(401, {"code": "secret-token", "message": "secret-token"})))

    def test_production_transport_rejects_plaintext_connections(self):
        with self.assertRaises(ServiceError):
            HttpClient().json("GET", "http://127.0.0.1:9/v1/models")


class BackendSession:
    def __init__(self, root):
        self.process = subprocess.Popen([sys.executable, "-u", str(PROJECT / "tests/fake_backend.py")],
            env={**os.environ, "AGENT_SHELL_HISTORY_DIR": str(root / "chats")},
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.events = queue.Queue()
        self.reader = threading.Thread(
            target=lambda: [self.events.put(json.loads(line)) for line in self.process.stdout], daemon=True)
        self.reader.start()

    def __enter__(self):
        self.wait_for("auth.refresh.finished")
        return self

    def send(self, message):
        self.process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
        self.process.stdin.flush()

    def wait_for(self, kind):
        while True:
            event = self.events.get(timeout=5)
            if event["type"] == kind:
                return event

    def __exit__(self, *args):
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.reader.join(timeout=2)
        errors = self.process.stderr.read()
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()
        if not args and errors:
            raise AssertionError(errors)


class ProcessTests(unittest.TestCase):
    def test_real_backend_starts_without_codex_and_does_not_spawn_children(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            process = subprocess.Popen([sys.executable, "-u", str(PROJECT / "backend/main.py"),
                "--session-root", str(root / "session"), "--history-root", str(root / "chats")],
                env={**os.environ, "PATH": str(root)}, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True)
            try:
                while json.loads(process.stdout.readline())["type"] != "auth.refresh.finished":
                    pass
                if sys.platform == "linux":
                    self.assertEqual(Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().strip(), "")
                process.terminate()
                self.assertEqual(process.wait(timeout=5), 0)
                self.assertEqual(process.stderr.read(), "")
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                for stream in (process.stdin, process.stdout, process.stderr):
                    stream.close()

    def test_malformed_and_oversize_input_do_not_break_protocol(self):
        session, client, output = FakeSession(), Mock(), QueueOutput()
        session.connected = False
        with tempfile.TemporaryDirectory() as temporary:
            server = HarnessServer(Path(temporary), output, session, client)
            server.serve(io.StringIO("invalid\n" + "x" * 70000 + '\n{"type":"chat.new"}\n'))
            types = [json.loads(line)["type"] for line in output.getvalue().splitlines()]
            self.assertEqual(types.count("error"), 2)
            self.assertIn("chat.reset", types)
            client.stream.assert_not_called()

    def test_invalid_session_does_not_prevent_reading_local_history(self):
        from harness.auth import ChatGPTSession
        session, client, output = Mock(spec=ChatGPTSession), Mock(), QueueOutput()
        session.account.side_effect = ServiceError("invalid session")
        with tempfile.TemporaryDirectory() as temporary:
            server = HarnessServer(Path(temporary), output, session, client)
            record = server.history.create("Existing chat")
            server.serve(io.StringIO(json.dumps({"type": "chat.open", "chat_id": record["chat_id"]}) + "\n"))
            self.assertEqual(server.conversation["chat_id"], record["chat_id"])
            client.stream.assert_not_called()
