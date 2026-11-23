"""Salida acotada que conserva el comienzo y el diagnóstico final de un comando."""

import re

DEFAULT_CONTEXT_OUTPUT = 6000
OMISSION_MARKER = "\n[…]\n"
ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")


def strip_ansi(text: str) -> str:
    """Elimina secuencias de color/control ANSI para evitar gastar tokens sin valor semántico."""
    return ANSI_ESCAPE_RE.sub("", text) if "\x1b" in text else text


class BoundedOutput:
    def __init__(self, limit: int) -> None:
        if type(limit) is not int or limit < 0:
            raise ValueError("El límite de salida debe ser un entero no negativo")
        self.limit = limit
        self.characters = 0
        self._head = ""
        self._tail = ""

    def append(self, text: str) -> None:
        self.characters += len(text)
        self._head += text[:max(0, self.limit - len(self._head))]
        if self.limit:
            self._tail = (self._tail + text)[-self.limit:]

    @property
    def truncated(self) -> bool:
        return self.characters > self.limit

    @property
    def text(self) -> str:
        if not self.truncated:
            return self._head
        marker = OMISSION_MARKER[:self.limit]
        available = self.limit - len(marker)
        head = available // 2
        tail = available - head
        return self._head[:head] + marker + (self._tail[-tail:] if tail else "")


def compact_result(result: dict, limit: int = DEFAULT_CONTEXT_OUTPUT) -> dict:
    """Vista para el modelo, creada una vez; la tarjeta conserva la captura más amplia."""
    output = BoundedOutput(limit)
    output.append(strip_ansi(result.get("output", "")))
    clean = {key: result[key] for key in ("status", "exit_code") if key in result}
    clean.update(output=output.text, truncated=bool(result.get("truncated") or output.truncated))
    if clean["truncated"]:
        clean["output_note"] = "Salida parcial: se conservan el inicio y el final; acota la lectura si faltan datos."
    return clean
