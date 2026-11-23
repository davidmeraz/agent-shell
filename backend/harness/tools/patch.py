"""Herramienta nativa apply_patch: edición quirúrgica multi-archivo, atómica y confinada."""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

MAX_PATCH_LENGTH = 256_000
MAX_PATCH_FILES = 64

APPLY_PATCH_TOOL = {
    "type": "function",
    "name": "apply_patch",
    "strict": True,
    "description": (
        "Apply a structured patch to create, update, move, or delete one or more files inside the "
        "working directory atomically. Prefer this over shell scripts or heredocs for all file edits. "
        "Use the standard format:\n"
        "*** Begin Patch\n"
        "*** Update File: relative/path.py\n"
        "@@ optional context anchor\n"
        " unchanged line\n"
        "-old line\n"
        "+new line\n"
        "*** Add File: relative/new.py\n"
        "+new file line\n"
        "*** Delete File: relative/old.py\n"
        "*** End Patch\n"
        "Use relative paths inside the workspace; include 2-3 context lines per hunk."
    ),
    "parameters": {
        "type": "object",
        "properties": {"patch": {"type": "string"}},
        "required": ["patch"],
        "additionalProperties": False,
    },
}


@dataclass
class _Hunk:
    anchor: str = ""
    lines: list[tuple[str, str]] = field(default_factory=list)  # (tag: ' '|'-'|'+', text)
    eof: bool = False


@dataclass
class _FileOp:
    action: str  # "add" | "delete" | "update"
    path: str
    move_to: str = ""
    add_lines: list[str] = field(default_factory=list)
    hunks: list[_Hunk] = field(default_factory=list)


def resolve_confined_path(workspace: Path, raw_path: str, *, allow_root: bool = False) -> Path:
    """Resuelve una ruta relativa garantizando confinamiento estricto al workspace sin escapes por symlinks."""
    if not isinstance(raw_path, str) or "\0" in raw_path:
        raise ValueError("Ruta inválida")
    cleaned = raw_path.strip()
    if not cleaned:
        if allow_root:
            return workspace.resolve(strict=True)
        raise ValueError("La ruta no puede estar vacía")
    candidate = Path(cleaned)
    if candidate.is_absolute():
        raise ValueError(f"Usa una ruta relativa dentro del workspace: {cleaned}")
    if ".." in candidate.parts:
        raise ValueError(f"Ruta fuera del workspace no permitida: {cleaned}")
    root = workspace.resolve(strict=True)
    current = root
    for part in candidate.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError(f"No se permiten enlaces simbólicos: {cleaned}")
    resolved = current.resolve(strict=False)
    if resolved != root and not resolved.is_relative_to(root):
        raise ValueError(f"Ruta fuera del workspace: {cleaned}")
    if resolved == root and not allow_root:
        raise ValueError("La ruta debe apuntar a un archivo dentro del workspace")
    return resolved


def parse_patch_argument(arguments: str) -> str:
    if not isinstance(arguments, str) or len(arguments) > MAX_PATCH_LENGTH * 2 + 256:
        raise ValueError("Argumentos de apply_patch inválidos")
    value = json.loads(arguments)
    if (not isinstance(value, dict) or set(value) != {"patch"}
            or not isinstance(value["patch"], str) or not value["patch"].strip()
            or len(value["patch"]) > MAX_PATCH_LENGTH or "\0" in value["patch"]):
        raise ValueError("apply_patch requiere un parche de texto válido")
    return value["patch"]


