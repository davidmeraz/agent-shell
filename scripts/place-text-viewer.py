"""Abre los visores junto al chat de este proceso, sin reglas globales de Hyprland."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time

# 0: carpetas; 1: texto derecho; 2: texto izquierdo; 3: chat; 4: uso; 5..20: visores flotantes extra.
ROLES = (0, 1, 2, 3, 4)
FLOATING_ROLES = tuple(range(5, 21))
# 21: cualquiera de las tarjetas de uso por proveedor; se alinean todas juntas.
PROVIDER_USAGE_ROLE = 21
# 22..25: ventanas de subagentes, por orden de aparición en el turno.
AGENT_ROLES = tuple(range(22, 26))
AGENT_PREPARE = "--prepare-agents"
AGENT_PLACE = "--place-agents"
AGENT_TITLE_PREFIX = "Agent Shell · Agente · "
AGENT_WIDTH_MAX = 480
AGENT_WIDTH_MIN = 360
AGENT_EXPANDED_HEIGHT = 420
AGENT_SOLO_EXPANDED_HEIGHT = 460
AGENT_EXPANDED_MIN_HEIGHT = 260
AGENT_COMPACT_HEIGHT = 126
AGENT_GAP = 12
USAGE_TITLE = "Agent Shell · Uso del plan"
PROVIDER_USAGE_TITLES = tuple(f"Agent Shell · Uso · {name}" for name in ("ChatGPT", "Gemini", "Claude"))
PROVIDER_USAGE_GAP = 10


def geometry(monitor: dict, viewer_id: int, usage_height: int = 140) -> tuple[int, int, int, int]:
    """Tres columnas centradas; los roles >= 5 ubican visores flotantes centrados en cascada."""
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
    if viewer_id >= 5:
        cascade = (viewer_id - 5) % 5
        float_w = max(520, min(860, round(width * 0.44)))
        float_h = max(440, min(820, round(height * 0.64)))
        x = round((width - float_w) / 2) + (cascade - 1) * 28
        y = round((height - float_h) / 2) + (cascade - 1) * 24
        w, h = float_w, float_h
        min_w, min_h = (420, 320)
    else:
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


def provider_usage_geometry(monitor: dict, index: int, count: int, height: int) -> tuple[int, int, int, int]:
    """Reparte el ancho de la columna del chat entre las tarjetas visibles."""
    x, _, total, _ = geometry(monitor, 3, height)
    _, y, _, _ = geometry(monitor, 4, height)
    usable = total - PROVIDER_USAGE_GAP * (count - 1)
    start = usable * index // count
    end = usable * (index + 1) // count
    return x + start + PROVIDER_USAGE_GAP * index, y, end - start, height


def agent_stack_geometry(
    monitor: dict,
    compact_flags: list[bool],
    right_occupied: bool = False,
    explorer_open: bool = False,
) -> tuple[str, list[tuple[int, int, int, int]]]:
    """Columna derecha por defecto; si Visor 1 la ocupa, baja a la izquierda sin tapar el Explorador."""
    scale = monitor.get("scale", 1) or 1
    mw, mh = monitor["width"], monitor["height"]
    if monitor.get("transform", 0) % 2:
        mw, mh = mh, mw
    res_l, res_t, res_r, res_b = monitor.get("reserved", [0, 0, 0, 0])
    usable_w = max(1, round(mw / scale) - res_l - res_r)
    usable_h = max(1, round(mh / scale) - res_t - res_b)
    origin_x = monitor["x"] + res_l
    margin = min(20, usable_w // 20, usable_h // 20)

    _, top, col_w, _ = geometry(monitor, 0)
    right_x, _, _, full_h = geometry(monitor, 1)
    _, bottom_y, _, bottom_h = geometry(monitor, 2)
    chat_x, _, _, _ = geometry(monitor, 3)

    max_fit_w = max(280, usable_w - 2 * margin)
    width = min(max_fit_w, min(AGENT_WIDTH_MAX, max(AGENT_WIDTH_MIN, col_w)))

    if not right_occupied:
        side = "right"
        x = max(origin_x + margin, min(origin_x + usable_w - margin - width, right_x))
        area_y, area_h = top, full_h
    else:
        side = "left"
        x = max(origin_x + margin, min(origin_x + usable_w - margin - width, chat_x - margin - width))
        area_y, area_h = (bottom_y, bottom_h) if explorer_open else (top, full_h)

    count = len(compact_flags)
    if count == 0:
        return side, []

    compact_h = min(AGENT_COMPACT_HEIGHT, area_h)
    n_compact = sum(1 for item in compact_flags if item)
    n_expanded = count - n_compact
    if n_expanded > 0:
        avail = area_h - n_compact * compact_h - AGENT_GAP * (count - 1)
        cap = AGENT_SOLO_EXPANDED_HEIGHT if count == 1 else AGENT_EXPANDED_HEIGHT
        expanded_h = min(area_h, min(cap, max(AGENT_EXPANDED_MIN_HEIGHT, avail // n_expanded)))
    else:
        expanded_h = compact_h

    heights = [compact_h if item else expanded_h for item in compact_flags]
    total_h = sum(heights) + AGENT_GAP * (count - 1)
    rects: list[tuple[int, int, int, int]] = []
    if count == 1 or total_h <= area_h:
        y = area_y
        for h in heights:
            rects.append((x, y, width, h))
            y += h + AGENT_GAP
    else:
        total_span = sum(heights[:-1]) + AGENT_GAP * (count - 1)
        max_span = max(1, area_h - heights[-1])
        offset = 0
        for idx, h in enumerate(heights):
            y = area_y + max_span if idx == count - 1 else area_y + round(offset * max_span / total_span)
            rects.append((x, y, width, h))
            offset += h + AGENT_GAP
    return side, rects


def agent_geometry(monitor: dict, slot: int) -> tuple[int, int, int, int]:
    """Columna derecha junto al chat; conserva compatibilidad por ranura para roles 22..25."""
    _, rects = agent_stack_geometry(monitor, [False] * len(AGENT_ROLES))
    return rects[max(0, min(slot, len(rects) - 1))]


def prepare_agent_windows() -> None:
    """Las ventanas de subagentes aparecen solas: no deben quitar el foco de lo que se esté usando."""
    version = json.loads(hyprctl("-j", "version"))
    match = re.search(r"(\d+)\.(\d+)", version.get("version", version.get("tag", "")))
    if match and tuple(map(int, match.groups())) >= (0, 55):
        # La regla con nombre se reemplaza a sí misma y no toca la configuración del usuario.
        result = hyprctl("eval", 'hl.window_rule({ name = "agent-shell-agents", match = { class = "^agent-shell$", '
                        'title = "^Agent Shell · Agente · .*" }, no_initial_focus = true })')
        if result.strip() != "ok":
            raise RuntimeError("El compositor rechazó la regla de foco de los subagentes: " + result.strip())


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


def _apply_placements(placements: list[tuple[dict, tuple[int, int, int, int]]], main: dict | None) -> None:
    # Valida todas las direcciones antes de construir cualquier orden.
    for window, _ in placements:
        if not re.fullmatch(r"0x[0-9a-fA-F]+", window.get("address", "")):
            raise ValueError("Dirección de ventana inválida")
    workspace = workspace_selector(main) if main else ""
    version = json.loads(hyprctl("-j", "version"))
    match = re.search(r"(\d+)\.(\d+)", version.get("version", version.get("tag", "")))
    lua = bool(match and tuple(map(int, match.groups())) >= (0, 55))
    commands = []
    for window, (x, y, width, height) in placements:
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


def _same_workspace_clients(clients: list[dict], pid: int, anchor: dict) -> list[dict]:
    anchor_ws = anchor.get("workspace", {}).get("id")
    return [c for c in clients if c.get("pid") == pid and c.get("mapped", True)
            and (anchor_ws is None or c.get("workspace", {}).get("id") == anchor_ws)]


def place_agents(pid: int, main_title: str, specs: list[dict]) -> str | None:
    """Coloca en bloque todas las ventanas de subagentes visibles respetando orden y estado compacto."""
    if not isinstance(specs, list) or not specs:
        raise ValueError("Especificación de subagentes inválida")
    clean_specs: list[tuple[str, bool]] = []
    seen: set[str] = set()
    for entry in specs:
        if not isinstance(entry, dict):
            raise ValueError("Entrada de subagente inválida")
        title = entry.get("title")
        compact = entry.get("compact")
        if not isinstance(title, str) or not title.startswith(AGENT_TITLE_PREFIX) or not isinstance(compact, bool):
            raise ValueError("Título o estado de subagente inválido")
        if title not in seen:
            seen.add(title)
            clean_specs.append((title, compact))

    for _ in range(20):
        clients = json.loads(hyprctl("-j", "clients"))
        mains = [c for c in clients if c.get("pid") == pid and c.get("title") == main_title
                 and c.get("mapped", True)] if main_title else []
        main = mains[0] if len(mains) == 1 else None
        matched = [
            next((c for c in clients if c.get("pid") == pid and c.get("title") == title
                  and c.get("mapped", True)), None)
            for title, _ in clean_specs
        ]
        if all(matched) and (not main_title or main):
            monitors = json.loads(hyprctl("-j", "monitors"))
            anchor = main or matched[0]
            monitor = next((m for m in monitors if m["id"] == anchor["monitor"]), None)
            if monitor:
                same_ws = _same_workspace_clients(clients, pid, anchor)
                right_occupied = any(c.get("title", "").startswith("Visor 1 · ") for c in same_ws)
                explorer_open = any(c.get("title", "").startswith("Explorador · ") for c in same_ws)
                side, rects = agent_stack_geometry(
                    monitor, [compact for _, compact in clean_specs],
                    right_occupied=right_occupied, explorer_open=explorer_open,
                )
                _apply_placements(list(zip(matched, rects)), main)
                return side
        time.sleep(.1)
    return None


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
                cards = [c for name in PROVIDER_USAGE_TITLES for c in clients
                         if c.get("pid") == pid and c.get("title") == name and c.get("mapped", True)]
                usage_height = max((c.get("size", [0, 140])[1] for c in ([usage] if usage else []) + cards), default=0)
                targets = [] if viewer_id == PROVIDER_USAGE_ROLE else [(client, viewer_id)]
                # Al abrir el árbol o la tarjeta de uso se alinea el centro.
                # Abrir/rotar un archivo no recoloca un chat movido manualmente.
                if main and viewer_id in (0, 4, PROVIDER_USAGE_ROLE):
                    targets.append((main, 3))
                    if usage and usage is not client:
                        targets.append((usage, 4))
                    targets.extend((card, PROVIDER_USAGE_ROLE) for card in cards)
                placements = [
                    (
                        window,
                        provider_usage_geometry(monitor, cards.index(window), len(cards), usage_height)
                        if role == PROVIDER_USAGE_ROLE
                        else agent_geometry(monitor, role - AGENT_ROLES[0]) if role in AGENT_ROLES
                        else geometry(monitor, role, usage_height),
                    )
                    for window, role in targets
                ]
                # Si se abre el Explorador o el Visor derecho, reacomoda subagentes ya visibles sin taparlos.
                if viewer_id in (0, 1):
                    same_ws = _same_workspace_clients(clients, pid, anchor)
                    open_agents = [c for c in same_ws if c.get("title", "").startswith(AGENT_TITLE_PREFIX)]
                    if open_agents:
                        open_agents.sort(key=lambda c: c.get("at", [0, 0])[1])
                        right_occupied = viewer_id == 1 or any(c.get("title", "").startswith("Visor 1 · ") for c in same_ws)
                        explorer_open = viewer_id == 0 or any(c.get("title", "").startswith("Explorador · ") for c in same_ws)
                        compact_flags = [
                            w.get("size", [0, AGENT_EXPANDED_HEIGHT])[1] <= AGENT_COMPACT_HEIGHT + 30
                            for w in open_agents
                        ]
                        _, agent_rects = agent_stack_geometry(
                            monitor, compact_flags, right_occupied=right_occupied, explorer_open=explorer_open
                        )
                        placements.extend(zip(open_agents, agent_rects))
                _apply_placements(placements, main)
                return True
        time.sleep(.1)
    return False


def main() -> int:
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") or not shutil.which("hyprctl"):
        return 0
    try:
        if sys.argv[1:] == [AGENT_PREPARE]:
            prepare_agent_windows()
            return 0
        if len(sys.argv) == 5 and sys.argv[1] == AGENT_PLACE:
            pid, main_title = int(sys.argv[2]), sys.argv[3]
            specs = json.loads(sys.argv[4])
            side = place_agents(pid, main_title, specs)
            if not side:
                raise RuntimeError("No se encontraron los subagentes o la ventana principal en el compositor")
            print(side)
            return 0
        pid, title, viewer_id = int(sys.argv[1]), sys.argv[2], int(sys.argv[3])
        main_title = sys.argv[4] if len(sys.argv) > 4 else ""
        if viewer_id not in (*ROLES, *FLOATING_ROLES, PROVIDER_USAGE_ROLE, *AGENT_ROLES):
            raise ValueError("Identificador de visor inválido")
        if not place(pid, title, viewer_id, main_title):
            raise RuntimeError("No se encontró el visor o su ventana principal en el compositor")
    except (ValueError, KeyError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
