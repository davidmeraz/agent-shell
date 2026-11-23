"""Presupuestos locales del agente, perfiles y persistencia atómica."""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

from ..tools.output import DEFAULT_CONTEXT_OUTPUT

LIMIT_FIELDS: dict[str, tuple[str, int, int, int]] = {
    # field: (env_var, min_val, max_val, min_nonzero)
    "max_steps": ("AGENT_SHELL_MAX_STEPS", 1, 256, 1),
    "max_tool_calls": ("AGENT_SHELL_MAX_TOOL_CALLS", 1, 1024, 1),
    "shell_timeout": ("AGENT_SHELL_COMMAND_TIMEOUT", 1, 3600, 1),
    "context_output_chars": ("AGENT_SHELL_CONTEXT_OUTPUT_CHARS", 256, 16000, 256),
    "max_turn_tokens": ("AGENT_SHELL_MAX_TURN_TOKENS", 0, 100000000, 1),
    "max_turn_billable_tokens": ("AGENT_SHELL_MAX_TURN_BILLABLE_TOKENS", 0, 10000000, 4000),
    "repeated_failures": ("AGENT_SHELL_REPEATED_FAILURES", 2, 20, 2),
    "compact_threshold_tokens": ("AGENT_SHELL_COMPACT_THRESHOLD_TOKENS", 0, 500000, 8000),
    "max_compactions": ("AGENT_SHELL_MAX_COMPACTIONS", 1, 20, 1),
}

LIMIT_PRESETS: dict[str, dict[str, int]] = {
    "ahorro": {
        "compact_threshold_tokens": 40000,
        "max_compactions": 3,
        "max_turn_billable_tokens": 200000,
        "max_turn_tokens": 0,
        "max_steps": 24,
        "max_tool_calls": 48,
        "context_output_chars": 4000,
    },
    "equilibrado": {
        "compact_threshold_tokens": 60000,
        "max_compactions": 3,
        "max_turn_billable_tokens": 0,
        "max_turn_tokens": 0,
        "max_steps": 32,
        "max_tool_calls": 64,
        "context_output_chars": DEFAULT_CONTEXT_OUTPUT,
    },
    "grande": {
        "compact_threshold_tokens": 80000,
        "max_compactions": 3,
        "max_turn_billable_tokens": 0,
        "max_turn_tokens": 0,
        "max_steps": 48,
        "max_tool_calls": 96,
        "context_output_chars": 8000,
    },
}


def _validate_field(field: str, raw_value, label: str) -> int:
    _, low, high, min_nonzero = LIMIT_FIELDS[field]
    if isinstance(raw_value, bool) or not isinstance(raw_value, int):
        raise ValueError(f"{label} debe ser un entero")
    if not low <= raw_value <= high or (raw_value > 0 and raw_value < min_nonzero):
        if low == 0 and min_nonzero > 1:
            raise ValueError(f"{label} debe ser 0 (desactivado) o un entero entre {min_nonzero} y {high}")
        raise ValueError(f"{label} debe ser un entero entre {low} y {high}")
    return raw_value


@dataclass(frozen=True)
class AgentLimits:
    max_steps: int = 32
    max_tool_calls: int = 64
    shell_timeout: int = 300
    context_output_chars: int = DEFAULT_CONTEXT_OUTPUT
    max_turn_tokens: int = 0
    max_turn_billable_tokens: int = 0
    repeated_failures: int = 3
    compact_threshold_tokens: int = 60000
    max_compactions: int = 3

    def to_dict(self) -> dict[str, int]:
        return asdict(self)

    def profile_name(self) -> str:
        current = self.to_dict()
        for name, spec in LIMIT_PRESETS.items():
            if all(current[key] == value for key, value in spec.items()):
                return name
        return "personalizado"

    @classmethod
    def from_dict(cls, data: dict, base: AgentLimits | None = None) -> AgentLimits:
        if not isinstance(data, dict):
            raise ValueError("Configuración de límites inválida")
        unknown = set(data) - set(LIMIT_FIELDS)
        if unknown:
            raise ValueError(f"Campo de límites desconocido: {', '.join(sorted(unknown))}")
        values = (base or cls()).to_dict()
        for field, raw in data.items():
            values[field] = _validate_field(field, raw, field)
        return cls(**values)

    @classmethod
    def preset(cls, name: str, base: AgentLimits | None = None) -> AgentLimits:
        if not isinstance(name, str) or name not in LIMIT_PRESETS:
            raise ValueError("Perfil desconocido. Usa ahorro, equilibrado o grande.")
        return cls.from_dict(LIMIT_PRESETS[name], base=base)

    @classmethod
    def from_environment(cls, base: AgentLimits | None = None) -> AgentLimits:
        values = (base or cls()).to_dict()
        for field, (env_name, low, high, min_nonzero) in LIMIT_FIELDS.items():
            if env_name not in os.environ:
                continue
            try:
                parsed = int(os.environ[env_name])
                values[field] = _validate_field(field, parsed, env_name)
            except ValueError:
                if low == 0 and min_nonzero > 1:
                    raise ValueError(f"{env_name} debe ser 0 (desactivado) o un entero entre {min_nonzero} y {high}") from None
                raise ValueError(f"{env_name} debe ser un entero entre {low} y {high}") from None
        return cls(**values)


class LimitsStore:
    """Guarda los presupuestos de tokens en JSON privado y atómico; ignora archivos dañados."""

    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.path = self.root / "limits.json"

    def load(self) -> AgentLimits:
        if self.path.is_symlink() or not self.path.exists():
            return AgentLimits()
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            if not isinstance(raw, dict) or raw.get("schema_version") != 1:
                return AgentLimits()
            data = {k: v for k, v in raw.items() if k in LIMIT_FIELDS}
            return AgentLimits.from_dict(data)
        except (OSError, ValueError, TypeError):
            return AgentLimits()

    def save(self, limits: AgentLimits) -> None:
        if self.path.is_symlink():
            raise ValueError("El archivo de límites no puede ser un enlace simbólico")
        payload = {"schema_version": 1, **limits.to_dict()}
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=self.root, prefix=".limits-", suffix=".tmp",
                delete=False,
            ) as handle:
                temporary = Path(handle.name)
                json.dump(payload, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, self.path)
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)


def billable_tokens(usage: dict | None) -> int:
    """Tokens facturables reales del turno: entrada no cacheada + salida."""
    if not isinstance(usage, dict):
        return 0
    in_tok = usage.get("input_tokens") or 0
    cached = usage.get("cached_tokens") or 0
    out_tok = usage.get("output_tokens") or 0
    return max(0, in_tok - cached) + out_tok


class FailureTracker:
    """Detecta el mismo fallo consecutivo; un resultado diferente reinicia la cuenta."""

    def __init__(self, limit: int) -> None:
        self.limit = limit
        self._last = None
        self._count = 0

    def observe(self, item: dict, result: dict) -> bool:
        if result.get("status") not in ("error", "timeout"):
            self._last, self._count = None, 0
            return False
        try:
            arguments = json.dumps(json.loads(item["arguments"]), sort_keys=True, ensure_ascii=False)
        except ValueError:
            arguments = item["arguments"]
        signature = (item["name"], arguments, result["status"], result.get("exit_code"), result.get("output"))
        self._count = self._count + 1 if signature == self._last else 1
        self._last = signature
        return self._count >= self.limit
