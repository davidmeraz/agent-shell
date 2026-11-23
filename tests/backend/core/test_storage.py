"""Pruebas de almacenamiento SQLite (WAL), blobs deduplicados y migración desde JSON."""

import base64
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from tests.support import paths  # noqa: F401
from benchmarks.runner import audit_history
from harness.chat.history import HistoryStore, now
from harness.chat.images import user_content
from harness.core.storage import BlobStore, StorageDB
from harness.work.projects import ProjectStore


def _png_data_url(color: str = "white", size: tuple[int, int] = (24, 24)) -> str:
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_wal_mode_permissions_and_symlink_rejection(self):
        db_path = self.root / "agent-shell.db"
        db = StorageDB(db_path)
        self.addCleanup(db.close)
        self.assertEqual(db.journal_mode(), "wal")
        if os.name == "posix":
            self.assertEqual(db_path.stat().st_mode & 0o777, 0o600)

        outside = self.root / "outside.db"
        outside.write_bytes(b"")
        link = self.root / "link.db"
        link.symlink_to(outside)
        with self.assertRaises(ValueError):
            StorageDB(link)

    def test_images_externalize_to_deduplicated_blobs_and_gc_on_delete(self):
        store = HistoryStore(self.root / "chats")
        self.addCleanup(store.close)
        img = _png_data_url("red", (40, 40))

        first = store.create("Imagen uno")
        first["messages"].append({"id": "m1", "role": "user", "text": "Mira", "status": "completed", "image": img})
        first["context"] = [{"role": "user", "content": user_content("Mira", img)}]
        store.save(first)
        # save() no muta el registro en memoria.
        self.assertEqual(first["messages"][0]["image"], img)

        # En SQLite sólo se guarda la referencia corta blob:sha256:..., no el base64 gigante.
        with store.db.read() as conn:
            raw_json = conn.execute("SELECT payload_json FROM chats WHERE chat_id = ?", (first["chat_id"],)).fetchone()[0]
        self.assertNotIn("data:image/png;base64,", raw_json)
        self.assertIn("blob:sha256:", raw_json)

        # Un segundo chat con la misma imagen reutiliza el mismo blob binario.
        second = store.create("Imagen dos")
        second["messages"].append({"id": "m2", "role": "user", "text": "Igual", "status": "completed", "image": img})
        store.save(second)

        blob_files = [p for p in store.blobs.root.rglob("*") if p.is_file()]
        self.assertEqual(len(blob_files), 1)
        if os.name == "posix":
            self.assertEqual(blob_files[0].stat().st_mode & 0o777, 0o600)

        # Al cargar se recompone la URL de datos original con integridad verificada.
        reloaded = store.load(first["chat_id"])
        self.assertEqual(reloaded["messages"][0]["image"], img)
        self.assertEqual(reloaded["context"][0]["content"][1]["image_url"], img)

        # Borrar el primer chat conserva el blob porque el segundo aún lo referencia.
        store.delete(first["chat_id"])
        self.assertTrue(blob_files[0].exists())
        self.assertEqual(store.load(second["chat_id"])["messages"][0]["image"], img)

        # Borrar el último chat recoge la basura del blob huérfano.
        store.delete(second["chat_id"])
        self.assertFalse(blob_files[0].exists())

    def test_corrupted_blob_detected_by_sha256_check(self):
        blobs = BlobStore(self.root / "blobs")
        sha, _ = blobs.put_bytes(b"contenido-original")
        target = blobs.path_for(sha)
        target.write_bytes(b"contenido-alterado")
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            blobs.get_bytes(sha)

    def test_legacy_json_chats_and_projects_migrate_automatically_and_preserve_backup(self):
        chats_dir = self.root / "chats"
        projects_dir = chats_dir / "projects"
        chats_dir.mkdir()
        projects_dir.mkdir()
        folder = self.root / "mi-repo"
        folder.mkdir()

        project_id = "1" * 32
        chat_id = "2" * 32
        img = _png_data_url("blue")
        ts = now()
        legacy_project = {
            "schema_version": 1, "project_id": project_id, "name": "Legacy",
            "workdir": str(folder.resolve()), "created_at": ts, "updated_at": ts,
        }
        legacy_chat = {
            "schema_version": 1, "chat_id": chat_id, "title": "Chat legado",
            "created_at": ts, "updated_at": ts, "thread_id": None, "model": "gpt-6.2-sol",
            "area": "work", "project_id": project_id, "compaction_count": 2,
            "messages": [{"id": "u1", "role": "user", "text": "Hola", "status": "completed", "image": img}],
            "performance": [{
                "turn_id": "t1", "model": "gpt-6.2-sol", "started_at": ts, "status": "completed",
                "elapsed_ms": 100.0, "total_ms": 100.0, "characters": 10, "input_characters": 4,
                "context_messages": 1, "model_calls": 1, "tool_calls": 0, "context_tokens": 1200,
                "usage": {"input_tokens": 1200, "cached_tokens": 400, "output_tokens": 100,
                          "reasoning_tokens": 0, "total_tokens": 1300},
            }],
            "tool_calls": [],
        }
        (projects_dir / f"{project_id}.json").write_text(json.dumps(legacy_project), encoding="utf-8")
        (chats_dir / f"{chat_id}.json").write_text(json.dumps(legacy_chat), encoding="utf-8")
        bad_file = chats_dir / ("f" * 32 + ".json")
        bad_file.write_text("{corrupto", encoding="utf-8")

        history = HistoryStore(chats_dir)
        projects = ProjectStore(projects_dir, db=history.db)
        self.addCleanup(history.close)

        # Migrado a SQLite + respaldo en .migrated-json + corrupto intacto.
        self.assertEqual(history.invalid_files, [bad_file.name])
        self.assertEqual(bad_file.read_text(encoding="utf-8"), "{corrupto")
        self.assertFalse((chats_dir / f"{chat_id}.json").exists())
        self.assertTrue((chats_dir / ".migrated-json" / f"{chat_id}.json").exists())
        self.assertTrue((projects_dir / ".migrated-json" / f"{project_id}.json").exists())

        loaded_project = projects.load(project_id)
        self.assertEqual(loaded_project["name"], "Legacy")
        loaded_chat = history.load(chat_id)
        self.assertEqual(loaded_chat["compaction_count"], 2)
        self.assertEqual(loaded_chat["messages"][0]["image"], img)
        self.assertEqual(len(history.performance()), 1)

        # La auditoría offline lee directamente de agent-shell.db en modo solo lectura.
        report = audit_history(chats_dir)
        self.assertEqual(report["chat_files"], 1)
        self.assertEqual(report["turns_with_usage"], 1)
        self.assertIn("work", report["by_area"])


if __name__ == "__main__":
    unittest.main()
