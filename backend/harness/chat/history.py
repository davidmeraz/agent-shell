"""Historial local en SQLite (WAL) con blobs binarios para adjuntos pesados.

Las escrituras son transaccionales (ACID) y las imágenes base64 se deduplican por
SHA-256 en `blobs/`. Conserva el esquema lógico v1 y migra automáticamente los
JSON heredados (`*.json`) sin tocar ni ocultar archivos dañados o enlaces simbólicos.
"""

from __future__ import annotations

import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

from ..core.storage import BlobStore, StorageDB
from .context import replay_items
from .images import validate_image
from .performance import safe_measurement


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _validate_record(chat_id: str, record: dict) -> dict:
    """Valida el esquema lógico v1 antes de entregar datos a Qt o reenviar contexto."""
    if not isinstance(record, dict) or record.get("schema_version") != 1 or record.get("chat_id") != chat_id:
        raise ValueError("Formato del historial incompatible")
    if not all(isinstance(record.get(key), str) for key in ("title", "created_at", "updated_at", "model")):
        raise ValueError("Metadatos del historial inválidos")
    if "reasoning_effort" in record and not isinstance(record["reasoning_effort"], str):
        raise ValueError("Esfuerzo de razonamiento del historial inválido")
    if "compaction_count" in record:
        if type(record["compaction_count"]) is not int or record["compaction_count"] < 0:
            raise ValueError("Contador de compactaciones del historial inválido")
    else:
        record["compaction_count"] = 0
    if "parent_chat_id" in record and record["parent_chat_id"] is not None:
        if not isinstance(record["parent_chat_id"], str) or not re.fullmatch(r"[0-9a-f]{32}", record["parent_chat_id"]):
            raise ValueError("Chat origen del historial inválido")
    if record.get("thread_id") is not None and not isinstance(record["thread_id"], str):
        raise ValueError("Thread del historial inválido")
    area, project_id = record.get("area", "chat"), record.get("project_id", "")
    if (area not in ("chat", "work") or not isinstance(project_id, str)
            or (area == "chat" and project_id != "")
            or (area == "work" and not re.fullmatch(r"[0-9a-f]{32}", project_id))):
        raise ValueError("Área de conversación inválida")
    record["area"], record["project_id"] = area, project_id
    messages = record.get("messages")
    if not isinstance(messages, list):
        raise ValueError("Mensajes del historial inválidos")
    for message in messages:
        if (not isinstance(message, dict) or message.get("role") not in ("user", "assistant", "system")
                or not all(isinstance(message.get(key), str) for key in ("id", "text", "status"))):
            raise ValueError("Mensaje del historial inválido")
        if "image" in message:
            if message["role"] != "user":
                raise ValueError("Imagen del historial inválida")
            validate_image(message["image"])
    measurements = record.get("performance")
    record["performance"] = []
    if isinstance(measurements, list):
        record["performance"] = [clean for row in measurements if (clean := safe_measurement(row))]
    if "context" in record:
        record["context"] = replay_items(record["context"])
    calls = record.get("tool_calls", [])
    if not isinstance(calls, list) or any(
        not isinstance(call, dict) or not all(isinstance(call.get(key), str)
        for key in ("id", "call_id", "turn_id", "command", "workdir", "status", "output"))
        or call["status"] not in ("pending", "running", "completed", "error", "timeout", "denied", "interrupted")
        for call in calls
    ):
        raise ValueError("Registro de herramientas inválido")
    record["tool_calls"] = calls
    return record


