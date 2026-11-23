"""Unified mode end to end: each provider as architect delegating through HarnessServer."""

import json
import tempfile
import threading
import unittest
from pathlib import Path

from tests.support import paths  # noqa: F401
from tests.backend.chat.test_agy import _FakeAgyClient
from tests.backend.chat.test_claude import _FakeClaudeClient, _OfflineSession
from tests.support.fake_service import FakeService, FakeSession
from tests.support.sessions import QueueOutput
from harness.account.codex_usage import UsageError
from harness.chat.chatgpt import ChatGPTClient
from harness.core.http import HttpClient
from harness.core.server import MAX_DELEGATION_ROUNDS, HarnessServer

BLOCK = '```delegate\n{"task": "create a.py", "role": "explorer", "provider": null}\n```'


def claude_turn(answer, **result):
    return [{"type": "init", "session_id": "s1", "model": "claude-opus-5-5"},
            {"type": "text_delta", "session_id": "s1", "message_id": "m1", "text": answer},
            {"type": "result", "session_id": "s1", "is_error": False, "result": answer, "error": "",
             "usage": {"total_tokens": 10}, **result}]


def agy_turn(answer):
    return [{"type": "init", "conversation_id": "a1", "model": "gemini"},
            {"type": "text_delta", "conversation_id": "a1", "step_index": 1, "state": "DONE", "text": answer,
             "done": True, "usage": {"total_tokens": 10}},
            {"type": "result", "conversation_id": "a1", "status": "SUCCESS", "response": answer,
             "usage": {"total_tokens": 10}, "error": ""}]


