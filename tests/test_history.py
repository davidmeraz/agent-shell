"""Persistencia, recuperación y continuación del historial sin una cuenta real."""

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
from unittest.mock import Mock, patch

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "backend"))

from harness.codex import CodexError
from harness.history import HistoryStore
from harness.server import HarnessServer


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.store = HistoryStore(Path(self.temp.name) / "chats")

    def test_unicode_messages_survive_new_store_instance(self):
        record = self.store.create("Una aplicación 🎵\ncon historial")
        record["messages"].append({"id": "a", "role": "user", "text": "¿Cómo estás? 🎵", "status": "completed"})
        record["thread_id"] = "thread-a"
        self.store.save(record)
        reopened = HistoryStore(self.store.root)
        self.assertEqual(reopened.load(record["chat_id"])["messages"], record["messages"])
        self.assertEqual(reopened.list()[0]["title"], "Una aplicación 🎵 con historial")
        self.assertNotIn("messages", reopened.list()[0])

    def test_atomic_write_failure_preserves_previous_json_and_cleans_temporary(self):
        record = self.store.create("original")
        original = self.store.load(record["chat_id"])
        record["title"] = "replacement"
        with patch("harness.history.os.replace", side_effect=OSError("disk error")):
            with self.assertRaises(OSError):
                self.store.save(record)
        self.assertEqual(self.store.load(record["chat_id"]), original)
        self.assertEqual(list(self.store.root.glob("*.tmp")), [])

    def test_bad_json_does_not_hide_valid_chat_and_is_preserved(self):
        good = self.store.create("válido")
        bad = self.store.root / ("a" * 32 + ".json")
        bad.write_text("{unfinished", encoding="utf-8")
        self.assertEqual([row["chat_id"] for row in self.store.list()], [good["chat_id"]])
        self.assertEqual(self.store.invalid_files, [bad.name])
        self.assertEqual(bad.read_text(), "{unfinished")

    def test_invalid_ids_and_symlinks_cannot_read_outside_history(self):
        for chat_id in (None, [], "../outside", "/tmp/outside", "", "A" * 32):
            with self.subTest(chat_id=chat_id), self.assertRaises(ValueError):
                self.store.load(chat_id)
        outside = Path(self.temp.name) / "outside.json"
        outside.write_text("{}")
        (self.store.root / ("a" * 32 + ".json")).symlink_to(outside)
        with self.assertRaises(ValueError):
            self.store.load("a" * 32)

    def test_bad_message_schema_is_rejected_without_modifying_file(self):
        record = self.store.create("test")
        record["messages"] = [{"id": "a", "role": "unknown", "text": 42}]
        self.store.save(record)
        path = self.store.root / f"{record['chat_id']}.json"
        before = path.read_bytes()
        with self.assertRaises(ValueError):
            self.store.load(record["chat_id"])
        self.assertEqual(path.read_bytes(), before)

    @unittest.skipUnless(os.name == "posix", "Permisos de archivo POSIX")
    def test_history_file_has_owner_only_permissions(self):
        record = self.store.create("private")
        path = self.store.root / f"{record['chat_id']}.json"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)


class HistoryServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = io.StringIO()
        self.server = HarnessServer(Path(self.temp.name), self.output, ["codex"])
        self.server.client = Mock()
        self.record = self.server.history.create("Mi chat")
        self.record.update(thread_id="stored-thread", model="stored-model")
        self.record["messages"] = [{"id": "first", "role": "user", "text": "Mi chat", "status": "completed"}]
        self.server.history.save(self.record)

    def events(self):
        return [json.loads(line) for line in self.output.getvalue().splitlines()]

    def test_offline_chat_can_be_opened_without_calling_codex(self):
        self.server.handle({"type": "chat.open", "chat_id": self.record["chat_id"]})
        self.assertEqual(self.events()[-1]["type"], "chat.loaded")
        self.assertEqual(self.server.conversation["messages"], self.record["messages"])
        self.server.client.request.assert_not_called()

    def test_reopened_chat_resumes_original_thread(self):
        self.server._open_chat(self.record["chat_id"])
        self.server.busy = True
        self.server.client.request.side_effect = [
            {"thread": {"id": "stored-thread"}, "model": "stored-model"},
            {"turn": {"id": "turn-a"}},
        ]
        self.server._start_turn("continúa")
        calls = self.server.client.request.call_args_list
        self.assertEqual([call.args[0] for call in calls], ["thread/resume", "turn/start"])
        self.assertEqual(calls[0].args[1]["threadId"], "stored-thread")

    def test_missing_codex_thread_does_not_replace_local_context(self):
        self.server._open_chat(self.record["chat_id"])
        self.server.busy = True
        self.server.client.request.side_effect = CodexError("Thread no encontrado")
        with self.assertRaises(CodexError):
            self.server._start_turn("continúa")
        self.assertEqual(self.server._resume_thread_id, "stored-thread")
        self.assertIsNone(self.server.thread_id)
        self.assertFalse(self.server.busy)
        self.assertEqual(self.server.history.load(self.record["chat_id"])["messages"], self.record["messages"])

    def test_interrupted_response_keeps_partial_text_without_duplicate_message(self):
        self.server._open_chat(self.record["chat_id"])
        self.server.thread_id = "stored-thread"
        self.server.busy = True
        for text in ("Hola ", "mundo"):
            self.server._on_message({"method": "item/agentMessage/delta", "params": {
                "threadId": "stored-thread", "itemId": "assistant-a", "delta": text}})
        self.server._finish("interrupted")
        saved = self.server.history.load(self.record["chat_id"])
        self.assertEqual(len(saved["messages"]), 2)
        self.assertEqual(saved["messages"][-1]["text"], "Hola mundo")
        self.assertEqual(saved["messages"][-1]["status"], "interrupted")


class BackendSession:
    """Proceso real del puente con directorios temporales y Codex de prueba."""

    def __init__(self, root):
        self.process = subprocess.Popen([
            sys.executable, "-u", str(PROJECT / "backend/main.py"),
            "--chat-root", str(root / "context"), "--history-root", str(root / "chats"),
            "--codex-executable", str(PROJECT / "tests/fake_codex.py"),
        ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.events = queue.Queue()
        self.reader = threading.Thread(
            target=lambda: [self.events.put(json.loads(line)) for line in self.process.stdout], daemon=True,
        )
        self.reader.start()

    def __enter__(self):
        self.wait_for("auth.state")
        return self

    def send(self, message):
        self.process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
        self.process.stdin.flush()

    def wait_for(self, event_type):
        while True:
            event = self.events.get(timeout=5)
            if event["type"] == event_type:
                return event

    def __exit__(self, *args):
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.reader.join(timeout=2)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()


class RestartTests(unittest.TestCase):
    def test_chat_survives_backend_restart_and_can_continue(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with BackendSession(root) as session:
                session.send({"type": "chat.send", "prompt": "historial 🎵"})
                chat_id = session.wait_for("chat.saved")["data"]["chat_id"]
                self.assertEqual(session.wait_for("chat.finished")["data"]["status"], "completed")
            first = HistoryStore(root / "chats").load(chat_id)
            self.assertEqual(len(first["messages"]), 2)
            with BackendSession(root) as session:
                session.send({"type": "chat.open", "chat_id": chat_id})
                loaded = session.wait_for("chat.loaded")["data"]["chat"]
                self.assertEqual(loaded["messages"], first["messages"])
                session.send({"type": "chat.send", "prompt": "continúa"})
                self.assertEqual(session.wait_for("chat.finished")["data"]["status"], "completed")
            final = HistoryStore(root / "chats").load(chat_id)
            self.assertEqual(final["thread_id"], first["thread_id"])
            self.assertEqual(len(final["messages"]), 4)
            self.assertEqual(len(list((root / "chats").glob("*.json"))), 1)