class HistoryStore:
    """Guarda conversaciones en SQLite (WAL) + blobs; migra JSON heredados y preserva dañados."""

    def __init__(self, root: Path, db: StorageDB | None = None, blobs: BlobStore | None = None) -> None:
        self.root = root.resolve()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.db = db if db is not None else StorageDB(self.root / "agent-shell.db")
        self._owns_db = db is None
        self.blobs = blobs if blobs is not None else BlobStore(self.root / "blobs")
        self.invalid_files: list[str] = []
        self._scan_legacy_json()

    def close(self) -> None:
        if self._owns_db:
            self.db.close()

    def _validate_id(self, chat_id: str) -> str:
        if not isinstance(chat_id, str) or not re.fullmatch(r"[0-9a-f]{32}", chat_id):
            raise ValueError("Identificador de conversación inválido")
        legacy = self.root / f"{chat_id}.json"
        if legacy.is_symlink():
            raise ValueError("No se permiten enlaces simbólicos en el historial")
        return chat_id

    def _has_legacy_json(self) -> bool:
        try:
            with os.scandir(self.root) as entries:
                for entry in entries:
                    if entry.name.endswith(".json"):
                        return True
        except OSError:
            pass
        return False

    def _scan_legacy_json(self) -> None:
        """Importa archivos JSON válidos heredados a SQLite y deja intactos los dañados/symlinks."""
        self.invalid_files = []
        if not self._has_legacy_json():
            return
        migrated_dir = self.root / ".migrated-json"
        for path in sorted(self.root.glob("*.json")):
            if path.is_symlink():
                self.invalid_files.append(path.name)
                continue
            chat_id = path.stem
            if not re.fullmatch(r"[0-9a-f]{32}", chat_id):
                self.invalid_files.append(path.name)
                continue
            try:
                record = json.loads(path.read_text(encoding="utf-8"))
                validated = _validate_record(chat_id, record)
                self._upsert_record(validated, preserve_updated_at=True)
            except (OSError, ValueError, KeyError, TypeError):
                self.invalid_files.append(path.name)
                continue
            try:
                migrated_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
                os.replace(path, migrated_dir / path.name)
            except OSError:
                pass

    def _upsert_record(self, record: dict, *, preserve_updated_at: bool = False) -> list[str]:
        chat_id = self._validate_id(record["chat_id"])
        updated_at = record["updated_at"] if preserve_updated_at and isinstance(record.get("updated_at"), str) else now()
        payload = {**record, "updated_at": updated_at}
        storable, blob_refs = self.blobs.externalize_record(payload)
        payload_json = json.dumps(storable, ensure_ascii=False)

        area = payload.get("area", "chat") if isinstance(payload.get("area"), str) else "chat"
        project_id = payload.get("project_id", "") if isinstance(payload.get("project_id"), str) else ""
        title = payload.get("title", "") if isinstance(payload.get("title"), str) else ""
        created_at = payload.get("created_at", updated_at) if isinstance(payload.get("created_at"), str) else updated_at
        model = payload.get("model", "") if isinstance(payload.get("model"), str) else ""
        reasoning_effort = payload.get("reasoning_effort", "") if isinstance(payload.get("reasoning_effort"), str) else ""
        thread_id = payload.get("thread_id") if isinstance(payload.get("thread_id"), str) else None
        compaction_count = payload.get("compaction_count", 0)
        if type(compaction_count) is not int or compaction_count < 0:
            compaction_count = 0
        parent_chat_id = payload.get("parent_chat_id") if isinstance(payload.get("parent_chat_id"), str) else None
        schema_version = payload.get("schema_version", 1)
        if type(schema_version) is not int:
            schema_version = 1

        perf_rows = []
        raw_perf = payload.get("performance")
        if isinstance(raw_perf, list):
            for row in raw_perf:
                clean = safe_measurement(row)
                if clean:
                    perf_rows.append((
                        clean["turn_id"], chat_id, clean["started_at"], clean["status"],
                        clean.get("model", ""), area, json.dumps(clean, ensure_ascii=False),
                    ))

        orphans: list[str] = []
        with self.db.transaction() as conn:
            old_shas = {
                row[0] for row in conn.execute("SELECT sha256 FROM chat_blobs WHERE chat_id = ?", (chat_id,))
            }
            conn.execute(
                """
                INSERT INTO chats (
                    chat_id, schema_version, title, created_at, updated_at,
                    area, project_id, model, reasoning_effort, thread_id,
                    compaction_count, parent_chat_id, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(chat_id) DO UPDATE SET
                    schema_version = excluded.schema_version,
                    title = excluded.title,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    area = excluded.area,
                    project_id = excluded.project_id,
                    model = excluded.model,
                    reasoning_effort = excluded.reasoning_effort,
                    thread_id = excluded.thread_id,
                    compaction_count = excluded.compaction_count,
                    parent_chat_id = excluded.parent_chat_id,
                    payload_json = excluded.payload_json
                """,
                (
                    chat_id, schema_version, title, created_at, updated_at,
                    area, project_id, model, reasoning_effort, thread_id,
                    compaction_count, parent_chat_id, payload_json,
                ),
            )
            conn.execute("DELETE FROM turn_performance WHERE chat_id = ?", (chat_id,))
            if perf_rows:
                conn.executemany(
                    """
                    INSERT OR REPLACE INTO turn_performance
                        (turn_id, chat_id, started_at, status, model, area, measurement_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    perf_rows,
                )
            conn.execute("DELETE FROM chat_blobs WHERE chat_id = ?", (chat_id,))
            if blob_refs:
                conn.executemany(
                    "INSERT OR REPLACE INTO chat_blobs (chat_id, sha256, mime, size_bytes) VALUES (?, ?, ?, ?)",
                    [(chat_id, sha, mime, size) for sha, (mime, size) in blob_refs.items()],
                )
            removed = old_shas - set(blob_refs)
            for sha in removed:
                still_used = conn.execute(
                    "SELECT 1 FROM chat_blobs WHERE sha256 = ? LIMIT 1", (sha,)
                ).fetchone()
                if still_used is None:
                    orphans.append(sha)

        if not preserve_updated_at:
            record["updated_at"] = updated_at
        for sha in orphans:
            self.blobs.delete(sha)
        return orphans

    def create(self, prompt: str, area: str = "chat", project_id: str = "") -> dict:
        """Crea una conversación cuando llega su primer mensaje; evita chats vacíos."""
        timestamp = now()
        record = {
            "schema_version": 1, "chat_id": uuid.uuid4().hex,
            "title": " ".join(prompt.split())[:72],
            "created_at": timestamp, "updated_at": timestamp,
            "thread_id": None, "model": "", "messages": [],
            "area": area, "project_id": project_id, "compaction_count": 0,
        }
        self.save(record)
        return record

    def save(self, record: dict) -> None:
        """Guarda conversación, métricas y referencias de blobs en una transacción ACID."""
        self._upsert_record(record, preserve_updated_at=False)

    def load(self, chat_id: str) -> dict:
        """Valida el esquema antes de entregar texto a Qt o usar un thread almacenado."""
        self._validate_id(chat_id)
        if (self.root / f"{chat_id}.json").exists():
            self._scan_legacy_json()
        with self.db.read() as conn:
            row = conn.execute("SELECT payload_json FROM chats WHERE chat_id = ?", (chat_id,)).fetchone()
        if row is None:
            raise FileNotFoundError(chat_id)
        record = json.loads(row["payload_json"])
        record = self.blobs.resolve_record(record)
        return _validate_record(chat_id, record)

    def delete(self, chat_id: str) -> None:
        """Borra únicamente la conversación identificada y limpia blobs huérfanos."""
        self._validate_id(chat_id)
        orphans: list[str] = []
        with self.db.transaction() as conn:
            old_shas = [
                row[0] for row in conn.execute("SELECT sha256 FROM chat_blobs WHERE chat_id = ?", (chat_id,))
            ]
            cursor = conn.execute("DELETE FROM chats WHERE chat_id = ?", (chat_id,))
            if cursor.rowcount == 0:
                raise FileNotFoundError(chat_id)
            for sha in old_shas:
                still_used = conn.execute(
                    "SELECT 1 FROM chat_blobs WHERE sha256 = ? LIMIT 1", (sha,)
                ).fetchone()
                if still_used is None:
                    orphans.append(sha)
        for sha in orphans:
            self.blobs.delete(sha)

    def performance(self, limit: int = 200) -> list[dict]:
        """Últimos turnos medidos mediante índice SQLite, sin leer historiales completos."""
        self._scan_legacy_json()
        with self.db.read() as conn:
            rows = conn.execute(
                "SELECT chat_id, measurement_json FROM turn_performance ORDER BY started_at DESC LIMIT ?",
                (max(0, int(limit)),),
            ).fetchall()
        result = []
        for entry in rows:
            try:
                row = json.loads(entry["measurement_json"])
            except (ValueError, TypeError):
                continue
            if row.get("status") == "streaming":
                row["status"] = "interrupted"
                row["total_ms"] = row.get("elapsed_ms")
            result.append({**row, "chat_id": entry["chat_id"]})
        return result

    def list(self) -> list[dict]:
        """Devuelve títulos recientes primero desde índice SQLite; conserva JSON dañados."""
        self._scan_legacy_json()
        with self.db.read() as conn:
            rows = conn.execute(
                "SELECT chat_id, title, updated_at, area, project_id FROM chats ORDER BY updated_at DESC"
            ).fetchall()
        return [
            {
                "chat_id": row["chat_id"],
                "title": row["title"],
                "updated_at": row["updated_at"],
                "area": row["area"],
                "project_id": row["project_id"],
            }
            for row in rows
        ]