def parse_patch(text: str) -> list[_FileOp]:
    raw_lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    # Permitir líneas en blanco antes/después de los marcadores.
    while raw_lines and not raw_lines[0].strip():
        raw_lines.pop(0)
    while raw_lines and not raw_lines[-1].strip():
        raw_lines.pop()
    if not raw_lines or raw_lines[0].strip() != "*** Begin Patch":
        raise ValueError("El parche debe comenzar con '*** Begin Patch'")
    if raw_lines[-1].strip() != "*** End Patch":
        raise ValueError("El parche debe terminar con '*** End Patch'")

    body = raw_lines[1:-1]
    ops: list[_FileOp] = []
    idx = 0
    while idx < len(body):
        line = body[idx]
        if not line.strip():
            idx += 1
            continue
        if line.startswith("*** Add File: "):
            path = line[len("*** Add File: "):].strip()
            idx += 1
            added: list[str] = []
            while idx < len(body) and not body[idx].startswith("*** "):
                entry = body[idx]
                if not entry.startswith("+"):
                    raise ValueError(f"Línea inválida en Add File '{path}': debe empezar con '+'")
                added.append(entry[1:])
                idx += 1
            ops.append(_FileOp("add", path, add_lines=added))
        elif line.startswith("*** Delete File: "):
            path = line[len("*** Delete File: "):].strip()
            idx += 1
            ops.append(_FileOp("delete", path))
        elif line.startswith("*** Update File: "):
            path = line[len("*** Update File: "):].strip()
            idx += 1
            move_to = ""
            if idx < len(body) and body[idx].startswith("*** Move to: "):
                move_to = body[idx][len("*** Move to: "):].strip()
                idx += 1
            hunks: list[_Hunk] = []
            current: _Hunk | None = None
            while idx < len(body) and not body[idx].startswith(("*** Add File: ", "*** Delete File: ", "*** Update File: ")):
                entry = body[idx]
                if entry == "*** End of File":
                    if current is None:
                        raise ValueError(f"'*** End of File' sin bloque @@ en '{path}'")
                    current.eof = True
                    idx += 1
                    continue
                if entry.startswith("@@"):
                    anchor = entry[2:].strip()
                    current = _Hunk(anchor=anchor)
                    hunks.append(current)
                    idx += 1
                    continue
                if entry == "":
                    if current is None:
                        idx += 1
                        continue
                    current.lines.append((" ", ""))
                    idx += 1
                    continue
                prefix = entry[0]
                if prefix not in (" ", "+", "-"):
                    raise ValueError(f"Prefijo inválido en hunk de '{path}': {entry[:40]!r}")
                if current is None:
                    current = _Hunk()
                    hunks.append(current)
                current.lines.append((prefix, entry[1:]))
                idx += 1
            if not hunks and not move_to:
                raise ValueError(f"Update File sin cambios para '{path}'")
            ops.append(_FileOp("update", path, move_to=move_to, hunks=hunks))
        else:
            raise ValueError(f"Cabecera de parche no reconocida: {line[:60]!r}")

    if not ops:
        raise ValueError("El parche no contiene operaciones")
    if len(ops) > MAX_PATCH_FILES:
        raise ValueError(f"El parche supera el límite de {MAX_PATCH_FILES} archivos")
    return ops


def _find_subsequence(haystack: list[str], needle: list[str], start: int, eof: bool) -> int:
    if not needle:
        return len(haystack) if eof else min(start, len(haystack))

    def _search(norm) -> int:
        n_hay = [norm(line) for line in haystack]
        n_ndl = [norm(line) for line in needle]
        limit = len(n_hay) - len(n_ndl)
        if limit < 0:
            return -1
        if eof and n_hay[limit:] == n_ndl:
            return limit
        for pos in range(max(0, start), limit + 1):
            if n_hay[pos:pos + len(n_ndl)] == n_ndl:
                return pos
        for pos in range(0, min(start, limit + 1)):
            if n_hay[pos:pos + len(n_ndl)] == n_ndl:
                return pos
        return -1

    for normalizer in (lambda s: s, lambda s: s.rstrip(), lambda s: s.strip()):
        found = _search(normalizer)
        if found >= 0:
            return found
    return -1


def _apply_hunks(original_text: str, hunks: list[_Hunk], path: str) -> str:
    had_trailing_nl = original_text.endswith("\n")
    lines = original_text.splitlines() if original_text else []
    cursor = 0
    for hunk in hunks:
        if hunk.anchor:
            for idx in range(cursor, len(lines)):
                if hunk.anchor in lines[idx]:
                    cursor = idx
                    break
        expected = [text for tag, text in hunk.lines if tag in (" ", "-")]
        replacement = [text for tag, text in hunk.lines if tag in (" ", "+")]
        match_at = _find_subsequence(lines, expected, cursor, hunk.eof)
        if match_at < 0:
            preview = expected[0][:60] if expected else hunk.anchor[:60]
            raise ValueError(f"No se encontró el contexto del parche en '{path}' cerca de: {preview!r}")
        lines[match_at:match_at + len(expected)] = replacement
        cursor = match_at + len(replacement)
    if not lines:
        return ""
    return "\n".join(lines) + ("\n" if had_trailing_nl or original_text == "" else "")