class UnifiedModeTests(unittest.TestCase):
    def start(self, provider, session=None, client=None, agy=None, claude=None):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.output = QueueOutput()
        server = HarnessServer(root / "chats", self.output, session or _OfflineSession(), client, workspace=root,
                               config_root=root / "config", agy_client=agy, claude_client=claude)

        def stop():
            server._stream.cancel()
            server.project_runner.close()
            for worker in server._workers:
                worker.join(3)
        self.addCleanup(stop)
        if claude:
            server._probe_claude_status_silent()
        if provider == "chatgpt":
            server._refresh_account()
        else:
            server.handle({"type": "provider.select", "provider": provider})
            self.output.wait_for("provider.refresh.finished")
        return server

    def send(self, server, prompt="build it"):
        server.handle({"type": "chat.send", "prompt": prompt})
        return self.output.wait_for("chat.finished")

    def test_claude_architect_delegates_and_resumes_its_session(self):
        claude = _FakeClaudeClient(turns=[claude_turn("Plan\n" + BLOCK), claude_turn("Created a.py"),
                                          claude_turn("All verified.")])
        server = self.start("claude", claude=claude)
        server.handle({"type": "unified.toggle"})
        self.assertEqual(self.send(server)["status"], "completed")
        architect, worker, followup = claude.calls
        self.assertIn("you are the architect", architect["prompt"])
        self.assertEqual((worker["model"], worker["session_id"]), ("claude-haiku", ""))
        self.assertNotIn("you are the architect", worker["prompt"])
        self.assertEqual([c["isolated"] for c in claude.calls], [False, True, False])
        self.assertEqual(followup["session_id"], "s1")
        self.assertIn("Created a.py", followup["prompt"])
        card, = [c for c in server.conversation["tool_calls"] if c["command"].startswith("delegate")]
        self.assertEqual((card["command"], card["status"]), ("delegate explorer claude/claude-haiku: create a.py", "completed"))
        answers = [m["text"] for m in server.conversation["messages"] if m["role"] == "assistant"]
        self.assertEqual(answers, ["Plan\n" + BLOCK, "All verified."])

    def test_gemini_architect_delegates_to_another_provider(self):
        agy = _FakeAgyClient(turns=[agy_turn(BLOCK.replace("null", '"claude"')), agy_turn("Verified.")])
        agy.models = lambda force=False: [{"slug": "gemini-4-argon-high", "display_name": "Gemini 4 Argon (High)",
                                           "reasoning_efforts": []}]
        claude = _FakeClaudeClient(turns=[claude_turn("Created a.py")])
        server = self.start("agy", agy=agy, claude=claude)
        server.handle({"type": "unified.toggle"})
        self.assertEqual(self.send(server)["status"], "completed")
        self.assertEqual([c["model"] for c in claude.calls], ["claude-haiku"])
        self.assertEqual(server.conversation["messages"][-1]["text"], "Verified.")

    def test_chatgpt_architect_receives_failed_worker_as_error(self):
        with FakeService() as service:
            service.tool_batches = [[{"name": "delegate", "arguments": json.dumps(
                {"task": "create a.py", "role": "explorer", "provider": "claude"})}]]
            claude = _FakeClaudeClient(turns=[claude_turn("", is_error=True, error="API error")])
            client = ChatGPTClient(FakeSession(), HttpClient(allow_loopback=True, timeout=5), service.url)
            server = self.start("chatgpt", FakeSession(), client, claude=claude)
            server.track_chat_quota = False
            server._last_quota_snapshots["claude"] = {"session_used": 98}
            server.handle({"type": "unified.toggle"})
            self.assertEqual(self.send(server, "shell delegate")["status"], "completed")
            body = service.requests[0]["body"]
            self.assertIn("delegate", [t["name"] for t in body["tools"]])
            self.assertIn("you are the architect", body["instructions"])
            card, = server.conversation["tool_calls"]
            self.assertEqual((card["status"], card["exit_code"]), ("error", 1))

    def test_off_mode_ignores_blocks_and_sends_the_plain_prompt(self):
        claude = _FakeClaudeClient(turns=[claude_turn(BLOCK)])
        server = self.start("claude", claude=claude)
        self.assertEqual(self.send(server)["status"], "completed")
        self.assertEqual([c["prompt"] for c in claude.calls], ["build it"])

    def test_malformed_block_is_reported_to_the_architect(self):
        claude = _FakeClaudeClient(turns=[claude_turn("```delegate\n{bad\n```"), claude_turn("Done.")])
        server = self.start("claude", claude=claude)
        server.handle({"type": "unified.toggle"})
        self.assertEqual(self.send(server)["status"], "completed")
        self.assertEqual(len(claude.calls), 2)

    def test_endless_delegation_is_stopped(self):
        turns = [turn for _ in range(MAX_DELEGATION_ROUNDS + 2)
                 for turn in (claude_turn(BLOCK), claude_turn("worked"))]
        claude = _FakeClaudeClient(turns=turns)
        server = self.start("claude", claude=claude)
        server.handle({"type": "unified.toggle"})
        self.assertEqual(self.send(server)["status"], "failed")
        self.assertEqual(len(claude.calls), 2 * MAX_DELEGATION_ROUNDS + 1)

    def test_cancelling_a_worker_interrupts_the_turn(self):
        working = threading.Event()
        claude = _FakeClaudeClient(turns=[claude_turn(BLOCK)])
        original = claude.stream_turn

        def stream(prompt, model, workspace, control, **kwargs):
            if model != "claude-haiku":
                yield from original(prompt, model, workspace, control, **kwargs)
                return
            working.set()
            control.cancelled.wait(5)
            control.check()

        claude.stream_turn = stream
        server = self.start("claude", claude=claude)
        server.handle({"type": "unified.toggle"})
        server.handle({"type": "chat.send", "prompt": "build it"})
        self.assertTrue(working.wait(5))
        server._stream.cancel()
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "interrupted")

    def test_toggle_is_rejected_while_busy_and_lists_workers_when_on(self):
        server = self.start("claude", claude=_FakeClaudeClient())
        server.busy = True
        server.handle({"type": "unified.toggle"})
        self.assertFalse(server.unified_mode)
        server.busy = False
        server.handle({"type": "unified.toggle"})
        state = {}
        while not state.get("unified_mode"):
            state = self.output.wait_for("provider.state")
        self.assertEqual([row["role"] for row in state["unified_team"]], ["explorer", "builder", "specialist", "reviewer"])
        self.assertEqual([row["workers"][0]["name"] for row in state["unified_team"]],
                         ["Claude Haiku", "Claude Sonnet", "Claude Opus", "Claude Sonnet"])
        server.handle({"type": "unified.toggle"})
        while state["unified_mode"]:
            state = self.output.wait_for("provider.state")
        self.assertEqual(state["unified_team"], [])

    def test_manual_selection_is_locked_and_restored(self):
        server = self.start("claude", claude=_FakeClaudeClient())
        original = (server.provider, server.model)
        server.handle({"type": "unified.toggle"})
        server.handle({"type": "provider.select", "provider": "chatgpt"})
        self.output.wait_for("provider.rejected")
        server.handle({"type": "model.select", "model": "claude-haiku"})
        self.output.wait_for("error")
        self.assertEqual((server.provider, server.model), original)
        server.handle({"type": "unified.toggle"})
        self.assertEqual((server.provider, server.model), original)
        server.handle({"type": "model.select", "model": "claude-haiku"})
        self.assertEqual(self.output.wait_for("model.selected")["model"], "claude-haiku")

    def test_provider_state_announces_architect_only_when_unified(self):
        server = self.start("claude", claude=_FakeClaudeClient())
        server.handle({"type": "unified.toggle"})
        state = {}
        while not state.get("unified_mode"):
            state = self.output.wait_for("provider.state")
        architect = state["unified_architect"]
        self.assertTrue(all(architect.get(key) for key in ("provider", "model", "name")))
        server.handle({"type": "unified.toggle"})
        while state.get("unified_mode"):
            state = self.output.wait_for("provider.state")
        self.assertEqual(state["unified_architect"], {})

    def test_unified_turn_records_actual_architect(self):
        claude = _FakeClaudeClient(turns=[claude_turn("Done.")])
        server = self.start("claude", claude=claude)
        server.handle({"type": "model.select", "model": "claude-haiku"})
        self.output.wait_for("model.selected")
        server.handle({"type": "unified.toggle"})
        self.assertEqual(self.send(server)["status"], "completed")
        self.assertEqual((server.conversation["provider"], server.conversation["model"]),
                         ("claude", claude.calls[0]["model"]))
        self.assertEqual(claude.calls[0]["model"], "claude-opus")
        events = [json.loads(line)["type"] for line in self.output.getvalue().splitlines()]
        started = events.index("chat.busy")
        finished = events.index("chat.finished", started)
        self.assertIn("provider.state", events[started:finished - 1])  # Arquitecto durante el turno.
        self.assertEqual(events[finished - 1], "provider.state")     # Arquitecto previsto para el próximo turno.

    def test_team_reports_quota_resolved_version_and_skips_exhausted(self):
        claude = _FakeClaudeClient()
        claude.resolved_models = {"claude-haiku": "claude-haiku-5-5"}
        server = self.start("claude", claude=claude)
        server.unified_mode = True
        server._last_quota_snapshots = {"claude": {"session_used": 12.4, "weekly_used": 3.0, "captured_at": 0}}
        first = server._unified_team()[0]["workers"][0]
        self.assertEqual(first, {"provider": "claude", "model": "claude-haiku", "name": "Claude Haiku 5.5",
                                 "effort": "medium", "remaining": 88})
        server.worker_router.mark_exhausted("claude")
        self.assertEqual([row["workers"] for row in server._unified_team()], [[], [], [], []])

    def test_every_subagent_is_announced_with_its_progress_and_outcome(self):
        tool = {"type": "tool_start", "session_id": "s", "tool_use_id": "t1", "tool_name": "Read",
                "parameters": {"file_path": "a.py"}}
        claude = _FakeClaudeClient(turns=[claude_turn(BLOCK + "\n" + BLOCK.replace("explorer", "builder")),
                                          [tool] + claude_turn("found it"), claude_turn("", is_error=True, error="boom"),
                                          claude_turn("Done.")])
        server = self.start("claude", claude=claude)
        server.handle({"type": "unified.toggle"})
        server.handle({"type": "chat.send", "prompt": "build it"})
        events = []
        while len({e["id"] for e in events if e["status"] != "running"}) < 2:
            events.append(self.output.wait_for("unified.agent"))
        first = [e for e in events if e["id"] == events[0]["id"]]
        self.assertEqual((first[0]["role"], first[0]["status"], first[0]["worker"]["model"], first[0]["task"]),
                         ("explorer", "running", "claude-haiku", "create a.py"))
        self.assertTrue(any("read_file a.py" in line for e in first for line in e["lines"]))
        self.assertEqual((first[-1]["status"], first[-1]["summary"], first[-1]["tool_calls"]), ("completed", "found it", 1))
        self.assertEqual((events[-1]["role"], events[-1]["status"], events[-1]["error"]), ("builder", "failed", "boom"))
        self.output.wait_for("chat.finished")

    def test_cancelled_subagent_is_not_left_running(self):
        working = threading.Event()
        claude = _FakeClaudeClient(turns=[claude_turn(BLOCK)])
        original = claude.stream_turn

        def stream(prompt, model, workspace, control, **kwargs):
            if model != "claude-haiku":
                yield from original(prompt, model, workspace, control, **kwargs)
                return
            working.set()
            control.cancelled.wait(5)
            control.check()

        claude.stream_turn = stream
        server = self.start("claude", claude=claude)
        server.handle({"type": "unified.toggle"})
        server.handle({"type": "chat.send", "prompt": "build it"})
        self.assertTrue(working.wait(5))
        server._stream.cancel()
        event = {"status": "running"}
        while event["status"] == "running":
            event = self.output.wait_for("unified.agent")
        self.assertEqual(event["status"], "interrupted")

    ARGON = [{"slug": "gemini-4-argon-high", "display_name": "Gemini 4 Argon (High)", "reasoning_efforts": []}]

    def test_architect_out_of_quota_is_replaced_within_the_turn(self):
        agy = _FakeAgyClient(turns=[agy_turn(BLOCK), [{"type": "error", "message": "RESOURCE_EXHAUSTED (code 429)"}]])
        agy.models = lambda force=False: self.ARGON
        claude = _FakeClaudeClient(turns=[claude_turn("found the bug"), claude_turn("Finished by Opus.")])
        server = self.start("agy", agy=agy, claude=claude)
        server._last_quota_snapshots["claude"] = {"session_used": 50, "captured_at": 0}
        server._last_quota_snapshots["agy:argon"] = {"session_used": 10, "captured_at": 0}
        server.handle({"type": "unified.toggle"})
        self.assertEqual(self.send(server)["status"], "completed")
        handoff = claude.calls[-1]
        self.assertEqual((handoff["model"], handoff["isolated"]), ("claude-opus", False))
        for fragment in ("you are the architect", "build it", "found the bug"):
            self.assertIn(fragment, handoff["prompt"])
        self.assertEqual((server.conversation["provider"], server.conversation["model"]), ("claude", "claude-opus"))
        self.assertEqual(server.conversation["messages"][-1]["text"], "Finished by Opus.")
        self.assertEqual(server._pick_architect().provider, "claude")

    def test_chatgpt_architect_out_of_quota_is_replaced(self):
        with FakeService() as service:
            service.models = [{"slug": "gpt-6.2-astra", "display_name": "GPT-6.2-Astra", "visibility": "list"}]
            claude = _FakeClaudeClient(turns=[claude_turn("Finished by Opus.")])
            client = ChatGPTClient(FakeSession(), HttpClient(allow_loopback=True, timeout=5), service.url)
            server = self.start("chatgpt", FakeSession(), client, claude=claude)
            server._last_quota_snapshots["claude"] = {"session_used": 80, "captured_at": 0}
            server.handle({"type": "unified.toggle"})
            self.assertEqual(self.send(server, "fail")["status"], "completed")
            self.assertEqual(server.conversation["messages"][-1]["text"], "Finished by Opus.")

    def test_claude_architect_hands_over_to_chatgpt(self):
        with FakeService() as service:
            service.models = [{"slug": "gpt-6.2-astra", "display_name": "GPT-6.2-Astra", "visibility": "list"}]
            claude = _FakeClaudeClient(turns=[claude_turn("", is_error=True, error="You've hit your session limit")])
            client = ChatGPTClient(FakeSession(), HttpClient(allow_loopback=True, timeout=5), service.url)
            server = self.start("chatgpt", FakeSession(), client, claude=claude)
            server._last_quota_snapshots["chatgpt"] = {"session_used": 80, "captured_at": 0}
            server.handle({"type": "unified.toggle"})
            self.assertEqual(self.send(server)["status"], "completed")
            self.assertEqual(service.requests[0]["body"]["model"], "gpt-6.2-astra")
            self.assertIn("build it", json.dumps(service.requests[0]["body"]["input"]))

    def test_turn_fails_when_every_architect_is_exhausted(self):
        limit = claude_turn("", is_error=True, error="You've hit your session limit")
        claude = _FakeClaudeClient(turns=[limit, limit])
        server = self.start("claude", claude=claude)
        server.handle({"type": "unified.toggle"})
        self.assertEqual(self.send(server)["status"], "failed")
        self.assertEqual(len(claude.calls), 1)

    def test_ordinary_architect_error_is_not_retried(self):
        agy = _FakeAgyClient()
        agy.models = lambda force=False: self.ARGON
        claude = _FakeClaudeClient(turns=[claude_turn("", is_error=True, error="API error")])
        server = self.start("claude", agy=agy, claude=claude)
        server._last_quota_snapshots["agy:argon"] = {"session_used": 80, "captured_at": 0}
        server.handle({"type": "unified.toggle"})
        self.assertEqual(self.send(server)["status"], "failed")

    def test_reviewer_avoids_the_vendor_that_built(self):
        agy = _FakeAgyClient(turns=[agy_turn("reviewed")])
        rows = [{"slug": "gemini-3.8-flash-medium", "display_name": "Gemini 3.8 Flash (Medium)", "reasoning_efforts": []}]
        agy.models = lambda force=False: rows
        claude = _FakeClaudeClient(turns=[
            claude_turn(BLOCK.replace("explorer", "builder") + "\n" + BLOCK.replace("explorer", "reviewer")),
            claude_turn("built"), claude_turn("Done.")])
        server = self.start("claude", agy=agy, claude=claude)
        server.handle({"type": "unified.toggle"})
        self.assertEqual(self.send(server)["status"], "completed")
        cards = [c["command"].split(":")[0] for c in server.conversation["tool_calls"]]
        self.assertEqual(cards, ["delegate builder claude/claude-sonnet", "delegate reviewer agy/gemini-3.8-flash-medium"])

    def test_usage_is_published_for_every_provider_and_errors_stay_isolated(self):
        agy = _FakeAgyClient()
        agy.usage = lambda: (_ for _ in ()).throw(UsageError("timeout", "agy tardó demasiado."))
        server = self.start("claude", agy=agy, claude=_FakeClaudeClient())
        server.handle({"type": "unified.usage"})
        rows = [self.output.wait_for("usage.provider") for _ in range(3)]
        self.output.wait_for("unified.usage.finished")
        by_provider = {row["provider"]: row for row in rows}
        self.assertEqual(set(by_provider), {"chatgpt", "agy", "claude"})
        self.assertEqual(by_provider["claude"]["limits"][0]["primary"]["used_percent"], 12.0)
        self.assertEqual(by_provider["claude"]["error"], "")
        self.assertEqual(by_provider["agy"]["error"], "agy tardó demasiado.")
        self.assertIn("sesión", by_provider["chatgpt"]["error"])
        self.assertEqual(server._remaining_quota(), {"claude": 88.0})
        self.assertFalse(server.team_usage_pending)

    def test_concurrent_usage_requests_are_merged(self):
        claude, gate, calls = _FakeClaudeClient(), threading.Event(), []
        original = claude.usage

        def usage():
            calls.append(1)
            gate.wait(3)
            return original()
        claude.usage = usage
        server = self.start("claude", claude=claude)
        server.handle({"type": "unified.usage"})
        server.handle({"type": "unified.usage"})
        gate.set()
        self.output.wait_for("unified.usage.finished")
        self.assertEqual(len(calls), 1)

    def test_worker_quota_uses_the_tightest_window_per_bucket(self):
        server = self.start("claude", claude=_FakeClaudeClient())
        server.track_chat_quota = True
        self.assertEqual(server._worker_quota(), {"claude": 88.0})


if __name__ == "__main__":
    unittest.main()
