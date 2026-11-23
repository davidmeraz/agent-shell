"""Perfil local del usuario (nombre visible) con guardado atómico privado."""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path

MAX_DISPLAY_NAME_LENGTH = 40


def normalize_display_name(raw) -> str:
    """Valida y limpia el nombre de usuario visible (vacío restaura el valor por defecto)."""
    if not isinstance(raw, str):
        raise ValueError("El nombre de usuario debe ser texto.")
    cleaned = "".join(ch for ch in raw if ch >= " " and ch != "\x7f").strip()
    cleaned = " ".join(cleaned.split())
    if len(cleaned) > MAX_DISPLAY_NAME_LENGTH:
        raise ValueError(f"El nombre de usuario no puede superar {MAX_DISPLAY_NAME_LENGTH} caracteres.")
    return cleaned


class ProfileStore:
    """Persiste `profile.json` en `config_root` sin seguir enlaces simbólicos."""

    def __init__(self, root: Path) -> None:
        self.root = Path(root)
        self.path = self.root / "profile.json"

    def load(self) -> dict[str, str]:
        try:
            if self.path.is_symlink() or not self.path.is_file():
                return {"display_name": ""}
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            if not isinstance(raw, dict):
                return {"display_name": ""}
            name = normalize_display_name(raw.get("display_name", ""))
            return {"display_name": name}
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            return {"display_name": ""}

    def save(self, display_name: str) -> dict[str, str]:
        normalized = normalize_display_name(display_name)
        if self.root.is_symlink():
            raise OSError("El directorio de configuración no puede ser un enlace simbólico.")
        self.root.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(self.root, 0o700)
        except OSError:
            pass
        if self.path.is_symlink():
            raise OSError("El archivo de perfil no puede ser un enlace simbólico.")
        payload = {"display_name": normalized}
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=self.root,
                prefix=".profile-",
                delete=False,
            ) as handle:
                temporary = Path(handle.name)
                os.chmod(temporary, 0o600)
                json.dump(payload, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, self.path)
            temporary = None
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        return payload
