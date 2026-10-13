"""Cambios reales durante herramientas, límites y aislamiento del observador."""

import json
import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

from tests.support.paths import PROJECT
from harness.work.activity import ProjectActivity
from tests.backend.tools import test_shell


class ActivityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.changes = []
        self.condition = threading.Condition()

    def emit(self, change):
        with self.condition:
            self.changes.append(change)
            self.condition.notify_all()

    def wait(self, predicate):
        with self.condition:
            self.assertTrue(self.condition.wait_for(lambda: any(predicate(c) for c in self.changes), 3), self.changes)
            return next(c for c in reversed(self.changes) if predicate(c))

    def test_nested_creation_and_partial_writes_arrive_before_command_ends(self):
        (self.root / "existing.txt").write_text("baseline")
        with ProjectActivity(self.root, self.emit) as observer:
            self.assertEqual(self.changes, [])
            (self.root / "src").mkdir()
            path = self.root / "src/main.py"
            path.write_text("first\n")
            first = self.wait(lambda c: c.get("preview", {}).get("text") == "first\n")
            with path.open("a") as handle:
                handle.write("second\n"); handle.flush()
                second = self.wait(lambda c: c.get("preview", {}).get("text") == "first\nsecond\n")
            self.assertEqual(first["path"], "src/main.py")
            self.assertGreater(second["sequence"], first["sequence"])
        self.assertEqual(observer.fd, -1)
        self.assertFalse(observer.thread.is_alive())

    def test_fast_commands_are_drained_on_exit_and_moves_and_deletes_reported(self):
        (self.root / "old.txt").write_text("old")
        with ProjectActivity(self.root, self.emit):
            (self.root / "old.txt").rename(self.root / "new.txt")
            (self.root / "quick.txt").write_text("quick")
        self.assertTrue(any(c.get("path") == "old.txt" and c["action"] == "deleted" for c in self.changes))
        self.assertTrue(any(c.get("path") == "new.txt" and c.get("preview", {}).get("text") == "old" for c in self.changes))
        self.assertTrue(any(c.get("preview", {}).get("text") == "quick" for c in self.changes))

    def test_exclusions_private_history_symlinks_special_files_and_binary(self):
        with ProjectActivity(self.root, self.emit, ignored=(self.root / "chats",)):
            for folder in (".git", "node_modules", "chats"):
                (self.root / folder).mkdir()
                (self.root / folder / "secret").write_text("private")
            (self.root / "link").symlink_to("/etc/passwd")
            os.mkfifo(self.root / "fifo")
            (self.root / "binary").write_bytes(b"a\0b")
        paths = [c.get("path", "") for c in self.changes]
        self.assertFalse(any(p.startswith((".git", "node_modules", "chats")) for p in paths))
        self.assertNotIn("link", paths)
        self.assertNotIn("fifo", paths)
        binary = next(c for c in self.changes if c.get("path") == "binary")
        self.assertNotIn("preview", binary)

    def test_watch_limit_and_unavailable_observer_are_not_command_errors(self):
        for index in range(5): (self.root / str(index)).mkdir()
        with patch("harness.work.activity.MAX_WATCHES", 2):
            with ProjectActivity(self.root, self.emit) as observer:
                self.assertLessEqual(len(observer.watches), 2)
        self.assertTrue(any(c["action"] == "notice" for c in self.changes))
        observer = ProjectActivity(self.root, self.emit)
        with patch.object(observer.libc, "inotify_init1", return_value=-1):
            with observer:
                (self.root / "still-works.txt").write_text("ok")
        self.assertEqual((self.root / "still-works.txt").read_text(), "ok")
        self.assertEqual(observer.fd, -1)


class WorkActivityContractTests(unittest.TestCase):
    # Reutiliza sólo la preparación y el cierre del motor, no sus escenarios.
    stop = test_shell.AgentShellTests.stop
    start = test_shell.AgentShellTests.start
    finished = test_shell.AgentShellTests.finished

    def setUp(self):
        test_shell.AgentShellTests.setUp(self)
        self.folder = self.root / "project"
        self.folder.mkdir()
        project = self.server.projects.create("Live", str(self.folder))
        self.server._select_area("work", project["project_id"])
        self.project_id = project["project_id"]

    def test_work_changes_stream_during_real_tool_and_are_not_model_context(self):
        self.service.tool_batches = [[{"command": "mkdir src; printf first > src/a.txt; sleep .4; printf second >> src/a.txt"}]]
        self.start()
        activity = self.output.wait_for("work.activity")
        self.assertEqual(activity["status"], "running")
        while True:
            change = self.output.wait_for("work.changed")
            if change.get("preview", {}).get("text") == "first": break
        self.assertTrue(self.server.busy)
        self.assertEqual(change["project_id"], self.project_id)
        self.assertEqual(change["call_id"], activity["call_id"])
        self.assertEqual(self.finished()["status"], "completed")
        events = [e for e in map(json.loads, self.output.getvalue().splitlines()) if e["type"] == "work.changed"]
        self.assertTrue(any(e["data"].get("preview", {}).get("text") == "firstsecond" for e in events))
        self.assertNotIn("work.changed", json.dumps(self.server.conversation))
        self.assertNotIn("preview", self.service.requests[-1]["body"]["input"][-1])

    def test_local_commands_and_chat_do_not_activate_work_observer(self):
        self.server.handle({"type": "shell.execute", "command": "printf local > local.txt"})
        self.output.wait_for("shell.finished")
        self.server._select_area("chat")
        self.start(); self.finished()
        self.assertFalse(any(e["type"].startswith("work.") for e in map(json.loads, self.output.getvalue().splitlines())))

    def test_cancel_discards_late_changes_and_stops_observer(self):
        self.service.tool_batches = [[{"command": "printf partial > a.txt; sleep 10; printf late >> a.txt"}]]
        self.start()
        self.output.wait_for("work.changed")
        self.server.handle({"type": "chat.cancel"})
        self.assertEqual(self.finished()["status"], "interrupted")
        self.stop()
        lines = list(map(json.loads, self.output.getvalue().splitlines()))
        finished = next(i for i,e in enumerate(lines) if e["type"] == "chat.finished")
        self.assertFalse(any(e["type"] == "work.changed" for e in lines[finished+1:]))
        self.assertEqual((self.folder / "a.txt").read_text(), "partial")
