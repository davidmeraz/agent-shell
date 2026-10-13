"""Exploración acotada, rutas confinadas y contrato sin inferencia ni historial."""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tests.support.paths import PROJECT
from harness.work.explorer import ProjectExplorer, MAX_PREVIEW
from harness.core.server import HarnessServer
from tests.support.fake_service import FakeSession
from tests.support.sessions import QueueOutput


class ExplorerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "project"
        self.root.mkdir()
        self.explorer = ProjectExplorer(self.root)

    def test_lazy_sorted_listing_exclusions_and_changes(self):
        (self.root / "src").mkdir()
        (self.root / "z.txt").write_text("hola", encoding="utf-8")
        for name in (".git", "node_modules", ".runtime"):
            (self.root / name).mkdir()
        self.assertEqual([e["name"] for e in self.explorer.list("")["entries"]], ["src", "z.txt"])
        self.assertEqual(self.explorer.list("src")["entries"], [])
        (self.root / "src" / "nuevo.py").write_text("print('🎵')", encoding="utf-8")
        row = self.explorer.list("src")["entries"][0]
        self.assertEqual(row["path"], "src/nuevo.py")
        self.assertIsInstance(row["modified_ns"], str)
        (self.root / "src" / "nuevo.py").rename(self.root / "src" / "otro.py")
        self.assertEqual(self.explorer.list("src")["entries"][0]["name"], "otro.py")
        (self.root / "src" / "otro.py").unlink()
        self.assertEqual(self.explorer.list("src")["entries"], [])

    def test_text_preview_size_binary_and_invalid_utf8(self):
        path = self.root / "file"
        path.write_text("<b>texto</b> 🎵", encoding="utf-8")
        self.assertEqual(self.explorer.read("file")["text"], "<b>texto</b> 🎵")
        path.write_bytes(b"a" * (MAX_PREVIEW + 10))
        self.assertTrue(self.explorer.read("file")["truncated"])
        self.assertEqual(len(self.explorer.read("file")["text"]), MAX_PREVIEW)
        for data in (b"a\0b", b"\xff"):
            path.write_bytes(data)
            with self.assertRaises(ValueError):
                self.explorer.read("file")

    def test_paths_symlinks_and_special_files_rejected(self):
        outside = self.root.parent / "outside"
        outside.mkdir()
        (outside / "secret").write_text("no", encoding="utf-8")
        (self.root / "link").symlink_to(outside, target_is_directory=True)
        (self.root / "file-link").symlink_to(outside / "secret")
        os.mkfifo(self.root / "pipe")
        self.assertEqual(self.explorer.list("")["entries"], [])
        for path in ("../outside/secret", str(outside / "secret"), "link/secret", "file-link", "pipe", "", "x\0"):
            with self.subTest(path=path), self.assertRaises((ValueError, OSError)):
                self.explorer.read(path)
        for path in ("../outside", "link", ".git", None):
            with self.subTest(path=path), self.assertRaises((ValueError, OSError)):
                self.explorer.list(path)

    def test_listing_is_bounded(self):
        for index in range(4):
            (self.root / str(index)).touch()
        with patch("harness.work.explorer.MAX_ENTRIES", 3):
            result = self.explorer.list("")
        self.assertEqual(len(result["entries"]), 3)
        self.assertTrue(result["truncated"])

    def test_symlink_swap_during_open_does_not_escape(self):
        (self.root / "src").mkdir()
        outside = self.root.parent / "outside"
        outside.mkdir()
        (outside / "secret").write_text("private", encoding="utf-8")
        original = os.open
        def swapping(path, flags, *args, **kwargs):
            if path == "src":
                (self.root / "src").rmdir()
                (self.root / "src").symlink_to(outside, target_is_directory=True)
            return original(path, flags, *args, **kwargs)
        with patch("harness.work.explorer.os.open", side_effect=swapping), self.assertRaises(OSError):
            self.explorer.read("src/secret")


class ExplorerContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folder = self.root / "project"
        self.folder.mkdir()
        self.output = QueueOutput()
        self.server = HarnessServer(self.root / "chats", self.output, FakeSession(), None)
        self.project = self.server.projects.create("Test", str(self.folder))
        self.server._select_area("work", self.project["project_id"])
        self.addCleanup(self.join_workers)

    def join_workers(self):
        for worker in self.server._workers:
            worker.join(timeout=3)

    def request(self, kind, path="", **extra):
        self.server.handle({"type": "explorer." + kind, "project_id": self.project["project_id"],
                            "request_id": "test", "path": path, **extra})

    def test_offline_and_busy_listing_and_read_leave_chat_untouched(self):
        (self.folder / "hello.txt").write_text("hola", encoding="utf-8")
        self.server.busy = True
        self.request("list")
        data = self.output.wait_for("explorer.list")
        self.assertEqual(data["project_id"], self.project["project_id"])
        self.assertEqual(data["request_id"], "test")
        self.request("read", "hello.txt")
        self.assertEqual(self.output.wait_for("explorer.file")["text"], "hola")
        self.assertIsNone(self.server.conversation)
        self.assertEqual(self.server.history.list(), [])

    def test_wrong_project_invalid_path_and_removed_file_return_scoped_errors(self):
        for extra in ({"project_id": "bad"}, {"path": "../secret"}, {"path": "gone"}, {"request_id": None}):
            self.request("read", **extra)
            self.assertIn("message", self.output.wait_for("explorer.error"))
        self.server._select_area("chat")
        self.request("list")
        self.assertEqual(self.output.wait_for("explorer.list")["project_id"], self.project["project_id"])
        self.server._select_area("work", "")
        self.request("list")
        self.assertIn("message", self.output.wait_for("explorer.error"))

    def test_chat_keeps_last_project_reads_live_and_independent_of_chat_folder(self):
        self.server._chat_workspace = self.root / "chat-folder"
        self.server._chat_workspace.mkdir()
        (self.folder / "hello.txt").write_text("proyecto", encoding="utf-8")
        (self.server._chat_workspace / "hello.txt").write_text("chat", encoding="utf-8")
        self.server._select_area("chat")
        self.server.busy = True
        self.request("read", "hello.txt")
        self.assertEqual(self.output.wait_for("explorer.file")["text"], "proyecto")
        (self.folder / "hello.txt").write_text("actualizado", encoding="utf-8")
        self.request("read", "hello.txt")
        self.assertEqual(self.output.wait_for("explorer.file")["text"], "actualizado")
        self.assertEqual(self.server.workspace, self.server._chat_workspace)
        self.assertIsNone(self.server.conversation)
        self.assertEqual(self.server.history.list(), [])

    def test_chat_rejects_other_registered_project_and_deleted_retained_project(self):
        other_folder = self.root / "other"
        other_folder.mkdir()
        other = self.server.projects.create("Other", str(other_folder))
        self.server._select_area("chat")
        self.request("list", project_id=other["project_id"])
        self.assertIn("message", self.output.wait_for("explorer.error"))
        self.server.handle({"type": "project.delete", "project_id": self.project["project_id"]})
        self.output.wait_for("project.deleted")
        self.request("list")
        self.assertIn("message", self.output.wait_for("explorer.error"))
        self.assertTrue(self.folder.is_dir())

    def test_switching_projects_rejects_old_context_in_work_and_chat(self):
        other_folder = self.root / "other"
        other_folder.mkdir()
        (other_folder / "hello.txt").write_text("otro", encoding="utf-8")
        other = self.server.projects.create("Other", str(other_folder))
        self.server._select_area("work", other["project_id"])
        for area in ("work", "chat"):
            self.server._select_area(area)
            self.request("list")
            self.assertIn("message", self.output.wait_for("explorer.error"))
            self.request("read", "hello.txt", project_id=other["project_id"])
            self.assertEqual(self.output.wait_for("explorer.file")["text"], "otro")
