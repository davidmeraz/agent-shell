"""Proyectos de Work en SQLite (WAL): identidad y carpeta local, separados de la sesión."""

from __future__ import annotations

import json
import os
import re
import sqlite3
import threading
import uuid
from pathlib import Path

from ..chat.history import now
from ..core.storage import StorageDB
from ..tools.shell import resolve_workspace


def _validate_project(project_id: str, project: dict) -> dict:
    if (not isinstance(project, dict) or project.get("schema_version") != 1
            or project.get("project_id") != project_id
            or not all(isinstance(project.get(key), str) and project[key]
                       for key in ("name", "workdir", "created_at", "updated_at"))):
        raise ValueError("Registro de proyecto inválido")
    kind = project.get("kind", "work")
    engine = project.get("engine", "python")
    if kind not in ("work", "app") or engine not in ("python", "rust"):
        raise ValueError("Metadatos de tipo o motor inválidos")
    project["kind"] = kind
    project["engine"] = engine
    return project


def _row_to_project(row: sqlite3.Row) -> dict:
    keys = row.keys()
    project = {
        "schema_version": row["schema_version"],
        "project_id": row["project_id"],
        "name": row["name"],
        "workdir": row["workdir"],
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "kind": row["kind"] if "kind" in keys and row["kind"] else "work",
        "engine": row["engine"] if "engine" in keys and row["engine"] else "python",
    }
    if row["launch_profile_json"] is not None:
        project["launch_profile"] = json.loads(row["launch_profile_json"])
    return project


class ProjectStore:
    def __init__(self, root: Path, db: StorageDB | None = None) -> None:
        self.root = root.resolve()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.db = db if db is not None else StorageDB(self.root / "projects.db")
        self._owns_db = db is None
        self._lock = threading.RLock()
        self._scan_legacy_json()

    def close(self) -> None:
        if self._owns_db:
            self.db.close()

    def _validate_id(self, project_id: str) -> str:
        if not isinstance(project_id, str) or not re.fullmatch(r"[0-9a-f]{32}", project_id):
            raise ValueError("Identificador de proyecto inválido")
        legacy = self.root / f"{project_id}.json"
        if legacy.is_symlink():
            raise ValueError("No se permiten enlaces simbólicos en los proyectos")
        return project_id

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
        if not self._has_legacy_json():
            return
        migrated_dir = self.root / ".migrated-json"
        for path in sorted(self.root.glob("*.json")):
            if path.is_symlink():
                continue
            project_id = path.stem
            if not re.fullmatch(r"[0-9a-f]{32}", project_id):
                continue
            try:
                project = json.loads(path.read_text(encoding="utf-8"))
                validated = _validate_project(project_id, project)
                self._save(validated, preserve_updated_at=True)
            except (OSError, ValueError, KeyError, TypeError, sqlite3.IntegrityError):
                continue
            try:
                migrated_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
                os.replace(path, migrated_dir / path.name)
            except OSError:
                pass

    def load(self, project_id: str) -> dict:
        self._validate_id(project_id)
        if (self.root / f"{project_id}.json").exists():
            self._scan_legacy_json()
        with self.db.read() as conn:
            row = conn.execute(
                """
                SELECT project_id, schema_version, name, workdir, created_at, updated_at, launch_profile_json, kind, engine
                FROM projects WHERE project_id = ?
                """,
                (project_id,),
            ).fetchone()
        if row is None:
            raise FileNotFoundError(project_id)
        return _validate_project(project_id, _row_to_project(row))

    def save(self, project: dict) -> None:
        with self._lock:
            self._save(project, preserve_updated_at=False)

    def _save(self, project: dict, *, preserve_updated_at: bool = False) -> None:
        project_id = self._validate_id(project["project_id"])
        updated_at = project["updated_at"] if preserve_updated_at and isinstance(project.get("updated_at"), str) else now()
        launch_json = json.dumps(project["launch_profile"], ensure_ascii=False) if "launch_profile" in project else None
        kind = project.get("kind", "work") if project.get("kind") in ("work", "app") else "work"
        engine = project.get("engine", "python") if project.get("engine") in ("python", "rust") else "python"
        with self.db.transaction() as conn:
            conn.execute(
                """
                INSERT INTO projects
                    (project_id, schema_version, name, workdir, created_at, updated_at, launch_profile_json, kind, engine)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(project_id) DO UPDATE SET
                    schema_version = excluded.schema_version,
                    name = excluded.name,
                    workdir = excluded.workdir,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    launch_profile_json = excluded.launch_profile_json,
                    kind = excluded.kind,
                    engine = excluded.engine
                """,
                (
                    project_id,
                    project.get("schema_version", 1),
                    project["name"],
                    project["workdir"],
                    project["created_at"],
                    updated_at,
                    launch_json,
                    kind,
                    engine,
                ),
            )
        project["kind"] = kind
        project["engine"] = engine
        if not preserve_updated_at:
            project["updated_at"] = updated_at

    def update_launch_profile(self, project_id: str, workspace: str, profile) -> bool:
        """Actualiza sólo el inicio, preservando cambios de carpeta concurrentes."""
        with self._lock:
            project = self.load(project_id)
            if project["workdir"] != workspace:
                return False
            if profile is None:
                if "launch_profile" not in project:
                    return True
                project.pop("launch_profile")
            else:
                project["launch_profile"] = profile
            self.save(project)
            return True

    def update_workdir(self, project_id: str, workspace: str) -> dict:
        with self._lock:
            project = self.load(project_id)
            if project["workdir"] != workspace:
                project.pop("launch_profile", None)
            project["workdir"] = workspace
            self.save(project)
            return project

    def rename(self, project_id: str, name: str) -> dict:
        if not isinstance(name, str) or not name.strip() or len(name.strip()) > 80 or "\0" in name:
            raise ValueError("Escribe un nombre de proyecto de entre 1 y 80 caracteres")
        with self._lock:
            project = self.load(project_id)
            project["name"] = name.strip()
            self.save(project)
            return project

    def create(self, name: str, workdir: str, *, kind: str = "work", engine: str = "python") -> dict:
        if not isinstance(name, str) or not name.strip() or len(name) > 80 or "\0" in name:
            raise ValueError("Escribe un nombre de proyecto de entre 1 y 80 caracteres")
        if kind not in ("work", "app") or engine not in ("python", "rust"):
            raise ValueError("Configuración de aplicación o proyecto inválida")
        folder = resolve_workspace(workdir)
        if any(row["workdir"] == str(folder) for row in self.list()):
            raise ValueError("Esta carpeta ya pertenece a un proyecto de Work o App")
        timestamp = now()
        project = {
            "schema_version": 1, "project_id": uuid.uuid4().hex, "name": name.strip(),
            "workdir": str(folder), "created_at": timestamp, "updated_at": timestamp,
            "kind": kind, "engine": engine,
        }
        try:
            self.save(project)
        except sqlite3.IntegrityError:
            raise ValueError("Esta carpeta ya pertenece a un proyecto de Work o App") from None
        return project

    def list(self, kind: str | None = None) -> list[dict]:
        self._scan_legacy_json()
        with self.db.read() as conn:
            rows = conn.execute(
                """
                SELECT project_id, schema_version, name, workdir, created_at, updated_at, launch_profile_json, kind, engine
                FROM projects ORDER BY updated_at DESC
                """
            ).fetchall()
        result = []
        for row in rows:
            try:
                item = _validate_project(row["project_id"], _row_to_project(row))
                if kind is None or item.get("kind", "work") == kind:
                    result.append(item)
            except (ValueError, KeyError, TypeError):
                continue
        return result
