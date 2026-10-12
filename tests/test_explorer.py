"""Exploración acotada, rutas confinadas y contrato sin inferencia ni historial."""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from harness.explorer import ProjectExplorer, MAX_PREVIEW
from harness.server import HarnessServer
from fake_service import FakeSession
from test_harness import QueueOutput


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
        with patch("harness.explorer.MAX_ENTRIES", 3):
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
        with patch("harness.explorer.os.open", side_effect=swapping), self.assertRaises(OSError):
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
        self.assertIn("message", self.output.wait_for("explorer.error"))
