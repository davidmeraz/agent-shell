"""Separación real de áreas, contexto y carpetas de proyectos sin cuenta de OpenAI."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "backend"))

from fake_service import FakeService, FakeSession
from test_harness import QueueOutput
from harness.chatgpt import ChatGPTClient
from harness.history import HistoryStore
from harness.http import HttpClient
from harness.projects import ProjectStore
from harness.server import HarnessServer


class ProjectStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folder = self.root / "mi proyecto"
        self.folder.mkdir()
        self.store = ProjectStore(self.root / "projects")

    def test_project_survives_restart_with_real_folder_and_private_file(self):
        project = self.store.create(" Proyecto 🎵 ", str(self.folder))
        restored = ProjectStore(self.store.root).load(project["project_id"])
        self.assertEqual(restored["name"], "Proyecto 🎵")
        self.assertEqual(restored["workdir"], str(self.folder.resolve()))
        self.assertEqual(self.store.list(), [restored])
        if os.name == "posix":
            self.assertEqual(self.store._path(project["project_id"]).stat().st_mode & 0o777, 0o600)

    def test_invalid_names_missing_folders_and_duplicate_alias_do_not_register(self):
        for name in (None, "", " ", "x" * 81, "x\0y"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.store.create(name, str(self.folder))
        with self.assertRaises(OSError):
            self.store.create("falta", str(self.root / "missing"))
        self.store.create("primero", str(self.folder))
        with self.assertRaises(ValueError):
            self.store.create("duplicado", str(self.folder / ".." / self.folder.name))
        self.assertEqual(len(self.store.list()), 1)

    def test_failed_atomic_update_preserves_project(self):
        project = self.store.create("original", str(self.folder))
        changed = {**project, "name": "cambio"}
        with patch("harness.projects.os.replace", side_effect=OSError("disk error")):
            with self.assertRaises(OSError):
                self.store.save(changed)
        self.assertEqual(self.store.load(project["project_id"]), project)
        self.assertEqual(list(self.store.root.glob("*.tmp")), [])

    def test_invalid_ids_symlinks_and_bad_json_do_not_hide_good_project(self):
        good = self.store.create("válido", str(self.folder))
        bad = self.store.root / ("a" * 32 + ".json")
        bad.write_text("{broken")
        outside = self.root / "outside.json"
        outside.write_text("{}")
        (self.store.root / ("b" * 32 + ".json")).symlink_to(outside)
        for project_id in (None, "../outside", "b" * 32):
            with self.subTest(project_id=project_id), self.assertRaises(ValueError):
                self.store.load(project_id)
        self.assertEqual(self.store.list(), [good])
        self.assertEqual(bad.read_text(), "{broken")
        self.assertEqual(outside.read_text(), "{}")


class WorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folders = [self.root / "proyecto A", self.root / "proyecto B"]
        for folder in self.folders:
            folder.mkdir()
        self.service = FakeService().__enter__()
        self.addCleanup(self.service.__exit__)
        self.output = QueueOutput()
        self.session = FakeSession()
        self.client = ChatGPTClient(self.session, HttpClient(allow_loopback=True, timeout=2), self.service.url)
        self.server = self.new_server()
        self.server._refresh_account()
        self.addCleanup(self.stop)

    def new_server(self):
        return HarnessServer(self.root / "chats", self.output, self.session, self.client, workspace=self.root)

    def stop(self):
        self.server._stream.cancel()
        self.server._shell_control.cancel()
        for worker in self.server._workers:
            worker.join(3)

    def create(self, index=0):
        self.server.handle({"type": "project.create", "name": f"Proyecto {index}", "workdir": str(self.folders[index])})
        state = self.output.wait_for("area.state")
        self.assertEqual(state["area"], "work")
        return state["project"]["project_id"]

    def send(self, prompt):
        self.server.handle({"type": "chat.send", "prompt": prompt})
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "completed")
        return self.server.conversation["chat_id"]

    def select(self, area, project_id=None):
        request = {"type": "area.select", "area": area}
        if project_id is not None:
            request["project_id"] = project_id
        self.server.handle(request)
        return self.output.wait_for("area.state")

    def test_legacy_chats_remain_chat_and_work_metadata_survives_load(self):
        chat = self.server.history.create("anterior")
        del chat["area"]
        del chat["project_id"]
        self.server.history.save(chat)
        self.assertEqual(self.server.history.load(chat["chat_id"])["area"], "chat")
        project_id = self.create()
        work_id = self.send("construye")
        work = HistoryStore(self.server.history.root).load(work_id)
        self.assertEqual((work["area"], work["project_id"]), ("work", project_id))

    def test_chat_and_two_projects_restore_conversations_and_never_mix_provider_input(self):
        chat_id = self.send("conversación personal")
        project_a = self.create(0)
        work_a = self.send("función del proyecto A")
        project_b = self.create(1)
        work_b = self.send("función del proyecto B")
        self.assertEqual([item["content"] for item in self.service.requests[-1]["body"]["input"]], ["función del proyecto B"])
        self.select("work", project_a)
        self.assertEqual(self.server.conversation["chat_id"], work_a)
        self.assertEqual(self.server.workspace, self.folders[0])
        self.send("continúa A")
        request = self.service.requests[-1]["body"]
        self.assertEqual([item["content"] for item in request["input"] if item["role"] == "user"], ["función del proyecto A", "continúa A"])
        self.assertIn("You are in Work", request["instructions"])
        self.assertIn(str(self.folders[0]), request["instructions"])
        self.select("chat")
        self.assertEqual(self.server.conversation["chat_id"], chat_id)
        self.assertEqual(self.server.workspace, self.root)
        self.send("sigue hablando")
        self.assertIn("You are in Chat", self.service.requests[-1]["body"]["instructions"])
        self.select("work", project_b)
        self.assertEqual(self.server.conversation["chat_id"], work_b)
        self.assertEqual(self.server.workspace, self.folders[1])

    def test_history_filters_and_cross_area_open_delete_rejected(self):
        chat_id = self.send("chat")
        project_id = self.create()
        work_id = self.send("work")
        self.server.handle({"type": "history.list"})
        # Descartar eventos anteriores para consultar el estado publicado actualmente.
        events = [json.loads(row) for row in self.output.getvalue().splitlines()]
        histories = [event["data"]["chats"] for event in events if event["type"] == "history.list"]
        self.assertEqual([row["chat_id"] for row in histories[-1]], [work_id])
        for action in ("chat.open", "chat.delete"):
            self.server.handle({"type": action, "chat_id": chat_id})
            self.output.wait_for("error")
            self.assertEqual(self.server.conversation["chat_id"], work_id)
        self.assertEqual(self.server.history.load(chat_id)["area"], "chat")
        self.assertEqual(self.server.history.load(work_id)["project_id"], project_id)

    def test_shell_uses_project_folder_offline_without_model_requests(self):
        self.server.authenticated = False
        self.server.models = []
        self.create()
        self.server.handle({"type": "shell.execute", "command": "printf 'creado' > resultado.txt; pwd"})
        self.assertEqual(self.output.wait_for("shell.finished")["status"], "completed")
        self.assertEqual((self.folders[0] / "resultado.txt").read_text(), "creado")
        self.assertFalse((self.root / "resultado.txt").exists())
        self.assertEqual(self.server.conversation["tool_calls"][0]["output"].strip(), str(self.folders[0]))
        self.assertEqual(self.service.requests, [])
        self.assertEqual(self.server.conversation["area"], "work")

    def test_switch_and_project_creation_rejected_during_running_command_and_after_cancel_safe(self):
        self.create()
        self.server.handle({"type": "shell.execute", "command": "printf iniciado; sleep 30"})
        self.output.wait_for("shell.started")
        for request in ({"type": "area.select", "area": "chat"},
                        {"type": "project.create", "name": "B", "workdir": str(self.folders[1])}):
            self.server.handle(request)
            self.output.wait_for("area.rejected")
            self.assertEqual(self.server.active_area, "work")
            self.assertEqual(self.server.workspace, self.folders[0])
        self.assertEqual(len(self.server.projects.list()), 1)
        self.server.handle({"type": "chat.cancel"})
        self.output.wait_for("shell.finished")
        self.select("chat")
        for worker in self.server._workers:
            worker.join(3)
        self.assertIsNone(self.server.conversation)

    def test_work_landing_cannot_execute_or_send_until_project_selected(self):
        self.select("work", "")
        self.server.handle({"type": "shell.execute", "command": "touch unexpected"})
        self.output.wait_for("shell.rejected")
        self.server.handle({"type": "chat.send", "prompt": "hola"})
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "failed")
        self.assertFalse((self.root / "unexpected").exists())
        self.assertEqual(self.service.requests, [])
        self.assertIsNone(self.server.conversation)

    def test_invalid_project_or_missing_folder_preserves_active_chat(self):
        chat_id = self.send("conservar")
        self.server.handle({"type": "area.select", "area": "work", "project_id": "../outside"})
        self.output.wait_for("area.rejected")
        self.assertEqual(self.server.conversation["chat_id"], chat_id)

        project = self.server.projects.create("perdido", str(self.folders[0]))
        self.folders[0].rmdir()
        self.server.handle({"type": "area.select", "area": "work", "project_id": project["project_id"]})
        self.output.wait_for("area.rejected")
        self.assertEqual((self.server.active_area, self.server.workspace), ("chat", self.root))
        self.assertEqual(self.server.conversation["chat_id"], chat_id)

    def test_work_tab_opens_project_list_if_last_folder_disappears(self):
        self.create()
        self.select("chat")
        self.folders[0].rmdir()
        state = self.select("work")
        self.assertEqual(state, {"area": "work", "project": None})
        self.assertIsNone(self.server.conversation)
        self.assertEqual(self.server.workspace, self.root)

    def test_project_folder_update_is_persisted_and_chat_folder_is_independent(self):
        project_id = self.create()
        self.server.handle({"type": "shell.configure", "workdir": str(self.folders[1])})
        self.assertEqual(self.server.projects.load(project_id)["workdir"], str(self.folders[1]))
        self.select("chat")
        self.assertEqual(self.server.workspace, self.root)
        self.select("work", project_id)
        self.assertEqual(self.server.workspace, self.folders[1])
        with patch.object(self.server.projects, "save", side_effect=OSError("disk error")):
            self.server.handle({"type": "shell.configure", "workdir": str(self.folders[0])})
            self.output.wait_for("error")
        self.assertEqual(self.server.workspace, self.folders[1])
        self.assertEqual(self.server.project["workdir"], str(self.folders[1]))

    def test_projects_and_conversations_survive_restart_and_open_without_reexecution(self):
        project_id = self.create()
        work_id = self.send("primero")
        self.stop()
        self.server = self.new_server()
        self.assertEqual(self.server.active_area, "chat")
        self.select("work", project_id)
        self.server.handle({"type": "chat.open", "chat_id": work_id})
        self.output.wait_for("chat.loaded")
        self.assertEqual(self.server.conversation["chat_id"], work_id)
        self.assertEqual(self.server.workspace, self.folders[0])
        self.assertEqual(len(self.service.requests), 1)

    def test_delete_active_project_clears_all_histories_context_and_keeps_source(self):
        chat_id = self.send("conversación general")
        project_id = self.create()
        work_id = self.send("primero")
        self.server.handle({"type": "chat.new"})
        self.output.wait_for("chat.reset")
        second_id = self.send("segundo")
        source = self.folders[0] / "main.py"
        source.write_text("print('conservar')")
        requests = len(self.service.requests)
        self.server.handle({"type": "project.delete", "project_id": project_id})
        deleted = self.output.wait_for("project.deleted")
        self.assertEqual(set(deleted["chat_ids"]), {work_id, second_id})
        self.assertEqual(self.server.active_area, "work")
        self.assertIsNone(self.server.project)
        self.assertIsNone(self.server.conversation)
        self.assertIsNone(self.server._performance)
        self.assertEqual(self.server.workspace, self.root)
        self.assertEqual(self.server._last_project_id, "")
        self.assertNotIn("work:" + project_id, self.server._area_chats)
        self.assertEqual(source.read_text(), "print('conservar')")
        self.assertEqual([row["chat_id"] for row in self.server.history.list()], [chat_id])
        self.assertEqual(self.server.projects.list(), [])
        self.assertFalse(any(row["chat_id"] in deleted["chat_ids"] for row in self.server.history.performance()))
        self.assertEqual(len(self.service.requests), requests)
        self.select("chat")
        self.assertEqual(self.server.conversation["chat_id"], chat_id)
        self.stop()
        self.server = self.new_server()
        self.assertEqual(self.server.projects.list(), [])
        self.assertEqual([row["chat_id"] for row in self.server.history.list()], [chat_id])
        self.select("work")
        self.assertIsNone(self.server.project)
        self.create()  # La misma carpeta puede vincularse de nuevo con otra identidad.
        self.assertIsNone(self.server.conversation)

    def test_delete_inactive_project_preserves_other_project_and_missing_folder_is_allowed(self):
        first = self.create()
        first_chat = self.send("A")
        second = self.create(1)
        second_chat = self.send("B")
        self.folders[0].rmdir()
        self.server.authenticated = False
        self.server.handle({"type": "project.delete", "project_id": first})
        self.output.wait_for("project.deleted")
        self.assertEqual(self.server.project["project_id"], second)
        self.assertEqual(self.server.conversation["chat_id"], second_chat)
        self.assertEqual(self.server.workspace, self.folders[1])
        self.assertFalse(self.server.history._path(first_chat).exists())
        self.assertTrue(self.server.history._path(second_chat).exists())

    def test_project_delete_failure_restores_records_and_memory(self):
        project_id = self.create()
        chat_id = self.send("conservar")
        record = self.server.conversation
        replace = os.replace
        def fail_project(source, destination):
            if source == self.server.projects._path(project_id):
                raise OSError("disk error")
            return replace(source, destination)
        with patch("harness.server.os.replace", side_effect=fail_project):
            self.server.handle({"type": "project.delete", "project_id": project_id})
        self.output.wait_for("area.rejected")
        self.assertIs(self.server.conversation, record)
        self.assertEqual(self.server.project["project_id"], project_id)
        self.assertEqual(self.server.history.load(chat_id)["chat_id"], chat_id)
        self.assertEqual(self.server.projects.load(project_id)["project_id"], project_id)
        self.assertEqual(list(self.server.history.root.glob(".deleted-project-*")), [])

    def test_delete_invalid_symlink_missing_ids_and_corrupt_history_preserve_unrelated_files(self):
        project_id = self.create()
        corrupt = self.server.history.root / ("c" * 32 + ".json")
        corrupt.write_text("{broken")
        outside = self.root / "outside.json"
        outside.write_text("{}")
        symlink = self.server.projects.root / ("a" * 32 + ".json")
        symlink.symlink_to(outside)
        for invalid in (None, "../outside", "a" * 32, "b" * 32):
            self.server.handle({"type": "project.delete", "project_id": invalid})
            self.output.wait_for("area.rejected")
            self.assertEqual(self.server.project["project_id"], project_id)
        self.server.handle({"type": "project.delete", "project_id": project_id})
        self.output.wait_for("project.deleted")
        self.assertEqual(outside.read_text(), "{}")
        self.assertTrue(symlink.is_symlink())
        self.assertEqual(corrupt.read_text(), "{broken")

    def test_project_delete_rejected_during_shell_login_or_account_refresh(self):
        project_id = self.create()
        self.server.handle({"type": "shell.execute", "command": "printf iniciado; sleep 30"})
        self.output.wait_for("shell.started")
        self.server.handle({"type": "project.delete", "project_id": project_id})
        self.output.wait_for("area.rejected")
        self.assertEqual(self.server.projects.load(project_id)["project_id"], project_id)
        self.server.handle({"type": "chat.cancel"})
        self.output.wait_for("shell.finished")
        for flag in ("login_pending", "account_pending"):
            setattr(self.server, flag, True)
            self.server.handle({"type": "project.delete", "project_id": project_id})
            self.output.wait_for("area.rejected")
            setattr(self.server, flag, False)
            self.assertEqual(self.server.projects.load(project_id)["project_id"], project_id)
