"""Coloca únicamente el visor de este proceso, sin reglas globales de Hyprland."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time

# Referencia de la captura: área útil de 2540 × 1370, sin las barras del monitor.
# 0: carpetas; 1: texto a la derecha; 2: texto abajo a la izquierda.
REFERENCE = {0: (154, 25, 553, 640), 1: (1740, 18, 781, 1334),
             2: (19, 687, 857, 662)}


def geometry(monitor: dict, viewer_id: int) -> tuple[int, int, int, int]:
    """Coordenadas lógicas globales, descontando barras y escala/rotación."""
    scale = monitor.get("scale", 1) or 1
    width, height = monitor["width"], monitor["height"]
    if monitor.get("transform", 0) % 2:
        width, height = height, width
    left, top, right, bottom = monitor.get("reserved", [0, 0, 0, 0])
    width = max(1, round(width / scale) - left - right)
    height = max(1, round(height / scale) - top - bottom)
    ref_x, ref_y, ref_w, ref_h = REFERENCE[viewer_id]
    min_w, min_h = (320, 400) if viewer_id == 0 else (420, 320)
    w = min(width, max(min_w, round(width * ref_w / 2540)))
    h = min(height, max(min_h, round(height * ref_h / 1370)))
    x, y = round(width * ref_x / 2540), round(height * ref_y / 1370)
    x = max(0, min(x, width - w)) + monitor["x"] + left
    y = max(0, min(y, height - h)) + monitor["y"] + top
    return x, y, w, h


def hyprctl(*args: str) -> str:
    return subprocess.check_output(["hyprctl", *args], text=True, timeout=1)


def place(pid: int, title: str, viewer_id: int) -> bool:
    # Espera acotada al mapeo de la superficie; nunca busca sólo por título.
    for _ in range(20):
        clients = json.loads(hyprctl("-j", "clients"))
        client = next((c for c in clients if c.get("pid") == pid and c.get("title") == title
                       and c.get("mapped", True)), None)
        if client:
            monitors = json.loads(hyprctl("-j", "monitors"))
            monitor = next((m for m in monitors if m["id"] == client["monitor"]), None)
            if monitor:
                x, y, width, height = geometry(monitor, viewer_id)
                address = client["address"]
                # Dirección validada: ni títulos ni rutas entran en los dispatchers.
                if not re.fullmatch(r"0x[0-9a-fA-F]+", address):
                    raise ValueError("Dirección de ventana inválida")
                target = "address:" + address
                version = json.loads(hyprctl("-j", "version"))
                match = re.search(r"(\d+)\.(\d+)", version.get("version", version.get("tag", "")))
                if match and tuple(map(int, match.groups())) >= (0, 55):
                    # Desde 0.55 los dispatchers usan Lua; dirección validada arriba.
                    result = hyprctl("eval",
                        f'hl.dispatch(hl.dsp.window.float({{action="enable", window="{target}"}})); '
                        f'hl.dispatch(hl.dsp.window.resize({{x={width}, y={height}, relative=false, window="{target}"}})); '
                        f'hl.dispatch(hl.dsp.window.move({{x={x}, y={y}, relative=false, window="{target}"}}))')
                else:
                    result = hyprctl("--batch", f"dispatch setfloating {target}; "
                                     f"dispatch resizewindowpixel exact {width} {height},{target}; "
                                     f"dispatch movewindowpixel exact {x} {y},{target}")
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
        if viewer_id not in REFERENCE:
            raise ValueError("Identificador de visor inválido")
        if not place(pid, title, viewer_id):
            raise RuntimeError("No se encontró el visor en el compositor")
    except (ValueError, KeyError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
