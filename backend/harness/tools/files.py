"""Herramientas de solo lectura seguras para paralelismo: read_file y grep_files."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from pathlib import Path

from .output import DEFAULT_CONTEXT_OUTPUT
from .patch import resolve_confined_path

MAX_READ_LINES = 400
MAX_READ_CHARS = 16000
MAX_GREP_MATCHES = 100
GREP_TIMEOUT = 15
EXCLUDED_DIRS = frozenset({".git", ".venv", "node_modules", "__pycache__", ".runtime", ".mypy_cache"})

READ_FILE_TOOL = {
    "type": "function",
    "name": "read_file",
    "strict": True,
    "description": (
        "Read a bounded line range of a UTF-8 text file inside the working directory with line numbers. "
        "Prefer this over shell (cat/sed) for reading files. Multiple read_file calls can run in parallel. "
        "Lines are 1-indexed inclusive; max 400 lines per call. Pass end_line=0 to read up to 200 lines from start_line."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "path": {"type": "string"},
            "start_line": {"type": "integer"},
            "end_line": {"type": "integer"},
        },
        "required": ["path", "start_line", "end_line"],
        "additionalProperties": False,
    },
}

GREP_TOOL = {
    "type": "function",
    "name": "grep_files",
    "strict": True,
    "description": (
        "Search text or regex patterns across files in the working directory (excluding .git, .venv, "
        "node_modules, __pycache__, .runtime). Prefer this over shell grep/rg. Multiple grep_files calls "
        "can run in parallel. Pass path='' to search the whole workspace, and max_matches=0 for the default (50)."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "pattern": {"type": "string"},
            "path": {"type": "string"},
            "max_matches": {"type": "integer"},
        },
        "required": ["pattern", "path", "max_matches"],
        "additionalProperties": False,
    },
}


def execute_read_file(workspace: Path, arguments: str) -> dict:
    if not isinstance(arguments, str) or len(arguments) > 8192:
        raise ValueError("Argumentos de read_file inválidos")
    data = json.loads(arguments)
    if not isinstance(data, dict) or set(data) != {"path", "start_line", "end_line"}:
        raise ValueError("read_file requiere path, start_line y end_line")
    raw_path, start, end = data["path"], data["start_line"], data["end_line"]
    if type(start) is not int or type(end) is not int or start < 1 or end < 0:
        raise ValueError("start_line debe ser >= 1 y end_line >= 0")
    target = resolve_confined_path(workspace, raw_path)
    if not target.exists():
        raise ValueError(f"El archivo no existe: {raw_path}")
    if not target.is_file():
        raise ValueError(f"La ruta no es un archivo regular: {raw_path}")
    raw = target.read_bytes()
    if b"\0" in raw[:8192]:
        raise ValueError(f"El archivo parece binario y no es texto UTF-8: {raw_path}")
    text = raw.decode("utf-8", errors="replace")
    all_lines = text.splitlines()
    total_lines = len(all_lines)
    effective_end = min(total_lines, start + 199) if end == 0 else min(total_lines, end)
    if effective_end - start + 1 > MAX_READ_LINES:
        effective_end = start + MAX_READ_LINES - 1
    if start > total_lines and total_lines > 0:
        return {
            "status": "completed",
            "exit_code": 0,
            "output": f"{raw_path}: vacío en el rango solicitado (total de líneas: {total_lines})\n",
            "truncated": False,
        }
    slice_lines = all_lines[start - 1:effective_end]
    formatted: list[str] = [f"{raw_path} (líneas {start}-{effective_end} de {total_lines}):"]
    chars = len(formatted[0])
    truncated = effective_end < total_lines
    for offset, line in enumerate(slice_lines):
        row = f"{start + offset}: {line}"
        if chars + len(row) + 1 > MAX_READ_CHARS:
            truncated = True
            break
        formatted.append(row)
        chars += len(row) + 1
    return {
        "status": "completed",
        "exit_code": 0,
        "output": "\n".join(formatted) + "\n",
        "truncated": truncated,
    }


def _python_grep(root: Path, target: Path, pattern: str, limit: int) -> tuple[list[str], bool]:
    try:
        regex = re.compile(pattern)
    except re.error as err:
        raise ValueError(f"Patrón regex inválido: {err}") from None
    matches: list[str] = []
    truncated = False
    files = [target] if target.is_file() else sorted(target.rglob("*"))
    for path in files:
        if any(part in EXCLUDED_DIRS for part in path.relative_to(root).parts):
            continue
        if not path.is_file() or path.is_symlink():
            continue
        try:
            raw = path.read_bytes()
        except OSError:
            continue
        if b"\0" in raw[:4096]:
            continue
        rel = str(path.relative_to(root))
        for lineno, line in enumerate(raw.decode("utf-8", errors="replace").splitlines(), start=1):
            if regex.search(line):
                matches.append(f"{rel}:{lineno}:{line[:300]}")
                if len(matches) >= limit:
                    return matches, True
    return matches, truncated


def execute_grep_files(workspace: Path, arguments: str) -> dict:
    if not isinstance(arguments, str) or len(arguments) > 8192:
        raise ValueError("Argumentos de grep_files inválidos")
    data = json.loads(arguments)
    if not isinstance(data, dict) or set(data) != {"pattern", "path", "max_matches"}:
        raise ValueError("grep_files requiere pattern, path y max_matches")
    pattern, raw_path, max_matches = data["pattern"], data["path"], data["max_matches"]
    if not isinstance(pattern, str) or not pattern or len(pattern) > 500 or "\0" in pattern:
        raise ValueError("pattern debe ser un texto no vacío de hasta 500 caracteres")
    if type(max_matches) is not int or max_matches < 0:
        raise ValueError("max_matches debe ser >= 0")
    limit = min(MAX_GREP_MATCHES, 50 if max_matches == 0 else max_matches)
    root = workspace.resolve(strict=True)
    target = resolve_confined_path(root, raw_path, allow_root=True)
    if not target.exists():
        raise ValueError(f"La ruta de búsqueda no existe: {raw_path}")

    rg = shutil.which("rg")
    if rg:
        rel_target = "." if target == root else str(target.relative_to(root))
        cmd = [
            rg, "--line-number", "--no-heading", "--color=never",
            "--max-columns", "300", "--max-columns-preview",
        ]
        for excluded in sorted(EXCLUDED_DIRS):
            cmd.extend(["--glob", f"!{excluded}"])
        cmd.extend(["--", pattern, rel_target])
        proc = subprocess.run(
            cmd, cwd=root, stdin=subprocess.DEVNULL, capture_output=True, text=True,
            timeout=GREP_TIMEOUT, env={k: v for k, v in os.environ.items() if k in ("PATH", "LANG", "LC_ALL")},
        )
        if proc.returncode == 2:
            raise ValueError((proc.stderr or "Error en patrón de búsqueda").strip()[:300])
        raw_lines = proc.stdout.splitlines() if proc.stdout else []
        truncated = len(raw_lines) > limit
        matches = raw_lines[:limit]
    else:
        matches, truncated = _python_grep(root, target, pattern, limit)

    if not matches:
        return {"status": "completed", "exit_code": 0, "output": "Sin coincidencias.\n", "truncated": False}
    text = "\n".join(matches) + "\n"
    if len(text) > DEFAULT_CONTEXT_OUTPUT:
        text = text[:DEFAULT_CONTEXT_OUTPUT - 32] + "\n[…]\n"
        truncated = True
    return {"status": "completed", "exit_code": 0, "output": text, "truncated": truncated}


def summarize_file_tool_command(name: str, arguments: str) -> str:
    try:
        data = json.loads(arguments)
        if name == "read_file":
            start, end = data.get("start_line", 1), data.get("end_line", 0)
            span = f":{start}-{end}" if end else f":{start}+"
            return f"read_file {data.get('path', '')}{span}"
        if name == "grep_files":
            where = f" in {data['path']}" if data.get("path") else ""
            return f"grep_files {data.get('pattern', '')!r}{where}"
    except (ValueError, TypeError):
        pass
    return name
