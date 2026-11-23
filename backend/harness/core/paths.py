"""Rutas XDG para Linux/Arch y migración automática no destructiva desde `.runtime/`."""

from __future__ import annotations

import os
import tempfile
from dataclasses import dataclass
from pathlib import Path

APP_DIR_NAME = "agent-shell"
MIGRATION_MARKER = ".migrated-from-runtime"


def _xdg_dir(env_var: str, fallback: Path) -> Path:
    raw = os.environ.get(env_var, "").strip()
    if raw:
        candidate = Path(raw).expanduser()
        if candidate.is_absolute():
            return candidate
    return fallback


def xdg_data_home() -> Path:
    return _xdg_dir("XDG_DATA_HOME", Path.home() / ".local" / "share")


def xdg_config_home() -> Path:
    return _xdg_dir("XDG_CONFIG_HOME", Path.home() / ".config")


def xdg_state_home() -> Path:
    return _xdg_dir("XDG_STATE_HOME", Path.home() / ".local" / "state")


def default_history_root() -> Path:
    return xdg_data_home() / APP_DIR_NAME


def default_config_root() -> Path:
    return xdg_config_home() / APP_DIR_NAME


def default_session_root() -> Path:
    return xdg_state_home() / APP_DIR_NAME / "session"


@dataclass(frozen=True)
class RuntimePaths:
    history_root: Path
    session_root: Path
    config_root: Path
    custom_history: bool = False
    custom_session: bool = False
    custom_config: bool = False


def resolve_runtime_paths(
    *,
    history_arg: Path | None = None,
    session_arg: Path | None = None,
    config_arg: Path | None = None,
) -> RuntimePaths:
    """Resuelve rutas priorizando CLI → variables AGENT_SHELL_* → directorios XDG."""
    env_history = os.environ.get("AGENT_SHELL_HISTORY_DIR", "").strip()
    env_session = os.environ.get("AGENT_SHELL_SESSION_DIR", "").strip()
    env_config = os.environ.get("AGENT_SHELL_CONFIG_DIR", "").strip()

    custom_history = history_arg is not None or bool(env_history)
    custom_session = session_arg is not None or bool(env_session)
    custom_config = config_arg is not None or bool(env_config)

    history_root = (
        history_arg.expanduser() if history_arg is not None
        else Path(env_history).expanduser() if env_history
        else default_history_root()
    )
    session_root = (
        session_arg.expanduser() if session_arg is not None
        else Path(env_session).expanduser() if env_session
        else default_session_root()
    )
    if config_arg is not None:
        config_root = config_arg.expanduser()
    elif env_config:
        config_root = Path(env_config).expanduser()
    elif custom_history:
        # Un --history-root explícito aísla también config/ para pruebas y perfiles aparte.
        config_root = history_root / "config"
    else:
        config_root = default_config_root()

    return RuntimePaths(
        history_root=history_root,
        session_root=session_root,
        config_root=config_root,
        custom_history=custom_history,
        custom_session=custom_session,
        custom_config=custom_config,
    )


def _atomic_copy_private(source: Path, destination: Path) -> bool:
    """Copia un archivo regular de forma atómica con permisos 0600, sin seguir enlaces."""
    if source.is_symlink() or not source.is_file():
        return False
    if destination.is_symlink() or destination.exists():
        return False
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if os.name == "posix":
        os.chmod(destination.parent, 0o700)
    data = source.read_bytes()
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", dir=destination.parent, prefix=".migrate-", suffix=".tmp", delete=False,
        ) as handle:
            temporary = Path(handle.name)
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        if os.name == "posix":
            os.chmod(temporary, 0o600)
        os.replace(temporary, destination)
        return True
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


def _backup_sqlite(source_db: Path, dest_db: Path) -> bool:
    """Copia consistente de SQLite (WAL incluido) mediante sqlite3.backup()."""
    import sqlite3
    if source_db.is_symlink() or not source_db.is_file():
        return False
    if dest_db.is_symlink() or dest_db.exists():
        return False
    dest_db.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = dest_db.parent / f".migrate-{os.getpid()}.db.tmp"
    src = dst = None
    try:
        src = sqlite3.connect(f"file:{source_db}?mode=ro", uri=True, timeout=5.0)
        dst = sqlite3.connect(str(temporary), timeout=5.0)
        src.backup(dst)
        dst.close()
        dst = None
        src.close()
        src = None
        if os.name == "posix":
            os.chmod(temporary, 0o600)
        os.replace(temporary, dest_db)
        return True
    except (OSError, sqlite3.Error):
        return False
    finally:
        if dst is not None:
            dst.close()
        if src is not None:
            src.close()
        temporary.unlink(missing_ok=True)


