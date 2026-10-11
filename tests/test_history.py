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

from harness.history import HistoryStore
from test_harness import BackendSession


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

    def test_delete_removes_only_selected_chat_and_survives_restart(self):
        removed = self.store.create("borrar")
        kept = self.store.create("conservar")
        self.store.delete(removed["chat_id"])
        reopened = HistoryStore(self.store.root)
        self.assertEqual([chat["chat_id"] for chat in reopened.list()], [kept["chat_id"]])
        with self.assertRaises(FileNotFoundError):
            reopened.load(removed["chat_id"])
        with self.assertRaises(FileNotFoundError):
            reopened.delete(removed["chat_id"])

    def test_delete_rejects_invalid_ids_and_symlinks_without_touching_other_files(self):
        record = self.store.create("conservar")
        outside = Path(self.temp.name) / "outside.json"
        outside.write_text("keep")
        link = self.store.root / ("a" * 32 + ".json")
        link.symlink_to(outside)
        for chat_id in (None, [], "../outside", str(outside), "", "A" * 32, "a" * 32):
            with self.subTest(chat_id=chat_id), self.assertRaises(ValueError):
                self.store.delete(chat_id)
        self.assertTrue(link.is_symlink())
        self.assertEqual(outside.read_text(), "keep")
        self.assertEqual(self.store.list()[0]["chat_id"], record["chat_id"])

    @unittest.skipUnless(os.name == "posix", "Permisos de archivo POSIX")
    def test_history_file_has_owner_only_permissions(self):
        record = self.store.create("private")
        path = self.store.root / f"{record['chat_id']}.json"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)


class RestartTests(unittest.TestCase):
    def test_deleted_chat_and_metrics_stay_removed_after_backend_restart(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with BackendSession(root) as session:
                session.send({"type": "chat.send", "prompt": "borrar"})
                chat_id = session.wait_for("chat.saved")["data"]["chat_id"]
                session.wait_for("chat.finished")
                session.send({"type": "chat.delete", "chat_id": chat_id})
                session.wait_for("chat.reset")
                self.assertEqual(session.wait_for("chat.deleted")["data"]["chat_id"], chat_id)
                self.assertEqual(session.wait_for("history.list")["data"]["chats"], [])
                self.assertEqual(session.wait_for("performance.list")["data"]["measurements"], [])
            with BackendSession(root) as session:
                session.send({"type": "history.list"})
                self.assertEqual(session.wait_for("history.list")["data"]["chats"], [])
                session.send({"type": "performance.list"})
                self.assertEqual(session.wait_for("performance.list")["data"]["measurements"], [])
            self.assertEqual(list((root / "chats").glob("*.json")), [])

    def test_chat_survives_restart_and_continues_without_codex_thread(self):
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
                self.assertEqual(loaded["performance"], first["performance"])
                session.send({"type": "chat.send", "prompt": "continúa"})
                self.assertEqual(session.wait_for("chat.finished")["data"]["status"], "completed")
            final = HistoryStore(root / "chats").load(chat_id)
            self.assertEqual(len(final["messages"]), 4)
            self.assertEqual(len(final["performance"]), 2)
            self.assertEqual(len(list((root / "chats").glob("*.json"))), 1)
