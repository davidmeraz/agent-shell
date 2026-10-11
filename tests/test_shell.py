"""Shell real en carpetas temporales y ciclo de herramientas con HTTP/SSE local."""

import json
import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "backend"))

from fake_service import FakeService, FakeSession
from test_harness import QueueOutput
from harness.chatgpt import ChatGPTClient
from harness.http import Cancelled, HttpClient
from harness.server import HarnessServer
from harness.shell import ShellControl, ShellExecutor, parse_command


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
        self.assertEqual(state, "Z", f"Proceso {pid} sobrevivió")

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
        with patch("harness.shell.subprocess.Popen") as spawn, self.assertRaises(Cancelled):
            self.execute("pwd")
        spawn.assert_not_called()

    def test_environment_does_not_inherit_arbitrary_backend_variables(self):
        with patch.dict(os.environ, {"AGENT_SHELL_TEST_SECRET": "test-only-secret"}):
            result = self.execute("printf '%s' ${AGENT_SHELL_TEST_SECRET-unset}")
        self.assertEqual(result["output"], "unset")

    def test_argument_schema_rejects_permissions_paths_and_invalid_commands(self):
        for value in (None, [], {}, {"command": ""}, {"command": 3}, {"command": "x\0y"},
                      {"command": "x" * 8001}, {"command": "pwd", "approved": True},
                      {"command": "pwd", "workdir": "/"}, {"command": "pwd", "background": True}):
            with self.subTest(value=str(value)[:70]), self.assertRaises(ValueError):
                parse_command(json.dumps(value))


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
        self.server.handle({"type": "shell.configure", "workdir": str(self.root), "enabled": True})
        self.output.wait_for("shell.state")
        self.server.handle({"type": "chat.send", "prompt": "shell-pwd"})

    def decide(self, approval, approved=True):
        self.server.handle({"type": "tool.decide", "request_id": approval["request_id"], "approved": approved})

    def test_complete_tool_cycle_returns_actual_result_and_preserves_provider_items(self):
        self.service.tool_preface = "Voy a consultar el directorio."
        self.start()
        approval = self.output.wait_for("tool.approval")
        self.assertTrue(self.server.busy)
        self.assertEqual(approval["call"]["command"], "pwd")
        self.assertEqual(approval["call"]["workdir"], str(self.root))
        self.assertIsNone(self.server._shell_control._process)
        self.decide(approval)
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "completed")
        record = self.server.history.load(self.server.conversation["chat_id"])
        self.assertEqual(record["tool_calls"][0]["output"].strip(), str(self.root))
        self.assertIn(str(self.root), record["messages"][-1]["text"])
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
        self.assertGreaterEqual(metrics["approval_ms"], 0)
        self.assertGreater(metrics["tool_ms"], 0)
        self.assertIsNone(metrics["characters_per_second"])

    def test_denied_command_has_no_side_effect_and_stops_model_loop(self):
        self.service.tool_batches = [[{"command": "touch forbidden"}]]
        self.start()
        approval = self.output.wait_for("tool.approval")
        self.decide(approval, False)
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "interrupted")
        self.assertFalse((self.root / "forbidden").exists())
        self.assertEqual(len(self.service.requests), 1)
        self.assertEqual(self.server.conversation["tool_calls"][0]["status"], "denied")
        self.assertEqual(json.loads(self.server.conversation["context"][-1]["output"])["status"], "denied")

    def test_empty_completed_output_replays_full_stream_items_after_completion(self):
        self.service.tool_stream_items = True
        self.service.tool_preface = "Consultaré la carpeta."
        self.start()
        approval = self.output.wait_for("tool.approval")
        self.decide(approval)
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "completed")
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
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "interrupted")
        self.assertIsNone(self.server._pending_approval)
        self.assertFalse(self.server.conversation.get("tool_calls"))

    def test_cancel_while_awaiting_approval_rejects_late_decision(self):
        self.service.tool_batches = [[{"command": "touch forbidden"}]]
        self.start()
        approval = self.output.wait_for("tool.approval")
        self.server.handle({"type": "chat.cancel"})
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "interrupted")
        self.decide(approval)
        self.assertIn("ya no", self.output.wait_for("error")["message"])
        self.assertFalse((self.root / "forbidden").exists())
        self.assertEqual(self.server.conversation["tool_calls"][0]["status"], "interrupted")

    def test_wrong_nonce_and_non_boolean_decisions_cannot_approve(self):
        self.start()
        approval = self.output.wait_for("tool.approval")
        for request in ({"request_id": "wrong", "approved": True},
                        {"request_id": approval["request_id"], "approved": "true"}):
            self.server.handle({"type": "tool.decide", **request})
            self.output.wait_for("error")
            self.assertIsNone(self.server._shell_control._process)
        self.decide(approval, False)
        self.output.wait_for("chat.finished")

    def test_partial_tool_arguments_never_execute_before_completed_response(self):
        self.service.tool_completion_gate = threading.Event()
        self.start()
        self.assertTrue(self.service.started.wait(2))
        self.assertIsNone(self.server._pending_approval)
        self.assertIsNone(self.server._shell_control._process)
        self.service.tool_completion_gate.set()
        self.decide(self.output.wait_for("tool.approval"))
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "completed")

    def test_unknown_tool_or_permission_spoof_is_returned_as_error_without_execution(self):
        for spec in ({"name": "other", "command": "touch forbidden"},
                     {"arguments": json.dumps({"command": "touch forbidden", "approved": True})}):
            self.service.tool_batches = [[spec]]
            self.start()
            self.assertEqual(self.output.wait_for("chat.finished")["status"], "completed")
            self.assertFalse((self.root / "forbidden").exists())
            self.assertIsNone(self.server._pending_approval)
            self.assertEqual(self.server.conversation["tool_calls"][-1]["status"], "error")

    def test_multiple_commands_are_approved_and_executed_sequentially(self):
        self.service.tool_batches = [[{"command": "printf first > state"}, {"command": "cat state"}]]
        self.start()
        first = self.output.wait_for("tool.approval")
        self.assertFalse((self.root / "state").exists())
        self.decide(first)
        second = self.output.wait_for("tool.approval")
        self.assertEqual((self.root / "state").read_text(), "first")
        self.decide(second)
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "completed")
        self.assertEqual(self.server.conversation["tool_calls"][-1]["output"], "first")

    def test_step_limit_does_not_execute_excess_commands(self):
        self.service.tool_batches = [[{"command": "pwd"}]] * 9
        self.start()
        for _ in range(7):
            self.decide(self.output.wait_for("tool.approval"))
        finished = self.output.wait_for("chat.finished")
        self.assertEqual(finished["status"], "failed")
        self.assertIn("límite", finished["message"])
        self.assertEqual(len(self.server.conversation["tool_calls"]), 7)

    def test_workspace_changes_are_validated_and_blocked_during_a_turn(self):
        self.server.handle({"type": "shell.configure", "workdir": str(self.root / "missing"), "enabled": True})
        self.output.wait_for("error")
        self.assertFalse(self.server.shell_enabled)
        self.start()
        approval = self.output.wait_for("tool.approval")
        self.server.handle({"type": "shell.configure", "workdir": "/", "enabled": False})
        self.output.wait_for("error")
        self.assertEqual(self.server.workspace, self.root)
        self.assertTrue(self.server.shell_enabled)
        self.decide(approval, False)
        self.output.wait_for("chat.finished")

    def test_cancel_running_shell_keeps_output_and_allows_new_turn(self):
        self.service.tool_batches = [[{"command": "printf partial; sleep 30"}]]
        self.start()
        self.decide(self.output.wait_for("tool.approval"))
        while True:
            call = self.output.wait_for("tool.updated")["call"]
            if call["status"] == "running" and call["output"]:
                break
        self.server.handle({"type": "chat.cancel"})
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "interrupted")
        record = self.server.history.load(self.server.conversation["chat_id"])
        self.assertEqual(record["tool_calls"][0]["output"], "partial")
        self.assertEqual(record["tool_calls"][0]["status"], "interrupted")
        self.server.handle({"type": "chat.send", "prompt": "hola"})
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "completed")
        self.assertEqual(self.server.conversation["tool_calls"][0]["output"], "partial")

    def test_shell_is_off_by_default_and_plain_text_does_not_execute(self):
        self.assertFalse(self.server.shell_enabled)
        self.server.handle({"type": "chat.send", "prompt": "shell-pwd"})
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "completed")
        self.assertNotIn("tools", self.service.requests[-1]["body"])
        self.assertNotIn("tool_calls", self.server.conversation)
        self.assertIsNone(self.server._shell_control._process)

    def test_completed_context_survives_new_backend_and_can_continue_without_tools(self):
        self.start()
        self.decide(self.output.wait_for("tool.approval"))
        self.output.wait_for("chat.finished")
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
        self.assertEqual(request["tools"], [])
        self.assertTrue(any(item.get("type") == "function_call_output" for item in request["input"]))
        self.assertEqual(len(restarted.conversation["tool_calls"]), 1)

    def test_context_excludes_plain_reasoning_but_preserves_encrypted_content(self):
        from harness.context import replay_items
        items = replay_items([{"type": "reasoning", "id": "reason-1", "encrypted_content": "opaque",
                               "summary": [{"type": "summary_text", "text": "private reasoning"}],
                               "content": [{"type": "reasoning_text", "text": "private reasoning"}]}])
        self.assertNotIn("private reasoning", str(items))
        self.assertEqual(items[0]["encrypted_content"], "opaque")

    def test_persistence_failure_after_approval_prevents_execution(self):
        self.service.tool_batches = [[{"command": "touch forbidden"}]]
        self.start()
        approval = self.output.wait_for("tool.approval")
        with patch.object(self.server.history, "save", side_effect=OSError("disk full")):
            self.decide(approval)
            self.assertEqual(self.output.wait_for("chat.finished")["status"], "failed")
        self.assertFalse((self.root / "forbidden").exists())

    def test_recovered_pending_calls_are_interrupted_and_never_reexecuted(self):
        self.service.tool_batches = [[{"command": "touch forbidden"}]]
        self.start()
        self.output.wait_for("tool.approval")
        saved_id = self.server.conversation["chat_id"]
        output = QueueOutput()
        restarted = HarnessServer(self.root / "chats", output, self.session, self.server.client, workspace=self.root)
        restarted.handle({"type": "chat.open", "chat_id": saved_id})
        loaded = output.wait_for("chat.loaded")["chat"]
        self.assertEqual(loaded["tool_calls"][0]["status"], "interrupted")
        self.assertFalse((self.root / "forbidden").exists())
        self.assertFalse(restarted.shell_enabled)
        self.assertIsNone(restarted._pending_approval)
        self.assertEqual(json.loads(restarted.conversation["context"][-1]["output"])["status"], "interrupted")
