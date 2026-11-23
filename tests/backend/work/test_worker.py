"""WorkerRouter: delegation across providers with fake clients."""

import json
import tempfile
import threading
import unittest
from pathlib import Path

from harness.core.http import Cancelled, ServiceError, StreamControl
from harness.work.worker import (
    DELEGATE_TOOL,
    WORKER_INSTRUCTIONS,
    WorkerResult,
    WorkerRouter,
    _infer_files_from_tool_event,
    _is_quota_error,
)


class FakeStreamControl(StreamControl):
    def __init__(self):
        super().__init__()

    def check(self):
        if self.cancelled.is_set():
            raise Cancelled()


class FakeChatGPTStream:
    """Yields a minimal sequence: one text response or tool calls then text."""

    def __init__(self, responses):
        self._responses = responses
        self._index = 0

    def __iter__(self):
        return self

    def __next__(self):
        if self._index >= len(self._responses):
            raise StopIteration
        event = self._responses[self._index]
        self._index += 1
        return event

    def close(self):
        pass


def _completed_response(output_items, usage=None):
    return {
        "type": "response.completed",
        "response": {
            "status": "completed",
            "output": output_items,
            "usage": usage or {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15},
        },
    }


def _text_message(text):
    return {
        "type": "message",
        "role": "assistant",
        "content": [{"type": "output_text", "text": text}],
    }


def _tool_call(name, arguments, call_id="call_1"):
    return {
        "type": "function_call",
        "name": name,
        "arguments": json.dumps(arguments),
        "call_id": call_id,
    }


class FakeChatGPTClient:
    def __init__(self, stream_responses):
        self._stream_responses = stream_responses
        self._call_count = 0

    def stream(self, model, messages, instructions, control, **kwargs):
        responses = self._stream_responses[min(self._call_count, len(self._stream_responses) - 1)]
        self._call_count += 1
        return FakeChatGPTStream(responses)


class FakeAgyClient:
    def __init__(self, events):
        self._events = events

    def is_available(self):
        return True

    def stream_turn(self, prompt, model, workspace, control, **kwargs):
        for event in self._events:
            yield event


class FakeClaudeClient:
    def __init__(self, events):
        self._events = events

    def is_available(self):
        return True

    def stream_turn(self, prompt, model, workspace, control, **kwargs):
        for event in self._events:
            yield event


class WorkerResultTests(unittest.TestCase):
    def test_to_dict_round_trip(self):
        r = WorkerResult(status="completed", summary="Done", provider="chatgpt", model="gpt-4.1-mini")
        d = r.to_dict()
        self.assertEqual(d["status"], "completed")
        self.assertEqual(d["summary"], "Done")
        self.assertEqual(d["provider"], "chatgpt")

    def test_to_tool_output_is_valid_json(self):
        r = WorkerResult(summary="OK")
        output = r.to_tool_output()
        parsed = json.loads(output)
        self.assertEqual(parsed["summary"], "OK")


class DelegateToolTests(unittest.TestCase):
    def test_delegate_tool_schema(self):
        self.assertEqual(DELEGATE_TOOL["name"], "delegate")
        self.assertTrue(DELEGATE_TOOL["strict"])
        props = DELEGATE_TOOL["parameters"]["properties"]
        self.assertIn("task", props)
        self.assertIn("provider", props)
        self.assertIn("model", props)
        self.assertIn("max_steps", props)
        self.assertEqual(DELEGATE_TOOL["parameters"]["required"], ["task"])


class ChatGPTWorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        self.events = []

    def emit(self, event_type, **data):
        self.events.append({"type": event_type, **data})

    def test_simple_text_response(self):
        client = FakeChatGPTClient([
            [_completed_response([_text_message("Task done.")])]
        ])
        router = WorkerRouter(client, None, None, None, self.workspace, self.emit)
        result = router.run("Do something", "chatgpt", "gpt-4.1-mini", FakeStreamControl())
        self.assertEqual(result.status, "completed")
        self.assertIn("Task done", result.summary)
        self.assertEqual(result.provider, "chatgpt")
        self.assertEqual(result.tool_calls, 0)

    def test_tool_call_then_response(self):
        step1 = [_completed_response([
            _tool_call("read_file", {"file_path": "test.py", "offset": 1, "limit": 50}),
        ])]
        step2 = [_completed_response([_text_message("Read the file.")])]
        client = FakeChatGPTClient([step1, step2])
        router = WorkerRouter(client, None, None, None, self.workspace, self.emit)
        (self.workspace / "test.py").write_text("print('hello')")
        result = router.run("Read test.py", "chatgpt", "gpt-4.1-mini", FakeStreamControl())
        self.assertEqual(result.status, "completed")
        self.assertEqual(result.tool_calls, 1)
        worker_tool_events = [e for e in self.events if e["type"] == "worker.tool"]
        self.assertEqual(len(worker_tool_events), 1)

    def test_cancelled_returns_interrupted(self):
        control = FakeStreamControl()
        control.cancelled.set()
        client = FakeChatGPTClient([[_completed_response([_text_message("OK")])]])
        router = WorkerRouter(client, None, None, None, self.workspace, self.emit)
        result = router.run("Task", "chatgpt", "gpt-4.1-mini", control)
        self.assertEqual(result.status, "interrupted")


class AgyWorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        self.events = []

    def emit(self, event_type, **data):
        self.events.append({"type": event_type, **data})

    def test_text_only_response(self):
        agy_events = [
            {"type": "init", "conversation_id": "conv-1"},
            {"type": "text_delta", "text": "Done.", "done": True,
             "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}},
            {"type": "result", "status": "SUCCESS", "response": "Done."},
        ]
        agy = FakeAgyClient(agy_events)
        router = WorkerRouter(None, agy, None, None, self.workspace, self.emit)
        result = router.run("Do it", "agy", "gemini-2.5-flash", FakeStreamControl())
        self.assertEqual(result.status, "completed")
        self.assertEqual(result.provider, "agy")
        self.assertIn("Done", result.summary)

    def test_tool_events_counted(self):
        agy_events = [
            {"type": "init"},
            {"type": "tool", "step_index": 0, "tool_name": "apply_patch", "state": "RUNNING",
             "parameters": {"file_path": "main.py"}},
            {"type": "tool", "step_index": 0, "tool_name": "apply_patch", "state": "DONE",
             "parameters": {"file_path": "main.py"}, "output": "patched"},
            {"type": "text_delta", "text": "Patched main.py", "done": True,
             "usage": {"input_tokens": 20, "output_tokens": 10, "total_tokens": 30}},
            {"type": "result", "status": "SUCCESS", "response": "Patched main.py"},
        ]
        agy = FakeAgyClient(agy_events)
        router = WorkerRouter(None, agy, None, None, self.workspace, self.emit)
        result = router.run("Patch it", "agy", "gemini-2.5-flash", FakeStreamControl())
        self.assertEqual(result.tool_calls, 1)
        self.assertEqual(len(result.files_changed), 1)
        self.assertEqual(result.files_changed[0]["path"], "main.py")


class ClaudeWorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        self.events = []

    def emit(self, event_type, **data):
        self.events.append({"type": event_type, **data})

    def test_text_only_response(self):
        claude_events = [
            {"type": "text_delta", "text": "Implemented."},
            {"type": "usage", "usage": {"input_tokens": 15, "output_tokens": 8}},
            {"type": "result", "response": "Implemented."},
        ]
        claude = FakeClaudeClient(claude_events)
        router = WorkerRouter(None, None, claude, None, self.workspace, self.emit)
        result = router.run("Do it", "claude", "claude-haiku", FakeStreamControl())
        self.assertEqual(result.status, "completed")
        self.assertEqual(result.provider, "claude")
        self.assertEqual(result.tokens_used["input"], 15)

    def test_tool_done_events_counted(self):
        claude_events = [
            {"type": "tool_start", "tool_name": "Write", "parameters": {"file_path": "new.py"}},
            {"type": "tool_done", "tool_name": "Write", "parameters": {"file_path": "new.py"}},
            {"type": "text_delta", "text": "Created new.py"},
            {"type": "result", "response": "Created new.py"},
        ]
        claude = FakeClaudeClient(claude_events)
        router = WorkerRouter(None, None, claude, None, self.workspace, self.emit)
        result = router.run("Write", "claude", "claude-haiku", FakeStreamControl())
        self.assertEqual(result.tool_calls, 1)
        self.assertEqual(len(result.files_changed), 1)


class InferFilesTests(unittest.TestCase):
    def test_apply_patch_infers_modified(self):
        result = _infer_files_from_tool_event("apply_patch", {"file_path": "a.py"}, Path("/tmp"))
        self.assertEqual(result, [{"path": "a.py", "action": "modified"}])

    def test_shell_write_infers_created(self):
        result = _infer_files_from_tool_event("shell", {"command": "echo x > file.txt"}, Path("/tmp"))
        self.assertEqual(result, [{"path": "(shell write)", "action": "created"}])

    def test_read_file_no_inference(self):
        result = _infer_files_from_tool_event("read_file", {"file_path": "a.py"}, Path("/tmp"))
        self.assertEqual(result, [])


class QuotaErrorDetectionTests(unittest.TestCase):
    def test_429_is_quota(self):
        self.assertTrue(_is_quota_error(ServiceError("too fast", status=429)))

    def test_rate_limit_text(self):
        self.assertTrue(_is_quota_error(ServiceError("rate limit exceeded")))

    def test_quota_text(self):
        self.assertTrue(_is_quota_error(ServiceError("quota exceeded")))

    def test_generic_error_not_quota(self):
        self.assertFalse(_is_quota_error(ServiceError("internal server error")))


if __name__ == "__main__":
    unittest.main()
