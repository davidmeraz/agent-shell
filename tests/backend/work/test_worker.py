"""Workers fed with the events the real CLI parsers produce."""

import json
import tempfile
import unittest
from pathlib import Path

from tests.support import paths  # noqa: F401
from harness.chat.agy import parse_stream_line
from harness.chat.claude import isolation_flags, parse_claude_stream_line
from harness.core.http import ServiceError, StreamControl
from harness.work.roster import Candidate
from harness.work.worker import (
    DELEGATE_TOOL, WorkerControl, WorkerRouter, extract_delegations, is_quota_error, parse_delegate_arguments,
)

CHATGPT = Candidate("chatgpt", "gpt-6-luna", "medium", "fast", "chatgpt")
AGY = Candidate("agy", "gemini-3.8-flash-medium", "", "fast", "agy:gemini")
CLAUDE = Candidate("claude", "claude-haiku", "medium", "fast", "claude")


class ScriptedCli:
    def __init__(self, parse, lines):
        self.parse, self.lines, self.calls = parse, lines, []

    def stream_turn(self, prompt, model, workspace, control, **kwargs):
        self.calls.append({"prompt": prompt, "model": model, **kwargs})
        for line in self.lines:
            events = self.parse(json.dumps(line))
            yield from events if isinstance(events, list) else [events]


class ScriptedChatGPT:
    def __init__(self, *responses):
        self.responses, self.calls = list(responses), []

    def stream(self, model, messages, instructions, control, **kwargs):
        self.calls.append({"messages": json.loads(json.dumps(messages)), **kwargs})
        yield self.responses.pop(0)


def completed(*output):
    return {"type": "response.completed", "response": {"output": list(output), "usage": {"total_tokens": 15}}}


def text(value):
    return {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": value}]}


def tool(name, arguments, call_id="c1"):
    return {"type": "function_call", "name": name, "call_id": call_id, "arguments": json.dumps(arguments)}


class WorkerCase(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.workspace = Path(temp.name)
        self.progress = []

    def run_worker(self, candidate, client, max_steps=8, control=None):
        router = WorkerRouter(*(client if candidate.provider == name else None
                                for name in ("chatgpt", "agy", "claude")))
        router.workspace = self.workspace
        return router.run("do it", candidate, control or StreamControl(), max_steps, self.progress.append)


class ClaudeWorkerTests(WorkerCase):
    def lines(self, **result):
        return ScriptedCli(parse_claude_stream_line, [
            {"type": "assistant", "message": {"id": "m", "content": [
                {"type": "tool_use", "id": "t1", "name": "Write", "input": {"file_path": str(self.workspace / "new.py")}},
                {"type": "tool_use", "id": "t2", "name": "Edit", "input": {"file_path": "denied.py"}}],
                "usage": {"input_tokens": 10, "output_tokens": 5}}},
            {"type": "user", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "t1", "content": "ok"},
                {"type": "tool_result", "tool_use_id": "t2", "content": "no", "is_error": True}]}},
            {"type": "result", "usage": {"input_tokens": 30, "output_tokens": 8}, **result},
        ])

    def test_reports_summary_files_and_tokens_once(self):
        client = self.lines(is_error=False, result="Created new.py")
        result = self.run_worker(CLAUDE, client)
        self.assertEqual((result.status, result.summary, result.files_changed, result.tool_calls, result.tokens_used),
                         ("completed", "Created new.py", ["new.py"], 2, 38))
        self.assertEqual((client.calls[0]["effort"], client.calls[0]["isolated"]), ("medium", True))
        self.assertIn("worker executing one bounded task", client.calls[0]["prompt"])
        self.assertTrue(self.progress)

    def test_error_result_is_never_completed(self):
        quota = self.run_worker(CLAUDE, self.lines(is_error=True, result="You've hit your session limit"))
        self.assertEqual(quota.status, "quota_exhausted")
        other = self.run_worker(CLAUDE, self.lines(is_error=True, result="API error"))
        self.assertEqual(other.status, "failed")

    def test_empty_report_is_a_failure(self):
        self.assertEqual(self.run_worker(CLAUDE, self.lines(is_error=False, result="")).status, "failed")


    def test_isolation_keeps_user_permission_settings(self):
        flags = isolation_flags()
        self.assertIn("--strict-mcp-config", flags)
        self.assertNotIn("--setting-sources", flags)
        self.assertEqual(set(json.loads(flags[-1])), {"claudeMdExcludes", "outputStyle"})


