"""Ejecución interna con HTTP/SSE local, archivos reales y procesos cancelables."""

import copy
import json
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from tests.support.paths import PROJECT
from tests.support.fake_service import FakeService, FakeSession
from tests.support.sessions import QueueOutput
from harness.chat.chatgpt import ChatGPTClient
from harness.core.http import HttpClient
from harness.core.server import HarnessServer
from harness.tools.shell import ShellExecutor


class ProjectRunTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folder = self.root / "project with spaces"
        self.folder.mkdir()
        self.service = FakeService().__enter__()
        self.addCleanup(self.service.__exit__)
        self.output = QueueOutput()
        self.session = FakeSession()
        self.client = ChatGPTClient(self.session, HttpClient(allow_loopback=True, timeout=2), self.service.url)
        self.server = HarnessServer(self.root / "chats", self.output, self.session, self.client)
        self.server._refresh_account()
        self.server.handle({"type": "project.create", "name": "Fixture", "workdir": str(self.folder)})
        self.project_id = self.server.project["project_id"]
        self.addCleanup(self.stop)

    def stop(self):
        self.server.project_runner.close()
        self.server._stream.cancel()
        self.server._shell_control.cancel()
        for worker in self.server._workers:
            worker.join(3)

    def start(self):
        self.server.handle({"type": "project.run", "project_id": self.project_id})

    def state(self, phase):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            state = self.output.wait_for("project.run.state")
            if state["phase"] == phase:
                return state
        self.fail("No llegó el estado " + phase)

    def events(self):
        return [json.loads(line) for line in self.output.getvalue().splitlines()]

    def test_inspects_real_files_and_runs_without_chat_history_or_metrics(self):
        self.server.handle({"type": "chat.send", "prompt": "Hola"})
        self.output.wait_for("chat.finished")
        original = copy.deepcopy(self.server.conversation)
        saved = self.server.history._path(original["chat_id"]).read_bytes()
        self.service.tool_preface = "Texto privado de la tarea interna"
        (self.folder / "run.sh").write_text("printf '%s' \"$PWD\" > launched.txt\n")
        before = len(self.events())
        self.start()
        state = self.state("completed")
        self.assertEqual(state["exit_code"], 0)
        self.assertEqual((self.folder / "launched.txt").read_text(), str(self.folder))
        self.assertEqual(self.server.conversation, original)
        self.assertEqual(self.server.history._path(original["chat_id"]).read_bytes(), saved)
        events = self.events()[before:]
        self.assertTrue(all(event["type"].startswith("project.run.") for event in events))
        internal = self.service.requests[-2:]
        self.assertEqual(len(internal), 2)
        self.assertEqual(internal[0]["body"]["model"], self.server.model)
        self.assertEqual([tool["name"] for tool in internal[0]["body"]["tools"]], ["shell", "launch_program"])
        self.assertFalse(internal[0]["body"]["store"])
        self.assertIn("README", internal[0]["body"]["input"][0]["content"])
        self.assertNotIn("Hola", json.dumps(internal[0]["body"]["input"]))
        results = [item for item in internal[1]["body"]["input"] if item.get("type") == "function_call_output"]
        self.assertIn("launched.txt", json.loads(results[0]["output"])["output"])

    def test_new_project_run_does_not_create_a_conversation(self):
        (self.folder / "run.sh").write_text("printf 'ok'\n")
        self.service.tool_stream_items = True
        self.start()
        self.assertEqual(self.state("completed")["output"], "ok")
        self.assertIsNone(self.server.conversation)
        self.assertEqual(self.server.history.list(), [])

    def test_prefetch_allows_one_request_and_repeat_uses_no_inference(self):
        (self.folder / "README.md").write_text("Start with sh run.sh")
        (self.folder / "package.json").write_text('{"name":"fixture"}')
        (self.folder / ".env").write_text("SECRET=never-prefetch")
        (self.folder / "run.sh").write_text("printf fast\n")
        self.service.project_run_batches = [[{"name": "launch_program", "command": "sh run.sh"}]]
        self.start()
        first = self.state("completed")
        self.assertTrue(first["cache_available"])
        self.assertEqual(len(self.service.requests), 1)
        prompt = self.service.requests[0]["body"]["input"][0]["content"]
        self.assertIn("Start with sh run.sh", prompt)
        self.assertIn("fixture", prompt)
        self.assertIn("printf fast", prompt)
        self.assertNotIn("never-prefetch", prompt)
        with patch.object(self.client, "stream", side_effect=AssertionError("Unexpected AI request")):
            self.start()
            second = self.state("completed")
        self.assertEqual(second["source"], "cache")
        self.assertEqual(second["output"], "fast")
        self.assertIsNone(self.server.conversation)
        self.server._publish_projects()
        published = self.output.wait_for("projects.list")["projects"]
        self.assertTrue(published[0]["has_launch_profile"])
        self.assertNotIn("launch_profile", published[0])

    def test_restart_can_run_cached_start_without_chatgpt(self):
        (self.folder / "run.sh").write_text("printf offline\n")
        self.start()
        self.state("completed")
        self.stop()
        self.output = QueueOutput()
        self.server = HarnessServer(self.root / "chats", self.output, self.session, self.client)
        self.server.handle({"type": "area.select", "area": "work", "project_id": self.project_id})
        self.assertFalse(self.server.authenticated)
        with patch.object(self.client, "stream", side_effect=AssertionError("Unexpected AI request")):
            self.start()
            state = self.state("completed")
        self.assertEqual(state["source"], "cache")
        self.assertEqual(state["output"], "offline")

    def test_changed_startup_is_redetected_and_offline_change_reports_connection_needed(self):
        (self.folder / "run.sh").write_text("printf old\n")
        self.start()
        self.state("completed")
        before = len(self.service.requests)
        (self.folder / "run.sh").write_text("printf new\n")
        self.start()
        state = self.state("completed")
        self.assertEqual(state["source"], "ai")
        self.assertEqual(state["output"], "new")
        self.assertGreater(len(self.service.requests), before)
        before = len(self.service.requests)
        self.server.authenticated = False
        (self.folder / "run.sh").write_text("printf changed-again\n")
        self.start()
        self.assertIn("Conecta ChatGPT", self.state("failed")["message"])
        self.assertEqual(len(self.service.requests), before)
        self.assertIsNone(self.server.project_runner.cache.load(self.project_id, self.folder))

    def test_failed_cached_start_retries_detection_once_with_real_failure(self):
        (self.folder / "run.sh").write_text("if test -f fail.flag; then printf failure; exit 7; fi; printf ok\n")
        (self.folder / "alternate.sh").write_text("printf recovered\n")
        self.service.project_run_batches = [[{"name": "launch_program", "command": "sh run.sh"}]]
        self.start()
        self.state("completed")
        (self.folder / "fail.flag").touch()
        self.service.project_run_batches = [[{"name": "launch_program", "command": "sh alternate.sh"}]]
        before = len(self.service.requests)
        self.start()
        state = self.state("completed")
        self.assertEqual(state["output"], "recovered")
        self.assertEqual(len(self.service.requests), before + 1)
        prompt = self.service.requests[-1]["body"]["input"][0]["content"]
        self.assertIn("failed_cached_start", prompt)
        self.assertIn('"exit_code": 7', prompt)
        self.assertIn("failure", prompt)
        self.start()
        self.assertEqual(self.state("completed")["source"], "cache")
        self.assertEqual(len(self.service.requests), before + 1)

    def test_stop_before_validation_does_not_save_but_live_start_persists(self):
        (self.folder / "run.sh").write_text("printf ready; sleep 30\n")
        self.start()
        state = self.state("running")
        self.server.handle({"type": "project.run.stop", "project_id": self.project_id,
                            "execution_id": state["execution_id"]})
        self.state("interrupted")
        self.assertIsNone(self.server.project_runner.cache.load(self.project_id, self.folder))
        self.start()
        self.state("running")
        deadline = time.monotonic() + 4
        while not self.server.project_runner.state["cache_available"] and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertTrue(self.server.project_runner.state["cache_available"])
        self.server.project_runner.close()
        self.assertTrue(self.state("interrupted")["cache_available"])
        self.assertIsNotNone(self.server.project_runner.cache.load(self.project_id, self.folder))

    def test_cache_write_failure_keeps_program_success(self):
        (self.folder / "run.sh").write_text("printf ok\n")
        with patch.object(self.server.project_runner.cache, "save", side_effect=OSError("disk failure")):
            self.start()
            state = self.state("completed")
        self.assertEqual(state["exit_code"], 0)
        self.assertFalse(state["cache_available"])

    def test_persistent_run_can_be_stopped_while_chat_and_area_switch_continue(self):
        (self.folder / "run.sh").write_text("sleep 30 & printf '%s' $! > child.pid; wait\n")
        self.start()
        state = self.state("running")
        self.server.handle({"type": "area.select", "area": "chat"})
        self.assertEqual(self.server.active_area, "chat")
        self.server.handle({"type": "chat.send", "prompt": "Hola"})
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "completed")
        self.assertTrue(self.server.project_runner.active)
        self.server.handle({"type": "project.run.stop", "project_id": self.project_id,
                            "execution_id": state["execution_id"]})
        self.state("interrupted")
        self.assertFalse(self.server.project_runner.active)
        pid = int((self.folder / "child.pid").read_text())
        stat = Path(f"/proc/{pid}/stat")
        if stat.exists():
            self.assertIn(stat.read_text().split()[2], ("Z", "X"))

    def test_run_has_no_shell_timeout_and_close_kills_it(self):
        (self.folder / "run.sh").write_text("sleep .25; printf ready; sleep 30\n")
        original = ShellExecutor.__init__
        def short_preparation(executor, workspace, timeout=120, max_output=16000):
            original(executor, workspace, timeout=None if timeout is None else .1, max_output=max_output)
        with patch.object(ShellExecutor, "__init__", short_preparation):
            self.start()
            self.state("running")
            deadline = time.monotonic() + 3
            while "ready" not in self.server.project_runner.state["output"] and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertIn("ready", self.server.project_runner.state["output"])
            self.assertTrue(self.server.project_runner.active)
            self.server.project_runner.close()
            self.state("interrupted")

    def test_launch_failure_is_reported_without_chat_messages(self):
        (self.folder / "run.sh").write_text("printf 'missing dependency' >&2; exit 7\n")
        self.start()
        state = self.state("failed")
        self.assertEqual(state["exit_code"], 7)
        self.assertEqual(state["output"], "missing dependency")
        self.assertIsNone(self.server.conversation)
        self.assertFalse(self.server.busy)

    def test_missing_launch_and_failed_stream_never_spawn_program(self):
        self.service.project_run_batches = []
        with patch("harness.tools.shell.subprocess.Popen") as spawn:
            self.start()
            self.state("failed")
            spawn.assert_not_called()
        self.assertIsNone(self.server.conversation)
        self.service.stream_content_type = "application/json"
        with patch("harness.tools.shell.subprocess.Popen") as spawn:
            self.start()
            self.state("failed")
            spawn.assert_not_called()

    def test_unconfirmed_tool_output_never_executes(self):
        def partial_stream(*args, **kwargs):
            yield {"type": "response.output_item.done", "item": {"type": "function_call",
                   "call_id": "unconfirmed", "name": "launch_program", "arguments": '{"command":"touch wrong"}'}}
        with patch.object(self.client, "stream", partial_stream), patch("harness.tools.shell.subprocess.Popen") as spawn:
            self.start()
            self.state("failed")
            spawn.assert_not_called()
        self.assertFalse((self.folder / "wrong").exists())

    def test_duplicate_call_does_not_execute_twice(self):
        call = {"type": "function_call", "call_id": "repeated", "name": "shell",
                "arguments": json.dumps({"command": "printf x >> once"})}
        def repeated_stream(*args, **kwargs):
            yield {"type": "response.completed", "response": {"status": "completed", "output": [call]}}
        with patch.object(self.client, "stream", repeated_stream):
            self.start()
            self.state("failed")
        self.assertEqual((self.folder / "once").read_text(), "x")

    def test_cancel_preparation_and_reopen_does_not_start_stale_program(self):
        (self.folder / "run.sh").write_text("printf ok\n")
        self.service.response_delay = .25
        self.start()
        state = self.state("preparing")
        self.server.handle({"type": "auth.select", "account_id": "fixture-second"})
        self.assertEqual(self.session.selected_account, "fixture-account")
        self.output.wait_for("error")
        self.server.handle({"type": "project.run.stop", "project_id": self.project_id,
                            "execution_id": state["execution_id"]})
        self.state("interrupted")
        self.service.response_delay = 0
        self.start()
        replacement = self.state("completed")
        self.assertNotEqual(replacement["execution_id"], state["execution_id"])
        self.server.handle({"type": "project.run.stop", "project_id": self.project_id,
                            "execution_id": state["execution_id"]})
        self.output.wait_for("project.run.rejected")
        self.assertEqual(self.server.project_runner.state, replacement)

    def test_rejects_duplicate_run_delete_active_project_and_wrong_identity(self):
        (self.folder / "run.sh").write_text("sleep 30\n")
        self.start()
        state = self.state("running")
        self.start()
        self.output.wait_for("project.run.rejected")
        self.server.handle({"type": "project.delete", "project_id": self.project_id})
        self.output.wait_for("area.rejected")
        self.assertEqual(len(self.server.projects.list()), 1)
        self.server.handle({"type": "project.run.stop", "project_id": "wrong",
                            "execution_id": state["execution_id"]})
        self.output.wait_for("project.run.rejected")
        self.assertTrue(self.server.project_runner.active)

    def test_rejects_invalid_start_requests_without_inference(self):
        before = len(self.service.requests)
        for request in ({"type": "project.run", "project_id": "wrong"},
                        {"type": "project.run", "project_id": self.project_id, "prompt": "injected"}):
            self.server.handle(request)
            self.output.wait_for("project.run.rejected")
        for flag in ("busy", "login_pending", "account_pending"):
            setattr(self.server, flag, True)
            self.start()
            self.output.wait_for("project.run.rejected")
            setattr(self.server, flag, False)
        self.server.authenticated = False
        self.start()
        self.output.wait_for("project.run.rejected")
        self.server.authenticated = True
        self.server.models = []
        self.start()
        self.output.wait_for("project.run.rejected")
        self.assertEqual(len(self.service.requests), before)
