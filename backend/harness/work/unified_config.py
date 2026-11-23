"""Configuración persistente del modo unificado: cascada de arquitectos, umbral y obreros."""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

from ..chat.models import EFFORTS

VALID_PROVIDERS = ("agy", "claude", "chatgpt")
VALID_EFFORTS = ("", *EFFORTS)
VALID_WORKER_TIERS = ("fast", "balanced", "strong")

DEFAULT_QUOTA_THRESHOLD = 35
MIN_QUOTA_THRESHOLD = 0
MAX_QUOTA_THRESHOLD = 95
MAX_CASCADE_STEPS = 6
MAX_WORKERS = 3


def _clean_model(raw) -> str:
    if not isinstance(raw, str) or "\0" in raw:
        raise ValueError("El identificador de modelo es inválido.")
    value = raw.strip()
    if len(value) > 128:
        raise ValueError("El identificador de modelo es demasiado largo.")
    return value


def _validate_provider(raw, label: str = "proveedor") -> str:
    if not isinstance(raw, str) or raw not in VALID_PROVIDERS:
        raise ValueError(f"El {label} debe ser 'agy', 'claude' o 'chatgpt'.")
    return raw


def _validate_effort(raw) -> str:
    if not isinstance(raw, str) or raw not in VALID_EFFORTS:
        raise ValueError("Nivel de razonamiento inválido.")
    return raw


def _validate_threshold(raw) -> int:
    if isinstance(raw, bool) or not isinstance(raw, int):
        raise ValueError("El umbral de cuota debe ser un número entero.")
    if not MIN_QUOTA_THRESHOLD <= raw <= MAX_QUOTA_THRESHOLD:
        raise ValueError(f"El umbral de cuota debe estar entre {MIN_QUOTA_THRESHOLD} y {MAX_QUOTA_THRESHOLD}%.")
    return raw


@dataclass(frozen=True)
class ArchitectStep:
    provider: str
    model: str = ""
    effort: str = ""

    def to_dict(self) -> dict[str, str]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> ArchitectStep:
        if not isinstance(data, dict):
            raise ValueError("Cada paso de la cascada debe ser un objeto.")
        unknown = set(data) - {"provider", "model", "effort"}
        if unknown:
            raise ValueError(f"Campo desconocido en la cascada: {', '.join(sorted(unknown))}.")
        return cls(
            provider=_validate_provider(data.get("provider"), "proveedor del arquitecto"),
            model=_clean_model(data.get("model", "")),
            effort=_validate_effort(data.get("effort", "")),
        )


@dataclass(frozen=True)
class WorkerSlotConfig:
    slot: str
    provider: str
    model: str = ""
    effort: str = "medium"
    tier: str = "balanced"

    def to_dict(self) -> dict[str, str]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> WorkerSlotConfig:
        if not isinstance(data, dict):
            raise ValueError("Cada obrero debe ser un objeto.")
        unknown = set(data) - {"slot", "provider", "model", "effort", "tier"}
        if unknown:
            raise ValueError(f"Campo desconocido en obrero: {', '.join(sorted(unknown))}.")
        provider = _validate_provider(data.get("provider"), "proveedor del obrero")
        slot = _validate_provider(data.get("slot") or provider, "identificador del obrero")
        tier = data.get("tier", "balanced")
        if not isinstance(tier, str) or tier not in VALID_WORKER_TIERS:
            raise ValueError("El nivel automático del obrero debe ser 'fast', 'balanced' o 'strong'.")
        return cls(
            slot=slot,
            provider=provider,
            model=_clean_model(data.get("model", "")),
            effort=_validate_effort(data.get("effort", "medium")),
            tier=tier,
        )


DEFAULT_ARCHITECT_CASCADE: tuple[ArchitectStep, ...] = (
    ArchitectStep(provider="agy", model="gemini-4-neon-xhigh", effort="xhigh"),
    ArchitectStep(provider="claude", model="claude-opus", effort="xhigh"),
    ArchitectStep(provider="chatgpt", model="gpt-6.2-astra", effort="high"),
)

