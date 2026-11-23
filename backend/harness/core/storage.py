"""Almacenamiento local SQLite (WAL) y blobs binarios deduplicados por SHA-256."""

from __future__ import annotations

import base64
import binascii
import hashlib
import os
import re
import sqlite3
import tempfile
import threading
import weakref
from contextlib import contextmanager
from pathlib import Path

SCHEMA_VERSION = 1

_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
BLOB_REF_RE = re.compile(r"^blob:sha256:([0-9a-f]{64});mime=(image/(?:png|jpeg|webp))$")
DATA_URL_RE = re.compile(r"^data:(image/(?:png|jpeg|webp));base64,(.+)$", re.DOTALL)

_SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS projects (
    project_id TEXT PRIMARY KEY,
    schema_version INTEGER NOT NULL DEFAULT 1,
    name TEXT NOT NULL,
    workdir TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    launch_profile_json TEXT
);

CREATE TABLE IF NOT EXISTS chats (
    chat_id TEXT PRIMARY KEY,
    schema_version INTEGER NOT NULL DEFAULT 1,
    title TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    area TEXT NOT NULL DEFAULT 'chat',
    project_id TEXT NOT NULL DEFAULT '',
    model TEXT NOT NULL DEFAULT '',
    reasoning_effort TEXT NOT NULL DEFAULT '',
    thread_id TEXT,
    compaction_count INTEGER NOT NULL DEFAULT 0,
    parent_chat_id TEXT,
    payload_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_chats_updated
    ON chats(updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_chats_area_project_updated
    ON chats(area, project_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS turn_performance (
    turn_id TEXT NOT NULL,
    chat_id TEXT NOT NULL,
    started_at TEXT NOT NULL,
    status TEXT NOT NULL,
    model TEXT NOT NULL DEFAULT '',
    area TEXT NOT NULL DEFAULT 'chat',
    measurement_json TEXT NOT NULL,
    PRIMARY KEY (chat_id, turn_id),
    FOREIGN KEY (chat_id) REFERENCES chats(chat_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_perf_started
    ON turn_performance(started_at DESC);

CREATE TABLE IF NOT EXISTS chat_blobs (
    chat_id TEXT NOT NULL,
    sha256 TEXT NOT NULL,
    mime TEXT NOT NULL,
    size_bytes INTEGER NOT NULL,
    PRIMARY KEY (chat_id, sha256),
    FOREIGN KEY (chat_id) REFERENCES chats(chat_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_chat_blobs_sha
    ON chat_blobs(sha256);
"""


def _close_connection(conn: sqlite3.Connection) -> None:
    try:
        conn.close()
    except sqlite3.Error:
        pass


class StorageDB:
    """Conexión SQLite en modo WAL con transacciones atómicas y permisos 0600."""

    def __init__(self, path: Path) -> None:
        if path.is_symlink():
            raise ValueError("No se permiten enlaces simbólicos en la base de datos local")
        self.path = path.parent.resolve() / path.name
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        self._check_no_symlinks()
        self._lock = threading.RLock()
        self._conn = sqlite3.connect(
            str(self.path),
            timeout=5.0,
            isolation_level=None,
            check_same_thread=False,
        )
        self._conn.row_factory = sqlite3.Row
        self._finalizer = weakref.finalize(self, _close_connection, self._conn)
        self._closed = False
        self._initialize()

    def _check_no_symlinks(self) -> None:
        for candidate in (self.path, Path(f"{self.path}-wal"), Path(f"{self.path}-shm")):
            if candidate.is_symlink():
                raise ValueError("No se permiten enlaces simbólicos en la base de datos local")

    def _ensure_permissions(self) -> None:
        if os.name != "posix":
            return
        for candidate in (self.path, Path(f"{self.path}-wal"), Path(f"{self.path}-shm")):
            try:
                if candidate.exists() and not candidate.is_symlink():
                    os.chmod(candidate, 0o600)
            except OSError:
                pass

    def _initialize(self) -> None:
        with self._lock:
            self._conn.execute("PRAGMA journal_mode = WAL")
            self._conn.execute("PRAGMA synchronous = NORMAL")
            self._conn.execute("PRAGMA foreign_keys = ON")
            self._conn.execute("PRAGMA busy_timeout = 5000")
            self._conn.execute("PRAGMA temp_store = MEMORY")
            version = self._conn.execute("PRAGMA user_version").fetchone()[0]
            if version > SCHEMA_VERSION:
                raise ValueError(f"Versión de base de datos incompatible: {version}")
            self._conn.executescript(_SCHEMA_SQL)
            if version < SCHEMA_VERSION:
                self._conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
            self._ensure_permissions()

    @contextmanager
    def transaction(self):
        with self._lock:
            self._check_no_symlinks()
            self._conn.execute("BEGIN IMMEDIATE")
            try:
                yield self._conn
            except BaseException:
                if self._conn.in_transaction:
                    try:
                        self._conn.execute("ROLLBACK")
                    except sqlite3.Error:
                        pass
                raise
            else:
                self._conn.execute("COMMIT")
                self._ensure_permissions()

    @contextmanager
    def read(self):
        with self._lock:
            yield self._conn

    def journal_mode(self) -> str:
        with self._lock:
            row = self._conn.execute("PRAGMA journal_mode").fetchone()
            return str(row[0]).lower() if row else ""

    def checkpoint(self) -> None:
        with self._lock:
            if not self._closed:
                try:
                    self._conn.execute("PRAGMA wal_checkpoint(PASSIVE)")
                except sqlite3.Error:
                    pass

    def close(self) -> None:
        with self._lock:
            if not self._closed:
                self._closed = True
                self._finalizer()


class BlobStore:
    """Almacén binario privado indexado por SHA-256 para adjuntos pesados (imágenes)."""

    def __init__(self, root: Path) -> None:
        if root.is_symlink():
            raise ValueError("No se permiten enlaces simbólicos en el almacén de blobs")
        self.root = root.resolve()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)

    def path_for(self, sha256: str) -> Path:
        if not isinstance(sha256, str) or not _SHA256_RE.fullmatch(sha256):
            raise ValueError("Identificador de blob inválido")
        bucket = self.root / sha256[:2]
        if bucket.is_symlink():
            raise ValueError("No se permiten enlaces simbólicos en el almacén de blobs")
        target = bucket / sha256
        if target.is_symlink():
            raise ValueError("No se permiten enlaces simbólicos en el almacén de blobs")
        return target

    def put_bytes(self, data: bytes) -> tuple[str, int]:
        sha256 = hashlib.sha256(data).hexdigest()
        target = self.path_for(sha256)
        if target.exists():
            return sha256, len(data)
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="wb", dir=target.parent, prefix=".blob-", suffix=".tmp", delete=False,
            ) as handle:
                temporary = Path(handle.name)
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            if os.name == "posix":
                os.chmod(temporary, 0o600)
            os.replace(temporary, target)
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)
        return sha256, len(data)

    def get_bytes(self, sha256: str) -> bytes:
        target = self.path_for(sha256)
        raw = target.read_bytes()
        if hashlib.sha256(raw).hexdigest() != sha256:
            raise ValueError("Blob dañado: la suma SHA-256 no coincide")
        return raw

    def delete(self, sha256: str) -> None:
        try:
            target = self.path_for(sha256)
            target.unlink(missing_ok=True)
            try:
                target.parent.rmdir()
            except OSError:
                pass
        except (OSError, ValueError):
            pass

    def externalize_image(self, value, collected: dict[str, tuple[str, int]]):
        if not isinstance(value, str) or not value:
            return value
        existing = BLOB_REF_RE.fullmatch(value)
        if existing:
            sha256, mime = existing.group(1), existing.group(2)
            size = 0
            try:
                target = self.path_for(sha256)
                if target.exists():
                    size = target.stat().st_size
            except (OSError, ValueError):
                pass
            collected[sha256] = (mime, size)
            return value
        matched = DATA_URL_RE.fullmatch(value)
        if not matched:
            return value
        mime, encoded = matched.group(1), matched.group(2)
        try:
            raw = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError):
            return value
        if not raw:
            return value
        sha256, size = self.put_bytes(raw)
        collected[sha256] = (mime, size)
        return f"blob:sha256:{sha256};mime={mime}"

    def resolve_image(self, value):
        if not isinstance(value, str) or not value:
            return value
        matched = BLOB_REF_RE.fullmatch(value)
        if not matched:
            return value
        sha256, mime = matched.group(1), matched.group(2)
        raw = self.get_bytes(sha256)
        return f"data:{mime};base64," + base64.b64encode(raw).decode("ascii")

    def externalize_record(self, record: dict) -> tuple[dict, dict[str, tuple[str, int]]]:
        """Devuelve una copia del registro con imágenes movidas a blobs (sin mutar `record`)."""
        collected: dict[str, tuple[str, int]] = {}
        copy_record = dict(record)
        messages = record.get("messages")
        if isinstance(messages, list):
            new_messages = []
            for msg in messages:
                if isinstance(msg, dict) and isinstance(msg.get("image"), str) and msg["image"]:
                    new_messages.append({**msg, "image": self.externalize_image(msg["image"], collected)})
                else:
                    new_messages.append(msg)
            copy_record["messages"] = new_messages
        context = record.get("context")
        if isinstance(context, list):
            new_context = []
            for item in context:
                if isinstance(item, dict) and isinstance(item.get("content"), list):
                    new_parts = []
                    changed = False
                    for part in item["content"]:
                        if (isinstance(part, dict) and part.get("type") == "input_image"
                                and isinstance(part.get("image_url"), str)):
                            ext = self.externalize_image(part["image_url"], collected)
                            if ext != part["image_url"]:
                                changed = True
                                new_parts.append({**part, "image_url": ext})
                            else:
                                new_parts.append(part)
                        else:
                            new_parts.append(part)
                    new_context.append({**item, "content": new_parts} if changed else item)
                else:
                    new_context.append(item)
            copy_record["context"] = new_context
        return copy_record, collected

    def resolve_record(self, record: dict) -> dict:
        """Restaura referencias `blob:sha256:...` a URLs de datos base64 en memoria."""
        if not isinstance(record, dict):
            return record
        messages = record.get("messages")
        if isinstance(messages, list):
            for msg in messages:
                if isinstance(msg, dict) and isinstance(msg.get("image"), str) and msg["image"].startswith("blob:"):
                    msg["image"] = self.resolve_image(msg["image"])
        context = record.get("context")
        if isinstance(context, list):
            for item in context:
                if isinstance(item, dict) and isinstance(item.get("content"), list):
                    for part in item["content"]:
                        if (isinstance(part, dict) and part.get("type") == "input_image"
                                and isinstance(part.get("image_url"), str)
                                and part["image_url"].startswith("blob:")):
                            part["image_url"] = self.resolve_image(part["image_url"])
        return record
