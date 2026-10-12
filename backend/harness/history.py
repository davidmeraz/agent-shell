"""Historial local legible: un JSON por conversación, sin credenciales.

Las escrituras reemplazan el archivo completo de forma atómica. Un lector ve la
versión anterior o la nueva, nunca un JSON escrito a medias. Los mensajes locales
son el contexto del modelo; thread_id se conserva por compatibilidad con 0.2.0.
"""

import json
import os
import re
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path

from .performance import safe_measurement
from .context import replay_items


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


class HistoryStore:
    """Guarda las conversaciones del proceso; conserva archivos dañados sin borrarlos."""

    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.invalid_files: list[str] = []

    def _path(self, chat_id: str) -> Path:
        if not isinstance(chat_id, str) or not re.fullmatch(r"[0-9a-f]{32}", chat_id):
            raise ValueError("Identificador de conversación inválido")
        path = self.root / f"{chat_id}.json"
        if path.is_symlink():
            raise ValueError("No se permiten enlaces simbólicos en el historial")
        return path

    def create(self, prompt: str, area: str = "chat", project_id: str = "") -> dict:
        """Crea una conversación cuando llega su primer mensaje; evita chats vacíos."""
        timestamp = now()
        record = {
            "schema_version": 1, "chat_id": uuid.uuid4().hex,
            "title": " ".join(prompt.split())[:72],
            "created_at": timestamp, "updated_at": timestamp,
            "thread_id": None, "model": "", "messages": [],
            "area": area, "project_id": project_id,
        }
        self.save(record)
        return record

    def save(self, record: dict) -> None:
        """Vacía el temporal a disco antes de reemplazar el JSON anterior."""
        destination = self._path(record["chat_id"])
        payload = {**record, "updated_at": now()}
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=self.root, prefix=".chat-", suffix=".tmp",
                delete=False,
            ) as handle:
                temporary = Path(handle.name)
                json.dump(payload, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, destination)
            record["updated_at"] = payload["updated_at"]
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)

    def load(self, chat_id: str) -> dict:
        """Valida el esquema antes de entregar texto a Qt o usar un thread almacenado."""
        record = json.loads(self._path(chat_id).read_text(encoding="utf-8"))
        if not isinstance(record, dict) or record.get("schema_version") != 1 or record.get("chat_id") != chat_id:
            raise ValueError("Formato del historial incompatible")
        if not all(isinstance(record.get(key), str) for key in ("title", "created_at", "updated_at", "model")):
            raise ValueError("Metadatos del historial inválidos")
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

    def delete(self, chat_id: str) -> None:
        """Borra únicamente el archivo local identificado; los errores se propagan."""
        self._path(chat_id).unlink()

    def performance(self, limit: int = 200) -> list[dict]:
        """Últimos turnos medidos, sin títulos, prompts ni datos de cuenta."""
        result = []
        for path in self.root.glob("*.json"):
            try:
                record = self.load(path.stem)
                for row in record["performance"]:
                    if row["status"] == "streaming":
                        row["status"] = "interrupted"
                        row["total_ms"] = row["elapsed_ms"]
                    result.append({**row, "chat_id": record["chat_id"]})
            except (OSError, ValueError, KeyError, TypeError):
                continue
        return sorted(result, key=lambda row: row["started_at"], reverse=True)[:limit]

    def list(self) -> list[dict]:
        """Devuelve títulos recientes primero; un JSON dañado no oculta el resto."""
        result = []
        self.invalid_files = []
        for path in self.root.glob("*.json"):
            try:
                record = self.load(path.stem)
                result.append({key: record[key] for key in ("chat_id", "title", "updated_at", "area", "project_id")})
            except (OSError, ValueError, KeyError, TypeError):
                self.invalid_files.append(path.name)
        return sorted(result, key=lambda entry: entry["updated_at"], reverse=True)
