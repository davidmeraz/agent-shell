"""Pruebas del perfil local de usuario (nombre visible persistente)."""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from pathlib import Path

from harness.core.profile import ProfileStore, normalize_display_name
from harness.core.server import HarnessServer


class _DummySession:
    def account(self):
        return {"authenticated": False, "method": "none", "email": "", "plan": "", "plan_enabled": False, "accounts": []}


class ProfileTests(unittest.TestCase):
    def test_store_round_trip_and_normalization(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = ProfileStore(Path(tmp) / "config")
            self.assertEqual(store.load(), {"display_name": ""})
            saved = store.save("  Dave\t  Pro\n ")
            self.assertEqual(saved, {"display_name": "Dave Pro"})
            self.assertEqual(store.load(), {"display_name": "Dave Pro"})
            self.assertEqual(store.save(""), {"display_name": ""})
            self.assertEqual(store.load(), {"display_name": ""})

    def test_validation_and_symlink_rejection(self):
        with self.assertRaises(ValueError):
            normalize_display_name(123)
        with self.assertRaises(ValueError):
            normalize_display_name("x" * 41)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "config"
            root.mkdir()
            target = Path(tmp) / "outside.json"
            target.write_text("{}", encoding="utf-8")
            (root / "profile.json").symlink_to(target)
            store = ProfileStore(root)
            self.assertEqual(store.load(), {"display_name": ""})
            with self.assertRaises(OSError):
                store.save("Dave")

    def test_server_emits_and_updates_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            output = io.StringIO()
            server = HarnessServer(root / "chats", output, _DummySession(), client=None, config_root=root / "config")
            server.handle({"type": "profile.update", "display_name": "Dav3e Dev"})
            events = [json.loads(line) for line in output.getvalue().splitlines() if line.strip()]
            profile_events = [e for e in events if e["type"] == "profile.state"]
            self.assertTrue(profile_events)
            self.assertEqual(profile_events[-1]["data"]["display_name"], "Dav3e Dev")

            # Nuevo servidor recarga el nombre guardado desde disco.
            output2 = io.StringIO()
            server2 = HarnessServer(root / "chats", output2, _DummySession(), client=None, config_root=root / "config")
            self.assertEqual(server2.profile["display_name"], "Dav3e Dev")

            # Rechaza nombres demasiado largos sin perder el anterior.
            server2.handle({"type": "profile.update", "display_name": "a" * 60})
            events2 = [json.loads(line) for line in output2.getvalue().splitlines() if line.strip()]
            self.assertTrue(any(e["type"] == "profile.rejected" for e in events2))
            self.assertEqual(server2.profile["display_name"], "Dav3e Dev")


if __name__ == "__main__":
    unittest.main()
