"""Preferencia local de motor de IA (ChatGPT, Antigravity CLI o Claude Code CLI)."""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path

VALID_PROVIDERS = ("chatgpt", "agy", "claude")


def normalize_provider(raw) -> str:
    if not isinstance(raw, str) or raw not in VALID_PROVIDERS:
        raise ValueError("Motor de IA no soportado. Elige 'chatgpt', 'agy' o 'claude'.")
    return raw


def _clean_field(raw, max_len: int = 128) -> str:
    if not isinstance(raw, str) or "\0" in raw:
        return ""
    value = raw.strip()
    return value[:max_len] if len(value) > max_len else value


class ProviderStore:
    """Persiste `provider.json` en `config_root` sin seguir enlaces simbólicos."""

    def __init__(self, root: Path) -> None:
        self.root = Path(root)
        self.path = self.root / "provider.json"

    def load(self) -> dict[str, str]:
        default = {"provider": "chatgpt", "agy_model": "", "claude_model": "", "claude_effort": ""}
        try:
            if self.path.is_symlink() or not self.path.is_file():
                return default
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            if not isinstance(raw, dict):
                return default
            provider = normalize_provider(raw.get("provider", "chatgpt"))
            return {
                "provider": provider,
                "agy_model": _clean_field(raw.get("agy_model", "")),
                "claude_model": _clean_field(raw.get("claude_model", "")),
                "claude_effort": _clean_field(raw.get("claude_effort", ""), 32),
            }
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            return default

    def save(
        self,
        provider: str,
        agy_model: str = "",
        claude_model: str = "",
        claude_effort: str = "",
    ) -> dict[str, str]:
        normalized = normalize_provider(provider)
        if self.root.is_symlink():
            raise OSError("El directorio de configuración no puede ser un enlace simbólico.")
        self.root.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(self.root, 0o700)
        except OSError:
            pass
        if self.path.is_symlink():
            raise OSError("El archivo de motor no puede ser un enlace simbólico.")
        payload = {
            "provider": normalized,
            "agy_model": _clean_field(agy_model),
            "claude_model": _clean_field(claude_model),
            "claude_effort": _clean_field(claude_effort, 32),
        }
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
