"""Salida acotada e inteligente: limpia ANSI/progreso, colapsa repeticiones y rescata diagnósticos."""

from __future__ import annotations

import re

DEFAULT_CONTEXT_OUTPUT = 6000
OMISSION_MARKER = "\n[…]\n"
MAX_SINGLE_LINE_CHARS = 1200
ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
DIAGNOSTIC_RE = re.compile(
    r"(?:^|\b)(?:"
    r"Traceback \(most recent call last\)|"
    r"FAIL:|ERROR:|FATAL:|PANIC:|"
    r"[A-Za-z_][A-Za-z0-9_]*(?:Error|Exception|Fault):|"
    r"AssertionError|error\[E\d+\]:|error:|fatal:|panic:"
    r")",
)


def strip_ansi(text: str) -> str:
    """Elimina secuencias de color/control ANSI para evitar gastar tokens sin valor semántico."""
    return ANSI_ESCAPE_RE.sub("", text) if "\x1b" in text else text


def collapse_carriage_returns(text: str) -> str:
    """Colapsa barras de progreso con `\\r` conservando sólo el último estado de cada línea."""
    if "\r" not in text:
        return text
    normalized = text.replace("\r\n", "\n")
    if "\r" not in normalized:
        return normalized
    out_lines: list[str] = []
    for line in normalized.split("\n"):
        if "\r" not in line:
            out_lines.append(line)
            continue
        segments = [seg for seg in line.split("\r") if seg]
        out_lines.append(segments[-1] if segments else "")
    return "\n".join(out_lines)


def collapse_repeated_lines(text: str, *, min_len: int = 4, threshold: int = 3) -> tuple[str, int]:
    """Colapsa bloques de líneas consecutivas idénticas (de al menos `min_len` chars útiles)."""
    if "\n" not in text:
        return text, 0
    lines = text.split("\n")
    if len(lines) <= threshold:
        return text, 0
    result: list[str] = []
    collapsed_total = 0
    i = 0
    n = len(lines)
    while i < n:
        current = lines[i]
        if len(current.strip()) < min_len:
            result.append(current)
            i += 1
            continue
        j = i + 1
        while j < n and lines[j] == current:
            j += 1
        count = j - i
        if count > threshold:
            result.append(current)
            omitted = count - 1
            collapsed_total += omitted
            result.append(f"[… línea repetida {omitted} veces …]")
        else:
            result.extend(lines[i:j])
        i = j
    return "\n".join(result), collapsed_total


def clip_long_lines(text: str, max_line_chars: int = MAX_SINGLE_LINE_CHARS) -> tuple[str, int]:
    """Recorta líneas individuales gigantes (p. ej. JS/JSON minificado en una sola línea)."""
    if len(text) <= max_line_chars:
        return text, 0
    lines = text.split("\n")
    # Si sólo son líneas de relleno sintético sin diagnóstico ni estructura (un único carácter repetido),
    # dejar que BoundedOutput aplique su recorte exacto.
    clipped_lines: list[str] = []
    clipped_count = 0
    head_part = (max_line_chars * 3) // 5
    tail_part = max_line_chars - head_part
    for line in lines:
        if len(line) > max_line_chars and len(set(line[:256])) > 2:
            extra = len(line) - head_part - tail_part
            marker = f" [… +{extra} chars en la misma línea …] "
            clipped_lines.append(line[:head_part] + marker + line[-tail_part:])
            clipped_count += 1
        else:
            clipped_lines.append(line)
    return ("\n".join(clipped_lines) if clipped_count else text), clipped_count


def extract_middle_diagnostics(middle: str, budget: int) -> str:
    """Extrae bloques de error/traceback del segmento central que sería descartado."""
    if not middle or budget < 80 or not DIAGNOSTIC_RE.search(middle):
        return ""
    lines = middle.splitlines()
    rescued: list[str] = []
    used = 0
    seen: set[str] = set()
    i = 0
    n = len(lines)
    while i < n and used < budget:
        line = lines[i]
        if DIAGNOSTIC_RE.search(line):
            block = [line[:240] for line in lines[i:min(n, i + 6)]]
            snippet = "\n".join(block).strip()
            if snippet and snippet not in seen:
                seen.add(snippet)
                addition = len(snippet) + (1 if rescued else 0)
                if used + addition <= budget:
                    rescued.append(snippet)
                    used += addition
                elif not rescued:
                    rescued.append(snippet[:budget])
                    break
            i += 6
        else:
            i += 1
    return "\n---\n".join(rescued)


