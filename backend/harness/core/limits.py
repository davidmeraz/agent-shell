"""Presupuestos locales del agente; no equivalen a la cuota del plan de ChatGPT."""

import json
import os
from dataclasses import dataclass

from ..tools.output import DEFAULT_CONTEXT_OUTPUT


@dataclass(frozen=True)
class AgentLimits:
    max_steps: int = 32
    max_tool_calls: int = 64
    shell_timeout: int = 300
    context_output_chars: int = DEFAULT_CONTEXT_OUTPUT
    max_turn_tokens: int = 0
    repeated_failures: int = 3

    @classmethod
    def from_environment(cls):
        fields = {
            "max_steps": ("AGENT_SHELL_MAX_STEPS", 1, 256),
            "max_tool_calls": ("AGENT_SHELL_MAX_TOOL_CALLS", 1, 1024),
            "shell_timeout": ("AGENT_SHELL_COMMAND_TIMEOUT", 1, 3600),
            "context_output_chars": ("AGENT_SHELL_CONTEXT_OUTPUT_CHARS", 256, 16000),
            "max_turn_tokens": ("AGENT_SHELL_MAX_TURN_TOKENS", 0, 100000000),
            "repeated_failures": ("AGENT_SHELL_REPEATED_FAILURES", 2, 20),
        }
        values = {}
        defaults = cls()
        for field, (name, low, high) in fields.items():
            try:
                value = int(os.environ.get(name, getattr(defaults, field)))
                if not low <= value <= high:
                    raise ValueError()
            except ValueError:
                raise ValueError(f"{name} debe ser un entero entre {low} y {high}") from None
            values[field] = value
        return cls(**values)


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
