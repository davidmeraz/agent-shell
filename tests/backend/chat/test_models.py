"""Familias, compatibilidad y esfuerzo real en peticiones HTTP y tareas de Work."""

import copy
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tests.support.paths import PROJECT
from tests.support.fake_service import FakeService, FakeSession
from tests.support.sessions import QueueOutput
from harness.chat.chatgpt import ChatGPTClient
from harness.core.http import HttpClient
from harness.chat.models import model_options
from harness.core.server import HarnessServer


class ModelOptionsTests(unittest.TestCase):
    def test_documented_models_and_unknown_slugs_do_not_share_assumed_support(self):
        known = model_options({"slug": "gpt-6.1-sol-2026-10-01"})
        self.assertEqual(known["family"], "gpt-6")
        self.assertEqual(known["reasoning_efforts"], ["low", "medium", "high", "xhigh", "max"])
        self.assertNotIn("none", known["reasoning_efforts"])
        for slug, family in (("gpt-5.99-custom", "gpt-5"), ("gpt-4.1", "gpt-4"), ("test-model", "otros")):
            row = model_options({"slug": slug})
            self.assertEqual(row["family"], family)
            self.assertEqual(row["reasoning_efforts"], [])

    def test_catalog_support_overrides_fallback_and_filters_invalid_levels(self):
        row = model_options({"slug": "gpt-6.1-sol", "supported_reasoning_levels": [
            {"effort": "high"}, {"effort": "low"}, {"effort": "invented"}, None, {"effort": "high"}],
            "default_reasoning_level": "low"})
        self.assertEqual(row["reasoning_efforts"], ["low", "high"])
        self.assertEqual(row["default_reasoning_effort"], "low")
        self.assertEqual(model_options({"slug": "gpt-6.1-sol", "supported_reasoning_levels": []})["reasoning_efforts"], [])
        self.assertEqual(model_options({"slug": "custom", "supported_reasoning_efforts": ["medium", "ultra"]})["reasoning_efforts"], ["medium", "ultra"])


class ModelSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.service = FakeService().__enter__()
        self.addCleanup(self.service.__exit__)
        self.service.models = [
            {"slug": "gpt-6.1-sol", "visibility": "list"},
            {"slug": "gpt-5.6-sol", "visibility": "list"},
            {"slug": "gpt-4.1", "visibility": "list"},
            {"slug": "gpt-6-hidden", "visibility": "hidden"},
        ]
        self.output = QueueOutput()
        self.session = FakeSession()
        self.client = ChatGPTClient(self.session, HttpClient(allow_loopback=True, timeout=2), self.service.url)
        self.server = self.make_server()
        self.addCleanup(self.stop)

    def make_server(self):
        server = HarnessServer(self.root / "chats", self.output, self.session, self.client)
        server._refresh_account()
        return server

    def stop(self):
        self.server._stream.cancel()
        self.server.project_runner.close()
        for worker in self.server._workers:
            worker.join(3)

    def select(self, slug="gpt-6.1-sol", effort="high"):
        self.server.handle({"type": "model.select", "model": slug, "reasoning_effort": effort})

    def send(self, prompt="Hola"):
        self.server.handle({"type": "chat.send", "prompt": prompt})
        return self.output.wait_for("chat.finished")

    def test_catalog_and_selection_are_local_and_default_omits_reasoning(self):
        catalog = self.output.wait_for("models.list")
        self.assertEqual([row["family"] for row in catalog["models"]], ["gpt-6", "gpt-5", "gpt-4"])
        self.assertEqual(catalog["reasoning_effort"], "")
        self.assertEqual(self.send()["status"], "completed")
        self.assertNotIn("reasoning", self.service.requests[-1]["body"])
        before = len(self.service.requests)
        self.select()
        selected = self.output.wait_for("model.selected")
        self.assertEqual(selected["reasoning_effort"], "high")
        self.assertEqual(len(self.service.requests), before)
        self.send()
        self.assertEqual(self.service.requests[-1]["body"]["reasoning"], {"effort": "high"})
        self.select(effort="")
        self.send()
        self.assertNotIn("reasoning", self.service.requests[-1]["body"])

    def test_tool_followup_preserves_effort_without_changing_input(self):
        self.select(effort="low")
        self.assertEqual(self.send("shell pwd")["status"], "completed")
        self.assertEqual(len(self.service.requests), 2)
        for request in self.service.requests:
            self.assertEqual(request["body"]["reasoning"], {"effort": "low"})
        self.assertIn("function_call_output", str(self.service.requests[-1]["body"]["input"]))

    def test_invalid_selection_is_atomic_and_unsupported_model_uses_auto(self):
        self.select()
        before = (self.server.model, self.server.reasoning_effort)
        for request in ({"type": "model.select", "model": "gpt-6.1-sol", "reasoning_effort": "none"},
                        {"type": "model.select", "model": "gpt-4.1", "reasoning_effort": "high"},
                        {"type": "model.select", "model": "gpt-6-hidden", "reasoning_effort": "high"},
                        {"type": "model.select", "model": "gpt-6.1-sol", "reasoning_effort": None},
                        {"type": "model.select"}):
            self.server.handle(request)
            self.output.wait_for("error")
            self.assertEqual((self.server.model, self.server.reasoning_effort), before)
        self.server.handle({"type": "model.select", "model": "gpt-4.1"})
        self.assertEqual(self.server.reasoning_effort, "")
        self.send()
        self.assertNotIn("reasoning", self.service.requests[-1]["body"])

    def test_selection_survives_restart_and_chat_switch_with_legacy_default(self):
        self.send()
        first = self.server.conversation["chat_id"]
        self.select(effort="max")
        self.assertEqual(self.server.history.load(first)["reasoning_effort"], "max")
        self.server.handle({"type": "chat.new"})
        self.select("gpt-5.6-sol", "low")
        self.send("Second")
        second = self.server.conversation["chat_id"]
        self.stop()
        self.server = self.make_server()
        self.server.handle({"type": "chat.open", "chat_id": first})
        self.assertEqual((self.server.model, self.server.reasoning_effort), ("gpt-6.1-sol", "max"))
        self.server.handle({"type": "chat.open", "chat_id": second})
        self.assertEqual((self.server.model, self.server.reasoning_effort), ("gpt-5.6-sol", "low"))
        legacy = self.server.history.create("Legacy")
        legacy["model"] = "gpt-6.1-sol"
        self.server.history.save(legacy)
        self.server.handle({"type": "chat.open", "chat_id": legacy["chat_id"]})
        self.assertEqual(self.server.reasoning_effort, "")
        unavailable = self.server.history.create("Unavailable model")
        unavailable.update(model="removed-model", reasoning_effort="high")
        self.server.history.save(unavailable)
        self.select(effort="max")
        self.server.handle({"type": "chat.open", "chat_id": unavailable["chat_id"]})
        self.assertEqual(self.server.model, "gpt-6.1-sol")
        self.assertEqual(self.server.reasoning_effort, "")

    def test_removed_effort_on_refresh_resets_to_provider_default(self):
        self.select(effort="max")
        self.service.models[0]["supported_reasoning_levels"] = [{"effort": "low"}]
        self.server._refresh_account()
        self.assertEqual(self.server.reasoning_effort, "")
        self.send()
        self.assertNotIn("reasoning", self.service.requests[-1]["body"])

    def test_failed_persistence_keeps_previous_selection_and_record(self):
        self.send()
        old = copy.deepcopy(self.server.conversation)
        with patch.object(self.server.history, "save", side_effect=OSError("disk failure")):
            self.select(effort="max")
            self.output.wait_for("error")
        self.assertEqual(self.server.conversation, old)
        self.assertEqual(self.server.reasoning_effort, "")

    def test_run_detection_uses_effort_and_cache_still_skips_ai(self):
        folder = self.root / "program"
        folder.mkdir()
        (folder / "run.sh").write_text("printf ready\n")
        self.server.handle({"type": "project.create", "name": "Fixture", "workdir": str(folder)})
        self.select(effort="high")
        project_id = self.server.project["project_id"]
        self.server.handle({"type": "project.run", "project_id": project_id})
        while self.output.wait_for("project.run.state")["phase"] != "completed":
            pass
        self.assertEqual(len(self.service.requests), 2)
        self.assertTrue(all(request["body"]["reasoning"] == {"effort": "high"} for request in self.service.requests))
        self.select(effort="low")
        self.server.handle({"type": "project.run", "project_id": project_id})
        while self.output.wait_for("project.run.state")["phase"] != "completed":
            pass
        self.assertEqual(len(self.service.requests), 2)
