"""Unified mode end to end: architect cascade with quota threshold and 2 dedicated workers (parallel)."""

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

BLOCK = '```delegate\n{"task": "create a.py", "worker": null, "read_only": false}\n```'
NEON_CATALOG = [
    {"slug": "gemini-4-neon-xhigh", "display_name": "Gemini 4 Neon (XHigh)", "reasoning_efforts": []},
    {"slug": "gemini-4-neon-high", "display_name": "Gemini 4 Neon (High)", "reasoning_efforts": []},
    {"slug": "gemini-4-argon-high", "display_name": "Gemini 4 Argon (High)", "reasoning_efforts": []},
    {"slug": "gemini-3.8-flash-medium", "display_name": "Gemini 3.8 Flash (Medium)", "reasoning_efforts": []},
]


def claude_turn(answer, **result):
    return [{"type": "init", "session_id": "s1", "model": "claude-opus-5-5"},
            {"type": "text_delta", "session_id": "s1", "message_id": "m1", "text": answer},
            {"type": "result", "session_id": "s1", "is_error": False, "result": answer, "error": "",
             "usage": {"total_tokens": 10}, **result}]


def agy_turn(answer):
    return [{"type": "init", "conversation_id": "a1", "model": "gemini-4-neon-xhigh"},
            {"type": "text_delta", "conversation_id": "a1", "step_index": 1, "state": "DONE", "text": answer,
             "done": True, "usage": {"total_tokens": 10}},
            {"type": "result", "conversation_id": "a1", "status": "SUCCESS", "response": answer,
             "usage": {"total_tokens": 10}, "error": ""}]


