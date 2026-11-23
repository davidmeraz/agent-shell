"""Pruebas unitarias e integración de apply_patch, read_file, grep_files, strip_ansi y paralelismo."""

import json
import tempfile
import unittest
from pathlib import Path

from tests.support import paths  # noqa: F401
from tests.support.fake_service import FakeService, FakeSession
from tests.support.sessions import QueueOutput
from harness.chat.chatgpt import ChatGPTClient
from harness.core.http import HttpClient
from harness.core.server import HarnessServer
from harness.tools.files import execute_grep_files, execute_read_file
from harness.tools.output import compact_result, strip_ansi
from harness.tools.patch import execute_apply_patch


class PatchToolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_update_add_move_and_delete_atomically(self):
        (self.root / "app.py").write_text("a = 1\nb = 2\nc = 3\n", encoding="utf-8")
        (self.root / "old.txt").write_text("bye\n", encoding="utf-8")
        patch = (
            "*** Begin Patch\n"
            "*** Update File: app.py\n"
            "@@\n"
            " a = 1\n"
            "-b = 2\n"
            "+b = 20\n"
            " c = 3\n"
            "*** Add File: sub/new.py\n"
            "+def ok():\n"
            "+    return True\n"
            "*** Delete File: old.txt\n"
            "*** End Patch\n"
        )
        res = execute_apply_patch(self.root, json.dumps({"patch": patch}))
        self.assertEqual(res["status"], "completed")
        self.assertEqual((self.root / "app.py").read_text(encoding="utf-8"), "a = 1\nb = 20\nc = 3\n")
        self.assertEqual((self.root / "sub/new.py").read_text(encoding="utf-8"), "def ok():\n    return True\n")
        self.assertFalse((self.root / "old.txt").exists())

    def test_failed_second_hunk_leaves_first_file_untouched(self):
        (self.root / "a.py").write_text("x = 1\n", encoding="utf-8")
        (self.root / "b.py").write_text("y = 2\n", encoding="utf-8")
        patch = (
            "*** Begin Patch\n"
            "*** Update File: a.py\n"
            "@@\n"
            "-x = 1\n"
            "+x = 99\n"
            "*** Update File: b.py\n"
            "@@\n"
            "-does_not_exist\n"
            "+boom\n"
            "*** End Patch\n"
        )
        with self.assertRaises(ValueError):
            execute_apply_patch(self.root, json.dumps({"patch": patch}))
        self.assertEqual((self.root / "a.py").read_text(encoding="utf-8"), "x = 1\n")

    def test_rejects_path_traversal_absolute_and_symlinks(self):
        outside = self.root.parent / "outside-secret.txt"
        link = self.root / "escape.txt"
        link.symlink_to(outside)
        for bad_path in ("../escape.txt", "/etc/passwd", "escape.txt"):
            patch = f"*** Begin Patch\n*** Add File: {bad_path}\n+x\n*** End Patch"
            with self.subTest(bad_path=bad_path), self.assertRaises(ValueError):
                execute_apply_patch(self.root, json.dumps({"patch": patch}))


class FileToolsAndAnsiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_read_file_returns_bounded_numbered_lines_and_blocks_escape(self):
        (self.root / "sample.py").write_text("l1\nl2\nl3\nl4\n", encoding="utf-8")
        res = execute_read_file(self.root, json.dumps({"path": "sample.py", "start_line": 2, "end_line": 3}))
        self.assertIn("2: l2", res["output"])
        self.assertIn("3: l3", res["output"])
        self.assertNotIn("1: l1", res["output"])
        self.assertTrue(res["truncated"])
        with self.assertRaises(ValueError):
            execute_read_file(self.root, json.dumps({"path": "../etc/passwd", "start_line": 1, "end_line": 5}))

    def test_grep_files_finds_matches_and_excludes_venv(self):
        (self.root / "src.py").write_text("alpha = 1\ntarget_fn()\n", encoding="utf-8")
        (self.root / ".venv").mkdir()
        (self.root / ".venv" / "ignored.py").write_text("target_fn()\n", encoding="utf-8")
        res = execute_grep_files(self.root, json.dumps({"pattern": "target_fn", "path": "", "max_matches": 10}))
        self.assertIn("src.py:2:target_fn()", res["output"])
        self.assertNotIn(".venv", res["output"])

    def test_strip_ansi_cleans_model_view(self):
        noisy = "\x1b[32mPASS\x1b[0m \x1b[1;31mERROR\x1b[0m\n"
        self.assertEqual(strip_ansi(noisy), "PASS ERROR\n")
        compact = compact_result({"status": "error", "exit_code": 1, "output": noisy})
        self.assertEqual(compact["output"], "PASS ERROR\n")


class ParallelToolBatchIntegrationTests(unittest.TestCase):
    def test_harness_executes_parallel_read_batch_and_apply_patch_in_one_turn(self):
        with tempfile.TemporaryDirectory() as tmp, FakeService() as service:
            root = Path(tmp)
            ws = root / "ws"
            ws.mkdir()
            (ws / "a.txt").write_text("hello a\n", encoding="utf-8")
            (ws / "b.txt").write_text("hello b\n", encoding="utf-8")
            # FakeService indexa tool_batches por len(results); 2 llamadas paralelas saltan de 0 a 2.
            service.tool_batches = [
                [
                    {"name": "read_file", "arguments": json.dumps({"path": "a.txt", "start_line": 1, "end_line": 0})},
                    {"name": "read_file", "arguments": json.dumps({"path": "b.txt", "start_line": 1, "end_line": 0})},
                ],
                [],
                [
                    {
                        "name": "apply_patch",
                        "arguments": json.dumps({
                            "patch": "*** Begin Patch\n*** Update File: a.txt\n@@\n-hello a\n+updated a\n*** End Patch"
                        }),
                    }
                ],
            ]
            output = QueueOutput()
            session = FakeSession()
            client = ChatGPTClient(session, HttpClient(allow_loopback=True, timeout=5), service.url)
            server = HarnessServer(root / "hist", output, session, client, workspace=ws)
            server._refresh_account()
            server.handle({"type": "chat.send", "prompt": "shell parallel test"})
            finished = output.wait_for("chat.finished")
            self.assertEqual(finished["status"], "completed")
            self.assertEqual((ws / "a.txt").read_text(encoding="utf-8"), "updated a\n")
            self.assertEqual(len(service.requests), 3)
            self.assertTrue(service.requests[0]["body"]["parallel_tool_calls"])
            tool_names = [t["name"] for t in service.requests[0]["body"]["tools"]]
            self.assertEqual(tool_names, ["shell", "read_file", "grep_files", "apply_patch"])


if __name__ == "__main__":
    unittest.main()