class BoundedOutput:
    def __init__(self, limit: int) -> None:
        if type(limit) is not int or limit < 0:
            raise ValueError("El límite de salida debe ser un entero no negativo")
        self.limit = limit
        self.characters = 0
        self._head = ""
        self._tail = ""
        self._diag_snippets: list[str] = []
        self._diag_chars = 0
        self._pending_line = ""

    def append(self, text: str) -> None:
        if not text:
            return
        self.characters += len(text)
        if len(self._head) < self.limit:
            self._head += text[:max(0, self.limit - len(self._head))]
        elif self._diag_chars < 1600:
            self._harvest_stream_diagnostics(text)
        if self.limit:
            self._tail = (self._tail + text)[-self.limit:]

    def _harvest_stream_diagnostics(self, chunk: str) -> None:
        combined = self._pending_line + chunk
        lines = combined.split("\n")
        self._pending_line = lines.pop()[-300:] if lines else combined[-300:]
        for line in lines:
            if self._diag_chars >= 1600:
                break
            clean = strip_ansi(line).strip()
            if clean and DIAGNOSTIC_RE.search(clean):
                clipped = clean[:240]
                if clipped not in self._diag_snippets:
                    self._diag_snippets.append(clipped)
                    self._diag_chars += len(clipped) + 1

    @property
    def diagnostics(self) -> str:
        return "\n".join(self._diag_snippets)

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
    """Vista enriquecida para el modelo: limpia ANSI/\\r, colapsa duplicados y rescata errores."""
    raw_text = strip_ansi(result.get("output", ""))
    cleaned = collapse_carriage_returns(raw_text)
    cleaned, collapsed_repeats = collapse_repeated_lines(cleaned)
    cleaned, clipped_lines = clip_long_lines(cleaned)

    middle_diagnostics = ""
    if len(cleaned) > limit >= 400:
        rough_half = limit // 2
        middle_slice = cleaned[rough_half:max(rough_half, len(cleaned) - rough_half)]
        middle_diagnostics = extract_middle_diagnostics(middle_slice, min(1200, limit // 4))
    if not middle_diagnostics and result.get("diagnostics"):
        middle_diagnostics = extract_middle_diagnostics(str(result["diagnostics"]), min(1200, max(0, limit // 4)))

    if len(cleaned) > limit and middle_diagnostics:
        diag_block = f"\n[… diagnósticos en parte omitida …]\n{middle_diagnostics}\n[…]\n"
        if len(diag_block) < limit - 64:
            available = limit - len(diag_block)
            head_len = available // 2
            tail_len = available - head_len
            final_text = cleaned[:head_len] + diag_block + cleaned[-tail_len:]
            was_truncated = True
        else:
            bounded = BoundedOutput(limit)
            bounded.append(cleaned)
            final_text = bounded.text
            was_truncated = bounded.truncated
    else:
        bounded = BoundedOutput(limit)
        bounded.append(cleaned)
        final_text = bounded.text
        was_truncated = bounded.truncated

    truncated = bool(result.get("truncated") or was_truncated or collapsed_repeats or clipped_lines)
    clean = {key: result[key] for key in ("status", "exit_code") if key in result}
    clean.update(output=final_text, truncated=truncated)

    notes: list[str] = []
    if result.get("output_note"):
        notes.append(str(result["output_note"]))
    elif result.get("truncated") or was_truncated:
        notes.append("Salida parcial: se conservan el inicio y el final; acota la lectura si faltan datos.")
    if middle_diagnostics:
        notes.append("Se rescataron diagnósticos de error del centro omitido.")
    if collapsed_repeats:
        notes.append(f"Se colapsaron {collapsed_repeats} líneas repetidas.")
    if clipped_lines:
        notes.append(f"Se recortaron {clipped_lines} líneas excesivamente largas.")
    if notes:
        clean["output_note"] = " ".join(notes)
    return clean
