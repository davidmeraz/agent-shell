#!/usr/bin/env python3
"""Integra o retira Agent Shell en Hyprland (Lua) y el dock/tema Gema con respaldos seguros."""
from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

BEGIN_MARKER = "-- AGENT-SHELL MANAGED BEGIN"
END_MARKER = "-- AGENT-SHELL MANAGED END"


def xdg_config() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))


def xdg_state() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))


def atomic_write(path: Path, content: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp_path, mode)
        os.replace(tmp_path, path)
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise


def backup_file(path: Path, backup_dir: Path) -> None:
    if not path.exists():
        return
    backup_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, backup_dir / path.name)


def build_lua_block(binary_path: str, keybind: str) -> str:
    safe_bin = binary_path.replace("\\", "\\\\").replace('"', '\\"')
    safe_key = keybind.replace("\\", "\\\\").replace('"', '\\"')
    return f"""{BEGIN_MARKER}
-- Reglas nativas para Agent Shell (app_id Wayland: "agent-shell") integradas con Gema.
hl.window_rule({{
    match = {{ class = "agent-shell" }},
    float = true,
    opaque = false,
    opacity = "1.0 override",
    border_size = 0,
    no_shadow = true,
    rounding = 20,
}})
hl.unbind("{safe_key}")
hl.bind("{safe_key}", hl.dsp.exec_cmd('"{safe_bin}" --toggle'))
{END_MARKER}"""


def strip_managed_block(text: str) -> str:
    pattern = re.compile(
        rf"\n?{re.escape(BEGIN_MARKER)}.*?{re.escape(END_MARKER)}\n?",
        re.DOTALL,
    )
    cleaned = pattern.sub("\n", text)
    return cleaned.rstrip() + ("\n" if cleaned.strip() else "")


def update_hypr_user(lua_path: Path, binary_path: str, keybind: str, backup_dir: Path) -> bool:
    if lua_path.exists():
        backup_file(lua_path, backup_dir)
        existing = lua_path.read_text(encoding="utf-8")
    else:
        existing = ""
    base = strip_managed_block(existing)
    block = build_lua_block(binary_path, keybind)
    updated = (base + "\n" + block + "\n") if base.strip() else (block + "\n")
    if updated == existing:
        return False
    mode = lua_path.stat().st_mode & 0o777 if lua_path.exists() else 0o600
    atomic_write(lua_path, updated, mode=mode)
    return True


def remove_hypr_user(lua_path: Path, backup_dir: Path) -> bool:
    if not lua_path.exists():
        return False
    existing = lua_path.read_text(encoding="utf-8")
    if BEGIN_MARKER not in existing:
        return False
    backup_file(lua_path, backup_dir)
    updated = strip_managed_block(existing)
    mode = lua_path.stat().st_mode & 0o777
    atomic_write(lua_path, updated, mode=mode)
    return True


def update_gema_dock(dock_path: Path, pin: bool, backup_dir: Path) -> bool:
    if not dock_path.exists():
        return False
    raw = dock_path.read_text(encoding="utf-8")
    data = json.loads(raw)
    pinned = list(data.get("pinnedApps", []))
    changed = False
    if pin:
        if "agent-shell" not in pinned:
            pinned.append("agent-shell")
            changed = True
    else:
        if "agent-shell" in pinned:
            pinned = [item for item in pinned if item != "agent-shell"]
            changed = True
    if not changed:
        return False
    backup_file(dock_path, backup_dir)
    data["pinnedApps"] = pinned
    mode = dock_path.stat().st_mode & 0o777
    atomic_write(dock_path, json.dumps(data, indent=2, ensure_ascii=False) + "\n", mode=mode)
    return True


def reload_hyprland() -> bool:
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return False
    hyprctl = shutil.which("hyprctl")
    if not hyprctl:
        return False
    result = subprocess.run([hyprctl, "reload"], capture_output=True, text=True, timeout=5)
    return result.returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "remove", "status"), default="install", nargs="?")
    parser.add_argument("--binary", default=str(Path.home() / ".local/bin/agent-shell"))
    parser.add_argument("--keybind", default="SUPER + A")
    parser.add_argument("--no-dock", action="store_true")
    parser.add_argument("--no-reload", action="store_true")
    args = parser.parse_args()

    gema_dir = xdg_config() / "gema"
    lua_path = gema_dir / "hypr-user.lua"
    dock_path = gema_dir / "dock.json"
    prefs_path = gema_dir / "preferences.json"
    backup_dir = xdg_state() / "agent-shell/backups" / datetime.now().strftime("%Y%m%d-%H%M%S")

    if args.action == "status":
        hypr_installed = lua_path.exists() and BEGIN_MARKER in lua_path.read_text(encoding="utf-8")
        dock_pinned = False
        if dock_path.exists():
            try:
                dock_pinned = "agent-shell" in json.loads(dock_path.read_text(encoding="utf-8")).get("pinnedApps", [])
            except (OSError, ValueError):
                pass
        print(json.dumps({
            "gema_detected": prefs_path.exists(),
            "hypr_user_lua": str(lua_path),
            "hyprland_integrated": hypr_installed,
            "dock_pinned": dock_pinned,
        }, indent=2, ensure_ascii=False))
        return 0

    if not gema_dir.exists():
        print("Directorio ~/.config/gema no encontrado; se omite la integración automática de Gema/Hyprland.")
        return 0

    if args.action == "install":
        hypr_changed = update_hypr_user(lua_path, args.binary, args.keybind, backup_dir)
        dock_changed = False if args.no_dock else update_gema_dock(dock_path, True, backup_dir)
        reloaded = False if args.no_reload else reload_hyprland()
        print(f"Hyprland/Gema ({lua_path}): {'actualizado' if hypr_changed else 'ya integrado'} (atajo {args.keybind})")
        if not args.no_dock and dock_path.exists():
            print(f"Dock Gema ({dock_path}): {'fijado' if dock_changed else 'ya fijado'}")
        if reloaded:
            print("Hyprland recargado en vivo.")
        return 0

    hypr_removed = remove_hypr_user(lua_path, backup_dir)
    dock_removed = update_gema_dock(dock_path, False, backup_dir)
    reloaded = False if args.no_reload else reload_hyprland()
    print(f"Hyprland/Gema ({lua_path}): {'retirado' if hypr_removed else 'sin bloque gestionado'}")
    if dock_path.exists():
        print(f"Dock Gema ({dock_path}): {'desfijado' if dock_removed else 'no estaba fijado'}")
    if reloaded:
        print("Hyprland recargado en vivo.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