class UnifiedModeTests(unittest.TestCase):
    def start(self, provider, session=None, client=None, agy=None, claude=None, root=None):
        if root is None:
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
        self.assertEqual((architect["model"], architect["effort"]), ("claude-opus", "xhigh"))
        self.assertEqual((worker["model"], worker["effort"], worker["session_id"]), ("claude-sonnet", "medium", ""))
        self.assertNotIn("you are the architect", worker["prompt"])
        self.assertEqual([c["isolated"] for c in claude.calls], [False, True, False])
        self.assertEqual(followup["session_id"], "s1")
        self.assertIn("Created a.py", followup["prompt"])
        card, = [c for c in server.conversation["tool_calls"] if c["command"].startswith("delegate")]
        self.assertEqual((card["command"], card["status"]), ("delegate claude claude/claude-sonnet: create a.py", "completed"))
        answers = [m["text"] for m in server.conversation["messages"] if m["role"] == "assistant"]
        self.assertEqual(answers, ["Plan\n" + BLOCK, "All verified."])

    def test_gemini_neon_architect_delegates_to_claude_worker(self):
        agy = _FakeAgyClient(turns=[agy_turn(BLOCK.replace("null", '"claude"')), agy_turn("Verified.")])
        agy.models = lambda force=False: NEON_CATALOG
        claude = _FakeClaudeClient(turns=[claude_turn("Created a.py")])
        server = self.start("agy", agy=agy, claude=claude)
        server.handle({"type": "unified.toggle"})
        self.assertEqual(self.send(server)["status"], "completed")
        self.assertEqual(agy.calls[0]["model"], "gemini-4-neon-xhigh")
        self.assertEqual([c["model"] for c in claude.calls], ["claude-sonnet"])
        self.assertEqual(server.conversation["messages"][-1]["text"], "Verified.")

    def test_cascade_switches_neon_to_opus_to_astra_at_35_percent(self):
        with FakeService() as service:
            service.models = [
                {"slug": "gpt-6.2-astra", "display_name": "GPT-6.2-Astra", "visibility": "list"},
                {"slug": "gpt-6.1-terra", "display_name": "GPT-6.1-Terra", "visibility": "list"},
            ]
            agy = _FakeAgyClient(turns=[agy_turn("Turn 1 by Neon.")])
            agy.models = lambda force=False: NEON_CATALOG
            claude = _FakeClaudeClient(turns=[claude_turn("Turn 2 by Opus.")])
            client = ChatGPTClient(FakeSession(), HttpClient(allow_loopback=True, timeout=5), service.url)
            server = self.start("chatgpt", FakeSession(), client, agy=agy, claude=claude)
            server._agy_models = list(NEON_CATALOG)
            server._last_quota_snapshots = {
                "agy:gemini": {"session_used": 20, "captured_at": 0},   # 80% remaining
                "claude": {"session_used": 10, "captured_at": 0},       # 90% remaining
                "chatgpt": {"session_used": 5, "captured_at": 0},       # 95% remaining
            }
            server.handle({"type": "unified.toggle"})

            # Turn 1: Gemini 4 Neon (xhigh)
            self.assertEqual(self.send(server, "step 1")["status"], "completed")
            self.assertEqual(agy.calls[0]["model"], "gemini-4-neon-xhigh")

            # Gemini drops to 35% remaining (65% used) -> switches to Claude Opus 5.5 (xhigh)
            server._last_quota_snapshots["agy:gemini"] = {"session_used": 65, "captured_at": 0}
            self.assertEqual(self.send(server, "step 2")["status"], "completed")
            self.assertEqual((claude.calls[0]["model"], claude.calls[0]["effort"]), ("claude-opus", "xhigh"))
            notices = [
                json.loads(line)["data"]["message"]
                for line in self.output.getvalue().splitlines()
                if json.loads(line)["type"] == "chat.notice"
            ]
            self.assertTrue(any("35%" in msg and "Opus" in msg for msg in notices), notices)

            # Claude drops to 35% remaining (65% used) -> switches to GPT-6.2-Astra (high)
            server._last_quota_snapshots["claude"] = {"session_used": 65, "captured_at": 0}
            self.assertEqual(self.send(server, "step 3")["status"], "completed")
            req_body = service.requests[-1]["body"]
            self.assertEqual(req_body["model"], "gpt-6.2-astra")
            self.assertEqual(req_body["reasoning"], {"effort": "high"})
            notices = [
                json.loads(line)["data"]["message"]
                for line in self.output.getvalue().splitlines()
                if json.loads(line)["type"] == "chat.notice"
            ]
            self.assertTrue(any("35%" in msg and "Astra" in msg for msg in notices), notices)

    def test_two_dedicated_workers_run_truly_in_parallel(self):
        barrier = threading.Barrier(2, timeout=4.0)
        with FakeService() as service:
            service.models = [
                {"slug": "gpt-6.2-astra", "display_name": "GPT-6.2-Astra", "visibility": "list"},
                {"slug": "gpt-6.1-terra", "display_name": "GPT-6.1-Terra", "visibility": "list"},
            ]
            parallel_blocks = (
                '```delegate\n{"task": "edit backend.py", "worker": "chatgpt", "read_only": false}\n```\n'
                '```delegate\n{"task": "edit ui.qml", "worker": "claude", "read_only": false}\n```'
            )
            agy = _FakeAgyClient(turns=[agy_turn(parallel_blocks), agy_turn("Both merged.")])
            agy.models = lambda force=False: NEON_CATALOG

            claude = _FakeClaudeClient(turns=[claude_turn("Claude finished ui.qml")])
            orig_claude = claude.stream_turn

            def synced_claude(prompt, model, workspace, control, **kwargs):
                barrier.wait()
                yield from orig_claude(prompt, model, workspace, control, **kwargs)

            claude.stream_turn = synced_claude

            client = ChatGPTClient(FakeSession(), HttpClient(allow_loopback=True, timeout=5), service.url)
            orig_chatgpt_stream = client.stream

            def synced_chatgpt(model, messages, instructions, control, **kwargs):
                barrier.wait()
                yield from orig_chatgpt_stream(model, messages, instructions, control, **kwargs)

            client.stream = synced_chatgpt

            server = self.start("chatgpt", FakeSession(), client, agy=agy, claude=claude)
            server._agy_models = list(NEON_CATALOG)
            server._last_quota_snapshots = {
                "agy:gemini": {"session_used": 10, "captured_at": 0},
                "claude": {"session_used": 10, "captured_at": 0},
                "chatgpt": {"session_used": 10, "captured_at": 0},
            }
            server.handle({"type": "unified.toggle"})
            # If the two workers ran sequentially, the barrier would raise BrokenBarrierError and fail.
            self.assertEqual(self.send(server, "work in parallel")["status"], "completed")
            self.assertEqual(server.conversation["messages"][-1]["text"], "Both merged.")
            cards = [c["command"] for c in server.conversation["tool_calls"]]
            self.assertEqual(len(cards), 2)
            self.assertIn("delegate chatgpt chatgpt/gpt-6.1-terra", cards[0])
            self.assertIn("delegate claude claude/claude-sonnet", cards[1])

    def test_chatgpt_architect_parallel_delegation_across_both_workers(self):
        barrier = threading.Barrier(2, timeout=4.0)
        with FakeService() as service:
            service.models = [
                {"slug": "gpt-6.2-astra", "display_name": "GPT-6.2-Astra", "visibility": "list"},
                {"slug": "gpt-6.1-terra", "display_name": "GPT-6.1-Terra", "visibility": "list"},
            ]
            service.tool_batches = [[
                {"name": "delegate", "arguments": json.dumps({"task": "work backend", "worker": "chatgpt", "read_only": False})},
                {"name": "delegate", "arguments": json.dumps({"task": "work ui", "worker": "claude", "read_only": False})},
            ]]
            claude = _FakeClaudeClient(turns=[claude_turn("Claude done")])
            orig_claude = claude.stream_turn

            def synced_claude(prompt, model, workspace, control, **kwargs):
                barrier.wait()
                yield from orig_claude(prompt, model, workspace, control, **kwargs)

            claude.stream_turn = synced_claude

            client = ChatGPTClient(FakeSession(), HttpClient(allow_loopback=True, timeout=5), service.url)
            orig_chatgpt_stream = client.stream

            def synced_chatgpt(model, messages, instructions, control, **kwargs):
                if model == "gpt-6.1-terra":
                    barrier.wait()
                yield from orig_chatgpt_stream(model, messages, instructions, control, **kwargs)

            client.stream = synced_chatgpt

            server = self.start("chatgpt", FakeSession(), client, claude=claude)
            server._last_quota_snapshots = {
                "claude": {"session_used": 70, "captured_at": 0},   # 30% <= 35% -> ChatGPT architect runs
                "chatgpt": {"session_used": 10, "captured_at": 0},
            }
            server.handle({"type": "unified.toggle"})
            self.assertEqual(self.send(server, "shell parallel")["status"], "completed")
            cards = [c["command"] for c in server.conversation["tool_calls"]]
            self.assertEqual(len(cards), 2)
            self.assertIn("delegate chatgpt chatgpt/gpt-6.1-terra", cards[0])
            self.assertIn("delegate claude claude/claude-sonnet", cards[1])

    def test_chatgpt_architect_receives_failed_worker_as_error(self):
        with FakeService() as service:
            service.tool_batches = [[{"name": "delegate", "arguments": json.dumps(
                {"task": "create a.py", "worker": "claude", "read_only": True})}]]
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
            if model != "claude-sonnet":
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

    def test_toggle_is_rejected_while_busy_and_lists_two_workers_when_on(self):
        server = self.start("claude", claude=_FakeClaudeClient())
        server.busy = True
        server.handle({"type": "unified.toggle"})
        self.assertFalse(server.unified_mode)
        server.busy = False
        server.handle({"type": "unified.toggle"})
        state = {}
        while not state.get("unified_mode"):
            state = self.output.wait_for("provider.state")
        self.assertEqual([row["role"] for row in state["unified_team"]], ["chatgpt", "claude"])
        self.assertEqual(state["unified_team"][0]["workers"], [])
        self.assertEqual(state["unified_team"][1]["workers"][0]["name"], "Claude Sonnet")
        self.assertEqual(len(state["unified_cascade"]), 3)
        self.assertEqual(state["unified_config"]["quota_threshold"], 35)
        server.handle({"type": "unified.toggle"})
        while state["unified_mode"]:
            state = self.output.wait_for("provider.state")
        self.assertEqual(state["unified_team"], [])
        self.assertEqual(state["unified_cascade"], [])

    def test_configure_unified_updates_persists_and_resets(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            claude = _FakeClaudeClient()
            server = self.start("claude", claude=claude, root=root)
            server.handle({"type": "unified.configure", "quota_threshold": 42, "parallel_workers": False})
            saved = self.output.wait_for("unified.config.state")
            self.assertEqual(saved["config"]["quota_threshold"], 42)
            self.assertFalse(saved["config"]["parallel_workers"])

            server.handle({"type": "unified.configure", "quota_threshold": 200})
            rejected = self.output.wait_for("unified.config.rejected")
            self.assertIn("umbral", rejected["message"].lower())

            # Reload in a fresh server instance to verify persistence
            reloaded_output = QueueOutput()
            reloaded = HarnessServer(
                root / "chats", reloaded_output, _OfflineSession(), None,
                workspace=root, config_root=root / "config", claude_client=claude,
            )
            self.addCleanup(reloaded.project_runner.close)
            self.assertEqual(reloaded.unified_config.quota_threshold, 42)
            self.assertFalse(reloaded.unified_config.parallel_workers)

            reloaded.handle({"type": "unified.configure", "reset": True})
            reset_state = reloaded_output.wait_for("unified.config.state")
            self.assertEqual(reset_state["config"]["quota_threshold"], 35)
            self.assertTrue(reset_state["config"]["parallel_workers"])

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
        self.assertEqual(architect["effort"], "xhigh")
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
        claude.resolved_models = {"claude-sonnet": "claude-sonnet-5-5"}
        server = self.start("claude", claude=claude)
        server.unified_mode = True
        server._last_quota_snapshots = {"claude": {"session_used": 12.4, "weekly_used": 3.0, "captured_at": 0}}
        claude_slot = next(row for row in server._unified_team() if row["role"] == "claude")
        self.assertEqual(claude_slot["workers"][0], {
            "provider": "claude", "model": "claude-sonnet", "name": "Claude Sonnet 5.5",
            "effort": "medium", "remaining": 88,
        })
        server.worker_router.mark_exhausted("claude")
        self.assertEqual([row["workers"] for row in server._unified_team()], [[], []])

    def test_every_subagent_is_announced_with_its_progress_and_outcome(self):
        tool = {"type": "tool_start", "session_id": "s", "tool_use_id": "t1", "tool_name": "Read",
                "parameters": {"file_path": "a.py"}}
        two_blocks = BLOCK + "\n" + BLOCK.replace("false", "true")
        claude = _FakeClaudeClient(turns=[claude_turn(two_blocks),
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
                         ("claude", "running", "claude-sonnet", "create a.py"))
        self.assertTrue(any("read_file a.py" in line for e in first for line in e["lines"]))
        self.assertEqual((first[-1]["status"], first[-1]["summary"], first[-1]["tool_calls"]), ("completed", "found it", 1))
        self.assertEqual((events[-1]["role"], events[-1]["status"], events[-1]["error"]), ("claude", "failed", "boom"))
        self.output.wait_for("chat.finished")

    def test_cancelled_subagent_is_not_left_running(self):
        working = threading.Event()
        claude = _FakeClaudeClient(turns=[claude_turn(BLOCK)])
        original = claude.stream_turn

        def stream(prompt, model, workspace, control, **kwargs):
            if model != "claude-sonnet":
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

    def test_architect_out_of_quota_is_replaced_within_the_turn(self):
        agy = _FakeAgyClient(turns=[agy_turn(BLOCK), [{"type": "error", "message": "RESOURCE_EXHAUSTED (code 429)"}]])
        agy.models = lambda force=False: NEON_CATALOG
        claude = _FakeClaudeClient(turns=[claude_turn("found the bug"), claude_turn("Finished by Opus.")])
        server = self.start("agy", agy=agy, claude=claude)
        server._last_quota_snapshots["claude"] = {"session_used": 50, "captured_at": 0}
        server._last_quota_snapshots["agy:gemini"] = {"session_used": 10, "captured_at": 0}
        server.handle({"type": "unified.toggle"})
        self.assertEqual(self.send(server)["status"], "completed")
        handoff = claude.calls[-1]
        self.assertEqual((handoff["model"], handoff["effort"], handoff["isolated"]), ("claude-opus", "xhigh", False))
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
            # Claude is <= 35% so ChatGPT runs first; ChatGPT hits quota error -> falls back to Claude (20% > 0).
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
            self.assertEqual(service.requests[0]["body"]["reasoning"], {"effort": "high"})
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
        agy.models = lambda force=False: NEON_CATALOG
        claude = _FakeClaudeClient(turns=[claude_turn("", is_error=True, error="API error")])
        server = self.start("claude", agy=agy, claude=claude)
        server._last_quota_snapshots["agy:gemini"] = {"session_used": 80, "captured_at": 0}
        server.handle({"type": "unified.toggle"})
        self.assertEqual(self.send(server)["status"], "failed")

    def test_worker_quota_exhausted_falls_back_to_other_dedicated_worker(self):
        with FakeService() as service:
            service.models = [{"slug": "gpt-6.1-terra", "display_name": "GPT-6.1-Terra", "visibility": "list"}]
            agy = _FakeAgyClient(turns=[agy_turn(BLOCK.replace("null", '"claude"')), agy_turn("Done by fallback.")])
            agy.models = lambda force=False: NEON_CATALOG
            claude = _FakeClaudeClient(turns=[claude_turn("", is_error=True, error="You've hit your session limit")])
            client = ChatGPTClient(FakeSession(), HttpClient(allow_loopback=True, timeout=5), service.url)
            server = self.start("chatgpt", FakeSession(), client, agy=agy, claude=claude)
            server._agy_models = list(NEON_CATALOG)
            server._last_quota_snapshots["agy:gemini"] = {"session_used": 10, "captured_at": 0}
            server.handle({"type": "unified.toggle"})
            self.assertEqual(self.send(server)["status"], "completed")
            self.assertEqual(server.conversation["messages"][-1]["text"], "Done by fallback.")
            self.assertEqual(service.requests[0]["body"]["model"], "gpt-6.1-terra")

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
