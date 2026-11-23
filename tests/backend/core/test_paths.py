"""Pruebas de rutas XDG, migración desde .runtime/ y lectura de versión instalada."""

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tests.support import paths  # noqa: F401
from harness.chat.history import HistoryStore, now
from harness.core.limits import AgentLimits, LimitsStore
from harness.core.paths import (
    MIGRATION_MARKER,
    default_workspace,
    migrate_legacy_runtime,
    resolve_runtime_paths,
)
from harness.core.version import get_version
from harness.work.projects import ProjectStore


class PathsAndMigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_xdg_resolution_and_explicit_overrides(self):
        env = {
            "XDG_DATA_HOME": str(self.root / "xdg-data"),
            "XDG_CONFIG_HOME": str(self.root / "xdg-config"),
            "XDG_STATE_HOME": str(self.root / "xdg-state"),
        }
        with patch.dict(os.environ, env, clear=True):
            resolved = resolve_runtime_paths()
        self.assertEqual(resolved.history_root, self.root / "xdg-data" / "agent-shell")
        self.assertEqual(resolved.config_root, self.root / "xdg-config" / "agent-shell")
        self.assertEqual(resolved.session_root, self.root / "xdg-state" / "agent-shell" / "session")
        self.assertFalse(resolved.custom_history or resolved.custom_session or resolved.custom_config)

        # Un --history-root explícito aísla config_root bajo <history_root>/config.
        with patch.dict(os.environ, env, clear=True):
            isolated = resolve_runtime_paths(history_arg=self.root / "custom-chats")
        self.assertEqual(isolated.history_root, self.root / "custom-chats")
        self.assertEqual(isolated.config_root, self.root / "custom-chats" / "config")
        self.assertTrue(isolated.custom_history)

        # Variables AGENT_SHELL_* tienen precedencia sobre XDG.
        with patch.dict(os.environ, {
            **env,
            "AGENT_SHELL_HISTORY_DIR": str(self.root / "env-h"),
            "AGENT_SHELL_SESSION_DIR": str(self.root / "env-s"),
            "AGENT_SHELL_CONFIG_DIR": str(self.root / "env-c"),
        }, clear=True):
            override = resolve_runtime_paths()
        self.assertEqual(override.history_root, self.root / "env-h")
        self.assertEqual(override.session_root, self.root / "env-s")
        self.assertEqual(override.config_root, self.root / "env-c")

    def test_legacy_runtime_migration_is_non_destructive_and_idempotent(self):
        legacy = self.root / ".runtime"
        (legacy / "session").mkdir(parents=True)
        (legacy / "session" / "session.json").write_text(
            json.dumps({"schema_version": 1, "host_id": "urn:uuid:test", "connection": None}),
            encoding="utf-8",
        )
        LimitsStore(legacy / "chats" / "config").save(AgentLimits.preset("ahorro"))

        legacy_history = HistoryStore(legacy / "chats")
        legacy_projects = ProjectStore(legacy / "chats" / "projects", db=legacy_history.db)
        work_dir = self.root / "repo"
        work_dir.mkdir()
        proj = legacy_projects.create("MiApp", str(work_dir))
        chat = legacy_history.create("Hola desde legacy", area="work", project_id=proj["project_id"])
        chat["messages"].append({"id": "m1", "role": "user", "text": "Hola", "status": "completed"})
        legacy_history.save(chat)
        legacy_history.close()

        env = {
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_STATE_HOME": str(self.root / "state"),
        }
        with patch.dict(os.environ, env, clear=True):
            target = resolve_runtime_paths()

        outcome = migrate_legacy_runtime(legacy, target)
        self.assertEqual(outcome, {"session": True, "limits": True, "history": True})

        # Archivos migrados con permisos privados y respaldo intacto en .runtime/.
        migrated_session = target.session_root / "session.json"
        self.assertTrue(migrated_session.is_file())
        self.assertTrue((legacy / "session" / "session.json").is_file())
        if os.name == "posix":
            self.assertEqual(migrated_session.stat().st_mode & 0o777, 0o600)
            self.assertEqual((target.config_root / "limits.json").stat().st_mode & 0o777, 0o600)
        self.assertEqual(LimitsStore(target.config_root).load().profile_name(), "ahorro")

        migrated_history = HistoryStore(target.history_root)
        migrated_projects = ProjectStore(target.history_root / "projects", db=migrated_history.db)
        self.addCleanup(migrated_history.close)
        self.assertEqual(migrated_history.load(chat["chat_id"])["title"], "Hola desde legacy")
        self.assertEqual(migrated_projects.load(proj["project_id"])["name"], "MiApp")
        self.assertTrue((target.history_root / MIGRATION_MARKER).exists())

        # Borrar el chat migrado y volver a ejecutar la migración NO lo re-importa (idempotente).
        migrated_history.delete(chat["chat_id"])
        second = migrate_legacy_runtime(legacy, target)
        self.assertEqual(second, {"session": False, "limits": False, "history": False})
        self.assertEqual(migrated_history.list(), [])

    def test_migration_skips_symlinks_and_supports_legacy_json_chats(self):
        legacy = self.root / ".runtime"
        (legacy / "session").mkdir(parents=True)
        (legacy / "chats").mkdir(parents=True)
        outside = self.root / "secret.json"
        outside.write_text('{"secret": true}', encoding="utf-8")
        (legacy / "session" / "session.json").symlink_to(outside)

        cid = "a" * 32
        ts = now()
        (legacy / "chats" / f"{cid}.json").write_text(json.dumps({
            "schema_version": 1, "chat_id": cid, "title": "JSON viejo",
            "created_at": ts, "updated_at": ts, "thread_id": None, "model": "",
            "area": "chat", "project_id": "", "messages": [], "performance": [], "tool_calls": [],
        }), encoding="utf-8")

        env = {
            "XDG_DATA_HOME": str(self.root / "d"),
            "XDG_CONFIG_HOME": str(self.root / "c"),
            "XDG_STATE_HOME": str(self.root / "s"),
        }
        with patch.dict(os.environ, env, clear=True):
            target = resolve_runtime_paths()
        outcome = migrate_legacy_runtime(legacy, target)
        self.assertFalse(outcome["session"])
        self.assertFalse((target.session_root / "session.json").exists())
        self.assertTrue(outcome["history"])
        store = HistoryStore(target.history_root)
        self.addCleanup(store.close)
        self.assertEqual(store.load(cid)["title"], "JSON viejo")

    def test_version_falls_back_to_package_metadata_and_workspace_avoids_usr(self):
        self.assertTrue(get_version())
        with patch.object(Path, "is_file", return_value=False), \
                patch("harness.core.version.importlib_metadata.version", return_value="9.9.9"):
            self.assertEqual(get_version(), "9.9.9")
        with patch.dict(os.environ, {}, clear=True), \
                patch("harness.core.paths.Path.cwd", return_value=Path("/usr/share/agent-shell")):
            self.assertEqual(default_workspace(), Path.home())


if __name__ == "__main__":
    unittest.main()