def _copy_blobs_tree(source_blobs: Path, dest_blobs: Path) -> int:
    if source_blobs.is_symlink() or not source_blobs.is_dir():
        return 0
    copied = 0
    for bucket in sorted(source_blobs.iterdir()):
        if bucket.is_symlink() or not bucket.is_dir():
            continue
        for entry in sorted(bucket.iterdir()):
            if entry.is_symlink() or not entry.is_file():
                continue
            target = dest_blobs / bucket.name / entry.name
            if _atomic_copy_private(entry, target):
                copied += 1
    return copied


def _copy_legacy_jsons(source_dir: Path, dest_dir: Path) -> int:
    if source_dir.is_symlink() or not source_dir.is_dir():
        return 0
    copied = 0
    for entry in sorted(source_dir.glob("*.json")):
        if _atomic_copy_private(entry, dest_dir / entry.name):
            copied += 1
    return copied


def migrate_legacy_runtime(legacy_runtime: Path, paths: RuntimePaths) -> dict[str, bool]:
    """Copia datos existentes de `.runtime/` a rutas XDG una sola vez, conservando respaldo."""
    result = {"session": False, "limits": False, "history": False}
    if legacy_runtime.is_symlink() or not legacy_runtime.is_dir():
        return result

    # 1. Sesión OAuth (.runtime/session/session.json -> XDG_STATE_HOME/agent-shell/session/session.json)
    if not paths.custom_session:
        legacy_session = legacy_runtime / "session" / "session.json"
        dest_session = paths.session_root / "session.json"
        if legacy_session.exists() and not dest_session.exists():
            try:
                result["session"] = _atomic_copy_private(legacy_session, dest_session)
            except OSError:
                pass

    # 2. Límites de tokens (.runtime/chats/config/limits.json -> XDG_CONFIG_HOME/agent-shell/limits.json)
    if not paths.custom_config and not paths.custom_history:
        legacy_limits = legacy_runtime / "chats" / "config" / "limits.json"
        dest_limits = paths.config_root / "limits.json"
        if legacy_limits.exists() and not dest_limits.exists():
            try:
                result["limits"] = _atomic_copy_private(legacy_limits, dest_limits)
            except OSError:
                pass

    # 3. Historial, proyectos y blobs (.runtime/chats/ -> XDG_DATA_HOME/agent-shell/)
    if not paths.custom_history:
        legacy_chats = legacy_runtime / "chats"
        marker = paths.history_root / MIGRATION_MARKER
        has_dest_data = (
            marker.exists()
            or (paths.history_root / "agent-shell.db").exists()
            or any(paths.history_root.glob("*.json")) if paths.history_root.exists() else False
        )
        if not has_dest_data and legacy_chats.is_dir() and not legacy_chats.is_symlink():
            migrated_any = False
            legacy_db = legacy_chats / "agent-shell.db"
            if legacy_db.is_file() and not legacy_db.is_symlink():
                if _backup_sqlite(legacy_db, paths.history_root / "agent-shell.db"):
                    migrated_any = True
                if _copy_blobs_tree(legacy_chats / "blobs", paths.history_root / "blobs") > 0:
                    migrated_any = True
            if _copy_legacy_jsons(legacy_chats, paths.history_root) > 0:
                migrated_any = True
            if _copy_legacy_jsons(legacy_chats / "projects", paths.history_root / "projects") > 0:
                migrated_any = True
            if migrated_any:
                try:
                    paths.history_root.mkdir(mode=0o700, parents=True, exist_ok=True)
                    marker.write_text(str(legacy_runtime.resolve()) + "\n", encoding="utf-8")
                    if os.name == "posix":
                        os.chmod(marker, 0o600)
                except OSError:
                    pass
                result["history"] = True
    return result


def default_workspace() -> Path:
    """Evita abrir la terminal de Chat en directorios del sistema de solo lectura (/usr, /)."""
    env_ws = os.environ.get("AGENT_SHELL_WORKSPACE", "").strip()
    if env_ws:
        return Path(env_ws).expanduser()
    cwd = Path.cwd()
    if cwd == Path("/") or str(cwd).startswith("/usr/"):
        return Path.home()
    return cwd


def legacy_runtime_for(anchor_file: Path) -> Path | None:
    """Devuelve `.runtime/` junto al repositorio sólo cuando corre desde un checkout local."""
    candidate = anchor_file.resolve().parents[1] / ".runtime"
    if candidate.is_dir() and not candidate.is_symlink() and not str(candidate).startswith("/usr/"):
        return candidate
    return None


__all__ = [
    "APP_DIR_NAME",
    "MIGRATION_MARKER",
    "RuntimePaths",
    "default_config_root",
    "default_history_root",
    "default_session_root",
    "default_workspace",
    "legacy_runtime_for",
    "migrate_legacy_runtime",
    "resolve_runtime_paths",
    "xdg_config_home",
    "xdg_data_home",
    "xdg_state_home",
]