class AgyWorkerTests(WorkerCase):
    def lines(self, status, error=""):
        step = {"step_type": "tool", "step_index": 1, "tool_name": "write_to_file",
                "tool_info": {"parameters": {"TargetFile": str(self.workspace / "a.py")}}}
        return ScriptedCli(parse_stream_line, [
            {"event": "step_update", "step_update": {**step, "state": "ACTIVE"}},
            {"event": "step_update", "step_update": {**step, "state": "DONE"}},
            {"event": "step_update", "step_update": {"step_type": "agent_response", "step_index": 2, "state": "DONE",
                                                     "text_delta": "Done.", "usage": {"total_tokens": 30}}},
            {"event": "result", "result": {"status": status, "response": "Done.", "error": error,
                                           "usage": {"total_tokens": 30}}},
        ])

    def test_counts_tool_once_and_does_not_double_tokens(self):
        result = self.run_worker(AGY, self.lines("SUCCESS"))
        self.assertEqual((result.status, result.files_changed, result.tool_calls, result.tokens_used),
                         ("completed", ["a.py"], 1, 30))

    def test_exhausted_resource_is_quota(self):
        self.assertEqual(self.run_worker(AGY, self.lines("ERROR", "RESOURCE_EXHAUSTED")).status, "quota_exhausted")


class ChatGPTWorkerTests(WorkerCase):
    PATCH = {"patch": "*** Begin Patch\n*** Add File: b.txt\n+hi\n*** End Patch"}

    def test_replays_reasoning_and_reports_real_paths(self):
        reasoning = {"type": "reasoning", "id": "r1", "summary": [], "encrypted_content": "opaque"}
        client = ScriptedChatGPT(completed(reasoning, tool("apply_patch", self.PATCH)), completed(text("Added b.txt")))
        result = self.run_worker(CHATGPT, client)
        self.assertEqual((result.status, result.files_changed, result.tokens_used), ("completed", ["b.txt"], 30))
        self.assertEqual((self.workspace / "b.txt").read_text(), "hi\n")
        kinds = [item.get("type", "message") for item in client.calls[1]["messages"]]
        self.assertEqual(kinds, ["message", "reasoning", "function_call", "function_call_output"])
        self.assertEqual(client.calls[0]["reasoning_effort"], "medium")

    def test_step_limit_is_incomplete(self):
        client = ScriptedChatGPT(*[completed(tool("shell", {"command": "true"}, f"c{i}")) for i in range(2)])
        self.assertEqual(self.run_worker(CHATGPT, client, max_steps=2).status, "incomplete")

    def test_failed_response_uses_error_code_for_quota(self):
        failed = {"type": "response.failed", "response": {"error": {"code": "subscription_sharing_usage_limit_exceeded"}}}
        self.assertEqual(self.run_worker(CHATGPT, ScriptedChatGPT(failed)).status, "quota_exhausted")
        self.assertEqual(self.run_worker(CHATGPT, ScriptedChatGPT({"type": "response.incomplete"})).status, "failed")

    def test_cancelled_is_interrupted(self):
        control = StreamControl()
        control.cancel()
        self.assertEqual(self.run_worker(CHATGPT, ScriptedChatGPT(), control=control).status, "interrupted")


class ContractTests(unittest.TestCase):
    def test_strict_schema_requires_every_property(self):
        schema = DELEGATE_TOOL["parameters"]
        self.assertEqual(set(schema["required"]), set(schema["properties"]))

    def test_worker_control_shares_only_cancellation(self):
        phases = []
        parent = StreamControl(phases.append)
        parent.turn_state = "architect"
        child = WorkerControl(parent)
        child.mark("request")
        self.assertEqual((phases, child.turn_state), ([], ""))
        parent.cancel()
        self.assertTrue(child.cancelled.is_set())

    def test_arguments_are_validated(self):
        self.assertEqual(parse_delegate_arguments('{"task": " x ", "level": "hard", "provider": null}'),
                         {"task": "x", "level": "hard", "provider": ""})
        for bad in ('[]', '{"task": ""}', '{"task": "x", "level": "epic"}', '{"task": "x", "provider": "other"}', '{'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                parse_delegate_arguments(bad)

    def test_only_delegate_fences_are_extracted(self):
        answer = 'Plan\n```json\n{"task": "no"}\n```\n```delegate\n{"task": "a"}\n```\n```delegate\n{"task": "b"}\n```\n'
        self.assertEqual(extract_delegations(answer), ['{"task": "a"}', '{"task": "b"}'])

    def test_quota_detection(self):
        for error in (ServiceError("x", status=429), ServiceError("rate limit"), ServiceError("You've hit your weekly limit"),
                      ServiceError("Alcanzaste un límite de uso."), ServiceError("x", code="usage_limit_reached")):
            self.assertTrue(is_quota_error(error), error)
        for message in ("internal server error", "context limit exceeded"):
            self.assertFalse(is_quota_error(ServiceError(message)), message)


if __name__ == "__main__":
    unittest.main()