DEFAULT_WORKERS: tuple[WorkerSlotConfig, ...] = (
    WorkerSlotConfig(slot="chatgpt", provider="chatgpt", model="", effort="medium", tier="balanced"),
    WorkerSlotConfig(slot="claude", provider="claude", model="", effort="medium", tier="balanced"),
)


@dataclass(frozen=True)
class UnifiedConfig:
    quota_threshold: int = DEFAULT_QUOTA_THRESHOLD
    parallel_workers: bool = True
    architect_cascade: tuple[ArchitectStep, ...] = DEFAULT_ARCHITECT_CASCADE
    workers: tuple[WorkerSlotConfig, ...] = DEFAULT_WORKERS

    def to_dict(self) -> dict:
        return {
            "quota_threshold": self.quota_threshold,
            "parallel_workers": self.parallel_workers,
            "architect_cascade": [step.to_dict() for step in self.architect_cascade],
            "workers": [worker.to_dict() for worker in self.workers],
        }

    @classmethod
    def default(cls) -> UnifiedConfig:
        return cls()

    @classmethod
    def from_dict(cls, data: dict, base: UnifiedConfig | None = None) -> UnifiedConfig:
        if not isinstance(data, dict):
            raise ValueError("Configuración del modo unificado inválida.")
        allowed = {"quota_threshold", "parallel_workers", "architect_cascade", "workers"}
        unknown = set(data) - allowed
        if unknown:
            raise ValueError(f"Campo desconocido en modo unificado: {', '.join(sorted(unknown))}.")
        current = base or cls()

        threshold = _validate_threshold(data["quota_threshold"]) if "quota_threshold" in data else current.quota_threshold

        if "parallel_workers" in data:
            if not isinstance(data["parallel_workers"], bool):
                raise ValueError("parallel_workers debe ser booleano.")
            parallel = data["parallel_workers"]
        else:
            parallel = current.parallel_workers

        if "architect_cascade" in data:
            raw_cascade = data["architect_cascade"]
            if not isinstance(raw_cascade, list) or not 1 <= len(raw_cascade) <= MAX_CASCADE_STEPS:
                raise ValueError(f"La cascada debe incluir entre 1 y {MAX_CASCADE_STEPS} arquitectos.")
            cascade = tuple(ArchitectStep.from_dict(entry) for entry in raw_cascade)
        else:
            cascade = current.architect_cascade

        if "workers" in data:
            raw_workers = data["workers"]
            if not isinstance(raw_workers, list) or not 1 <= len(raw_workers) <= MAX_WORKERS:
                raise ValueError(f"Debe haber entre 1 y {MAX_WORKERS} obreros configurados.")
            workers = tuple(WorkerSlotConfig.from_dict(entry) for entry in raw_workers)
            slots = [item.slot for item in workers]
            if len(set(slots)) != len(slots):
                raise ValueError("Cada obrero debe tener un proveedor/ranura distinto.")
        else:
            workers = current.workers

        return cls(
            quota_threshold=threshold,
            parallel_workers=parallel,
            architect_cascade=cascade,
            workers=workers,
        )


class UnifiedConfigStore:
    """Guarda `unified.json` en `config_root` de forma atómica y privada sin seguir enlaces simbólicos."""

    def __init__(self, root: Path) -> None:
        self.root = Path(root).resolve()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.path = self.root / "unified.json"

    def load(self) -> UnifiedConfig:
        if self.path.is_symlink() or not self.path.is_file():
            return UnifiedConfig.default()
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            if not isinstance(raw, dict) or raw.get("schema_version") != 1:
                return UnifiedConfig.default()
            data = {k: v for k, v in raw.items() if k != "schema_version"}
            return UnifiedConfig.from_dict(data)
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            return UnifiedConfig.default()

    def save(self, config: UnifiedConfig) -> None:
        if self.root.is_symlink():
            raise OSError("El directorio de configuración no puede ser un enlace simbólico.")
        if self.path.is_symlink():
            raise ValueError("El archivo de configuración unificada no puede ser un enlace simbólico.")
        payload = {"schema_version": 1, **config.to_dict()}
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=self.root, prefix=".unified-", suffix=".tmp",
                delete=False,
            ) as handle:
                temporary = Path(handle.name)
                json.dump(payload, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, self.path)
            temporary = None
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
