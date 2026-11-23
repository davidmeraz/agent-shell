"""Pruebas de integración nativa: binario Qt6/C++, IPC de instancia única e integración Hyprland/Gema."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

from tests.support.paths import PROJECT

SPEC = importlib.util.spec_from_file_location(
    "hyprland_integrate", PROJECT / "scripts/hyprland-integrate.py"
)
HYPR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HYPR)


class HyprlandIntegrationTests(unittest.TestCase):
    def test_install_idempotent_and_clean_remove_preserves_user_config(self):
        with tempfile.TemporaryDirectory(prefix="agent-shell-hypr-test.") as tmp:
            root = Path(tmp)
            cfg = root / "config"
            state = root / "state"
            gema = cfg / "gema"
            gema.mkdir(parents=True)

            lua_path = gema / "hypr-user.lua"
            dock_path = gema / "dock.json"
            prefs_path = gema / "preferences.json"
            original_lua = "-- Mi config personal\nhl.bind(\"SUPER + Z\", hl.dsp.exec_cmd(\"foot\"))\n"
            original_dock = {"enabled": True, "pinnedApps": ["zen", "foot"]}
            lua_path.write_text(original_lua, encoding="utf-8")
            dock_path.write_text(json.dumps(original_dock, indent=2) + "\n", encoding="utf-8")
            prefs_path.write_text('{"accent":"#c4dcff"}\n', encoding="utf-8")

            env = {**os.environ, "XDG_CONFIG_HOME": str(cfg), "XDG_STATE_HOME": str(state)}
            script = str(PROJECT / "scripts/hyprland-integrate.py")

            res1 = subprocess.run(
                ["python3", script, "install", "--binary", "/home/test/.local/bin/agent-shell", "--no-reload"],
                env=env, capture_output=True, text=True, check=True,
            )
            self.assertIn("actualizado", res1.stdout)
            lua_after = lua_path.read_text(encoding="utf-8")
            self.assertIn("-- Mi config personal", lua_after)
            self.assertIn(HYPR.BEGIN_MARKER, lua_after)
            self.assertIn('class = "agent-shell"', lua_after)
            self.assertIn('SUPER + A', lua_after)
            dock_after = json.loads(dock_path.read_text(encoding="utf-8"))
            self.assertEqual(dock_after["pinnedApps"], ["zen", "foot", "agent-shell"])

            # Segunda ejecución idempotente.
            res2 = subprocess.run(
                ["python3", script, "install", "--binary", "/home/test/.local/bin/agent-shell", "--no-reload"],
                env=env, capture_output=True, text=True, check=True,
            )
            self.assertIn("ya integrado", res2.stdout)
            self.assertEqual(lua_path.read_text(encoding="utf-8").count(HYPR.BEGIN_MARKER), 1)

            # Estado JSON.
            status = subprocess.run(
                ["python3", script, "status"], env=env, capture_output=True, text=True, check=True
            )
            parsed = json.loads(status.stdout)
            self.assertTrue(parsed["gema_detected"])
            self.assertTrue(parsed["hyprland_integrated"])
            self.assertTrue(parsed["dock_pinned"])

            # Retiro limpio conservando la config del usuario y respaldos.
            subprocess.run(
                ["python3", script, "remove", "--no-reload"],
                env=env, capture_output=True, text=True, check=True,
            )
            self.assertEqual(lua_path.read_text(encoding="utf-8"), original_lua)
            self.assertEqual(json.loads(dock_path.read_text(encoding="utf-8"))["pinnedApps"], ["zen", "foot"])
            backups = list((state / "agent-shell/backups").glob("*/*"))
            self.assertGreaterEqual(len(backups), 2)


class NativeBinaryTests(unittest.TestCase):
    def test_single_instance_ipc_status_and_quit(self):
        binary = PROJECT / "build/agent-shell"
        if not binary.is_file():
            self.skipTest("Binario nativo build/agent-shell no compilado todavía")

        with tempfile.TemporaryDirectory(prefix="agent-shell-ipc-test.") as tmp:
            root = Path(tmp)
            runtime_dir = root / "runtime"
            workspace = root / "workspace"
            chats = root / "chats"
            runtime_dir.mkdir(mode=0o700)
            workspace.mkdir()
            env = {
                **os.environ,
                "XDG_RUNTIME_DIR": str(runtime_dir),
                "QT_QPA_PLATFORM": "offscreen",
                "AGENT_SHELL_APP_DIR": str(PROJECT),
                "AGENT_SHELL_WORKSPACE": str(workspace),
                "AGENT_SHELL_PYTHON": str(PROJECT / ".venv/bin/python"),
                "AGENT_SHELL_BACKEND_ENTRY": str(PROJECT / "tests/support/fake_backend.py"),
                "AGENT_SHELL_HISTORY_DIR": str(chats),
            }
            env.pop("WAYLAND_DISPLAY", None)

            # Antes de iniciar debe reportar running=false.
            offline = subprocess.run(
                [str(binary), "--status"], env=env, capture_output=True, text=True, check=True, timeout=5
            )
            self.assertFalse(json.loads(offline.stdout)["running"])

            proc = subprocess.Popen(
                [str(binary)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            try:
                online_data = None
                deadline = time.monotonic() + 8.0
                while time.monotonic() < deadline:
                    probe = subprocess.run(
                        [str(binary), "--status"], env=env, capture_output=True, text=True, timeout=5
                    )
                    if probe.returncode == 0 and probe.stdout.strip():
                        payload = json.loads(probe.stdout)
                        if payload.get("running"):
                            online_data = payload
                            break
                    time.sleep(0.1)

                self.assertIsNotNone(online_data, "La instancia nativa no respondió por IPC")
                self.assertEqual(online_data["app_id"], "agent-shell")
                self.assertEqual(online_data["pid"], proc.pid)

                # Invocar --toggle y --quit por IPC.
                subprocess.run([str(binary), "--toggle"], env=env, check=True, timeout=5)
                subprocess.run([str(binary), "--quit"], env=env, check=True, timeout=5)
                proc.wait(timeout=8)
                self.assertEqual(proc.returncode, 0)
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.wait(timeout=3)
