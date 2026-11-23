"""Preferencia local de motor de IA (ChatGPT o Antigravity CLI) con guardado atómico."""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path

VALID_PROVIDERS = ("chatgpt", "agy")


def normalize_provider(raw) -> str:
    if not isinstance(raw, str) or raw not in VALID_PROVIDERS:
        raise ValueError("Motor de IA no soportado. Elige 'chatgpt' o 'agy'.")
    return raw


class ProviderStore:
    """Persiste `provider.json` en `config_root` sin seguir enlaces simbólicos."""

    def __init__(self, root: Path) -> None:
        self.root = Path(root)
        self.path = self.root / "provider.json"

    def load(self) -> dict[str, str]:
        default = {"provider": "chatgpt", "agy_model": ""}
        try:
            if self.path.is_symlink() or not self.path.is_file():
                return default
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            if not isinstance(raw, dict):
                return default
            provider = normalize_provider(raw.get("provider", "chatgpt"))
            agy_model = raw.get("agy_model", "")
            if not isinstance(agy_model, str) or len(agy_model) > 128 or "\0" in agy_model:
                agy_model = ""
            return {"provider": provider, "agy_model": agy_model.strip()}
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            return default

    def save(self, provider: str, agy_model: str = "") -> dict[str, str]:
        normalized = normalize_provider(provider)
        clean_model = agy_model.strip() if isinstance(agy_model, str) and "\0" not in agy_model else ""
        if len(clean_model) > 128:
            clean_model = clean_model[:128]
        if self.root.is_symlink():
            raise OSError("El directorio de configuración no puede ser un enlace simbólico.")
        self.root.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(self.root, 0o700)
        except OSError:
            pass
        if self.path.is_symlink():
            raise OSError("El archivo de motor no puede ser un enlace simbólico.")
        payload = {"provider": normalized, "agy_model": clean_model}
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=self.root,
                prefix=".provider-",
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
