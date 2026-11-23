"""Pruebas de compactación inteligente, límite de 3 compactaciones y relevo con Git."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

from tests.support import paths  # noqa: F401
from tests.support.fake_service import FakeService, FakeSession
from tests.support.sessions import QueueOutput
from harness.chat.chatgpt import ChatGPTClient
from harness.chat.compaction import (
    BOOTSTRAP_PREFIX,
    COMPACTION_HEADER,
    HANDOFF_HEADER,
    handoff_title,
    render_for_summary,
    split_for_compaction,
)
from harness.core.http import Cancelled, HttpClient
from harness.core.limits import AgentLimits
from harness.core.server import HarnessServer


class CompactionUnitTests(unittest.TestCase):
    def test_split_preserves_bootstrap_and_never_breaks_tool_pairs(self):
        ctx = [
            {"role": "developer", "content": BOOTSTRAP_PREFIX + "test)\ngit_repo: no\nfiles (1):\na.py"},
            {"role": "user", "content": "Turno 1"},
            {"type": "reasoning", "id": "r1", "summary": [], "encrypted_content": "opaque"},
            {"type": "function_call", "call_id": "c1", "name": "shell", "arguments": '{"command":"pwd"}'},
            {"type": "function_call_output", "call_id": "c1", "output": '{"status":"completed","output":"/tmp"}'},
            {"role": "assistant", "content": "Listo 1"},
            {"role": "user", "content": "Turno 2"},
            {"role": "assistant", "content": "Listo 2"},
        ]
        prefix, older, tail = split_for_compaction(ctx, keep_recent_turns=1)
        self.assertEqual(len(prefix), 1)
        self.assertTrue(prefix[0]["content"].startswith(BOOTSTRAP_PREFIX))
        self.assertEqual(tail[0]["content"], "Turno 2")
        call_ids = {i["call_id"] for i in older if i.get("type") == "function_call"}
        out_ids = {i["call_id"] for i in older if i.get("type") == "function_call_output"}
        self.assertEqual(call_ids, out_ids)

    def test_render_for_summary_omits_reasoning_and_base64_images(self):
        items = [
            {"type": "reasoning", "encrypted_content": "SECRET_OPAQUE_BLOB"},
            {
                "role": "user",
                "content": [
                    {"type": "input_text", "text": "Mira esta captura"},
                    {"type": "input_image", "image_url": "data:image/png;base64,AAAA1234", "detail": "auto"},
                ],
            },
        ]
        rendered = render_for_summary(items)
        self.assertNotIn("SECRET_OPAQUE_BLOB", rendered)
        self.assertNotIn("AAAA1234", rendered)
        self.assertIn("Imagen adjunta omitida", rendered)
        self.assertEqual(handoff_title("Mi app (continuación)"), "Mi app (continuación)")


class CompactionServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.workspace = self.root / "repo"
        self.workspace.mkdir()
        # Crear un repo Git real para verificar que el relevo lleva commits reales.
        env = {
            "PATH": "/usr/bin:/bin", "GIT_AUTHOR_NAME": "Dev", "GIT_AUTHOR_EMAIL": "d@e.invalid",
            "GIT_COMMITTER_NAME": "Dev", "GIT_COMMITTER_EMAIL": "d@e.invalid",
        }
        subprocess.run(["git", "init", "-b", "main"], cwd=self.workspace, check=True, capture_output=True, env=env)
        (self.workspace / "AGENTS.md").write_text("# Proyecto\nUsa unittest.\n", encoding="utf-8")
        (self.workspace / "core.py").write_text("VERSION = 1\n", encoding="utf-8")
        subprocess.run(["git", "add", "."], cwd=self.workspace, check=True, capture_output=True, env=env)
        subprocess.run(["git", "commit", "-m", "feat: arquitectura base del software"], cwd=self.workspace, check=True, capture_output=True, env=env)

        self.service = FakeService().__enter__()
        self.addCleanup(self.service.__exit__)
        self.output = QueueOutput()
        self.session = FakeSession()
        self.client = ChatGPTClient(self.session, HttpClient(allow_loopback=True, timeout=5), self.service.url)
        self.limits = AgentLimits(compact_threshold_tokens=0, max_compactions=3)
        self.server = HarnessServer(
            self.root / "history", self.output, self.session, self.client,
            workspace=self.workspace, limits=self.limits,
        )
        self.server._refresh_account()
        self.server.handle({"type": "project.create", "name": "MiSoftware", "workdir": str(self.workspace)})
        self.output.wait_for("area.state")
        self.addCleanup(self.stop)

    def stop(self):
        self.server._stream.cancel()
        for worker in self.server._workers:
            worker.join(timeout=3)

    def send(self, prompt: str):
        self.server.handle({"type": "chat.send", "prompt": prompt})
        return self.output.wait_for("chat.finished")

    def test_three_compactions_in_place_then_fourth_creates_clean_handoff_chat_with_git_log(self):
        self.assertEqual(self.send("Construye el módulo core")["status"], "completed")
        self.assertEqual(self.send("Añade validaciones")["status"], "completed")
        original_id = self.server.conversation["chat_id"]
        original_visible_count = len(self.server.conversation["messages"])

        # Compactaciones 1, 2 y 3 permanecen en el mismo chat conservando mensajes visibles.
        for expected_count in (1, 2, 3):
            self.server.handle({"type": "chat.compact"})
            ev = self.output.wait_for("chat.compacted")
            self.assertEqual(ev["status"], "completed")
            self.assertFalse(ev["handoff"])
            self.assertEqual(ev["chat_id"], original_id)
            self.assertEqual(ev["compaction_count"], expected_count)
            self.assertEqual(self.server.conversation["compaction_count"], expected_count)
            self.assertEqual(len(self.server.conversation["messages"]), original_visible_count)
            self.assertTrue(any(
                isinstance(item.get("content"), str) and item["content"].startswith(COMPACTION_HEADER)
                for item in self.server.conversation["context"]
            ))
            # Agregar un nuevo turno para tener material fresco antes de la siguiente compactación.
            self.assertEqual(self.send(f"Paso adicional {expected_count}")["status"], "completed")
            original_visible_count = len(self.server.conversation["messages"])

        # 4.ª compactación: alcanza límite de 3 → crea un chat NUEVO con relevo esencial + git log.
        self.server.handle({"type": "chat.compact"})
        ev = self.output.wait_for("chat.compacted")
        self.assertEqual(ev["status"], "completed")
        self.assertTrue(ev["handoff"])
        self.assertEqual(ev["previous_chat_id"], original_id)
        self.assertNotEqual(ev["chat_id"], original_id)
        self.assertEqual(ev["compaction_count"], 0)

        new_chat = self.server.conversation
        self.assertEqual(new_chat["chat_id"], ev["chat_id"])
        self.assertEqual(new_chat["parent_chat_id"], original_id)
        self.assertEqual(new_chat["compaction_count"], 0)
        self.assertEqual(new_chat["area"], "work")
        self.assertIn("(continuación)", new_chat["title"])

        # El prompt de handoff enviado a OpenAI recibió el git log real del repo.
        handoff_req = self.service.requests[-1]["body"]
        self.assertIn("feat: arquitectura base del software", handoff_req["input"][0]["content"])

        # El contexto del chat nuevo tiene bootstrap fresco con git log + relevo esencial.
        self.assertTrue(new_chat["context"][0]["content"].startswith(BOOTSTRAP_PREFIX))
        self.assertIn("feat: arquitectura base del software", new_chat["context"][0]["content"])
        self.assertTrue(new_chat["context"][1]["content"].startswith(HANDOFF_HEADER))

        # El chat original sigue intacto y recuperable en el historial.
        old_saved = self.server.history.load(original_id)
        self.assertEqual(old_saved["compaction_count"], 3)
        self.assertEqual(len(old_saved["messages"]), original_visible_count)

    def test_auto_compaction_and_auto_handoff_trigger_on_threshold_before_turn(self):
        self.server.limits = AgentLimits(compact_threshold_tokens=10, max_compactions=1)
        self.assertEqual(self.send("Primer turno")["status"], "completed")
        # FakeService reporta input_tokens=12 (>= umbral 10): el 2.º mensaje dispara auto-compactación 1/1.
        self.assertEqual(self.send("Segundo turno")["status"], "completed")
        self.assertEqual(self.server.conversation["compaction_count"], 1)
        first_chat_id = self.server.conversation["chat_id"]

        # Como ya alcanzó max_compactions=1 y context_tokens=12 >= 10, el 3.er mensaje hace auto-handoff
        # a un chat nuevo llevando consigo el 3.er mensaje del usuario y respondiéndolo ahí.
        self.assertEqual(self.send("Tercer turno en nuevo chat")["status"], "completed")
        self.assertNotEqual(self.server.conversation["chat_id"], first_chat_id)
        self.assertEqual(self.server.conversation["parent_chat_id"], first_chat_id)
        self.assertEqual(self.server.conversation["compaction_count"], 0)
        user_texts = [m["text"] for m in self.server.conversation["messages"] if m["role"] == "user"]
        self.assertEqual(user_texts, ["Tercer turno en nuevo chat"])
        # El chat anterior no se contaminó con el 3.er mensaje.
        old_users = [m["text"] for m in self.server.history.load(first_chat_id)["messages"] if m["role"] == "user"]
        self.assertNotIn("Tercer turno en nuevo chat", old_users)

    def test_cancelled_compaction_preserves_original_context(self):
        self.assertEqual(self.send("Turno uno")["status"], "completed")
        self.assertEqual(self.send("Turno dos")["status"], "completed")
        before_context = json.dumps(self.server.conversation["context"], sort_keys=True)
        self.server.client = Mock()
        self.server.client.stream.side_effect = Cancelled()
        self.server.handle({"type": "chat.compact"})
        ev = self.output.wait_for("chat.compacted")
        self.assertEqual(ev["status"], "interrupted")
        self.assertFalse(self.server.busy)
        self.assertEqual(self.server.conversation["compaction_count"], 0)
        self.assertEqual(json.dumps(self.server.conversation["context"], sort_keys=True), before_context)


if __name__ == "__main__":
    unittest.main()
