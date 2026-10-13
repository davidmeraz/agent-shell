"""Inicio persistente por proyecto y lectura acotada de su configuración local."""

import hashlib
import json
import os
import shlex
import stat
from dataclasses import dataclass
from pathlib import Path

from ..chat.history import now
from ..tools.shell import parse_command

MAX_FILES = 64
MAX_FILE_BYTES = 1024 * 1024
MAX_READ_BYTES = 8 * 1024 * 1024
MAX_CONTEXT_BYTES = 32 * 1024
CONFIG_NAMES = {
    "agents.md", "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lock", "bun.lockb",
    "pyproject.toml", "requirements.txt", "poetry.lock", "uv.lock", "pipfile", "pipfile.lock",
    "cargo.toml", "cargo.lock", "go.mod", "go.sum", "makefile", "gnumakefile", "justfile",
    "cmakelists.txt", "cmakepresets.json", "meson.build", "meson_options.txt", "build.gradle",
    "build.gradle.kts", "settings.gradle", "pom.xml", "composer.json", "composer.lock", "gemfile",
    "gemfile.lock", "mix.exs", "pubspec.yaml", "pubspec.lock", "docker-compose.yml", "compose.yaml",
}
ENTRY_NAMES = {"main.py", "app.py", "server.py", "manage.py", "main.qml", "shell.qml",
               "index.js", "index.ts", "server.js", "main.js", "main.ts"}


@dataclass
class LaunchSnapshot:
    fingerprint: str
    context: dict
    watched_paths: list[str]
    cacheable: bool


def command_paths(command: str, workspace: Path) -> list[str]:
    """Sigue archivos citados por la orden, sin interpretar ni ejecutar la shell."""
    try:
        tokens = shlex.split(command)
    except ValueError:
        return []
    paths = []
    for token in tokens:
        candidate = token.partition("=")[2] if "=" in token else token
        path = Path(candidate)
        if not path.is_absolute():
            path = workspace / path
        try:
            relative = path.relative_to(workspace).as_posix()
            if path.is_file() and not path.is_symlink() and relative not in paths:
                paths.append(relative)
        except (ValueError, OSError):
            continue
    return paths[:MAX_FILES]


def project_snapshot(workspace: Path, watched_paths=()) -> LaunchSnapshot:
    """Prefetch de manifiestos, instrucciones y puntos de entrada; nunca de .env."""
    paths = set(watched_paths)
    entries = []
    cacheable = True
    with os.scandir(workspace) as directory:
        for entry in directory:
            if len(entries) == 256:
                cacheable = False
                break
            entries.append(entry.name)
            lower = entry.name.lower()
            if (lower in CONFIG_NAMES or lower in ENTRY_NAMES or lower.startswith("readme")
                    or lower.endswith((".sh", ".csproj", ".sln"))):
                paths.add(entry.name)
    paths.update(("scripts/run.sh", "scripts/start.sh", "scripts/dev.sh"))
    fingerprints = {}
    files = []
    bytes_read = 0
    context_bytes = 0
    if len(paths) > MAX_FILES:
        cacheable = False
    for relative in sorted(paths)[:MAX_FILES]:
        path = workspace / relative
        try:
            if not isinstance(relative, str) or Path(relative).is_absolute() or ".." in Path(relative).parts:
                raise ValueError("Ruta no local")
            resolved = path.resolve()
            if not resolved.is_relative_to(workspace) or path.is_symlink():
                raise ValueError("Ruta no local")
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            with os.fdopen(fd, "rb") as handle:
                info = os.fstat(handle.fileno())
                if not stat.S_ISREG(info.st_mode):
                    raise ValueError("Archivo no regular")
                remaining = max(0, MAX_READ_BYTES - bytes_read)
                lower = path.name.lower()
                source = lower in ENTRY_NAMES or path.suffix.lower() in (".py", ".js", ".ts", ".qml", ".rs", ".go", ".c", ".cpp")
                contextual = source or lower in CONFIG_NAMES or lower.startswith("readme") or lower.endswith((".sh", ".csproj", ".sln"))
                content = handle.read(min(MAX_FILE_BYTES, remaining) + 1) if contextual else b""
                bytes_read += len(content)
                complete = len(content) == info.st_size and len(content) <= MAX_FILE_BYTES and bytes_read <= MAX_READ_BYTES
                # Editar el código no cambia el comando; sí importan su presencia y permisos.
                mode = str(info.st_mode & 0o777)
                fingerprints[relative] = "entry:" + mode if source or not contextual else mode + ":" + hashlib.sha256(content).hexdigest()
                if not complete and contextual and not source:
                    cacheable = False
                if contextual and b"\0" not in content and context_bytes < MAX_CONTEXT_BYTES:
                    sample = content[:min(4096, MAX_CONTEXT_BYTES - context_bytes)]
                    context_bytes += len(sample)
                    files.append({"path": relative, "text": sample.decode("utf-8", errors="replace"),
                                  "truncated": len(sample) < info.st_size})
        except FileNotFoundError:
            fingerprints[relative] = "missing"
        except (OSError, ValueError, TypeError):
            fingerprints[relative] = "unreadable"
            cacheable = False
    fingerprint = hashlib.sha256(json.dumps(fingerprints, sort_keys=True).encode()).hexdigest()
    return LaunchSnapshot(fingerprint, {"entries": sorted(entries), "files": files}, sorted(paths)[:MAX_FILES], cacheable)


class LaunchCache:
    def __init__(self, projects):
        self.projects = projects

    def load(self, project_id, workspace):
        try:
            profile = self.projects.load(project_id).get("launch_profile")
            if (not isinstance(profile, dict) or profile.get("version") != 1
                    or profile.get("workspace") != str(workspace)
                    or not isinstance(profile.get("fingerprint"), str)
                    or not isinstance(profile.get("watched_paths"), list)
                    or len(profile["watched_paths"]) > MAX_FILES
                    or not all(isinstance(path, str) for path in profile["watched_paths"])):
                return None
            parse_command(json.dumps({"command": profile.get("command")}))
            return profile
        except (OSError, ValueError, TypeError, KeyError):
            return None

    def save(self, project_id, workspace, command, snapshot):
        profile = {"version": 1, "workspace": str(workspace), "command": command,
                   "fingerprint": snapshot.fingerprint, "watched_paths": snapshot.watched_paths,
                   "validated_at": now()}
        return self.projects.update_launch_profile(project_id, str(workspace), profile)

    def invalidate(self, project_id, workspace):
        return self.projects.update_launch_profile(project_id, str(workspace), None)
