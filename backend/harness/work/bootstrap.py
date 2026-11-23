"""Contexto inicial estático y acotado para conversaciones nuevas de Work.

Se captura una sola vez al crear la conversación para que el prefijo sea
inmutable y favorezca la caché de prompts. Nunca incluye secretos (.env) ni
enlaces simbólicos.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

EXCLUDED_DIRS = frozenset({
    ".git", ".venv", "venv", "node_modules", "__pycache__",
    ".runtime", ".mypy_cache", ".pytest_cache", ".ruff_cache",
    "dist", "build", "target", ".idea", ".vscode",
})
MAX_FILES = 120
MAX_DEPTH = 4
MAX_AGENTS_BYTES = 4096
MAX_GIT_COMMITS = 8
MAX_GIT_STATUS_LINES = 25
GIT_TIMEOUT = 2.0


def _run_git(root: Path, args: list[str]) -> str:
    git = shutil.which("git")
    if not git:
        return ""
    env = {k: v for k, v in os.environ.items() if k in ("PATH", "LANG", "LC_ALL", "HOME")}
    env["GIT_TERMINAL_PROMPT"] = "0"
    try:
        proc = subprocess.run(
            [git, *args], cwd=root, stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=GIT_TIMEOUT, env=env,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return proc.stdout.strip() if proc.returncode == 0 else ""


def git_software_context(workspace: Path) -> str:
    """Resumen compacto del estado Git real (rama, últimos commits y archivos modificados)."""
    try:
        root = workspace.resolve(strict=True)
    except OSError:
        return ""
    if not (root / ".git").exists():
        return ""
    branch = _run_git(root, ["branch", "--show-current"]) or _run_git(root, ["rev-parse", "--short", "HEAD"])
    log_raw = _run_git(root, ["log", f"-n{MAX_GIT_COMMITS}", "--date=short", "--format=%h %ad %s"])
    status_raw = _run_git(root, ["status", "--short", "--untracked-files=normal"])

    sections: list[str] = []
    if branch:
        sections.append(f"git_branch: {branch[:80]}")
    if log_raw:
        commits = [line[:140] for line in log_raw.splitlines()[:MAX_GIT_COMMITS]]
        sections.append("recent_commits:\n" + "\n".join(commits))
    if status_raw:
        clean_status = []
        for line in status_raw.splitlines():
            path_part = line[3:].strip().strip('"')
            if any(_is_secret_name(part) for part in Path(path_part).parts):
                continue
            clean_status.append(line[:140])
            if len(clean_status) >= MAX_GIT_STATUS_LINES:
                break
        if clean_status:
            sections.append("git_status:\n" + "\n".join(clean_status))
    return "\n".join(sections)


def _is_secret_name(name: str) -> bool:
    lower = name.lower()
    return lower == ".env" or (lower.startswith(".env.") and lower != ".env.example")


def _list_files(root: Path, ignored: tuple[Path, ...] = ()) -> tuple[list[str], bool]:
    ignored_resolved = [p.resolve() for p in ignored]
    files: list[str] = []
    truncated = False

    def _walk(current: Path, depth: int) -> None:
        nonlocal truncated
        if depth > MAX_DEPTH or truncated:
            return
        try:
            entries = sorted(os.scandir(current), key=lambda e: e.name)
        except OSError:
            return
        dirs: list[Path] = []
        for entry in entries:
            if entry.is_symlink():
                continue
            path = Path(entry.path)
            if any(path.resolve() == ign for ign in ignored_resolved):
                continue
            if entry.is_dir(follow_symlinks=False):
                if entry.name in EXCLUDED_DIRS:
                    continue
                if depth < MAX_DEPTH:
                    dirs.append(path)
                else:
                    truncated = True
            elif entry.is_file(follow_symlinks=False):
                if _is_secret_name(entry.name):
                    continue
                files.append(str(path.relative_to(root)))
                if len(files) >= MAX_FILES:
                    truncated = True
                    return
        for sub in dirs:
            if truncated:
                return
            _walk(sub, depth + 1)

    _walk(root, 0)
    return files, truncated


def _read_agents_md(root: Path) -> str:
    candidate = root / "AGENTS.md"
    if not candidate.exists() or candidate.is_symlink() or not candidate.is_file():
        return ""
    try:
        raw = candidate.read_bytes()[:MAX_AGENTS_BYTES + 1]
    except OSError:
        return ""
    if b"\0" in raw[:4096]:
        return ""
    clipped = len(raw) > MAX_AGENTS_BYTES
    text = raw[:MAX_AGENTS_BYTES].decode("utf-8", errors="replace").strip()
    if not text:
        return ""
    return text + ("\n[…]" if clipped else "")


def build_work_bootstrap(workspace: Path, ignored: tuple[Path, ...] = ()) -> str:
    """Devuelve un resumen compacto del proyecto o cadena vacía si la carpeta está vacía."""
    try:
        root = workspace.resolve(strict=True)
    except OSError:
        return ""
    if not root.is_dir():
        return ""
    files, truncated = _list_files(root, ignored=ignored)
    agents_md = _read_agents_md(root)
    is_git = (root / ".git").exists()
    if not files and not agents_md:
        return ""
    header = (
        "Workspace snapshot (captured once at conversation start; use directly instead of "
        "re-listing files or rereading AGENTS.md; only run git commands if git_repo is yes).\n"
        f"git_repo: {'yes' if is_git else 'no'}\n"
    )
    if is_git:
        git_info = git_software_context(root)
        if git_info:
            header += git_info + "\n"
    header += (
        f"files ({len(files)}{'+' if truncated else ''}):\n"
        + "\n".join(files)
    )
    if agents_md:
        header += "\n\nAGENTS.md:\n" + agents_md
    return header
