"""Abre los visores junto al chat de este proceso, sin reglas globales de Hyprland."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time

# 0: carpetas; 1: texto derecho; 2: texto izquierdo; 3: chat; 4: uso.
ROLES = (0, 1, 2, 3, 4)
USAGE_TITLE = "Agent Shell · Uso del plan"


def geometry(monitor: dict, viewer_id: int, usage_height: int = 140) -> tuple[int, int, int, int]:
    """Tres columnas centradas; redondeo simétrico hasta un píxel lógico."""
    scale = monitor.get("scale", 1) or 1
    width, height = monitor["width"], monitor["height"]
    if monitor.get("transform", 0) % 2:
        width, height = height, width
    left, top, right, bottom = monitor.get("reserved", [0, 0, 0, 0])
    width = max(1, round(width / scale) - left - right)
    height = max(1, round(height / scale) - top - bottom)
    margin = min(20, width // 20, height // 20)
    gap = margin
    column = max(1, (width - 2 * margin - 2 * gap) // 3)
    full_height = max(1, height - 2 * margin)
    half_height = max(1, (full_height - gap) // 2)
    quota = min(full_height, max(0, usage_height))
    positions = {
        0: (margin, margin, column, half_height),
        1: (width - margin - column, margin, column, full_height),
        2: (margin, height - margin - half_height, column, half_height),
        3: (round((width - column) / 2), margin + quota + (gap if quota else 0),
            column, max(1, full_height - quota - (gap if quota else 0))),
        4: (round((width - column) / 2), margin, column, max(140, quota)),
    }
    x, y, w, h = positions[viewer_id]
    min_w, min_h = {0: (320, 400), 1: (420, 320), 2: (420, 320),
                    3: (560, 560), 4: (260, 140)}[viewer_id]
    # Si tres columnas no caben, conserva legibilidad y limita la superposición
    # al área útil. No puede garantizarse un mosaico en una pantalla pequeña.
    fit_w, fit_h = min(width, max(min_w, w)), min(height, max(min_h, h))
    x -= (fit_w - w) // 2
    w, h = fit_w, fit_h
    x = max(0, min(x, width - w)) + monitor["x"] + left
    y = max(0, min(y, height - h)) + monitor["y"] + top
    return x, y, w, h


def hyprctl(*args: str) -> str:
    return subprocess.check_output(["hyprctl", *args], text=True, timeout=1)


def workspace_selector(client: dict) -> str:
    workspace = client.get("workspace", {})
    identifier = workspace.get("id")
    if type(identifier) is not int or identifier == 0:
        raise ValueError("Escritorio de la ventana principal inválido")
    if identifier > 0:
        return str(identifier)
    name = workspace.get("name", "")
    if not isinstance(name, str) or not re.fullmatch(r"[\w .:+-]+", name):
        raise ValueError("Nombre de escritorio de la ventana principal inválido")
    # Hyprland asigna también IDs negativos a escritorios normales con nombre.
    return name if name == "special" or name.startswith("special:") else "name:" + name


def place(pid: int, title: str, viewer_id: int, main_title: str = "") -> bool:
    # Espera acotada al mapeo de la superficie; nunca busca sólo por título.
    prefix = f"Visor {viewer_id} · " if viewer_id else ""
    for _ in range(20):
        clients = json.loads(hyprctl("-j", "clients"))
        # La IA puede rotar el archivo antes de que Wayland mapee la ventana.
        client = next((c for c in clients if c.get("pid") == pid
                       and (c.get("title") == title or (prefix and title.startswith(prefix)
                            and c.get("title", "").startswith(prefix)))
                       and c.get("mapped", True)), None)
        mains = [c for c in clients if c.get("pid") == pid and c.get("title") == main_title
                 and c.get("mapped", True)] if main_title else []
        main = mains[0] if len(mains) == 1 else None
        if client and (not main_title or main):
            monitors = json.loads(hyprctl("-j", "monitors"))
            anchor = main or client
            monitor = next((m for m in monitors if m["id"] == anchor["monitor"]), None)
            if monitor:
                quotas = [c for c in clients if c.get("pid") == pid and c.get("title") == USAGE_TITLE
                          and c.get("mapped", True)]
                usage = quotas[0] if len(quotas) == 1 else None
                usage_height = usage.get("size", [0, 140])[1] if usage else 0
                targets = [(client, viewer_id)]
                # Al abrir el árbol o la tarjeta de uso se alinea el centro.
                # Abrir/rotar un archivo no recoloca un chat movido manualmente.
                if main and viewer_id in (0, 4):
                    targets.append((main, 3))
                    if usage and usage is not client:
                        targets.append((usage, 4))
                # Valida todas las direcciones antes de construir cualquier orden.
                for window, _ in targets:
                    if not re.fullmatch(r"0x[0-9a-fA-F]+", window.get("address", "")):
                        raise ValueError("Dirección de ventana inválida")
                workspace = workspace_selector(main) if main else ""
                version = json.loads(hyprctl("-j", "version"))
                match = re.search(r"(\d+)\.(\d+)", version.get("version", version.get("tag", "")))
                lua = bool(match and tuple(map(int, match.groups())) >= (0, 55))
                commands = []
                for window, role in targets:
                    x, y, width, height = geometry(monitor, role, usage_height)
                    target = "address:" + window["address"]
                    move_workspace = bool(main and (window.get("workspace", {}).get("id") != main["workspace"]["id"]
                                                   or window["monitor"] != main["monitor"]))
                    if lua:
                        commands.append(f'hl.dispatch(hl.dsp.window.float({{action="enable", window="{target}"}}))')
                        if move_workspace:
                            selector = json.dumps(workspace, ensure_ascii=False)
                            commands.append(f'hl.dispatch(hl.dsp.window.move({{workspace={selector}, follow=false, window="{target}"}}))')
                        commands.extend([
                            f'hl.dispatch(hl.dsp.window.resize({{x={width}, y={height}, relative=false, window="{target}"}}))',
                            f'hl.dispatch(hl.dsp.window.move({{x={x}, y={y}, relative=false, window="{target}"}}))'])
                    else:
                        commands.append(f"dispatch setfloating {target}")
                        if move_workspace:
                            commands.append(f"dispatch movetoworkspacesilent {workspace},{target}")
                        commands.extend([f"dispatch resizewindowpixel exact {width} {height},{target}",
                                         f"dispatch movewindowpixel exact {x} {y},{target}"])
                if lua:
                    result = hyprctl("eval", "; ".join(commands))
                else:
                    result = hyprctl("--batch", "; ".join(commands))
                if any(line.strip() != "ok" for line in result.splitlines() if line.strip()):
                    raise RuntimeError("El compositor rechazó la colocación del visor")
                return True
        time.sleep(.1)
    return False


def main() -> int:
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") or not shutil.which("hyprctl"):
        return 0
    try:
        pid, title, viewer_id = int(sys.argv[1]), sys.argv[2], int(sys.argv[3])
        main_title = sys.argv[4] if len(sys.argv) > 4 else ""
        if viewer_id not in ROLES:
            raise ValueError("Identificador de visor inválido")
        if not place(pid, title, viewer_id, main_title):
            raise RuntimeError("No se encontró el visor o su ventana principal en el compositor")
    except (ValueError, KeyError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
