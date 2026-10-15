"""Shell real en carpetas temporales y ciclo de herramientas con HTTP/SSE local."""

import json
import os
import shlex
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from tests.support.paths import PROJECT

from tests.support.fake_service import FakeService, FakeSession
from tests.support.sessions import QueueOutput
from harness.chat.chatgpt import ChatGPTClient
from harness.core.http import Cancelled, HttpClient
from harness.core.server import HarnessServer
from harness.core.limits import AgentLimits
from harness.tools.shell import ShellControl, ShellExecutor, parse_command


class ExecutorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.control = ShellControl(threading.Event())
        self.addCleanup(self.control.cancel)
        self.executor = ShellExecutor(self.root, timeout=2)

    def execute(self, command):
        return self.executor.execute(parse_command(json.dumps({"command": command})), self.control)

    def assert_dead(self, pid):
        stat = Path(f"/proc/{pid}/stat")
        try:
            state = stat.read_text().split()[2]
        except (FileNotFoundError, ProcessLookupError):
            return
        self.assertIn(state, ("Z", "X"), f"Proceso {pid} sobrevivió")

    def test_pwd_uses_selected_directory_and_returns_exit_code(self):
        result = self.execute("pwd")
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["exit_code"], 0)
        self.assertEqual(result["output"].strip(), str(self.root))

    def test_stdout_stderr_and_nonzero_exit_are_preserved(self):
        result = self.execute("printf 'out'; printf 'err' >&2; exit 7")
        self.assertEqual(result["output"], "outerr")
        self.assertEqual(result["exit_code"], 7)
        self.assertEqual(result["status"], "error")

    def test_unicode_fragments_and_output_limit_do_not_break_stream(self):
        result = self.execute("printf '\\360\\237'; sleep 0.1; printf '\\216\\265'")
        self.assertEqual(result["output"], "🎵")
        self.executor.max_output = 32
        result = self.execute("yes x | head -c 100000")
        self.assertEqual(result["status"], "completed")
        self.assertEqual(len(result["output"]), 32)
        self.assertTrue(result["truncated"])

    def test_timeout_kills_shell_and_descendant_and_keeps_partial_output(self):
        self.executor.timeout = 0.3
        result = self.execute("sleep 30 & printf '%s' $!; wait")
        self.assertEqual(result["status"], "timeout")
        self.assert_dead(int(result["output"]))

    def test_closed_output_does_not_terminate_a_process_still_working(self):
        result = self.execute("exec 1>&- 2>&-; sleep 0.1; printf done > finished.txt")
        self.assertEqual(result["status"], "completed")
        self.assertEqual((self.root / "finished.txt").read_text(), "done")

    def test_closed_output_still_obeys_timeout(self):
        self.executor.timeout = 0.15
        result = self.execute("exec 1>&- 2>&-; sleep 30; touch unexpected")
        self.assertEqual(result["status"], "timeout")
        self.assertFalse((self.root / "unexpected").exists())

    def test_cancel_with_closed_output_terminates_promptly(self):
        result = []
        worker = threading.Thread(target=lambda: result.append(self.execute(
            "printf ready > started.txt; exec 1>&- 2>&-; sleep 30; touch unexpected")))
        worker.start()
        deadline = time.monotonic() + 2
        while not (self.root / "started.txt").exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.control.cancel()
        worker.join(2)
        self.assertFalse(worker.is_alive())
        self.assertEqual(result[0]["status"], "interrupted")
        self.assertFalse((self.root / "unexpected").exists())

    def test_truncated_output_keeps_initial_context_and_final_error(self):
        self.executor.max_output = 80
        result = self.execute("printf START; yes x | head -c 100000; printf FINAL_ERROR >&2; exit 7")
        self.assertTrue(result["truncated"])
        self.assertEqual(len(result["output"]), 80)
        self.assertTrue(result["output"].startswith("START"))
        self.assertTrue(result["output"].endswith("FINAL_ERROR"))
        self.assertEqual(result["exit_code"], 7)

    def test_cancel_kills_running_process_group(self):
        result, output = [], []
        ready = threading.Event()
        def capture(text):
            if text:
                output.append(text)
                ready.set()
        worker = threading.Thread(target=lambda: result.append(self.executor.execute(
            "sleep 30 & printf '%s' $!; wait", self.control, capture)))
        worker.start()
        self.assertTrue(ready.wait(2))
        self.control.cancel()
        worker.join(2)
        self.assertFalse(worker.is_alive())
        self.assertEqual(result[0]["status"], "interrupted")
        self.assert_dead(int(output[0]))

    def test_cancelled_command_never_spawns_and_stdin_is_closed(self):
        result = self.execute("read value; printf 'no-input'")
        self.assertEqual(result["output"], "no-input")
        self.control.cancel()
        with patch("harness.tools.shell.subprocess.Popen") as spawn, self.assertRaises(Cancelled):
            self.execute("pwd")
        spawn.assert_not_called()

    def test_environment_does_not_inherit_arbitrary_backend_variables(self):
        with patch.dict(os.environ, {"AGENT_SHELL_TEST_SECRET": "test-only-secret"}):
            result = self.execute("printf '%s' ${AGENT_SHELL_TEST_SECRET-unset}")
        self.assertEqual(result["output"], "unset")

    def child_environment(self):
        code = "import json, os; print(json.dumps(dict(os.environ)))"
        result = self.execute(shlex.quote(sys.executable) + " -c " + shlex.quote(code))
        self.assertEqual(result["status"], "completed")
        return json.loads(result["output"])

    def test_wayland_command_preserves_desktop_session_and_filters_backend_secrets(self):
        desktop = {"PATH": os.defpath, "HOME": str(self.root), "USER": "fixture-user",
                   "WAYLAND_DISPLAY": "wayland-fixture", "XDG_RUNTIME_DIR": str(self.root),
                   "DBUS_SESSION_BUS_ADDRESS": "unix:path=/tmp/fixture-bus",
                   "XDG_SESSION_TYPE": "wayland", "XDG_CONFIG_HOME": str(self.root / "config"),
                   "QT_QPA_PLATFORM": "wayland", "QT_IM_MODULE": "fixture-ime",
                   "HYPRLAND_INSTANCE_SIGNATURE": "fixture-compositor", "LANG": "C.UTF-8"}
        with patch.dict(os.environ, {**desktop, "AGENT_SHELL_TEST_SECRET": "test-only-secret",
                                    "OPENAI_API_KEY": "test-only-api-key", "TERM": "xterm"}, clear=True):
            environment = self.child_environment()
        for name, value in desktop.items():
            self.assertEqual(environment[name], value, name)
        self.assertEqual(environment["TERM"], "dumb")
        self.assertNotIn("AGENT_SHELL_TEST_SECRET", environment)
        self.assertNotIn("OPENAI_API_KEY", environment)

    def test_x11_command_preserves_display_and_authorization_without_forcing_wayland(self):
        desktop = {"PATH": os.defpath, "DISPLAY": ":93", "XAUTHORITY": str(self.root / "authority"),
                   "QT_QPA_PLATFORM": "xcb", "LANG": "C.UTF-8"}
        with patch.dict(os.environ, desktop, clear=True):
            environment = self.child_environment()
        for name, value in desktop.items():
            self.assertEqual(environment[name], value, name)
        self.assertNotIn("WAYLAND_DISPLAY", environment)
        self.assertNotIn("XDG_RUNTIME_DIR", environment)

    def test_headless_command_does_not_invent_graphical_session(self):
        with patch.dict(os.environ, {}, clear=True):
            environment = self.child_environment()
        self.assertEqual(environment["PATH"], os.defpath)
        self.assertEqual(environment["LANG"], "C.UTF-8")
        for name in ("WAYLAND_DISPLAY", "DISPLAY", "XDG_RUNTIME_DIR", "XAUTHORITY", "QT_QPA_PLATFORM"):
            self.assertNotIn(name, environment)

    def test_argument_schema_rejects_permissions_paths_and_invalid_commands(self):
        for value in (None, [], {}, {"command": ""}, {"command": 3}, {"command": "x\0y"},
                      {"command": "x" * 8001}, {"command": "pwd", "approved": True},
                      {"command": "pwd", "workdir": "/"}, {"command": "pwd", "background": True}):
            with self.subTest(value=str(value)[:70]), self.assertRaises(ValueError):
                parse_command(json.dumps(value))

    def test_invalid_output_limit_does_not_leave_a_running_process(self):
        self.executor.max_output = -1
        with patch("harness.tools.shell.subprocess.Popen") as spawn, self.assertRaises(ValueError):
            self.execute("sleep 30")
        spawn.assert_not_called()


class AgentShellTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.service = FakeService().__enter__()
        self.addCleanup(self.service.__exit__)
        self.output = QueueOutput()
        self.session = FakeSession()
        client = ChatGPTClient(self.session, HttpClient(allow_loopback=True, timeout=2), self.service.url)
        self.server = HarnessServer(self.root / "chats", self.output, self.session, client, workspace=self.root)
        self.server._refresh_account()
        self.addCleanup(self.stop)

    def stop(self):
        self.server._stream.cancel()
        self.server._shell_control.cancel()
        for worker in self.server._workers:
            worker.join(3)

    def start(self):
        self.server.handle({"type": "chat.send", "prompt": "shell-pwd"})

    def finished(self):
        return self.output.wait_for("chat.finished")

    def test_local_shell_works_without_auth_models_or_provider_requests(self):
        self.server.authenticated = False
        self.server.models = []
        self.server.model = ""
        requests = len(self.service.requests)
        self.server.handle({"type": "shell.execute", "command": "pwd"})
        self.assertEqual(self.output.wait_for("shell.finished")["status"], "completed")
        record = self.server.history.load(self.server.conversation["chat_id"])
        call = record["tool_calls"][0]
        self.assertEqual(call["output"].strip(), str(self.root))
        self.assertEqual(call["source"], "local")
        self.assertEqual(call["message_index"], 0)
        self.assertEqual(call["exit_code"], 0)
        self.assertEqual(record["messages"], [])
        self.assertFalse(record.get("context"))
        self.assertFalse(record.get("performance"))
        self.assertEqual(len(self.service.requests), requests)
        self.assertIsNone(self.server._performance)
        events = [json.loads(line) for line in self.output.getvalue().splitlines()]
        self.assertFalse(any(event["type"] in ("chat.busy", "chat.delta", "performance.updated") for event in events))

    def test_local_shell_preserves_quotes_pipelines_newlines_and_exit_status(self):
        command = "printf '%s\\n' 'a b' | tr a-z A-Z\nprintf 'failure' >&2; exit 7 "
        self.server.handle({"type": "shell.execute", "command": command})
        self.assertEqual(self.output.wait_for("shell.finished")["status"], "error")
        call = self.server.conversation["tool_calls"][0]
        self.assertEqual(call["command"], command)
        self.assertEqual(call["output"], "A B\nfailure")
        self.assertEqual(call["exit_code"], 7)

    def test_local_shell_does_not_change_existing_ai_context_or_metrics(self):
        self.start()
        self.assertEqual(self.finished()["status"], "completed")
        original = json.loads(json.dumps(self.server.conversation))
        requests = len(self.service.requests)
        self.server.handle({"type": "shell.execute", "command": "printf private-local-output"})
        self.output.wait_for("shell.finished")
        for key in ("messages", "context", "performance", "model"):
            self.assertEqual(self.server.conversation[key], original[key])
        self.assertEqual(len(self.service.requests), requests)
        self.assertEqual(self.server.conversation["tool_calls"][-1]["message_index"], len(original["messages"]))
        self.server.handle({"type": "chat.send", "prompt": "Hola"})
        self.finished()
        self.assertNotIn("private-local-output", json.dumps(self.service.requests[-1]["body"]["input"]))

    def test_local_shell_invalid_or_busy_requests_never_start_a_process(self):
        with patch("harness.tools.shell.subprocess.Popen") as spawn:
            for command in (None, "", " ", "pwd\0", "x" * 8001, 7):
                self.server.handle({"type": "shell.execute", "command": command})
                self.output.wait_for("shell.rejected")
            for flag in ("busy", "login_pending", "account_pending"):
                setattr(self.server, flag, True)
                self.server.handle({"type": "shell.execute", "command": "pwd"})
                self.output.wait_for("shell.rejected")
                self.assertTrue(getattr(self.server, flag))
                setattr(self.server, flag, False)
            spawn.assert_not_called()
        self.assertIsNone(self.server.conversation)

    def test_local_shell_persistence_failure_prevents_execution_and_restores_chat(self):
        self.server.conversation = self.server.history.create("Existing chat")
        original = json.loads(json.dumps(self.server.conversation))
        with patch.object(self.server.history, "save", side_effect=OSError("test disk failure")), \
                patch("harness.tools.shell.subprocess.Popen") as spawn:
            self.server.handle({"type": "shell.execute", "command": "pwd"})
            self.output.wait_for("shell.rejected")
            spawn.assert_not_called()
        self.assertEqual(self.server.conversation, original)
        self.assertFalse(self.server.busy)

    def test_local_shell_cancel_keeps_output_and_late_updates_cannot_overwrite_next_run(self):
        self.server.handle({"type": "shell.execute", "command": "printf ready; sleep 30"})
        while not self.output.wait_for("tool.updated")["call"]["output"]:
            pass
        old_call = self.server.conversation["tool_calls"][0]
        old_generation = self.server._generation
        self.server.handle({"type": "chat.cancel"})
        self.assertEqual(self.output.wait_for("shell.finished")["status"], "interrupted")
        self.assertEqual(old_call["output"], "ready")
        self.server.handle({"type": "shell.execute", "command": "printf next"})
        self.server._tool_output(old_call, "late", old_generation)
        self.assertEqual(self.output.wait_for("shell.finished")["status"], "completed")
        self.assertEqual(old_call["output"], "ready")
        self.assertEqual(old_call["status"], "interrupted")
        self.assertEqual(self.server.conversation["tool_calls"][-1]["output"], "next")
        self.assertFalse(self.server.busy)

    def test_local_shell_timeout_and_history_load_do_not_execute_again(self):
        with patch("harness.core.server.ShellExecutor", side_effect=lambda workdir: ShellExecutor(workdir, timeout=0.1)):
            self.server.handle({"type": "shell.execute", "command": "printf partial; sleep 30"})
            self.assertEqual(self.output.wait_for("shell.finished")["status"], "timeout")
        chat_id = self.server.conversation["chat_id"]
        with patch("harness.tools.shell.subprocess.Popen") as spawn:
            self.server.handle({"type": "chat.new"})
            self.server.handle({"type": "chat.open", "chat_id": chat_id})
            call = self.output.wait_for("chat.loaded")["chat"]["tool_calls"][0]
            self.assertEqual(call["status"], "timeout")
            self.assertEqual(call["output"], "partial")
            self.assertEqual(call["source"], "local")
            spawn.assert_not_called()

    def test_complete_tool_cycle_executes_automatically_and_preserves_provider_items(self):
        self.service.tool_preface = "Voy a consultar el directorio."
        self.service.response_delay = 0.12
        self.start()
        self.assertEqual(self.finished()["status"], "completed")
        record = self.server.history.load(self.server.conversation["chat_id"])
        call = record["tool_calls"][0]
        self.assertEqual(call["command"], "pwd")
        self.assertEqual(call["workdir"], str(self.root))
        self.assertEqual(call["output"].strip(), str(self.root))
        self.assertIn(str(self.root), record["messages"][-1]["text"])
        events = [json.loads(line) for line in self.output.getvalue().splitlines()]
        self.assertTrue(all(event["version"] == 2 for event in events))
        self.assertFalse(any(event["type"].startswith("tool.approval") for event in events))
        request = self.service.requests[-1]["body"]
        self.assertFalse(request["store"])
        self.assertFalse(request["parallel_tool_calls"])
        self.assertEqual(request["tools"][0]["name"], "shell")
        calls = [item for item in request["input"] if item.get("type") == "function_call"]
        results = [item for item in request["input"] if item.get("type") == "function_call_output"]
        self.assertEqual(calls[0]["call_id"], results[0]["call_id"])
        self.assertEqual(json.loads(results[0]["output"])["exit_code"], 0)
        self.assertTrue(any(item.get("encrypted_content") == "test-opaque-reasoning" for item in request["input"]))
        self.assertTrue(any(item.get("phase") == "commentary" for item in request["input"]))
        self.server.handle({"type": "chat.open", "chat_id": record["chat_id"]})
        visible = self.output.wait_for("chat.loaded")["chat"]
        self.assertNotIn("context", visible)
        self.assertEqual(visible["tool_calls"][0]["status"], "completed")
        metrics = record["performance"][-1]
        self.assertEqual(metrics["model_calls"], 2)
        self.assertEqual(metrics["tool_calls"], 1)
        self.assertEqual(metrics["usage"]["total_tokens"], 40)
        self.assertEqual(metrics["usage"]["input_tokens"], 24)
        self.assertEqual(metrics["context_tokens"], 12)
        self.assertIsNotNone(metrics["model_request_ms"])
        self.assertGreaterEqual(metrics["model_request_ms"], 240)
        self.assertAlmostEqual(metrics["tokens_per_second"],
                               metrics["usage"]["output_tokens"] * 1000 / metrics["model_request_ms"], places=1)
        self.assertEqual(metrics["approval_ms"], 0)
        self.assertGreater(metrics["tool_ms"], 0)
        self.assertIsNone(metrics["characters_per_second"])

    def test_commands_have_no_allowlist_and_support_changes_and_pipelines(self):
        self.service.tool_batches = [[{"command": "printf 'hello' > example; cat example | tr a-z A-Z; rm example"}]]
        self.start()
        self.assertEqual(self.finished()["status"], "completed")
        call = self.server.conversation["tool_calls"][0]
        self.assertEqual(call["status"], "completed")
        self.assertEqual(call["output"], "HELLO")
        self.assertFalse((self.root / "example").exists())

    def test_empty_completed_output_replays_full_stream_items_after_completion(self):
        self.service.tool_stream_items = True
        self.service.tool_preface = "Consultaré la carpeta."
        self.start()
        self.assertEqual(self.finished()["status"], "completed")
        context = self.server.conversation["context"]
        self.assertEqual(sum(item.get("type") == "function_call" for item in context), 1)
        self.assertEqual(sum(item.get("type") == "function_call_output" for item in context), 1)
        phases = [item.get("phase") for item in context if item.get("type") == "message"]
        self.assertEqual(phases, ["commentary", "final"])
        self.assertIn(str(self.root), self.server.conversation["messages"][-1]["text"])

    def test_done_tool_item_without_completed_response_cannot_execute(self):
        self.service.tool_stream_items = True
        gate = self.service.tool_completion_gate = threading.Event()
        self.addCleanup(gate.set)
        self.start()
        self.assertTrue(self.service.started.wait(2))
        self.server.handle({"type": "chat.cancel"})
        self.assertEqual(self.finished()["status"], "interrupted")
        self.assertFalse(self.server.conversation.get("tool_calls"))
        self.assertIsNone(self.server._shell_control._process)

    def test_cancel_before_process_creation_prevents_execution(self):
        self.service.tool_batches = [[{"command": "touch unexpected"}]]
        save = self.server.history.save
        def cancel_before_start(record):
            if any(call["status"] == "running" for call in record.get("tool_calls", [])):
                self.server._shell_control.cancel()
            save(record)
        with patch.object(self.server.history, "save", side_effect=cancel_before_start):
            self.start()
            self.assertEqual(self.finished()["status"], "interrupted")
        self.assertFalse((self.root / "unexpected").exists())

    def test_obsolete_decisions_do_not_spawn_a_process(self):
        with patch("harness.tools.shell.subprocess.Popen") as spawn:
            self.server.handle({"type": "tool.decide", "request_id": "old-id", "approved": True})
            self.output.wait_for("error")
            spawn.assert_not_called()

    def test_partial_tool_arguments_never_execute_before_completed_response(self):
        gate = self.service.tool_completion_gate = threading.Event()
        self.addCleanup(gate.set)
        self.start()
        self.assertTrue(self.service.started.wait(2))
        self.assertIsNone(self.server._shell_control._process)
        self.assertFalse(self.server.conversation.get("tool_calls"))
        gate.set()
        self.assertEqual(self.finished()["status"], "completed")

    def test_unknown_tool_or_extra_arguments_are_returned_as_error_without_execution(self):
        for spec in ({"name": "other", "command": "touch unexpected"},
                     {"arguments": json.dumps({"command": "touch unexpected", "approved": True})}):
            self.service.tool_batches = [[spec]]
            self.start()
            self.assertEqual(self.finished()["status"], "completed")
            self.assertFalse((self.root / "unexpected").exists())
            self.assertEqual(self.server.conversation["tool_calls"][-1]["status"], "error")

    def test_multiple_commands_execute_automatically_in_order(self):
        self.service.tool_batches = [[{"command": "printf first > state"}, {"command": "cat state"}]]
        self.start()
        self.assertEqual(self.finished()["status"], "completed")
        self.assertEqual((self.root / "state").read_text(), "first")
        self.assertEqual(self.server.conversation["tool_calls"][-1]["output"], "first")

    def test_step_limit_does_not_execute_excess_commands(self):
        self.server.limits = AgentLimits(max_steps=3)
        self.service.tool_batches = [[{"command": "pwd"}]] * 9
        self.start()
        finished = self.finished()
        self.assertEqual(finished["status"], "failed")
        self.assertIn("límite", finished["message"])
        self.assertEqual(len(self.service.requests), 3)
        self.assertEqual(len(self.server.conversation["tool_calls"]), 3)
        context = self.server.conversation["context"]
        self.assertEqual(sum(item.get("type") == "function_call_output" for item in context), 3)

    def test_task_continues_beyond_eight_steps_until_a_final_response(self):
        self.service.tool_batches = [[{"command": "printf step"}]] * 12
        self.start()
        self.assertEqual(self.finished()["status"], "completed")
        self.assertEqual(len(self.server.conversation["tool_calls"]), 12)
        self.assertEqual(len(self.service.requests), 13)
        # Los resultados previos permanecen inmutables para reutilizar el prefijo.
        for previous, current in zip(self.service.requests, self.service.requests[1:]):
            prefix = previous["body"]["input"]
            self.assertEqual(current["body"]["input"][:len(prefix)], prefix)

    def test_tool_budget_rejects_entire_excess_batch_and_closes_pending_calls(self):
        self.server.limits = AgentLimits(max_tool_calls=1)
        self.service.tool_batches = [[{"command": "touch unexpected"}, {"command": "pwd"}]]
        self.start()
        self.assertEqual(self.finished()["status"], "failed")
        self.assertFalse((self.root / "unexpected").exists())
        self.assertFalse(self.server.conversation.get("tool_calls"))
        results = [item for item in self.server.conversation["context"]
                   if item.get("type") == "function_call_output"]
        self.assertEqual(len(results), 2)
        self.assertTrue(all(json.loads(item["output"])["status"] == "interrupted" for item in results))

    def test_reported_token_budget_stops_before_another_model_request(self):
        self.server.limits = AgentLimits(max_turn_tokens=40)
        self.service.tool_batches = [[{"command": "pwd"}]] * 5
        self.start()
        finished = self.finished()
        self.assertEqual(finished["status"], "failed")
        self.assertIn("tokens", finished["message"])
        self.assertEqual(len(self.service.requests), 2)
        self.assertEqual(len(self.server.conversation["tool_calls"]), 2)

    def test_identical_failures_stop_without_repeating_forever(self):
        self.service.tool_batches = [[{"command": "printf broken; exit 7"}]] * 10
        self.start()
        finished = self.finished()
        self.assertEqual(finished["status"], "failed")
        self.assertIn("mismo comando", finished["message"])
        self.assertEqual(len(self.service.requests), 3)
        results = [json.loads(item["output"]) for item in self.server.conversation["context"]
                   if item.get("type") == "function_call_output"]
        self.assertEqual(len(results), 3)
        self.assertTrue(all(result["exit_code"] == 7 for result in results))

    def test_changed_approach_after_failure_can_complete(self):
        self.service.tool_batches = [[{"command": "test -f repaired"}],
                                     [{"command": "touch repaired"}],
                                     [{"command": "test -f repaired"}]]
        self.start()
        self.assertEqual(self.finished()["status"], "completed")
        self.assertEqual([call["status"] for call in self.server.conversation["tool_calls"]],
                         ["error", "completed", "completed"])

    def test_context_output_is_smaller_than_card_and_keeps_tail(self):
        self.service.tool_batches = [[{"command": "printf START; yes x | head -c 12000; printf END"}]]
        self.start()
        self.assertEqual(self.finished()["status"], "completed")
        record = self.server.conversation
        self.assertGreater(len(record["tool_calls"][0]["output"]), 12000)
        result = next(item for item in self.service.requests[-1]["body"]["input"]
                      if item.get("type") == "function_call_output")
        content = json.loads(result["output"])
        self.assertEqual(len(content["output"]), 6000)
        self.assertTrue(content["output"].startswith("START"))
        self.assertTrue(content["output"].endswith("END"))
        self.assertTrue(content["truncated"])
        self.assertNotIn("duration_ms", content)
        saved = self.server.history.load(record["chat_id"])
        self.assertEqual(saved["context"], record["context"])

    def test_http_stream_is_released_before_shell_execution(self):
        execute = self.server._run_tool
        def check_stream(*args):
            self.assertIsNone(self.server._stream._connection)
            return execute(*args)
        with patch.object(self.server, "_run_tool", side_effect=check_stream):
            self.start()
            self.assertEqual(self.finished()["status"], "completed")

    def test_workspace_changes_are_validated_and_blocked_during_a_turn(self):
        self.server.handle({"type": "shell.configure", "workdir": str(self.root / "missing")})
        self.output.wait_for("error")
        self.assertEqual(self.server.workspace, self.root)
        self.server.handle({"type": "shell.configure", "workdir": str(self.root), "enabled": False})
        self.assertIn("permanece activa", self.output.wait_for("error")["message"])
        gate = self.service.tool_completion_gate = threading.Event()
        self.addCleanup(gate.set)
        self.start()
        self.assertTrue(self.service.started.wait(2))
        self.server.handle({"type": "shell.configure", "workdir": "/"})
        self.output.wait_for("error")
        self.assertEqual(self.server.workspace, self.root)
        self.assertTrue(self.server.shell_enabled)
        gate.set()
        self.assertEqual(self.finished()["status"], "completed")

    def test_cancel_running_shell_keeps_output_and_allows_new_turn(self):
        self.service.tool_batches = [[{"command": "printf partial; sleep 30"}]]
        self.start()
        while True:
            call = self.output.wait_for("tool.updated")["call"]
            if call["status"] == "running" and call["output"]:
                break
        self.server.handle({"type": "chat.cancel"})
        self.assertEqual(self.finished()["status"], "interrupted")
        record = self.server.history.load(self.server.conversation["chat_id"])
        self.assertEqual(record["tool_calls"][0]["output"], "partial")
        self.assertEqual(record["tool_calls"][0]["status"], "interrupted")
        self.server.handle({"type": "chat.send", "prompt": "hola"})
        self.assertEqual(self.finished()["status"], "completed")
        self.assertEqual(self.server.conversation["tool_calls"][0]["output"], "partial")

    def test_shell_is_always_available_and_conversation_needs_no_command(self):
        self.assertTrue(self.server.shell_enabled)
        self.server.handle({"type": "chat.send", "prompt": "hola"})
        self.assertEqual(self.finished()["status"], "completed")
        self.assertEqual(self.service.requests[-1]["body"]["tools"][0]["name"], "shell")
        self.assertFalse(self.server.conversation.get("tool_calls"))
        self.assertIsNone(self.server._shell_control._process)

    def test_completed_context_survives_restart_with_shell_still_available(self):
        self.start()
        self.finished()
        record = self.server.history.load(self.server.conversation["chat_id"])
        output = QueueOutput()
        restarted = HarnessServer(self.root / "chats", output, self.session, self.server.client, workspace=self.root)
        restarted._refresh_account()
        self.addCleanup(restarted._stream.cancel)
        restarted.handle({"type": "chat.open", "chat_id": record["chat_id"]})
        self.assertEqual(restarted.conversation["context"], record["context"])
        restarted.handle({"type": "chat.send", "prompt": "continúa"})
        self.assertEqual(output.wait_for("chat.finished")["status"], "completed")
        request = self.service.requests[-1]["body"]
        self.assertEqual(request["tools"][0]["name"], "shell")
        self.assertTrue(any(item.get("type") == "function_call_output" for item in request["input"]))
        self.assertEqual(len(restarted.conversation["tool_calls"]), 1)

    def test_context_excludes_plain_reasoning_but_preserves_encrypted_content(self):
        from harness.chat.context import replay_items
        items = replay_items([{"type": "reasoning", "id": "reason-1", "encrypted_content": "opaque",
                               "summary": [{"type": "summary_text", "text": "private reasoning"}],
                               "content": [{"type": "reasoning_text", "text": "private reasoning"}]}])
        self.assertNotIn("private reasoning", str(items))
        self.assertEqual(items[0]["encrypted_content"], "opaque")

    def test_persistence_failure_before_execution_prevents_process_creation(self):
        self.service.tool_batches = [[{"command": "touch unexpected"}]]
        save = self.server.history.save
        def fail_before_start(record):
            if any(call["status"] == "running" for call in record.get("tool_calls", [])):
                raise OSError("disk full")
            save(record)
        with patch.object(self.server.history, "save", side_effect=fail_before_start):
            self.start()
            self.assertEqual(self.finished()["status"], "failed")
        self.assertFalse((self.root / "unexpected").exists())

    def test_recovered_running_calls_are_interrupted_and_never_reexecuted(self):
        self.start()
        self.finished()
        record = self.server.history.load(self.server.conversation["chat_id"])
        call = record["tool_calls"][0]
        call.update(status="running", output="", exit_code=None)
        record["context"] = [item for item in record["context"]
                             if item.get("type") != "function_call_output"]
        self.server.history.save(record)
        output = QueueOutput()
        restarted = HarnessServer(self.root / "chats", output, self.session, self.server.client, workspace=self.root)
        with patch("harness.core.server.ShellExecutor.execute") as execute:
            restarted.handle({"type": "chat.open", "chat_id": record["chat_id"]})
            loaded = output.wait_for("chat.loaded")["chat"]
            execute.assert_not_called()
        self.assertEqual(loaded["tool_calls"][0]["status"], "interrupted")
        self.assertTrue(restarted.shell_enabled)
        self.assertEqual(json.loads(restarted.conversation["context"][-1]["output"])["status"], "interrupted")
