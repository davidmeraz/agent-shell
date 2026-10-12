"""Coloca únicamente el visor de este proceso, sin reglas globales de Hyprland."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time


def geometry(monitor: dict, viewer_id: int) -> tuple[int, int, int, int]:
    """Coordenadas lógicas globales, descontando barras y escala/rotación."""
    scale = monitor.get("scale", 1) or 1
    width, height = monitor["width"], monitor["height"]
    if monitor.get("transform", 0) % 2:
        width, height = height, width
    left, top, right, bottom = monitor.get("reserved", [0, 0, 0, 0])
    width = max(1, round(width / scale) - left - right)
    height = max(1, round(height / scale) - top - bottom)
    w = min(width, max(420, round(width * .30)))
    h = min(height, max(320, round(height * (.48 if viewer_id == 1 else .95))))
    x = round(width * .025) if viewer_id == 1 else width - round(width * .025) - w
    y = height - round(height * .015) - h if viewer_id == 1 else round(height * .025)
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
                if not address.startswith("0x") or any(c not in "0123456789abcdefABCDEF" for c in address[2:]):
                    raise ValueError("Dirección de ventana inválida")
                target = "address:" + address
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
        if viewer_id not in (1, 2):
            raise ValueError("Identificador de visor inválido")
        if not place(pid, title, viewer_id):
            raise RuntimeError("No se encontró el visor en el compositor")
    except (ValueError, KeyError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