def _atomic_write(path: Path, content: str, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, prefix=".patch-", delete=False,
        ) as handle:
            temporary = Path(handle.name)
            handle.write(content)
            handle.flush()
        if mode is not None:
            os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


def execute_apply_patch(workspace: Path, arguments: str) -> dict:
    """Valida y aplica todo el parche atómicamente sobre el workspace."""
    patch_text = parse_patch_argument(arguments)
    ops = parse_patch(patch_text)
    root = workspace.resolve(strict=True)

    # Fase 1: Validar y calcular todo en memoria antes de escribir en disco.
    virtual: dict[Path, str | None] = {}
    modes: dict[Path, int | None] = {}
    summary: list[dict[str, str]] = []

    def _read_virtual(target: Path) -> str | None:
        if target in virtual:
            return virtual[target]
        if not target.exists():
            return None
        if not target.is_file():
            raise ValueError(f"No es un archivo regular: {target.relative_to(root)}")
        raw = target.read_bytes()
        if b"\0" in raw[:8192]:
            raise ValueError(f"Archivo binario no editable con apply_patch: {target.relative_to(root)}")
        modes[target] = target.stat().st_mode & 0o777
        text = raw.decode("utf-8")
        virtual[target] = text
        return text

    for op in ops:
        source = resolve_confined_path(root, op.path)
        if op.action == "add":
            if _read_virtual(source) is not None:
                raise ValueError(f"El archivo ya existe (usa Update File): {op.path}")
            virtual[source] = ("\n".join(op.add_lines) + "\n") if op.add_lines else ""
            modes[source] = None
            summary.append({"path": op.path, "action": "added"})
        elif op.action == "delete":
            if _read_virtual(source) is None:
                raise ValueError(f"El archivo a eliminar no existe: {op.path}")
            virtual[source] = None
            summary.append({"path": op.path, "action": "deleted"})
        elif op.action == "update":
            current_text = _read_virtual(source)
            if current_text is None:
                raise ValueError(f"El archivo a modificar no existe: {op.path}")
            updated = _apply_hunks(current_text, op.hunks, op.path) if op.hunks else current_text
            if op.move_to:
                dest = resolve_confined_path(root, op.move_to)
                if dest != source and _read_virtual(dest) is not None:
                    raise ValueError(f"El destino ya existe: {op.move_to}")
                modes[dest] = modes.get(source)
                virtual[source] = None
                virtual[dest] = updated
                summary.append({"path": op.path, "to": op.move_to, "action": "moved"})
            else:
                virtual[source] = updated
                summary.append({"path": op.path, "action": "updated"})

    # Fase 2: Aplicar escrituras y borrados validados.
    for path, content in virtual.items():
        if content is None:
            path.unlink(missing_ok=True)
        else:
            _atomic_write(path, content, mode=modes.get(path))

    lines = [
        f"{entry['action']}: {entry['path']}" + (f" -> {entry['to']}" if "to" in entry else "")
        for entry in summary
    ]
    return {
        "status": "completed",
        "exit_code": 0,
        "output": "\n".join(lines) + "\n",
        "truncated": False,
        "files": summary,
    }


def summarize_patch_command(arguments: str) -> str:
    """Etiqueta breve para mostrar el parche en la tarjeta de herramientas de Qt."""
    try:
        ops = parse_patch(parse_patch_argument(arguments))
        names = [op.path for op in ops[:3]]
        suffix = f" +{len(ops) - 3}" if len(ops) > 3 else ""
        return f"apply_patch ({', '.join(names)}{suffix})"
    except (ValueError, TypeError):
        return "apply_patch"
