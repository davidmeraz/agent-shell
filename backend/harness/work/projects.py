"""Proyectos de Work: identidad y carpeta local, separados de conversaciones y sesión."""

import json
import os
import re
import tempfile
import threading
import uuid
from pathlib import Path

from ..chat.history import now
from ..tools.shell import resolve_workspace


class ProjectStore:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        self._lock = threading.RLock()

    def _path(self, project_id: str) -> Path:
        if not isinstance(project_id, str) or not re.fullmatch(r"[0-9a-f]{32}", project_id):
            raise ValueError("Identificador de proyecto inválido")
        path = self.root / f"{project_id}.json"
        if path.is_symlink():
            raise ValueError("No se permiten enlaces simbólicos en los proyectos")
        return path

    def load(self, project_id: str) -> dict:
        project = json.loads(self._path(project_id).read_text(encoding="utf-8"))
        if (not isinstance(project, dict) or project.get("schema_version") != 1
                or project.get("project_id") != project_id
                or not all(isinstance(project.get(key), str) and project[key]
                           for key in ("name", "workdir", "created_at", "updated_at"))):
            raise ValueError("Registro de proyecto inválido")
        return project

    def save(self, project: dict) -> None:
        with self._lock:
            self._save(project)

    def _save(self, project: dict) -> None:
        destination = self._path(project["project_id"])
        payload = {**project, "updated_at": now()}
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=self.root,
                                             prefix=".project-", suffix=".tmp", delete=False) as handle:
                temporary = Path(handle.name)
                json.dump(payload, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, destination)
            project["updated_at"] = payload["updated_at"]
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)

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

    def create(self, name: str, workdir: str) -> dict:
        if not isinstance(name, str) or not name.strip() or len(name) > 80 or "\0" in name:
            raise ValueError("Escribe un nombre de proyecto de entre 1 y 80 caracteres")
        folder = resolve_workspace(workdir)
        if any(row["workdir"] == str(folder) for row in self.list()):
            raise ValueError("Esta carpeta ya pertenece a un proyecto de Work")
        timestamp = now()
        project = {"schema_version": 1, "project_id": uuid.uuid4().hex,
                   "name": name.strip(), "workdir": str(folder),
                   "created_at": timestamp, "updated_at": timestamp}
        self.save(project)
        return project

    def list(self) -> list[dict]:
        projects = []
        for path in self.root.glob("*.json"):
            try:
                projects.append(self.load(path.stem))
            except (OSError, ValueError, KeyError, TypeError):
                continue
        return sorted(projects, key=lambda row: row["updated_at"], reverse=True)
